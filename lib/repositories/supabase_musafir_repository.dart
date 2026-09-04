import 'dart:async';

import '../core/state/safe_notifier.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    hide User, RealtimeChannel;
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../data/facility_catalog.dart';
import '../models/availability_block.dart';
import '../models/booking.dart';
import '../models/booking_conflict_exception.dart';
import '../models/booking_contacts.dart';
import '../models/booking_rejected_exception.dart';
import '../models/disbursement.dart';
import '../models/payment_record.dart';
import '../models/payout_method.dart';
import '../models/booking_duration.dart';
import '../models/booking_status.dart';
import '../models/facility.dart';
import '../models/host_verifications.dart';
import '../models/landmark.dart';
import '../models/leaderboard_entry.dart';
import '../models/listing.dart';
import '../models/listing_exact_address.dart';
import '../models/listing_purpose.dart';
import '../models/listing_type.dart';
import '../models/owner_registration_draft.dart';
import '../models/review.dart';
import '../models/search_filters.dart';
import '../models/user.dart';
import '../models/user_role.dart';
import '../services/app_settings_service.dart';
import 'musafir_repository.dart';

/// Supabase-backed implementation of [MusafirRepository].
///
/// This repository fetches and caches data from Supabase PostgreSQL database.
/// It extends [ChangeNotifier] to support reactive UI updates.
class SupabaseMusafirRepository extends ChangeNotifier
    with SafeNotifier
    implements MusafirRepository {
  SupabaseMusafirRepository() {
    _initialize();
  }

  SupabaseClient get _client => Supabase.instance.client;

  // Local cache
  final List<Listing> _listings = [];
  List<Booking> _bookings = [];
  List<Review> _reviews = [];
  final Map<String, User> _users = {};

  // Error notification stream for booking updates
  final _bookingUpdateErrorController =
      StreamController<BookingUpdateError>.broadcast();

  @override
  Stream<BookingUpdateError> get bookingUpdateErrors =>
      _bookingUpdateErrorController.stream;

  // Realtime subscription for bookings
  RealtimeChannel? _bookingsChannel;

  // Pagination state - Listings
  static const int _pageSize = 10;
  int _listingsOffset = 0;
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
    _setupBookingsRealtimeSubscription();
    notifyListeners();
  }

  /// Wipe all cached state and tear down the realtime subscription.
  /// Called on logout so the next user never sees the previous user's data.
  void _clearCaches() {
    _bookingsChannel?.unsubscribe();
    _bookingsChannel = null;
    _listings.clear();
    _bookings = [];
    _reviews = [];
    _users.clear();
    _cachedBookingCounts = null;
    _listingsOffset = 0;
    _hasMoreListings = true;
    _isLoadingListings = false;
    _bookingsCursor = null;
    _hasMoreBookings = true;
    _isLoadingBookings = false;
    _currentBookingsUserId = null;
  }

  /// Clear all cached data on logout.
  void clearSession() {
    _clearCaches();
    notifyListeners();
  }

  /// Re-initialize for a (possibly different) logged-in user: drop the previous
  /// user's cache, refetch, and re-establish the bookings realtime subscription.
  /// The subscription is otherwise only created once in the constructor, so a
  /// session that started logged-out (or a re-login) would never get live
  /// booking updates without this.
  Future<void> resetForAuthChange() async {
    _clearCaches();
    notifyListeners();
    await _initialize();
  }

  /// Set up realtime subscription for booking changes.
  /// This ensures the UI updates when bookings are created/updated from other devices.
  void _setupBookingsRealtimeSubscription() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      debugPrint(
          '[Bookings Realtime] No user logged in, skipping subscription');
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
  void _handleBookingRealtimeChange(Map<String, dynamic> record,
      {required bool isInsert}) {
    try {
      final booking = _bookingFromJson(record);
      final userId = _client.auth.currentUser?.id;

      // Only process if this booking is relevant to the current user
      // (they're the tenant or the host of the listing)
      final isRelevant = booking.userId == userId ||
          _listings.any((l) => l.id == booking.listingId && l.hostId == userId);

      if (!isRelevant) {
        debugPrint(
            '[Bookings Realtime] Ignoring irrelevant booking: ${booking.id}');
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
          debugPrint(
              '[Bookings Realtime] Updated booking: ${booking.id}, status: ${booking.status.name}');
          notifyListeners();
        } else {
          // Booking not in cache, add it
          _bookings.add(booking);
          debugPrint(
              '[Bookings Realtime] Added missing booking: ${booking.id}');
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
      _loadOwnListings(),
      _refreshBookings(),
      _refreshReviews(),
      _refreshBlockedUsers(),
    ]);
  }

  /// Refresh only what [getUnreviewedCompletedBookings] reads.
  ///
  /// The review-prompt check runs on every app resume; routing it through the
  /// full [refresh] made a resume re-fetch the entire catalog, which is both a
  /// wasted round-trip and (before the reset above became non-destructive) a
  /// visible reload of the Explore feed.
  Future<void> refreshBookingsAndReviews() async {
    await Future.wait([_refreshBookings(), _refreshReviews()]);
  }

  // ============== Safety: reports & blocks ==============

  final Set<String> _blockedUserIds = {};

  @override
  Set<String> get blockedUserIds => Set.unmodifiable(_blockedUserIds);

  Future<void> _refreshBlockedUsers() async {
    final userId = _client.auth.currentUser?.id;
    _blockedUserIds.clear();
    if (userId == null) return;
    try {
      final rows = await _client
          .from('user_blocks')
          .select('blocked_id')
          .eq('blocker_id', userId);
      _blockedUserIds
          .addAll((rows as List).map((e) => e['blocked_id'] as String));
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading blocked users: $e');
    }
  }

  @override
  Future<bool> submitReport({
    String? reportedUserId,
    String? listingId,
    String? bookingId,
    required String category,
    String? details,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      await _client.from('reports').insert({
        'reporter_id': userId,
        'reported_user_id': reportedUserId,
        'listing_id': listingId,
        'booking_id': bookingId,
        'category': category,
        'details':
            (details == null || details.trim().isEmpty) ? null : details.trim(),
      });
      return true;
    } catch (e) {
      debugPrint('Error submitting report: $e');
      return false;
    }
  }

  @override
  Future<bool> blockUser(String userId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null || me == userId) return false;
    try {
      await _client.from('user_blocks').upsert(
        {'blocker_id': me, 'blocked_id': userId},
        onConflict: 'blocker_id,blocked_id',
      );
      _blockedUserIds.add(userId);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error blocking user: $e');
      return false;
    }
  }

  @override
  Future<bool> unblockUser(String userId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return false;
    try {
      await _client
          .from('user_blocks')
          .delete()
          .eq('blocker_id', me)
          .eq('blocked_id', userId);
      _blockedUserIds.remove(userId);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error unblocking user: $e');
      return false;
    }
  }

  /// Loads ALL of the signed-in user's own listings into the cache.
  ///
  /// The explore pagination only holds the newest marketplace-wide page, so
  /// a host's listing can easily fall outside it — which made that listing's
  /// bookings invisible on the host screens (Reservations, Dashboard, ...),
  /// since they derive "my listings" from this cache.
  Future<void> _loadOwnListings() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await _client
          .from('listings')
          .select('*, listing_facilities(facility_id, facilities(name))')
          .eq('owner_id', userId);

      final own = (response as List)
          .map((e) => _listingFromJson(e as Map<String, dynamic>))
          .toList();
      if (own.isEmpty) return;

      final ownIds = own.map((l) => l.id).toSet();
      _listings.removeWhere((l) => ownIds.contains(l.id));
      _listings.addAll(own);
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading own listings: $e');
    }
  }

  // ============== Listings ==============

  /// Fetch first page of listings (called on init)
  Future<void> _refreshListings() async {
    await resetListingsPagination();
  }

  @override
  Future<void> resetListingsPagination() async {
    // Fetch BEFORE clearing. Emptying the cache and notifying up front left
    // Explore with `listings.isEmpty && isLoading` for a whole network
    // round-trip, which renders its full-screen spinner — so every refresh
    // (pull-to-refresh, auth change, the resume check) looked like the page had
    // reloaded. Swapping the page in only once it has arrived keeps the current
    // feed on screen throughout.
    if (_isLoadingListings) return;
    _isLoadingListings = true;
    notifyListeners();

    try {
      final page = await searchListingsFromDb(
        const SearchFilters(),
        limit: _pageSize,
        offset: 0,
      );
      // Keep the signed-in user's own listings — host screens depend on them
      // being present regardless of where they rank in the explore feed.
      final ownId = _client.auth.currentUser?.id;
      final own = ownId == null
          ? const <Listing>[]
          : _listings.where((l) => l.hostId == ownId).toList();
      final ownIds = own.map((l) => l.id).toSet();

      _listings
        ..clear()
        ..addAll(own)
        ..addAll(page.listings.where((l) => !ownIds.contains(l.id)));
      _listingsOffset = page.listings.length;
      _hasMoreListings = page.listings.length >= _pageSize;
    } catch (e) {
      // A failed refresh must not empty the feed — keep what is already cached.
      debugPrint('Error resetting listings pagination: $e');
    } finally {
      _isLoadingListings = false;
      notifyListeners();
    }
  }

  @override
  Future<List<Listing>> fetchNextListingsPage() async {
    if (_isLoadingListings || !_hasMoreListings) {
      return [];
    }

    _isLoadingListings = true;
    notifyListeners();

    try {
      // The default feed is an unfiltered search: server-side ranked (rating,
      // reviews, recency), host_available enforced in SQL, offset-paginated.
      final page = await searchListingsFromDb(
        const SearchFilters(),
        limit: _pageSize,
        offset: _listingsOffset,
      );
      final newListings = page.listings;
      _listingsOffset += newListings.length;

      // Add to accumulated list (skip ids already cached, e.g. the user's own
      // listings loaded by _loadOwnListings).
      final existingIds = _listings.map((l) => l.id).toSet();
      _listings.addAll(newListings.where((l) => !existingIds.contains(l.id)));

      if (newListings.length < _pageSize) {
        _hasMoreListings = false;
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

  /// Full-catalog listing search via the `search_listings` RPC. Every filter is
  /// applied server-side and results are ranked (rating desc, reviews desc,
  /// newest). Used both for the default feed (empty filters) and Explore search.
  @override
  Future<ListingSearchResult> searchListingsFromDb(
    SearchFilters filters, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final location = filters.location?.trim();
      // Three anchored modes, in priority order:
      //  1. A purpose landmark → single fixed ring around the place.
      //  2. A geocoded place with a known extent (bounds) → cover exactly that
      //     box, so "Uttara" stays within Uttara and never spills into Tongi.
      //  3. A bare center point (current location, or a place with no box) →
      //     expanding proximity tiers.
      // In every anchored mode the typed text is only a display label —
      // geocoding already resolved it, so it must not also be AND-ed against
      // city/address/title.
      final landmark = filters.landmark;
      final bounds = landmark == null ? filters.bounds : null;
      final hasBounds = bounds != null && bounds.isValid;
      final useTiers = landmark == null &&
          !hasBounds &&
          filters.latitude != null &&
          filters.longitude != null;
      // Expanding proximity rings, and the landmark ring, are admin-configured
      // (app_settings → SearchAreaSettings). Awaited rather than read from the
      // cached getter because startup calls load() unawaited, and the first
      // search can beat it.
      final searchArea = await AppSettingsService.instance.ensureSearchArea();
      final rows = await _client.rpc('search_listings', params: {
        'p_property_types': filters.propertyTypes.isEmpty
            ? null
            : filters.propertyTypes.map((t) => t.name).toList(),
        'p_guest_count': filters.guestCount,
        'p_min_price': filters.minPrice,
        'p_max_price': filters.maxPrice,
        'p_amenities': filters.amenities.isEmpty ? null : filters.amenities,
        // Any anchored search (landmark ring or tiered center point) already
        // has its geography — the typed text (e.g. the landmark's own name)
        // is only a display label and must not also be AND-ed against
        // city/address/title, or it would zero out the results.
        'p_location': (landmark != null ||
                useTiers ||
                hasBounds ||
                location == null ||
                location.isEmpty)
            ? null
            : location,
        'p_limit': limit,
        'p_offset': offset,
        // With a landmark anchor the guest wants everything AROUND the place,
        // distance-ranked — not only listings the host happened to tag with
        // that purpose. Tags only filter when no landmark is set.
        'p_purpose_tags': (landmark != null || filters.purposeTags.isEmpty)
            ? null
            : filters.purposeTags.map((p) => p.wireName).toList(),
        'p_center_lat': landmark?.latitude ?? filters.latitude,
        'p_center_lng': landmark?.longitude ?? filters.longitude,
        'p_radius_m': landmark != null
            ? (filters.radiusMeters ?? searchArea.landmarkRadiusMeters)
            : null,
        'p_radii': useTiers ? searchArea.radiusTiersMeters : null,
        // The place's box. When set, the RPC filters to listings inside it
        // (distance-ranked to the center) and ignores the radius paths.
        'p_ne_lat': hasBounds ? bounds.neLat : null,
        'p_ne_lng': hasBounds ? bounds.neLng : null,
        'p_sw_lat': hasBounds ? bounds.swLat : null,
        'p_sw_lng': hasBounds ? bounds.swLng : null,
      });

      final list = (rows as List).cast<Map<String, dynamic>>();
      final listings = list.map(_listingFromJson).toList();
      final first = list.isEmpty ? null : list.first;
      return ListingSearchResult(
        listings: listings,
        matchedRadiusMeters: (first?['search_radius_m'] as num?)?.toInt(),
        usedNearestFallback: first?['radius_fallback'] as bool? ?? false,
      );
    } catch (e) {
      debugPrint('Error searching listings: $e');
      return const ListingSearchResult(listings: []);
    }
  }

  @override
  Future<List<Landmark>> searchLandmarks({String? query, String? type}) async {
    try {
      final rows = await _client.rpc('search_landmarks', params: {
        'p_query':
            (query == null || query.trim().isEmpty) ? null : query.trim(),
        'p_type': type,
        'p_limit': 30,
      });
      return (rows as List)
          .map((e) => Landmark.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      debugPrint('Error searching landmarks: $e');
      return [];
    }
  }

  @override
  Future<List<Landmark>> nearbyLandmarks({
    required double latitude,
    required double longitude,
    int limit = 5,
    String? type,
  }) async {
    try {
      final rows = await _client.rpc('nearby_landmarks', params: {
        'p_lat': latitude,
        'p_lng': longitude,
        'p_limit': limit,
        'p_type': type,
      });
      return (rows as List)
          .map((e) => Landmark.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      debugPrint('Error fetching nearby landmarks: $e');
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
      hostAvailable: json['host_available'] as bool? ?? true,
      hostId: json['owner_id'] as String?,
      hostAvatarUrl: json['host_avatar_url'] as String?,
      description: json['description'] as String?,
      city: json['city'] as String?,
      country: json['country'] as String?,
      // Normally ABSENT: public.listings no longer has these columns, so a
      // browsing guest gets nulls here. The host and an accepted guest read the
      // real values from public.listing_addresses via
      // fetchListingExactAddress(). Still mapped so any other row shape that
      // does carry them (a local/mock listing) keeps working.
      flatFloor: json['flat_floor'] as String?,
      houseNo: json['house_no'] as String?,
      street: json['street'] as String?,
      area: json['area'] as String?,
      postalCode: json['postal_code'] as String?,
      landmark: json['landmark'] as String?,
      imageUrls: (json['image_urls'] as List?)?.cast<String>() ?? [],
      maxGuests: json['max_guests'] as int? ?? 2,
      bedrooms: json['bedrooms'] as int? ?? 1,
      beds: json['beds'] as int? ?? 1,
      bathrooms: json['bathrooms'] as int? ?? 1,
      rating: (json['rating'] as num?)?.toDouble(),
      reviewCount: json['review_count'] as int? ?? 0,
      isSuperhost: json['is_superhost'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      purposeTags: listingPurposesFromWire(json['purpose_tags']),
      distanceMeters: (json['distance_m'] as num?)?.toDouble(),
      bookingLimits: BookingLimits(
        minHours: json['min_hours'] as int?,
        maxHours: json['max_hours'] as int?,
        minNights: json['min_nights'] as int?,
        maxNights: json['max_nights'] as int?,
        minMonths: json['min_months'] as int?,
        maxMonths: json['max_months'] as int?,
      ),
      houseRules: HouseRules(
        checkInTime: json['check_in_time'] as String?,
        checkOutTime: json['check_out_time'] as String?,
        smokingAllowed: json['smoking_allowed'] as bool? ?? false,
        petsAllowed: json['pets_allowed'] as bool? ?? false,
        partiesAllowed: json['parties_allowed'] as bool? ?? false,
        quietHours: json['quiet_hours'] as String?,
        additionalRules: json['additional_rules'] as String?,
      ),
      // Sensitive check-in details are NOT embedded in the listings query —
      // that coupling would break the whole (guest-facing) explore feed if the
      // table/relationship isn't present. Hosts load them on demand via
      // fetchCheckInDetails() when editing.
    );
  }

  Map<String, dynamic> _listingToJson(Listing listing) {
    return {
      'title': listing.title,
      // `address` is NOT sent: a trigger on public.listings derives it from
      // area/city so the table can never hold a door-level address. The exact
      // line goes to public.listing_addresses via _saveListingExactAddress.
      'listing_type': listing.type.name,
      // Sent exact; the same trigger snaps these to a ~110m grid before they
      // land. The precise point is preserved in public.listing_addresses.
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
      // flat_floor / house_no / street are gone from public.listings — they
      // named a specific door. See _saveListingExactAddress.
      'area': listing.area,
      'postal_code': listing.postalCode,
      'landmark': listing.landmark,
      'purpose_tags': listing.purposeTags.map((p) => p.wireName).toList(),
      'image_urls': listing.imageUrls,
      'max_guests': listing.maxGuests,
      'bedrooms': listing.bedrooms,
      'beds': listing.beds,
      'bathrooms': listing.bathrooms,
      // Per-plan booking limits.
      'min_hours': listing.bookingLimits.minHours,
      'max_hours': listing.bookingLimits.maxHours,
      'min_nights': listing.bookingLimits.minNights,
      'max_nights': listing.bookingLimits.maxNights,
      'min_months': listing.bookingLimits.minMonths,
      'max_months': listing.bookingLimits.maxMonths,
      // House rules (public).
      'check_in_time': listing.houseRules.checkInTime,
      'check_out_time': listing.houseRules.checkOutTime,
      'smoking_allowed': listing.houseRules.smokingAllowed,
      'pets_allowed': listing.houseRules.petsAllowed,
      'parties_allowed': listing.houseRules.partiesAllowed,
      'quiet_hours': listing.houseRules.quietHours,
      'additional_rules': listing.houseRules.additionalRules,
    };
  }

  @override
  Future<CheckInDetails?> fetchCheckInDetails(String listingId) async {
    try {
      final row = await _client
          .from('listing_checkin_details')
          .select()
          .eq('listing_id', listingId)
          .maybeSingle();
      if (row == null) return null;
      return CheckInDetails(
        directions: row['directions'] as String?,
        wifiName: row['wifi_name'] as String?,
        wifiPassword: row['wifi_password'] as String?,
        accessCode: row['access_code'] as String?,
      );
    } catch (e) {
      debugPrint('Error fetching check-in details: $e');
      return null;
    }
  }

  @override
  Future<ListingExactAddress?> fetchListingExactAddress(
      String listingId) async {
    try {
      final row = await _client
          .from('listing_addresses')
          .select()
          .eq('listing_id', listingId)
          .maybeSingle();
      // Null covers both "no row" and "RLS says no" — PostgREST reports a
      // policy refusal as an empty result, not an error. Either way the caller
      // must fall back to the area, so they are the same answer here.
      if (row == null) return null;
      return ListingExactAddress.fromJson(row);
    } catch (e) {
      // Fail closed: a network or policy error must not be read as entitlement.
      debugPrint('Error fetching listing address: $e');
      return null;
    }
  }

  /// Writes the exact address to the gated side table. RLS restricts this to the
  /// listing's owner, so a host editing their own place is the only caller that
  /// can succeed.
  Future<void> _saveListingExactAddress(
      String listingId, Listing listing) async {
    final exact = ListingExactAddress(
      listingId: listingId,
      houseNo: listing.houseNo,
      flatFloor: listing.flatFloor,
      street: listing.street,
      // The composed line, built from the parts the host actually entered —
      // NOT listing.address, which by now may already be the redacted form the
      // server handed back.
      address: Listing.composeAddress(
        houseNo: listing.houseNo,
        flatFloor: listing.flatFloor,
        street: listing.street,
        area: listing.area,
        city: listing.city,
        postalCode: listing.postalCode,
      ),
      latitude: listing.latitude,
      longitude: listing.longitude,
    );

    try {
      await _client.from('listing_addresses').upsert(exact.toJson());
    } catch (e) {
      // Non-fatal: the listing itself saved, and the public area-level location
      // is already correct. Surfacing this would fail an otherwise good edit.
      debugPrint('Error saving listing address: $e');
    }
  }

  @override
  Future<BookingContacts?> fetchBookingContacts(String bookingId) async {
    try {
      final rows = await _client.rpc(
        'get_booking_contacts',
        params: {'p_booking_id': bookingId},
      );
      if (rows is List && rows.isNotEmpty) {
        final r = rows.first as Map<String, dynamic>;
        return BookingContacts(
          guestName: r['guest_name'] as String?,
          guestPhone: r['guest_phone'] as String?,
          hostName: r['host_name'] as String?,
          hostPhone: r['host_phone'] as String?,
        );
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching booking contacts: $e');
      return null;
    }
  }

  /// Upsert the host-only check-in access details for a listing. A null/empty
  /// [details] clears the row.
  Future<void> _saveCheckInDetails(
      String listingId, CheckInDetails? details) async {
    if (details == null || details.isEmpty) {
      await _client
          .from('listing_checkin_details')
          .delete()
          .eq('listing_id', listingId);
      return;
    }
    await _client.from('listing_checkin_details').upsert({
      'listing_id': listingId,
      'directions': details.directions,
      'wifi_name': details.wifiName,
      'wifi_password': details.wifiPassword,
      'access_code': details.accessCode,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
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

      _bookings = (response as List)
          .map((e) => _bookingFromJson(e as Map<String, dynamic>))
          .toList();
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
      paymentStatus: json['payment_status'] as String? ?? 'unpaid',
      paidAt: json['paid_at'] != null
          ? DateTime.parse(json['paid_at'] as String)
          : null,
      paymentMethod: json['payment_method'] as String?,
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
      // Serialize as UTC — a naive local (UTC+6) string is read by the
      // timestamptz column as UTC, shifting every booking 6 hours ahead.
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
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
      // Order newest-first so that if PostgREST's row cap ever truncates the
      // result, the rows kept are the most recent — the ones a user is most
      // likely to be checking against (e.g. "did I already review this stay?").
      final response = await _client
          .from('reviews')
          .select()
          .order('created_at', ascending: false);

      _reviews = (response as List)
          .map((e) => _reviewFromJson(e as Map<String, dynamic>))
          .toList();
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
        communication:
            (json['communication_rating'] as num?)?.toDouble() ?? 0.0,
        location: (json['location_rating'] as num?)?.toDouble() ?? 0.0,
        value: (json['value_rating'] as num?)?.toDouble() ?? 0.0,
      );
    }

    return Review(
      id: json['id'] as String,
      bookingId: json['booking_id'] as String? ?? '',
      listingId: json['listing_id'] as String?,
      reviewerId:
          json['reviewer_id'] as String? ?? json['user_id'] as String? ?? '',
      reviewerName: json['reviewer_name'] as String? ??
          json['user_name'] as String? ??
          'Guest',
      reviewerAvatarUrl: json['reviewer_avatar_url'] as String? ??
          json['user_avatar_url'] as String?,
      revieweeId: json['reviewee_id'] as String? ?? '',
      reviewType: _reviewTypeFromString(json['review_type'] as String?),
      overallRating: (json['overall_rating'] as num?)?.toDouble() ??
          (json['rating'] as num?)?.toDouble() ??
          0.0,
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
    if (review.reviewType == ReviewType.guestToHost &&
        review.categoryRatings != null) {
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
      return listing.available &&
          listing.hostAvailable &&
          insideLat &&
          insideLng;
    }).toList();
  }

  @override
  void registerOwnerListing(OwnerRegistrationDraft draft) async {
    try {
      final data = {
        'owner_name': draft.mobile,
        'title': draft.title,
        // No 'address': a trigger derives public.listings.address from
        // area/city. This legacy quick-register draft carries only a free-text
        // address and no area, so the public label stays blank until the host
        // fills in area/city from the full edit screen — we can't safely guess
        // which part of a typed line is the house number.
        'listing_type': draft.type.name,
        'latitude': draft.latitude,
        'longitude': draft.longitude,
        'hourly_rate': draft.hourlyRate,
        'daily_rate': draft.dailyRate,
        'monthly_rate': draft.monthlyRate,
        'is_active': true,
      };

      final inserted =
          await _client.from('listings').insert(data).select('id').single();

      // The typed address and exact pin go to the gated table rather than being
      // dropped on the floor.
      await _client.from('listing_addresses').upsert({
        'listing_id': inserted['id'],
        'exact_address': draft.address,
        'latitude': draft.latitude,
        'longitude': draft.longitude,
      });

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
        } ??
        0;

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
      // Cross-user lookup → public_profiles view (no PII; see migration 061).
      final response = await _client
          .from('public_profiles')
          .select()
          .eq('id', id)
          .maybeSingle();

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
      if (!listing.hostAvailable) return false;

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
    final available =
        _listings.where((l) => l.available && l.hostAvailable).toList()
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

  /// Replace the full amenity set for a listing in the listing_facilities
  /// join table. Facility rows are matched by name against the facilities
  /// catalog; unknown names are skipped rather than failing the whole save.
  Future<void> _saveListingFacilities(
      String listingId, List<Facility> facilities) async {
    // Clear the existing set first so edits that remove an amenity take effect.
    await _client
        .from('listing_facilities')
        .delete()
        .eq('listing_id', listingId);
    if (facilities.isEmpty) return;

    final catalog = await _client.from('facilities').select('id, name') as List;
    final idByName = <String, String>{
      for (final row in catalog)
        (row['name'] as String).toLowerCase(): row['id'] as String,
    };

    final rows = <Map<String, dynamic>>[];
    for (final f in facilities) {
      final id = idByName[f.name.toLowerCase()];
      if (id != null) {
        rows.add({'listing_id': listingId, 'facility_id': id});
      }
    }
    if (rows.isNotEmpty) {
      await _client.from('listing_facilities').insert(rows);
    }
  }

  @override
  Future<void> addListing(Listing listing) async {
    // Optimistic add for instant UI feedback (carries the client temp id).
    _listings.add(listing);
    notifyListeners();

    try {
      // Insert WITHOUT an id and read back the DB-assigned uuid, so the local
      // cache uses the real id — otherwise the temp-id copy lingers alongside
      // the real row and edits target a non-existent id.
      final inserted = await _client
          .from('listings')
          .insert(_listingToJson(listing))
          .select()
          .single();
      final realId = inserted['id'] as String;

      await _saveListingFacilities(realId, listing.facilities);
      await _saveCheckInDetails(realId, listing.checkInDetails);
      await _saveListingExactAddress(realId, listing);

      // Drop the temp-id copy; _refreshListings brings in the canonical row.
      _listings.removeWhere((l) => l.id == listing.id);
      await _refreshListings();
    } catch (e) {
      // Roll back the optimistic add so a failed create doesn't leave a ghost.
      _listings.removeWhere((l) => l.id == listing.id);
      notifyListeners();
      debugPrint('Error adding listing: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateListing(Listing listing) async {
    final index = _listings.indexWhere((l) => l.id == listing.id);
    if (index == -1) return;

    final previous = _listings[index];
    _listings[index] = listing;
    notifyListeners();

    try {
      await _client
          .from('listings')
          .update(_listingToJson(listing))
          .eq('id', listing.id);
      await _saveListingFacilities(listing.id, listing.facilities);
      await _saveCheckInDetails(listing.id, listing.checkInDetails);
      await _saveListingExactAddress(listing.id, listing);
    } catch (e) {
      // Roll back to the previous value on failure.
      final i = _listings.indexWhere((l) => l.id == listing.id);
      if (i != -1) _listings[i] = previous;
      notifyListeners();
      debugPrint('Error updating listing: $e');
      rethrow;
    }
  }

  @override
  Future<void> setListingAvailability(String listingId, bool available) async {
    final index = _listings.indexWhere((l) => l.id == listingId);
    if (index == -1) return;

    final previous = _listings[index];
    if (previous.available == available) return;
    _listings[index] = previous.copyWith(available: available);
    notifyListeners();

    try {
      await _client
          .from('listings')
          .update({'is_active': available}).eq('id', listingId);
    } catch (e) {
      // Roll back to the previous value on failure.
      final i = _listings.indexWhere((l) => l.id == listingId);
      if (i != -1) _listings[i] = previous;
      notifyListeners();
      debugPrint('Error updating listing availability: $e');
      rethrow;
    }
  }

  @override
  Future<List<AvailabilityBlock>> listingAvailabilityBlocks(
      String listingId) async {
    // Read straight from the table rather than through listing_blocked_ranges:
    // that RPC deliberately withholds `note`, and this is the host's own screen,
    // where the note is the whole point. The owner-scoped SELECT policy on
    // listing_availability_blocks is what makes this safe.
    final rows = await _client
        .from('listing_availability_blocks')
        .select()
        .eq('listing_id', listingId)
        .order('starts_at');
    return (rows as List)
        .map((r) => AvailabilityBlock.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<AvailabilityBlock> blockListingDates({
    required String listingId,
    required DateTime startsAt,
    required DateTime endsAt,
    String? note,
  }) async {
    // Through the RPC, not a direct insert: the table has no INSERT policy, and
    // the "are these dates already booked?" check lives inside the function so
    // it can't be skipped by writing to PostgREST directly.
    final row = await _client.rpc('block_listing_dates', params: {
      'p_listing_id': listingId,
      'p_starts_at': startsAt.toUtc().toIso8601String(),
      'p_ends_at': endsAt.toUtc().toIso8601String(),
      'p_note': note,
    });
    return AvailabilityBlock.fromJson(row as Map<String, dynamic>);
  }

  @override
  Future<void> unblockListingDates(String blockId) async {
    await _client.rpc('unblock_listing_dates', params: {
      'p_block_id': blockId,
    });
  }

  @override
  Future<void> deleteListing(String listingId) async {
    // Refuse to delete a listing that still has live bookings. bookings.listing_id
    // is ON DELETE CASCADE, so deleting would silently destroy guests' pending/
    // confirmed/active reservations with no cancellation or notification.
    final live = await _client
        .from('bookings')
        .select('id')
        .eq('listing_id', listingId)
        .inFilter(
            'booking_status', ['pending', 'confirmed', 'active']).limit(1);
    if ((live as List).isNotEmpty) {
      throw Exception(
        'This listing has active or upcoming bookings. Cancel or complete them '
        'before deleting.',
      );
    }

    final removed = _listings.where((l) => l.id == listingId).toList();
    _listings.removeWhere((l) => l.id == listingId);
    notifyListeners();

    try {
      await _client.from('listings').delete().eq('id', listingId);
    } catch (e) {
      // Restore the optimistic removal so the UI reflects reality.
      _listings.addAll(removed);
      notifyListeners();
      debugPrint('Error deleting listing: $e');
      rethrow;
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
        final avgRating = reviews.map((r) => r.rating).reduce((a, b) => a + b) /
            reviews.length;
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
  Future<bool> saveReview(Review review) async {
    _reviews.add(review);
    notifyListeners();

    try {
      // Upsert on the (booking, reviewer, type) unique key so retrying a
      // submission never fails with a duplicate error.
      await _client.from('reviews').upsert(
            _reviewToJson(review),
            onConflict: 'booking_id,reviewer_id,review_type',
          );
      await _refreshReviews();
      return true;
    } catch (e) {
      debugPrint('Error saving review: $e');
      // Roll back the optimistic local copy so the UI reflects reality.
      _reviews.removeWhere((r) => r.id == review.id);
      notifyListeners();
      return false;
    }
  }

  @override
  Future<String?> fetchHostIdForListing(String listingId) async {
    final cached = getListingById(listingId)?.hostId;
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      // The listings cache is paginated and RLS hides inactive listings, so
      // resolve the owner through a definer function that also covers
      // listings the caller has booked.
      final result = await _client.rpc(
        'get_listing_owner',
        params: {'p_listing_id': listingId},
      );
      final hostId = result as String?;
      return (hostId != null && hostId.isNotEmpty) ? hostId : null;
    } catch (e) {
      debugPrint('Error fetching listing owner: $e');
      return null;
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

  /// Fetch booking directly from Supabase (async version for when local cache
  /// misses). With [forceRefresh] the server is always consulted and the
  /// cached row replaced — use when the status must be authoritative (e.g.
  /// deciding whether a booking request is still pending).
  Future<Booking?> fetchBookingById(String id,
      {bool forceRefresh = false}) async {
    final local = _bookings.where((b) => b.id == id).firstOrNull;
    if (local != null && !forceRefresh) return local;

    // Fetch from Supabase
    try {
      final response =
          await _client.from('bookings').select().eq('id', id).maybeSingle();

      if (response != null) {
        final booking = _bookingFromJson(response);
        _bookings.removeWhere((b) => b.id == id);
        _bookings.add(booking);
        notifyListeners();
        return booking;
      }
    } catch (e) {
      debugPrint('Error fetching booking $id: $e');
    }
    return local;
  }

  @override
  Future<bool> isHostAvailable(String hostId) async {
    // Trust a cached profile if we have it; otherwise check the server.
    final cached = getUserById(hostId);
    if (cached != null) return cached.hostAvailable;
    try {
      final row = await _client
          .from('public_profiles')
          .select('is_available')
          .eq('id', hostId)
          .maybeSingle();
      return row?['is_available'] as bool? ?? true;
    } catch (e) {
      debugPrint('Error checking host availability: $e');
      return true; // fail-open: don't block booking on a lookup error
    }
  }

  @override
  Future<HostVerifications> fetchHostVerifications(String hostId) async {
    // Cross-user read → public_profiles, which carries the three flags and no
    // document detail (migration 094). The base `profiles` table is own-row
    // only under RLS (061), so a guest asking about a host must come here.
    try {
      final row = await _client
          .from('public_profiles')
          .select('phone_verified, identity_verified, address_verified')
          .eq('id', hostId)
          .maybeSingle();
      if (row == null) return HostVerifications.none;
      return HostVerifications.fromJson(row);
    } catch (e) {
      debugPrint('Error fetching host verifications: $e');
      // Fail CLOSED, unlike availability above: a lookup error must not paint
      // badges the database never granted.
      return HostVerifications.none;
    }
  }

  @override
  Future<List<LeaderboardEntry>> getHostLeaderboard({
    required LeaderboardPeriod period,
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final rows = await _client.rpc('get_host_leaderboard', params: {
        'p_period': period.apiValue,
        'p_limit': limit,
        'p_offset': offset,
      });
      return (rows as List)
          .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching host leaderboard: $e');
      return [];
    }
  }

  @override
  Future<LeaderboardEntry?> getMyHostRank({
    required String hostId,
    required LeaderboardPeriod period,
  }) async {
    try {
      final rows = await _client.rpc('get_host_rank', params: {
        'p_host_id': hostId,
        'p_period': period.apiValue,
      });
      final list = rows as List;
      if (list.isEmpty) return null;
      return LeaderboardEntry.fromJson(list.first as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Error fetching host rank: $e');
      return null;
    }
  }

  @override
  @override
  Future<List<PaymentRecord>> fetchUserPayments(String userId) async {
    try {
      final rows = await _client
          .from('payments')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return (rows as List)
          .map(
              (r) => PaymentRecord.fromJson((r as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      debugPrint('Error fetching user payments: $e');
      return [];
    }
  }

  @override
  Future<bool> isBookingAvailable({
    required String listingId,
    required DateTime checkIn,
    required DateTime checkOut,
  }) async {
    // Server-authoritative: the RPC sees ALL bookings (SECURITY-independent read
    // of the whole table), so it detects other guests' bookings that RLS keeps
    // out of this client's local cache.
    final available = await _client.rpc('is_booking_available', params: {
      'p_listing_id': listingId,
      'p_starts_at': checkIn.toUtc().toIso8601String(),
      'p_ends_at': checkOut.toUtc().toIso8601String(),
    });
    return available == true;
  }

  @override
  Future<Booking> createMarketplaceBooking({
    required String listingId,
    required String userId,
    required String userName,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guestCount,
    required double totalPrice,
    required String unitLabel,
    // Coupon applied at checkout (already server-validated). [totalPrice] is the
    // final, discounted amount; [discountAmount] is what the coupon took off.
    String? couponCode,
    double discountAmount = 0,
    String? couponId,
  }) async {
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
      status: BookingStatus
          .pending, // New bookings start as pending until host accepts
      guestCount: guestCount,
      createdAt: DateTime.now(),
      listingTitle: listing.title,
      listingImageUrl: listing.primaryImage,
      listingCity: listing.city,
    );

    _bookings.add(booking);
    notifyListeners();

    // Await the insert so a failure (offline, RLS, overlap constraint, or a
    // server-side price/coupon rejection) is surfaced to the caller instead of
    // leaving a phantom local booking that the host never received. Roll back
    // the optimistic add on failure.
    try {
      final result = await _insertMarketplaceBooking(
        booking,
        couponCode: couponCode,
        discountAmount: discountAmount,
        couponId: couponId,
      );
      // Reconcile the optimistic booking with the server's authoritative id and
      // price (the server, not the client, decides the money now).
      final reconciled = booking.copyWith(
        id: result.id,
        totalPrice: result.totalPrice,
      );
      final i = _bookings.indexWhere((b) => b.id == booking.id);
      if (i != -1) _bookings[i] = reconciled;
      notifyListeners();
      return reconciled;
    } catch (e) {
      _bookings.removeWhere((b) => b.id == booking.id);
      notifyListeners();
      // Always log the raw failure. Every branch below narrows it to something
      // showable, and the fallback rethrow reaches a generic banner — so this
      // line is the only place the server's actual words survive. A booking
      // that "just fails" with no trace is undiagnosable from a bug report.
      debugPrint('createMarketplaceBooking failed: $e');
      // Translate the server's conflict (the manual guard AND the
      // bookings_no_overlap exclusion constraint both raise SQLSTATE 23P01) into
      // a typed BookingConflictException, so the UI shows a specific "slot was
      // just taken" message instead of a generic failure. Without this the
      // server race-loss surfaces as a bare PostgrestException → generic banner.
      if (e is PostgrestException && e.code == '23P01') {
        // Which of the two sentences to show is decided by
        // [bookingConflictTypeFrom] — a pure function with its own tests —
        // rather than by grepping the server's English here, which is how a
        // reworded migration used to be able to silently flip the message.
        final conflictType =
            bookingConflictTypeFrom(hint: e.hint, message: e.message);
        final isUserConflict = conflictType == ConflictType.user;
        throw BookingConflictException(
          isUserConflict
              ? 'You already have a booking during this time period'
              : 'This time slot was just booked by someone else',
          conflictType: conflictType,
          // The conflicting booking belongs to another guest — RLS keeps it out
          // of this client, so there is nothing to list.
          conflictingBookings: const [],
        );
      }
      // The RPC's other refusals are raised with guest-facing sentences under
      // three deliberate SQLSTATEs: 22023 (capacity, dates, duration, an
      // unbookable rate, a rejected coupon), P0002 (listing vanished) and 42501
      // (session expired mid-booking). Those explain exactly which field to
      // change, so pass the server's own words through instead of flattening
      // them. Anything else is a fault, not a refusal — it keeps the generic
      // banner, because its text is for us, not the guest.
      if (e is PostgrestException && isGuestFacingBookingRefusal(e.code)) {
        throw BookingRejectedException(e.message, code: e.code);
      }
      rethrow;
    }
  }

  /// Creates the booking through the server-authoritative
  /// `create_marketplace_booking` RPC. The server recomputes the price from the
  /// listing's own rates and the reserved interval (the client no longer sets
  /// `total_price`), validates + applies the coupon, checks conflicts, and
  /// records the redemption — all in one transaction. Returns the server's
  /// authoritative id and total so the optimistic booking can be reconciled.
  ///
  /// [couponCode] is passed straight to the server, which re-validates it; the
  /// client-side [couponId]/[discountAmount] are no longer trusted for money.
  Future<({String id, double totalPrice, double discountAmount})>
      _insertMarketplaceBooking(
    Booking booking, {
    String? couponCode,
    double discountAmount = 0,
    String? couponId,
  }) async {
    final row = await _client.rpc('create_marketplace_booking', params: {
      'p_listing_id': booking.listingId,
      // Serialize as UTC — a naive local (UTC+6) string is read by the
      // timestamptz column as UTC, shifting every booking 6 hours ahead.
      'p_starts_at':
          (booking.checkIn ?? booking.startAt).toUtc().toIso8601String(),
      'p_ends_at':
          (booking.checkOut ?? booking.endAt).toUtc().toIso8601String(),
      'p_pricing_unit': booking.unitLabel,
      'p_guest_count': booking.guestCount,
      'p_tenant_name': booking.tenantName,
      'p_coupon_code':
          (couponCode != null && couponCode.isNotEmpty) ? couponCode : null,
      'p_listing_image_url': booking.listingImageUrl,
    });

    final data = (row as Map).cast<String, dynamic>();
    await _refreshBookings();
    return (
      id: data['id'] as String,
      totalPrice:
          (data['total_price'] as num?)?.toDouble() ?? booking.totalPrice,
      discountAmount: (data['discount_amount'] as num?)?.toDouble() ?? 0,
    );
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
  Future<void> _persistBookingUpdate(
      Booking booking, Booking originalBooking) async {
    try {
      final currentUserId = _client.auth.currentUser?.id;
      final updateData = <String, dynamic>{
        'booking_status': booking.status.name,
      };
      debugPrint('[DEBUG-booking] Updating Supabase with: $updateData');
      debugPrint(
          '[DEBUG-booking] Current user: $currentUserId, booking tenant: ${booking.userId}');

      // Add lifecycle fields if present
      if (booking.hostMessage != null) {
        updateData['host_message'] = booking.hostMessage;
      }
      if (booking.rejectionReason != null) {
        updateData['rejection_reason'] = booking.rejectionReason;
      }
      // Milestone timestamps come from DateTime.now() (local, UTC+6 here);
      // serialize as UTC or Postgres reads them 6 hours in the future.
      if (booking.confirmedAt != null) {
        updateData['confirmed_at'] =
            booking.confirmedAt!.toUtc().toIso8601String();
      }
      if (booking.actualCheckIn != null) {
        updateData['actual_check_in'] =
            booking.actualCheckIn!.toUtc().toIso8601String();
      }
      if (booking.completedAt != null) {
        updateData['completed_at'] =
            booking.completedAt!.toUtc().toIso8601String();
      }
      if (booking.cancelledBy != null) {
        updateData['cancelled_by'] = booking.cancelledBy;
      }
      if (booking.cancelledAt != null) {
        updateData['cancelled_at'] =
            booking.cancelledAt!.toUtc().toIso8601String();
      }

      debugPrint('[DEBUG-booking] Full update data: $updateData');

      final response = await _client
          .from('bookings')
          .update(updateData)
          .eq('id', booking.id)
          .select();

      // Check if update actually affected any rows
      if (response.isEmpty) {
        final errorMsg =
            'Update failed - you may not have permission to modify this booking';
        debugPrint(
            '[DEBUG-booking] WARNING: No rows updated for ${booking.id}! RLS may be blocking the update.');
        debugPrint(
            '[DEBUG-booking] Check that current user ($currentUserId) is the host of listing ${booking.listingId}');

        // Emit error so UI can notify user
        _bookingUpdateErrorController.add(BookingUpdateError(
          bookingId: booking.id,
          message: errorMsg,
          originalBooking: originalBooking,
        ));

        // Rollback local state
        _rollbackBookingUpdate(booking.id, originalBooking);
      } else {
        debugPrint(
            '[DEBUG-booking] Supabase update SUCCESS for ${booking.id}, response: $response');
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
      debugPrint(
          '[DEBUG-booking] Rolling back booking $bookingId to original state');
      _bookings[index] = originalBooking;
      notifyListeners();
    }
  }

  @override
  List<Booking> getPendingBookingsForHost(String hostId) {
    // Get listings owned by this host
    final hostListingIds =
        _listings.where((l) => l.hostId == hostId).map((l) => l.id).toSet();

    return _bookings
        .where((b) =>
            hostListingIds.contains(b.listingId) &&
            b.status == BookingStatus.pending)
        .toList()
      ..sort(
          (a, b) => a.createdAt?.compareTo(b.createdAt ?? DateTime.now()) ?? 0);
  }

  @override
  List<Booking> getBookingsForHost(String hostId) {
    // Get listings owned by this host
    final hostListingIds =
        _listings.where((l) => l.hostId == hostId).map((l) => l.id).toSet();

    return _bookings.where((b) => hostListingIds.contains(b.listingId)).toList()
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
    final userBookings = _bookings
        .where((b) =>
            b.userId == userId &&
            b.status.isActive &&
            (excludeListingId == null || b.listingId != excludeListingId))
        .toList();

    return userBookings.where((booking) {
      final bookingStart = booking.effectiveCheckIn;
      final bookingEnd = booking.effectiveCheckOut;

      // Check for overlap
      final hasOverlap =
          checkIn.isBefore(bookingEnd) && bookingStart.isBefore(checkOut);

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
    final completedBookings = _bookings
        .where((b) => b.userId == userId && b.status == BookingStatus.completed)
        .toList();

    // Filter out bookings that already have a guest review
    return completedBookings.where((booking) {
      final existingReview = _reviews.any((r) =>
          r.bookingId == booking.id &&
          r.reviewerId == userId &&
          r.reviewType == ReviewType.guestToHost);
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
    // Only drop this tenant's own bookings. The cache also holds bookings
    // for listings the user HOSTS (loaded by _refreshBookings); wiping those
    // here made accepted reservations vanish from the host's Reservations
    // tab whenever the guest-mode Trips tab (re)loaded its pages.
    _bookings.removeWhere((b) => b.userId == userId);
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
      var query = _client.from('bookings').select().eq('tenant_id', userId);

      // Apply cursor if we have one (fetch items older than cursor)
      if (_bookingsCursor != null) {
        query = query.lt('created_at', _bookingsCursor!.toIso8601String());
      }

      final bookingsResponse =
          await query.order('created_at', ascending: false).limit(_pageSize);

      final newBookings = <Booking>[];

      if ((bookingsResponse as List).isEmpty) {
        _hasMoreBookings = false;
      } else {
        // Parse bookings
        for (final e in bookingsResponse) {
          newBookings.add(_bookingFromJson(e));
        }

        // Update cursor to the oldest item's created_at
        final lastItem = bookingsResponse.last;
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

  // ── Payout methods & disbursements (migration 100) ─────────────────────────

  @override
  Future<List<PayoutMethod>> fetchPayoutMethods(String userId) async {
    try {
      final rows = await _client
          .from('payout_methods')
          .select()
          .eq('user_id', userId)
          .isFilter('retired_at', null)
          .order('is_default', ascending: false)
          .order('created_at');
      return (rows as List)
          .map((r) => PayoutMethod.fromJson((r as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      debugPrint('Error fetching payout methods: $e');
      return [];
    }
  }

  @override
  Future<String?> addPayoutMethod({
    required PayoutChannel channel,
    required String accountName,
    required String accountNumber,
    String? bankName,
    String? branchName,
    String? routingNumber,
  }) async {
    return _payoutRpc('add_payout_method', {
      'p_channel': channel.wireName,
      'p_account_name': accountName,
      'p_account_number': accountNumber,
      'p_bank_name': bankName,
      'p_branch_name': branchName,
      'p_routing_number': routingNumber,
    });
  }

  @override
  Future<String?> setDefaultPayoutMethod(String payoutMethodId) =>
      _payoutRpc('set_default_payout_method', {'p_id': payoutMethodId});

  @override
  Future<String?> retirePayoutMethod(String payoutMethodId) =>
      _payoutRpc('retire_payout_method', {'p_id': payoutMethodId});

  /// Calls a payout RPC and turns whatever comes back into either null
  /// (success) or a sentence worth showing someone.
  ///
  /// The RPCs in migration 100 raise with deliberately user-facing messages
  /// ("you have already added that account"), because the alternative — a
  /// generic "Something went wrong" over a specific, fixable problem — is how
  /// a user ends up adding the same wallet four times. Anything that is NOT
  /// one of those deliberate raises (a network drop, a missing migration) is
  /// logged and reported generically, since its text is for us, not them.
  Future<String?> _payoutRpc(String fn, Map<String, dynamic> params) async {
    try {
      await _client.rpc(fn, params: params);
      return null;
    } on PostgrestException catch (e) {
      debugPrint('Payout RPC $fn failed: ${e.code} ${e.message}');
      // 22023 invalid_parameter_value, 23505 unique_violation and 42501
      // insufficient_privilege are the codes the RPCs raise on purpose; their
      // messages are written to be read by the person who caused them.
      const speakable = {'22023', '23505', '42501'};
      if (speakable.contains(e.code) && e.message.trim().isNotEmpty) {
        return e.message;
      }
      // PGRST202 = the function isn't there. Almost always migration 100 has
      // not been applied to this environment, which is worth saying plainly
      // rather than dressing up as a payment failure.
      if (e.code == 'PGRST202') {
        return 'Payouts aren\'t set up on this server yet.';
      }
      return 'Could not save that right now. Please try again.';
    } catch (e) {
      debugPrint('Payout RPC $fn failed: $e');
      return 'Could not save that right now. Please try again.';
    }
  }

  @override
  Future<List<Disbursement>> fetchDisbursements(String userId) async {
    try {
      // The joined method is what makes a row readable — "৳8,000 to bKash
      // ••••5678" instead of "৳8,000 to some uuid". Because payout methods are
      // immutable, this join can never rewrite where a past payout went.
      final rows = await _client
          .from('disbursements')
          .select('*, payout_methods(*)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return (rows as List)
          .map((r) => Disbursement.fromJson((r as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      debugPrint('Error fetching disbursements: $e');
      return [];
    }
  }
}
