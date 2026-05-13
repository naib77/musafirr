import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../data/facility_catalog.dart';
import '../models/booking.dart';
import '../models/booking_duration.dart';
import '../models/booking_status.dart';
import '../models/facility.dart';
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
class SupabaseMusafirRepository extends ChangeNotifier
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

  bool _initialized = false;

  Future<void> _initialize() async {
    await _refreshAll();
    _initialized = true;
    notifyListeners();
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _refreshListings(),
      _refreshBookings(),
      _refreshReviews(),
    ]);
  }

  // ============== Listings ==============

  Future<void> _refreshListings() async {
    try {
      final response = await _client
          .from('listings')
          .select('*, listing_facilities(facility_id, facilities(name))')
          .eq('is_active', true);

      _listings = (response as List).map((e) => _listingFromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching listings: $e');
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
      hourlyRate: (json['hourly_rate'] as num?)?.toDouble() ?? 0.0,
      dailyRate: (json['daily_rate'] as num?)?.toDouble() ?? 0.0,
      monthlyRate: (json['monthly_rate'] as num?)?.toDouble() ?? 0.0,
      facilities: facilities,
      available: json['is_active'] as bool? ?? true,
      hostId: json['owner_id'] as String?,
      hostAvatarUrl: json['host_avatar_url'] as String?,
      description: json['description'] as String?,
      city: json['city'] as String?,
      country: json['country'] as String?,
      pricePerNight: (json['daily_rate'] as num?)?.toDouble(),
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
      final response = await _client.from('bookings').select();

      _bookings = (response as List).map((e) => _bookingFromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching bookings: $e');
    }
  }

  Booking _bookingFromJson(Map<String, dynamic> json) {
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
      'booking_status': 'confirmed',
      'listing_title': listingTitle,
      'listing_image_url': listingImageUrl,
      'listing_city': listingCity,
    };
  }

  BookingStatus _bookingStatusFromString(String? value) {
    return switch (value?.toLowerCase()) {
      'pending' => BookingStatus.pending,
      'confirmed' => BookingStatus.confirmed,
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
    return Review(
      id: json['id'] as String,
      listingId: json['listing_id'] as String,
      userId: json['user_id'] as String,
      userName: json['user_name'] as String? ?? 'Guest',
      userAvatarUrl: json['user_avatar_url'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      comment: json['comment'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
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
    };

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

    // Update listing rating locally
    final listing = getListingById(review.listingId);
    if (listing != null) {
      final reviews = getReviewsForListing(review.listingId);
      final avgRating =
          reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;
      final index = _listings.indexOf(listing);
      _listings[index] = listing.copyWith(
        rating: avgRating,
        reviewCount: reviews.length,
      );
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
        .where((b) =>
            b.userId == userId &&
            b.status.isActive &&
            b.effectiveCheckIn.isAfter(now))
        .toList()
      ..sort((a, b) => a.effectiveCheckIn.compareTo(b.effectiveCheckIn));
  }

  @override
  List<Booking> getPastBookings(String userId) {
    final now = DateTime.now();
    return _bookings
        .where((b) =>
            b.userId == userId &&
            (b.status.isPast || b.effectiveCheckOut.isBefore(now)))
        .toList()
      ..sort((a, b) => b.effectiveCheckIn.compareTo(a.effectiveCheckIn));
  }

  @override
  Booking? getBookingById(String id) {
    return _bookings.where((b) => b.id == id).firstOrNull;
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
      status: BookingStatus.confirmed,
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

  /// Manually refresh all data from Supabase
  Future<void> refresh() async {
    await _refreshAll();
  }
}
