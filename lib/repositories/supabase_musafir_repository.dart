import 'dart:async';

import 'package:flutter/foundation.dart';
import '../core/state/safe_notifier.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User, RealtimeChannel;
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../data/facility_catalog.dart';
import '../models/booking.dart';
import '../models/booking_conflict_exception.dart';
import '../models/booking_duration.dart';
import '../models/booking_status.dart';
import '../models/facility.dart';
import '../models/guest_review_ratings.dart';
import '../models/listing.dart';
import '../models/listing_type.dart';
import '../models/owner_registration_draft.dart';
import '../models/review.dart';
import '../models/search_filters.dart';
import '../models/user.dart';
import '../models/user_role.dart';
import 'musafir_repository.dart';

/// Supabase-backed implementation of [MusafirRepository].
///
/// This repository fetches and caches data from Supabase PostgreSQL database.
/// It extends [ChangeNotifier] to support reactive UI updates.
class SupabaseMusafirRepository extends ChangeNotifier with SafeNotifier
    implements MusafirRepository {
  SupabaseMusafirRepository() {
    _initialize();
  }

  SupabaseClient get _client => Supabase.instance.client;

  // Local cache
  List<Listing> _listings = [];
  List<Booking> _bookings = [];
  List<Review> _reviews = [];
  final Map<String, User> _users = {};

  // Error notification stream for booking updates
  final _bookingUpdateErrorController = StreamController<BookingUpdateError>.broadcast();

  @override
  Stream<BookingUpdateError> get bookingUpdateErrors => _bookingUpdateErrorController.stream;

  // Realtime subscription for bookings
  RealtimeChannel? _bookingsChannel;

  bool _initialized = false;

  // Pagination state - Listings
  static const int _pageSize = 10;
  DateTime? _listingsCursor;
  bool _hasMoreListings = true;
  bool _isLoadingListings = false;

  // Pagination state - Bookings
  DateTime? _bookingsCursor;
  bool _hasMoreBookings = true;
  bool _isLoadingBookings = false;
  String? _currentBookingsUserId;

  // Booking counts cache
  Map<String, int>? _cachedBookingCounts;

  @override
  bool get hasMoreListings => _hasMoreListings;

  @override
  bool get isLoadingListings => _isLoadingListings;

  @override
  bool get hasMoreBookings => _hasMoreBookings;

  @override
  bool get isLoadingBookings => _isLoadingBookings;

  @override
  Map<String, int>? get cachedBookingCounts => _cachedBookingCounts;

  Future<void> _initialize() async {
    await _refreshAll();
    _initialized = true;
    _setupBookingsRealtimeSubscription();
    notifyListeners();
  }

  /// Set up realtime subscription for booking changes.
  /// This ensures the UI updates when bookings are created/updated from other devices.
  void _setupBookingsRealtimeSubscription() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('[Bookings Realtime] No user logged in, skipping subscription');
      return;
    }

    // Clean up existing subscription
    _bookingsChannel?.unsubscribe();

    _bookingsChannel = _client.channel('bookings:$userId');

    _bookingsChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'bookings',
          callback: (payload) {
            _handleBookingRealtimeChange(payload.newRecord, isInsert: true);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'bookings',
          callback: (payload) {
            _handleBookingRealtimeChange(payload.newRecord, isInsert: false);
          },
        )
        .subscribe();

    debugPrint('[Bookings Realtime] Subscription active for user: $userId');
  }

  /// Handle realtime booking changes
  void _handleBookingRealtimeChange(Map<String, dynamic> record, {required bool isInsert}) {
    try {
      final booking = _bookingFromJson(record);
      final userId = _client.auth.currentUser?.id;

      // Only process if this booking is relevant to the current user
      // (they're the tenant or the host of the listing)
      final isRelevant = booking.userId == userId ||
          _listings.any((l) => l.id == booking.listingId && l.hostId == userId);

      if (!isRelevant) {
        debugPrint('[Bookings Realtime] Ignoring irrelevant booking: ${booking.id}');
        return;
      }

      if (isInsert) {
        // Add new booking if not already in cache
        if (!_bookings.any((b) => b.id == booking.id)) {
          _bookings.add(booking);
          debugPrint('[Bookings Realtime] Added new booking: ${booking.id}');
          notifyListeners();
        }
      } else {
        // Update existing booking
        final index = _bookings.indexWhere((b) => b.id == booking.id);
        if (index != -1) {
          _bookings[index] = booking;
          debugPrint('[Bookings Realtime] Updated booking: ${booking.id}, status: ${booking.status.name}');
          notifyListeners();
        } else {
          // Booking not in cache, add it
          _bookings.add(booking);
          debugPrint('[Bookings Realtime] Added missing booking: ${booking.id}');
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[Bookings Realtime] Error handling change: $e');
    }
  }

  @override
  void dispose() {
    _bookingsChannel?.unsubscribe();
    _bookingUpdateErrorController.close();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _refreshListings(),
      _refreshBookings(),
      _refreshReviews(),
    ]);
  }

  // ============== Listings ==============

  /// Fetch first page of listings (called on init)
  Future<void> _refreshListings() async {
    await resetListingsPagination();
  }

  @override
  Future<void> resetListingsPagination() async {
    _listings = [];
    _listingsCursor = null;
    _hasMoreListings = true;
    _isLoadingListings = false;
    notifyListeners();
    await fetchNextListingsPage();
  }

  @override
  Future<List<Listing>> fetchNextListingsPage() async {
    if (_isLoadingListings || !_hasMoreListings) {
      return [];
    }

    _isLoadingListings = true;
    notifyListeners();

    try {
      // Build query with cursor pagination
      // Note: filters must come before order/limit
      var query = _client
          .from('listings')
          .select('*, listing_facilities(facility_id, facilities(name))')
          .eq('is_active', true);

      // Apply cursor if we have one (fetch items older than cursor)
      if (_listingsCursor != null) {
        query = query.lt('created_at', _listingsCursor!.toIso8601String());
      }

      final listingsResponse = await query
          .order('created_at', ascending: false)
          .limit(_pageSize);

      final newListings = <Listing>[];

      if ((listingsResponse as List).isEmpty) {
        _hasMoreListings = false;
      } else {
        // Fetch rating data for these listings
        final listingIds = listingsResponse.map((e) => e['id'] as String).toList();
        final ratingsResponse = await _client
            .from('listing_ratings')
            .select('listing_id, review_count, average_rating')
            .inFilter('listing_id', listingIds);

        // Create ratings map
        final ratingsMap = <String, Map<String, dynamic>>{};
        for (final row in ratingsResponse as List) {
          final listingId = row['listing_id'] as String;
          ratingsMap[listingId] = row as Map<String, dynamic>;
        }

        // Parse listings and merge with ratings
        for (final e in listingsResponse) {
          final json = e as Map<String, dynamic>;
          final listingId = json['id'] as String;
          final ratingData = ratingsMap[listingId];

          if (ratingData != null) {
            json['rating'] = ratingData['average_rating'];
            json['review_count'] = ratingData['review_count'];
          }

          newListings.add(_listingFromJson(json));
        }

        // Update cursor to the oldest item's created_at
        final lastItem = listingsResponse.last as Map<String, dynamic>;
        final createdAtStr = lastItem['created_at'] as String?;
        if (createdAtStr != null) {
          _listingsCursor = DateTime.parse(createdAtStr);
        }

        // Add to accumulated list
        _listings.addAll(newListings);

        // Check if we got fewer items than page size (means no more)
        if (listingsResponse.length < _pageSize) {
          _hasMoreListings = false;
        }
      }

      _isLoadingListings = false;
      notifyListeners();
      return newListings;
    } catch (e) {
      debugPrint('Error fetching listings page: $e');
      _isLoadingListings = false;
      notifyListeners();
      return [];
    }
  }

  Listing _listingFromJson(Map<String, dynamic> json) {
    // Parse facilities from join
    final facilitiesData = json['listing_facilities'] as List? ?? [];
    final facilities = facilitiesData.map<Facility>((f) {
      final name = f['facilities']?['name'] as String? ?? '';
      return _facilityFromName(name);
    }).toList();

    return Listing(
      id: json['id'] as String,
      ownerName: json['owner_name'] as String? ?? '',
      title: json['title'] as String,
      address: json['address'] as String? ?? '',
      type: _listingTypeFromString(json['listing_type'] as String?),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      hourlyRate: (json['hourly_rate'] as num?)?.toDouble(),
      dailyRate: (json['daily_rate'] as num?)?.toDouble(),
      monthlyRate: (json['monthly_rate'] as num?)?.toDouble(),
      facilities: facilities,
      available: json['is_active'] as bool? ?? true,
      hostId: json['owner_id'] as String?,
      hostAvatarUrl: json['host_avatar_url'] as String?,
      description: json['description'] as String?,
      city: json['city'] as String?,
      country: json['country'] as String?,
      imageUrls: (json['image_urls'] as List?)?.cast<String>() ?? [],
      maxGuests: json['max_guests'] as int? ?? 2,
      bedrooms: json['bedrooms'] as int? ?? 1,
      beds: json['beds'] as int? ?? 1,
      bathrooms: json['bathrooms'] as int? ?? 1,
      rating: (json['rating'] as num?)?.toDouble(),
      reviewCount: json['review_count'] as int? ?? 0,
      isSuperhost: json['is_superhost'] as bool? ?? false,
    );
  }

  Map<String, dynamic> _listingToJson(Listing listing) {
    return {
      'title': listing.title,
      'address': listing.address,
      'listing_type': listing.type.name,
      'latitude': listing.latitude,
      'longitude': listing.longitude,
      'hourly_rate': listing.hourlyRate,
      'daily_rate': listing.dailyRate,
      'monthly_rate': listing.monthlyRate,
      'is_active': listing.available,
      'owner_id': listing.hostId,
      'owner_name': listing.ownerName,
      'description': listing.description,
      'city': listing.city,
      'country': listing.country,
      'image_urls': listing.imageUrls,
      'max_guests': listing.maxGuests,
      'bedrooms': listing.bedrooms,
      'beds': listing.beds,
      'bathrooms': listing.bathrooms,
    };
  }

  ListingType _listingTypeFromString(String? value) {
    return switch (value?.toLowerCase()) {
      'seat' => ListingType.seat,
      'room' => ListingType.room,
      'fullhouse' || 'full_house' => ListingType.fullHouse,
      _ => ListingType.room,
    };
  }

  Facility _facilityFromName(String name) {
    return switch (name.toLowerCase()) {
      'wi-fi' || 'wifi' => FacilityCatalog.wifi,
      'ac' => FacilityCatalog.ac,
      'attached bath' || 'bath' => FacilityCatalog.bath,
      'kitchen' => FacilityCatalog.kitchen,
      'parking' => FacilityCatalog.parking,
      _ => Facility(name: name, icon: Icons.check),
    };
  }

  // ============== Bookings ==============

  Future<void> _refreshBookings() async {
    try {
      // Join with listings to get listing_type
      final response = await _client.from('bookings').select('''
        *,
        listings!inner(listing_type)
      ''');

      _bookings = (response as List).map((e) => _bookingFromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching bookings: $e');
    }
  }

  Booking _bookingFromJson(Map<String, dynamic> json) {
    // Extract listing_type from joined data or direct field
    String? listingType = json['listing_type'] as String?;
    if (listingType == null && json['listings'] != null) {
      final listings = json['listings'];
      if (listings is Map<String, dynamic>) {
        listingType = listings['listing_type'] as String?;
      }
    }

    return Booking(
      id: json['id'] as String,
      listingId: json['listing_id'] as String,
      tenantName: json['tenant_name'] as String? ?? '',
      startAt: DateTime.parse(json['starts_at'] as String),
      endAt: DateTime.parse(json['ends_at'] as String),
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0.0,
      unitLabel: json['pricing_unit'] as String? ?? 'day',
      userId: json['tenant_id'] as String?,
      status: _bookingStatusFromString(json['booking_status'] as String?),
      guestCount: json['guest_count'] as int? ?? 1,
      checkIn: json['starts_at'] != null
          ? DateTime.parse(json['starts_at'] as String)
          : null,
      checkOut: json['ends_at'] != null
          ? DateTime.parse(json['ends_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      listingTitle: json['listing_title'] as String?,
      listingImageUrl: json['listing_image_url'] as String?,
      listingCity: json['listing_city'] as String?,
      listingType: listingType,
      // Lifecycle fields
      hostMessage: json['host_message'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      confirmedAt: json['confirmed_at'] != null
          ? DateTime.parse(json['confirmed_at'] as String)
          : null,
      actualCheckIn: json['actual_check_in'] != null
          ? DateTime.parse(json['actual_check_in'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      cancelledBy: json['cancelled_by'] as String?,
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.parse(json['cancelled_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> _bookingToJson({
    required String listingId,
    required String tenantId,
    required String tenantName,
    required DateTime startsAt,
    required DateTime endsAt,
    required double totalPrice,
    required String pricingUnit,
    required int guestCount,
    String? listingTitle,
    String? listingImageUrl,
    String? listingCity,
  }) {
    return {
      'listing_id': listingId,
      'tenant_id': tenantId,
      'tenant_name': tenantName,
      'starts_at': startsAt.toIso8601String(),
      'ends_at': endsAt.toIso8601String(),
      'total_price': totalPrice,
      'pricing_unit': pricingUnit,
      'guest_count': guestCount,
      'booking_status': 'pending',
      'listing_title': listingTitle,
      'listing_image_url': listingImageUrl,
      'listing_city': listingCity,
    };
  }

  BookingStatus _bookingStatusFromString(String? value) {
    return switch (value?.toLowerCase()) {
      'pending' => BookingStatus.pending,
      'confirmed' => BookingStatus.confirmed,
      'rejected' => BookingStatus.rejected,
      'active' => BookingStatus.active,
      'completed' => BookingStatus.completed,
      'cancelled' => BookingStatus.cancelled,
      _ => BookingStatus.pending,
    };
  }

  // ============== Reviews ==============

  Future<void> _refreshReviews() async {
    try {
      final response = await _client.from('reviews').select();

      _reviews = (response as List).map((e) => _reviewFromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching reviews: $e');
    }
  }

  Review _reviewFromJson(Map<String, dynamic> json) {
    // Parse category ratings if present (for guest-to-host reviews)
    GuestReviewRatings? categoryRatings;
    if (json['cleanliness_rating'] != null) {
      categoryRatings = GuestReviewRatings(
        overall: (json['overall_rating'] as num?)?.toDouble() ?? 0.0,
        cleanliness: (json['cleanliness_rating'] as num?)?.toDouble() ?? 0.0,
        accuracy: (json['accuracy_rating'] as num?)?.toDouble() ?? 0.0,
        communication: (json['communication_rating'] as num?)?.toDouble() ?? 0.0,
        location: (json['location_rating'] as num?)?.toDouble() ?? 0.0,
        value: (json['value_rating'] as num?)?.toDouble() ?? 0.0,
      );
    }

    return Review(
      id: json['id'] as String,
      bookingId: json['booking_id'] as String? ?? '',
      listingId: json['listing_id'] as String?,
      reviewerId: json['reviewer_id'] as String? ?? json['user_id'] as String? ?? '',
      reviewerName: json['reviewer_name'] as String? ?? json['user_name'] as String? ?? 'Guest',
      reviewerAvatarUrl: json['reviewer_avatar_url'] as String? ?? json['user_avatar_url'] as String?,
      revieweeId: json['reviewee_id'] as String? ?? '',
      reviewType: _reviewTypeFromString(json['review_type'] as String?),
      overallRating: (json['overall_rating'] as num?)?.toDouble() ?? (json['rating'] as num?)?.toDouble() ?? 0.0,
      categoryRatings: categoryRatings,
      comment: json['comment'] as String?,
      isRevealed: json['is_revealed'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      revealedAt: json['revealed_at'] != null
          ? DateTime.parse(json['revealed_at'] as String)
          : null,
    );
  }

  ReviewType _reviewTypeFromString(String? value) {
    return switch (value?.toLowerCase()) {
      'guest_to_host' => ReviewType.guestToHost,
      'host_to_guest' => ReviewType.hostToGuest,
      _ => ReviewType.guestToHost,
    };
  }

  Map<String, dynamic> _reviewToJson(Review review) {
    // Send null for empty comments (consistent with database expectations)
    final comment = review.comment?.trim();
    final json = <String, dynamic>{
      'booking_id': review.bookingId,
      'listing_id': review.listingId,
      'reviewer_id': review.reviewerId,
      'reviewer_name': review.reviewerName,
      'reviewer_avatar_url': review.reviewerAvatarUrl,
      'reviewee_id': review.revieweeId,
      'review_type': review.reviewType == ReviewType.guestToHost
          ? 'guest_to_host'
          : 'host_to_guest',
      'overall_rating': review.overallRating,
      'comment': (comment != null && comment.isNotEmpty) ? comment : null,
    };

    // Add category ratings for guest-to-host reviews
    if (review.reviewType == ReviewType.guestToHost && review.categoryRatings != null) {
      json['cleanliness_rating'] = review.categoryRatings!.cleanliness;
      json['accuracy_rating'] = review.categoryRatings!.accuracy;
      json['communication_rating'] = review.categoryRatings!.communication;
      json['location_rating'] = review.categoryRatings!.location;
      json['value_rating'] = review.categoryRatings!.value;
    }

    return json;
  }

  // ============== Users ==============

  User _userFromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      name: json['full_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      role: _userRoleFromString(json['role'] as String?),
      phone: json['mobile'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      isHost: json['is_host'] as bool? ?? false,
      hostSince: json['host_since'] != null
          ? DateTime.parse(json['host_since'] as String)
          : null,
      bio: json['bio'] as String?,
    );
  }

  UserRole _userRoleFromString(String? value) {
    return switch (value?.toLowerCase()) {
      'admin' => UserRole.admin,
      'owner' => UserRole.owner,
      'tenant' => UserRole.tenant,
      _ => UserRole.tenant,
    };
  }

  // ============== Repository Interface Implementation ==============

  @override
  List<Listing> get listings => List.unmodifiable(_listings);

  @override
  List<Booking> get bookings => List.unmodifiable(_bookings);

  @override
  int get availableCount => _listings.where((l) => l.available).length;

  @override
  int get ownerCount => _listings.map((l) => l.ownerName).toSet().length;

  @override
  List<Listing> searchByArea({
    required double centerLat,
    required double centerLng,
    required double delta,
  }) {
    // For now, use local filtering. In production, use PostGIS ST_DWithin
    return _listings.where((listing) {
      final insideLat = (listing.latitude - centerLat).abs() <= delta;
      final insideLng = (listing.longitude - centerLng).abs() <= delta;
      return listing.available && insideLat && insideLng;
    }).toList();
  }

  @override
  void registerOwnerListing(OwnerRegistrationDraft draft) async {
    try {
      final data = {
        'owner_name': draft.mobile,
        'title': draft.title,
        'address': draft.address,
        'listing_type': draft.type.name,
        'latitude': draft.latitude,
        'longitude': draft.longitude,
        'hourly_rate': draft.hourlyRate,
        'daily_rate': draft.dailyRate,
        'monthly_rate': draft.monthlyRate,
        'is_active': true,
      };

      await _client.from('listings').insert(data);
      await _refreshListings();
    } catch (e) {
      debugPrint('Error registering listing: $e');
    }
  }

  @override
  Booking createBooking({
    required Listing listing,
    required String tenantName,
    required BookingDuration duration,
  }) {
    final now = DateTime.now();
    final endAt = switch (duration.unitLabel) {
      'hour' => now.add(Duration(hours: duration.multiplier)),
      'day' => now.add(Duration(days: duration.multiplier)),
      _ => DateTime(
          now.year,
          now.month + duration.multiplier,
          now.day,
          now.hour,
          now.minute,
        ),
    };
    final unitRate = switch (duration.unitLabel) {
      'hour' => listing.hourlyRate,
      'day' => listing.dailyRate,
      _ => listing.monthlyRate,
    } ?? 0;

    final booking = Booking(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      listingId: listing.id,
      tenantName: tenantName,
      startAt: now,
      endAt: endAt,
      totalPrice: unitRate * duration.multiplier,
      unitLabel: duration.unitLabel,
    );

    // Insert async
    _insertBookingAsync(booking, listing);

    return booking;
  }

  Future<void> _insertBookingAsync(Booking booking, Listing listing) async {
    try {
      final data = _bookingToJson(
        listingId: booking.listingId,
        tenantId: booking.userId ?? '',
        tenantName: booking.tenantName,
        startsAt: booking.startAt,
        endsAt: booking.endAt,
        totalPrice: booking.totalPrice,
        pricingUnit: booking.unitLabel,
        guestCount: booking.guestCount,
        listingTitle: listing.title,
        listingImageUrl: listing.primaryImage,
        listingCity: listing.city,
      );

      await _client.from('bookings').insert(data);
      await _refreshBookings();
    } catch (e) {
      debugPrint('Error inserting booking: $e');
    }
  }

  // ============== User Methods ==============

  @override
  User? getUserById(String id) {
    if (_users.containsKey(id)) return _users[id];

    // Fetch async and cache
    _fetchUserById(id);
    return null;
  }

  Future<void> _fetchUserById(String id) async {
    try {
      final response =
          await _client.from('profiles').select().eq('id', id).maybeSingle();

      if (response != null) {
        _users[id] = _userFromJson(response);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching user: $e');
    }
  }

  @override
  User? getUserByEmail(String email) {
    return _users.values
        .where((u) => u.email?.toLowerCase() == email.toLowerCase())
        .firstOrNull;
  }

  @override
  void addUser(User user) async {
    _users[user.id] = user;

    try {
      await _client.from('profiles').upsert({
        'id': user.id,
        'full_name': user.name,
        'email': user.email,
        'mobile': user.phone,
        'role': user.role.name,
        'avatar_url': user.avatarUrl,
        'is_host': user.isHost,
      });
      notifyListeners();
    } catch (e) {
      debugPrint('Error adding user: $e');
    }
  }

  // ============== Listing Methods ==============

  @override
  Listing? getListingById(String id) {
    return _listings.where((l) => l.id == id).firstOrNull;
  }

  @override
  List<Listing> searchListings(SearchFilters filters) {
    return _listings.where((listing) {
      if (!listing.available) return false;

      if (filters.propertyTypes.isNotEmpty &&
          !filters.propertyTypes.contains(listing.type)) {
        return false;
      }

      if (listing.maxGuests < filters.guestCount) {
        return false;
      }

      final price = listing.displayPrice;
      if (filters.minPrice != null && price < filters.minPrice!) {
        return false;
      }
      if (filters.maxPrice != null && price > filters.maxPrice!) {
        return false;
      }

      if (filters.amenities.isNotEmpty) {
        final listingAmenities = listing.amenityNames;
        for (final amenity in filters.amenities) {
          if (!listingAmenities.contains(amenity)) {
            return false;
          }
        }
      }

      if (filters.location != null && filters.location!.isNotEmpty) {
        final searchLower = filters.location!.toLowerCase();
        final matchesCity =
            listing.city?.toLowerCase().contains(searchLower) ?? false;
        final matchesAddress =
            listing.address.toLowerCase().contains(searchLower);
        final matchesTitle = listing.title.toLowerCase().contains(searchLower);
        if (!matchesCity && !matchesAddress && !matchesTitle) {
          return false;
        }
      }

      return true;
    }).toList()
      ..sort((a, b) {
        final ratingA = a.rating ?? 0;
        final ratingB = b.rating ?? 0;
        if (ratingA != ratingB) {
          return ratingB.compareTo(ratingA);
        }
        return b.reviewCount.compareTo(a.reviewCount);
      });
  }

  @override
  List<Listing> getFeaturedListings({int limit = 10}) {
    final available = _listings.where((l) => l.available).toList()
      ..sort((a, b) {
        final ratingA = a.rating ?? 0;
        final ratingB = b.rating ?? 0;
        if (ratingA != ratingB) {
          return ratingB.compareTo(ratingA);
        }
        return b.reviewCount.compareTo(a.reviewCount);
      });
    return available.take(limit).toList();
  }

  @override
  List<Listing> getListingsByHost(String hostId) {
    return _listings.where((l) => l.hostId == hostId).toList();
  }

  @override
  void addListing(Listing listing) async {
    _listings.add(listing);
    notifyListeners();

    try {
      await _client.from('listings').insert(_listingToJson(listing));
      await _refreshListings();
    } catch (e) {
      debugPrint('Error adding listing: $e');
    }
  }

  @override
  void updateListing(Listing listing) async {
    final index = _listings.indexWhere((l) => l.id == listing.id);
    if (index != -1) {
      _listings[index] = listing;
      notifyListeners();

      try {
        await _client
            .from('listings')
            .update(_listingToJson(listing))
            .eq('id', listing.id);
      } catch (e) {
        debugPrint('Error updating listing: $e');
      }
    }
  }

  @override
  void deleteListing(String listingId) async {
    _listings.removeWhere((l) => l.id == listingId);
    notifyListeners();

    try {
      await _client.from('listings').delete().eq('id', listingId);
    } catch (e) {
      debugPrint('Error deleting listing: $e');
    }
  }

  // ============== Review Methods ==============

  @override
  List<Review> getReviewsForListing(String listingId) {
    return _reviews.where((r) => r.listingId == listingId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  void addReview(Review review) async {
    _reviews.add(review);

    // Update listing rating locally if listingId is present
    if (review.listingId != null) {
      final listing = getListingById(review.listingId!);
      if (listing != null) {
        final reviews = getReviewsForListing(review.listingId!);
        final avgRating =
            reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;
        final index = _listings.indexOf(listing);
        _listings[index] = listing.copyWith(
          rating: avgRating,
          reviewCount: reviews.length,
        );
      }
    }
    notifyListeners();

    try {
      await _client.from('reviews').insert({
        'listing_id': review.listingId,
        'user_id': review.userId,
        'user_name': review.userName,
        'user_avatar_url': review.userAvatarUrl,
        'rating': review.rating,
        'comment': review.comment,
      });
    } catch (e) {
      debugPrint('Error adding review: $e');
    }
  }

  @override
  double getAverageRating(String listingId) {
    final reviews = getReviewsForListing(listingId);
    if (reviews.isEmpty) return 0;
    return reviews.map((r) => r.rating).reduce((a, b) => a + b) /
        reviews.length;
  }

  // ============== Bidirectional Review Methods ==============

  @override
  List<Review> getReviewsForBooking(String bookingId) {
    return _reviews.where((r) => r.bookingId == bookingId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  List<Review> getRevealedReviewsForListing(String listingId) {
    return _reviews
        .where((r) =>
            r.listingId == listingId &&
            r.isRevealed &&
            r.reviewType == ReviewType.guestToHost)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  List<Review> getRevealedReviewsForGuest(String guestId) {
    return _reviews
        .where((r) =>
            r.revieweeId == guestId &&
            r.isRevealed &&
            r.reviewType == ReviewType.hostToGuest)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  void saveReview(Review review) async {
    _reviews.add(review);
    notifyListeners();

    try {
      final reviewJson = _reviewToJson(review);
      debugPrint('[DEBUG-review] Saving review: $reviewJson');
      debugPrint('[DEBUG-review] Current user: ${_client.auth.currentUser?.id}');

      // Check booking status in database
      final bookingCheck = await _client
          .from('bookings')
          .select('id, booking_status, tenant_id')
          .eq('id', review.bookingId)
          .maybeSingle();
      debugPrint('[DEBUG-review] Booking in DB: $bookingCheck');

      await _client.from('reviews').insert(reviewJson);
      await _refreshReviews();
    } catch (e) {
      debugPrint('Error saving review: $e');
    }
  }

  @override
  void updateReview(Review review) async {
    final index = _reviews.indexWhere((r) => r.id == review.id);
    if (index != -1) {
      _reviews[index] = review;
      notifyListeners();

      try {
        await _client
            .from('reviews')
            .update(_reviewToJson(review))
            .eq('id', review.id);
      } catch (e) {
        debugPrint('Error updating review: $e');
      }
    }
  }

  // ============== Booking Methods ==============

  @override
  List<Booking> getBookingsForUser(String userId) {
    return _bookings.where((b) => b.userId == userId).toList()
      ..sort((a, b) => b.effectiveCheckIn.compareTo(a.effectiveCheckIn));
  }

  @override
  List<Booking> getUpcomingBookings(String userId) {
    final now = DateTime.now();
    return _bookings
        .where((b) => b.userId == userId && b.isUpcomingAt(now))
        .toList()
      ..sort((a, b) => a.effectiveCheckIn.compareTo(b.effectiveCheckIn));
  }

  @override
  List<Booking> getPastBookings(String userId) {
    final now = DateTime.now();
    return _bookings
        .where((b) => b.userId == userId && b.isPastAt(now))
        .toList()
      ..sort((a, b) => b.effectiveCheckIn.compareTo(a.effectiveCheckIn));
  }

  @override
  Booking? getBookingById(String id) {
    return _bookings.where((b) => b.id == id).firstOrNull;
  }

  /// Fetch booking directly from Supabase (async version for when local cache misses)
  Future<Booking?> fetchBookingById(String id) async {
    // First check local cache
    final local = _bookings.where((b) => b.id == id).firstOrNull;
    if (local != null) return local;

    // Fetch from Supabase
    try {
      final response = await _client
          .from('bookings')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (response != null) {
        final booking = _bookingFromJson(response);
        // Add to local cache
        _bookings.add(booking);
        notifyListeners();
        return booking;
      }
    } catch (e) {
      debugPrint('Error fetching booking $id: $e');
    }
    return null;
  }

  @override
  Booking createMarketplaceBooking({
    required String listingId,
    required String userId,
    required String userName,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guestCount,
    required double totalPrice,
    required String unitLabel,
  }) {
    final listing = getListingById(listingId);
    if (listing == null) {
      throw Exception('Listing not found');
    }

    // Check for listing conflicts (same seat/room can't be double-booked)
    final listingConflicts = getConflictingBookings(
      listingId: listingId,
      checkIn: checkIn,
      checkOut: checkOut,
    );
    if (listingConflicts.isNotEmpty) {
      throw BookingConflictException(
        'This time slot is already booked by another user',
        conflictType: ConflictType.listing,
        conflictingBookings: listingConflicts,
      );
    }

    // Check for user conflicts (same user can't book multiple places at same time)
    final userConflicts = getUserConflictingBookings(
      userId: userId,
      checkIn: checkIn,
      checkOut: checkOut,
    );
    if (userConflicts.isNotEmpty) {
      throw BookingConflictException(
        'You already have a booking during this time period',
        conflictType: ConflictType.user,
        conflictingBookings: userConflicts,
      );
    }

    final booking = Booking(
      id: 'booking_${DateTime.now().millisecondsSinceEpoch}',
      listingId: listingId,
      userId: userId,
      tenantName: userName,
      startAt: checkIn,
      endAt: checkOut,
      checkIn: checkIn,
      checkOut: checkOut,
      totalPrice: totalPrice,
      unitLabel: unitLabel,
      status: BookingStatus.pending, // New bookings start as pending until host accepts
      guestCount: guestCount,
      createdAt: DateTime.now(),
      listingTitle: listing.title,
      listingImageUrl: listing.primaryImage,
      listingCity: listing.city,
    );

    _bookings.add(booking);
    notifyListeners();

    // Insert async
    _insertMarketplaceBookingAsync(booking);

    return booking;
  }

  Future<void> _insertMarketplaceBookingAsync(Booking booking) async {
    try {
      final data = _bookingToJson(
        listingId: booking.listingId,
        tenantId: booking.userId ?? '',
        tenantName: booking.tenantName,
        startsAt: booking.checkIn ?? booking.startAt,
        endsAt: booking.checkOut ?? booking.endAt,
        totalPrice: booking.totalPrice,
        pricingUnit: booking.unitLabel,
        guestCount: booking.guestCount,
        listingTitle: booking.listingTitle,
        listingImageUrl: booking.listingImageUrl,
        listingCity: booking.listingCity,
      );

      await _client.from('bookings').insert(data);
      await _refreshBookings();
    } catch (e) {
      debugPrint('Error inserting marketplace booking: $e');
    }
  }

  @override
  void cancelBooking(String bookingId) async {
    final index = _bookings.indexWhere((b) => b.id == bookingId);
    if (index != -1) {
      _bookings[index] = _bookings[index].copyWith(
        status: BookingStatus.cancelled,
      );
      notifyListeners();

      try {
        await _client
            .from('bookings')
            .update({'booking_status': 'cancelled'}).eq('id', bookingId);
      } catch (e) {
        debugPrint('Error cancelling booking: $e');
      }
    }
  }

  // ============== Booking Lifecycle Methods ==============

  @override
  Future<void> updateBooking(Booking booking) async {
    final index = _bookings.indexWhere((b) => b.id == booking.id);
    if (index == -1) return;

    // Store original booking for potential rollback
    final originalBooking = _bookings[index];

    // Optimistic update - update local cache immediately (synchronous, so the
    // UI reflects the change before the awaited persist below completes).
    _bookings[index] = booking;
    notifyListeners();

    // Persist to Supabase. Awaited so callers can sequence dependent writes
    // (e.g. booking messages) after the status is committed.
    await _persistBookingUpdate(booking, originalBooking);
  }

  /// Persist booking update to Supabase.
  /// If persistence fails, emits an error to [bookingUpdateErrors] stream
  /// and optionally rolls back the local state.
  Future<void> _persistBookingUpdate(Booking booking, Booking originalBooking) async {
    try {
      final currentUserId = _client.auth.currentUser?.id;
      final updateData = <String, dynamic>{
        'booking_status': booking.status.name,
      };
      debugPrint('[DEBUG-booking] Updating Supabase with: $updateData');
      debugPrint('[DEBUG-booking] Current user: $currentUserId, booking tenant: ${booking.userId}');

      // Add lifecycle fields if present
      if (booking.hostMessage != null) {
        updateData['host_message'] = booking.hostMessage;
      }
      if (booking.rejectionReason != null) {
        updateData['rejection_reason'] = booking.rejectionReason;
      }
      if (booking.confirmedAt != null) {
        updateData['confirmed_at'] = booking.confirmedAt!.toIso8601String();
      }
      if (booking.actualCheckIn != null) {
        updateData['actual_check_in'] = booking.actualCheckIn!.toIso8601String();
      }
      if (booking.completedAt != null) {
        updateData['completed_at'] = booking.completedAt!.toIso8601String();
      }
      if (booking.cancelledBy != null) {
        updateData['cancelled_by'] = booking.cancelledBy;
      }
      if (booking.cancelledAt != null) {
        updateData['cancelled_at'] = booking.cancelledAt!.toIso8601String();
      }

      debugPrint('[DEBUG-booking] Full update data: $updateData');

      final response = await _client.from('bookings').update(updateData).eq('id', booking.id).select();

      // Check if update actually affected any rows
      if (response is List && response.isEmpty) {
        final errorMsg = 'Update failed - you may not have permission to modify this booking';
        debugPrint('[DEBUG-booking] WARNING: No rows updated for ${booking.id}! RLS may be blocking the update.');
        debugPrint('[DEBUG-booking] Check that current user ($currentUserId) is the host of listing ${booking.listingId}');

        // Emit error so UI can notify user
        _bookingUpdateErrorController.add(BookingUpdateError(
          bookingId: booking.id,
          message: errorMsg,
          originalBooking: originalBooking,
        ));

        // Rollback local state
        _rollbackBookingUpdate(booking.id, originalBooking);
      } else {
        debugPrint('[DEBUG-booking] Supabase update SUCCESS for ${booking.id}, response: $response');
      }
    } catch (e, stackTrace) {
      // Log the full error
      debugPrint('[DEBUG-booking] ERROR updating booking ${booking.id}: $e');
      debugPrint('[DEBUG-booking] Stack trace: $stackTrace');

      // Emit error so UI can notify user
      _bookingUpdateErrorController.add(BookingUpdateError(
        bookingId: booking.id,
        message: 'Failed to save booking update. Please try again.',
        originalBooking: originalBooking,
      ));

      // Rollback local state
      _rollbackBookingUpdate(booking.id, originalBooking);
    }
  }

  /// Rollback a failed booking update to the original state
  void _rollbackBookingUpdate(String bookingId, Booking originalBooking) {
    final index = _bookings.indexWhere((b) => b.id == bookingId);
    if (index != -1) {
      debugPrint('[DEBUG-booking] Rolling back booking ${bookingId} to original state');
      _bookings[index] = originalBooking;
      notifyListeners();
    }
  }

  @override
  List<Booking> getPendingBookingsForHost(String hostId) {
    // Get listings owned by this host
    final hostListingIds = _listings
        .where((l) => l.hostId == hostId)
        .map((l) => l.id)
        .toSet();

    return _bookings
        .where((b) =>
            hostListingIds.contains(b.listingId) &&
            b.status == BookingStatus.pending)
        .toList()
      ..sort((a, b) => a.createdAt?.compareTo(b.createdAt ?? DateTime.now()) ?? 0);
  }

  @override
  List<Booking> getBookingsForHost(String hostId) {
    // Get listings owned by this host
    final hostListingIds = _listings
        .where((l) => l.hostId == hostId)
        .map((l) => l.id)
        .toSet();

    return _bookings
        .where((b) => hostListingIds.contains(b.listingId))
        .toList()
      ..sort((a, b) => b.effectiveCheckIn.compareTo(a.effectiveCheckIn));
  }

  @override
  List<Booking> getStaleBookings({Duration? maxAge}) {
    final threshold = maxAge ?? const Duration(hours: 24);
    final cutoff = DateTime.now().subtract(threshold);

    return _bookings
        .where((b) =>
            b.status == BookingStatus.pending &&
            b.createdAt != null &&
            b.createdAt!.isBefore(cutoff))
        .toList();
  }

  // ============== Availability Methods ==============

  @override
  List<Booking> getBookingsForListing(String listingId) {
    return _bookings.where((b) => b.listingId == listingId).toList()
      ..sort((a, b) => a.effectiveCheckIn.compareTo(b.effectiveCheckIn));
  }

  @override
  List<Booking> getActiveBookingsForListing(String listingId) {
    return _bookings
        .where((b) => b.listingId == listingId && b.status.isActive)
        .toList()
      ..sort((a, b) => a.effectiveCheckIn.compareTo(b.effectiveCheckIn));
  }

  @override
  bool isTimeSlotAvailable({
    required String listingId,
    required DateTime checkIn,
    required DateTime checkOut,
  }) {
    final conflicts = getConflictingBookings(
      listingId: listingId,
      checkIn: checkIn,
      checkOut: checkOut,
    );
    return conflicts.isEmpty;
  }

  @override
  List<Booking> getConflictingBookings({
    required String listingId,
    required DateTime checkIn,
    required DateTime checkOut,
  }) {
    final activeBookings = getActiveBookingsForListing(listingId);

    return activeBookings.where((booking) {
      final bookingStart = booking.effectiveCheckIn;
      final bookingEnd = booking.effectiveCheckOut;

      // Two ranges overlap if: start1 < end2 AND start2 < end1
      final hasOverlap =
          checkIn.isBefore(bookingEnd) && bookingStart.isBefore(checkOut);

      return hasOverlap;
    }).toList();
  }

  @override
  List<Booking> getUserConflictingBookings({
    required String userId,
    required DateTime checkIn,
    required DateTime checkOut,
    String? excludeListingId,
  }) {
    // Get all active bookings for this user
    final userBookings = _bookings.where((b) =>
      b.userId == userId &&
      b.status.isActive &&
      (excludeListingId == null || b.listingId != excludeListingId)
    ).toList();

    return userBookings.where((booking) {
      final bookingStart = booking.effectiveCheckIn;
      final bookingEnd = booking.effectiveCheckOut;

      // Check for overlap
      final hasOverlap = checkIn.isBefore(bookingEnd) &&
                         bookingStart.isBefore(checkOut);

      return hasOverlap;
    }).toList();
  }

  @override
  bool canUserBookDuring({
    required String userId,
    required DateTime checkIn,
    required DateTime checkOut,
  }) {
    final conflicts = getUserConflictingBookings(
      userId: userId,
      checkIn: checkIn,
      checkOut: checkOut,
    );
    return conflicts.isEmpty;
  }

  @override
  List<Booking> getUnreviewedCompletedBookings(String userId) {
    // Get all completed bookings for this user
    final completedBookings = _bookings.where((b) =>
      b.userId == userId &&
      b.status == BookingStatus.completed
    ).toList();

    // Filter out bookings that already have a guest review
    return completedBookings.where((booking) {
      final existingReview = _reviews.any((r) =>
        r.bookingId == booking.id &&
        r.reviewerId == userId &&
        r.reviewType == ReviewType.guestToHost
      );
      return !existingReview;
    }).toList()
      ..sort((a, b) => (a.completedAt ?? a.effectiveCheckOut)
          .compareTo(b.completedAt ?? b.effectiveCheckOut));
  }

  /// Manually refresh all data from Supabase
  @override
  Future<void> refresh() async {
    await _refreshAll();
  }

  // ============== Booking Pagination Methods ==============

  @override
  Future<void> resetBookingsPagination(String userId) async {
    _bookings = [];
    _bookingsCursor = null;
    _hasMoreBookings = true;
    _isLoadingBookings = false;
    _currentBookingsUserId = userId;
    notifyListeners();
    await fetchNextBookingsPage(userId);
  }

  @override
  Future<List<Booking>> fetchNextBookingsPage(String userId) async {
    if (_isLoadingBookings || !_hasMoreBookings) {
      return [];
    }

    // If user changed, reset pagination
    if (_currentBookingsUserId != userId) {
      _bookingsCursor = null;
      _hasMoreBookings = true;
      _currentBookingsUserId = userId;
    }

    _isLoadingBookings = true;
    notifyListeners();

    try {
      // Build query with cursor pagination
      var query = _client
          .from('bookings')
          .select()
          .eq('tenant_id', userId);

      // Apply cursor if we have one (fetch items older than cursor)
      if (_bookingsCursor != null) {
        query = query.lt('created_at', _bookingsCursor!.toIso8601String());
      }

      final bookingsResponse = await query
          .order('created_at', ascending: false)
          .limit(_pageSize);

      final newBookings = <Booking>[];

      if ((bookingsResponse as List).isEmpty) {
        _hasMoreBookings = false;
      } else {
        // Parse bookings
        for (final e in bookingsResponse) {
          newBookings.add(_bookingFromJson(e as Map<String, dynamic>));
        }

        // Update cursor to the oldest item's created_at
        final lastItem = bookingsResponse.last as Map<String, dynamic>;
        final createdAtStr = lastItem['created_at'] as String?;
        if (createdAtStr != null) {
          _bookingsCursor = DateTime.parse(createdAtStr);
        }

        // Add to accumulated list (avoid duplicates)
        final existingIds = _bookings.map((b) => b.id).toSet();
        for (final booking in newBookings) {
          if (!existingIds.contains(booking.id)) {
            _bookings.add(booking);
          }
        }

        // Check if we got fewer items than page size (means no more)
        if (bookingsResponse.length < _pageSize) {
          _hasMoreBookings = false;
        }
      }

      _isLoadingBookings = false;
      notifyListeners();
      return newBookings;
    } catch (e) {
      debugPrint('Error fetching bookings page: $e');
      _isLoadingBookings = false;
      notifyListeners();
      return [];
    }
  }

  // ============== Booking Counts ==============

  @override
  Future<Map<String, int>> getBookingCounts(String userId) async {
    try {
      final now = DateTime.now();

      // Fetch all bookings for this user (just id, status, dates for counting)
      final response = await _client
          .from('bookings')
          .select('id, booking_status, starts_at, ends_at')
          .eq('tenant_id', userId);

      int upcoming = 0;
      int current = 0;
      int past = 0;

      for (final row in response as List) {
        // Build a minimal Booking and reuse the single source-of-truth
        // categorization so these badge counts always agree with the lists
        // rendered from getUpcomingBookings/getPastBookings and the tabs.
        final b = Booking(
          id: row['id'] as String,
          listingId: '',
          tenantName: '',
          startAt: DateTime.parse(row['starts_at'] as String),
          endAt: DateTime.parse(row['ends_at'] as String),
          totalPrice: 0,
          unitLabel: 'night',
          status: _bookingStatusFromString(row['booking_status'] as String?),
        );

        if (b.isOngoingAt(now)) {
          current++;
        } else if (b.isPastAt(now)) {
          past++;
        } else if (b.isUpcomingAt(now)) {
          upcoming++;
        }
      }

      _cachedBookingCounts = {
        'upcoming': upcoming,
        'current': current,
        'past': past,
      };

      notifyListeners();
      return _cachedBookingCounts!;
    } catch (e) {
      debugPrint('Error fetching booking counts: $e');
      return {'upcoming': 0, 'current': 0, 'past': 0};
    }
  }
}
