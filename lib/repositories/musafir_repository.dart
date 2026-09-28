import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/availability_block.dart';
import '../models/booking.dart';
import '../models/booking_contacts.dart';
import '../models/booking_duration.dart';
import '../models/disbursement.dart';
import '../models/host_verifications.dart';
import '../models/listing_exact_address.dart';
import '../models/landmark.dart';
import '../models/leaderboard_entry.dart';
import '../models/listing.dart';
import '../models/owner_registration_draft.dart';
import '../models/payment_record.dart';
import '../models/payout_method.dart';
import '../models/review.dart';
import '../models/search_filters.dart';
import '../models/user.dart';
import '../services/booking/booking_lifecycle_service.dart';

/// Error information for failed booking updates
class BookingUpdateError {
  BookingUpdateError({
    required this.bookingId,
    required this.message,
    this.originalBooking,
  });

  final String bookingId;
  final String message;
  final Booking? originalBooking;
}

/// Result of a full-catalog listing search: the listings plus proximity
/// metadata when the search ran with a center point and expanding radius
/// tiers (see [MusafirRepository.searchListingsFromDb]).
class ListingSearchResult {
  const ListingSearchResult({
    required this.listings,
    this.matchedRadiusMeters,
    this.usedNearestFallback = false,
  });

  final List<Listing> listings;

  /// The smallest radius tier (in meters) that contained results, when a
  /// tiered proximity search ran. Null for non-proximity searches and for the
  /// nearest fallback.
  final int? matchedRadiusMeters;

  /// True when no tier contained a match and [listings] are simply the
  /// nearest stays regardless of distance.
  final bool usedNearestFallback;
}

/// Abstract repository interface for Musafir data operations.
///
/// Extends [Listenable] to support reactive UI updates via [ListenableBuilder].
/// Implements [BookingStore] for compatibility with [BookingLifecycleService].
/// Implementations should call [notifyListeners] after data mutations.
abstract class MusafirRepository implements Listenable, BookingStore {
  // Existing getters
  List<Listing> get listings;
  List<Booking> get bookings;
  int get availableCount;
  int get ownerCount;

  // Existing methods
  List<Listing> searchByArea({
    required double centerLat,
    required double centerLng,
    required double delta,
  });

  void registerOwnerListing(OwnerRegistrationDraft draft);

  Booking createBooking({
    required Listing listing,
    required String tenantName,
    required BookingDuration duration,
  });

  // New marketplace methods

  // User methods
  User? getUserById(String id);
  User? getUserByEmail(String email);
  void addUser(User user);

  /// Whether a host is currently accepting bookings (host-wide availability).
  /// Defaults to true if the host can't be resolved.
  Future<bool> isHostAvailable(String hostId);

  /// The host's verified-credential flags, for the trust badges on a listing
  /// page. Returns [HostVerifications.none] when the host can't be resolved —
  /// a lookup failure must never present as a verified host.
  Future<HostVerifications> fetchHostVerifications(String hostId);

  /// Ranked hosts for the public leaderboard (composite "Host Score").
  /// Computed server-side; the app only reads the ranked rows.
  Future<List<LeaderboardEntry>> getHostLeaderboard({
    required LeaderboardPeriod period,
    int limit,
    int offset,
  });

  /// This host's own leaderboard rank, or null if they aren't ranked yet
  /// (e.g. no completed bookings, or opted out).
  Future<LeaderboardEntry?> getMyHostRank({
    required String hostId,
    required LeaderboardPeriod period,
  });

  // Listing methods
  Listing? getListingById(String id);

  /// One listing fetched from the database, whether or not it is cached.
  ///
  /// [getListingById] only ever reads the in-memory cache, which holds the
  /// newest page of the feed plus the signed-in user's own listings — so it
  /// answers null for a listing opened from a shared `/listing/<id>` link in a
  /// cold tab. Null here means genuinely not found or not visible: the SELECT
  /// policy shows only `is_active` listings to anyone but the owner.
  Future<Listing?> fetchListingById(String id);

  List<Listing> searchListings(SearchFilters filters);

  /// Full-catalog listing search via the server-side `search_listings` RPC.
  /// Applies every filter in SQL and returns results ranked by rating, then
  /// review count, then recency. Unlike [searchListings] (which only filters
  /// listings already paginated into memory) this searches the whole catalog.
  ///
  /// When the filters carry a center point (a geocoded place or the guest's
  /// current location, without a purpose landmark) the search expands through
  /// radius tiers (1 → 3 → 5 → 10 km) and returns the first tier with matches,
  /// falling back to the nearest stays — the result's metadata says which.
  Future<ListingSearchResult> searchListingsFromDb(
    SearchFilters filters, {
    int limit,
    int offset,
  });
  List<Listing> getFeaturedListings({int limit = 10});
  List<Listing> getListingsByHost(String hostId);
  Future<void> addListing(Listing listing);
  Future<void> updateListing(Listing listing);
  Future<void> deleteListing(String listingId);

  /// Flips only a listing's visibility (`is_active`). Unlike [updateListing]
  /// this never touches the facilities or check-in-details tables, so the
  /// Hide/Show toggle can't wipe check-in details (which aren't loaded into the
  /// in-memory listing) or get rolled back by an unrelated secondary write.
  Future<void> setListingAvailability(String listingId, bool available);

  /// The host's own blocked date ranges for a listing, earliest first.
  ///
  /// Owner-only: the rows carry the host's private `note`, so the table's
  /// SELECT policy is scoped to the listing's owner. A guest asking the same
  /// question goes through `is_booking_available`, which answers yes/no without
  /// revealing why.
  Future<List<AvailabilityBlock>> listingAvailabilityBlocks(String listingId);

  /// Marks [startsAt]–[endsAt] unavailable on a listing the caller owns.
  ///
  /// Throws if the range already holds a pending/confirmed/active booking —
  /// the host has to decline that booking explicitly rather than have it
  /// quietly stranded behind a block — or if it overlaps a block they already
  /// have.
  Future<AvailabilityBlock> blockListingDates({
    required String listingId,
    required DateTime startsAt,
    required DateTime endsAt,
    String? note,
  });

  /// Removes one block. Only the owning host (or an admin) can.
  Future<void> unblockListingDates(String blockId);

  /// Loads the host-only check-in access details for a listing (or null if
  /// none / not the owner). Kept separate from the main listing fetch so the
  /// guest-facing explore feed never depends on this private table.
  Future<CheckInDetails?> fetchCheckInDetails(String listingId);

  /// A listing's real street address and coordinates, or null when the caller
  /// isn't entitled to them.
  ///
  /// `public.listings` only ever carries the area-level address and coordinates
  /// snapped to a ~110m grid; the precise values live in
  /// `public.listing_addresses` behind RLS that admits the host, an admin, or a
  /// guest with a confirmed/active/completed booking. A null here is the server
  /// declining, not a failure — fall back to the area.
  Future<ListingExactAddress?> fetchListingExactAddress(String listingId);

  /// Contact phone numbers for both parties of a confirmed booking (the guest's
  /// and host's login numbers). Returns null if the booking isn't confirmed yet
  /// or the caller isn't a participant. Backed by the `get_booking_contacts`
  /// SECURITY DEFINER RPC, which enforces those rules.
  Future<BookingContacts?> fetchBookingContacts(String bookingId);

  // Safety: reports & blocks (migration 088)

  /// Files a report against a user / listing / booking for the admin safety
  /// queue. Returns true on success.
  Future<bool> submitReport({
    String? reportedUserId,
    String? listingId,
    String? bookingId,
    required String category,
    String? details,
  });

  /// User ids the signed-in user has blocked. Loaded at startup; the app
  /// hides blocked users' listings and conversations.
  Set<String> get blockedUserIds;
  Future<bool> blockUser(String userId);
  Future<bool> unblockUser(String userId);

  // Review methods (legacy - for simple listing reviews)
  List<Review> getReviewsForListing(String listingId);
  void addReview(Review review);
  double getAverageRating(String listingId);

  // Bidirectional review methods
  List<Review> getReviewsForBooking(String bookingId);
  List<Review> getRevealedReviewsForListing(String listingId);
  List<Review> getRevealedReviewsForGuest(String guestId);

  /// Persists a review. Returns false if saving failed (e.g. network or
  /// permission error) so callers can surface the failure to the user.
  Future<bool> saveReview(Review review);

  /// Resolves the host (owner) of a listing, even when the listing is not in
  /// the local cache or is no longer active (e.g. reviewing an old stay).
  Future<String?> fetchHostIdForListing(String listingId);
  void updateReview(Review review);

  // Booking methods
  List<Booking> getBookingsForUser(String userId);
  List<Booking> getUpcomingBookings(String userId);
  List<Booking> getPastBookings(String userId);
  @override
  Booking? getBookingById(String id);
  Future<Booking> createMarketplaceBooking({
    required String listingId,
    required String userId,
    required String userName,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guestCount,
    required double totalPrice,
    required String unitLabel,
    String? couponCode,
    double discountAmount,
    String? couponId,
  });
  void cancelBooking(String bookingId);

  // Booking lifecycle methods
  /// Persists a booking update. Returns a future that completes when the
  /// remote write finishes — await it before performing actions that depend on
  /// the new status being committed (e.g. sending booking messages gated by
  /// RLS on booking status). Safe to call fire-and-forget for optimistic UI.
  @override
  Future<void> updateBooking(Booking booking);
  List<Booking> getPendingBookingsForHost(String hostId);
  List<Booking> getBookingsForHost(String hostId);
  List<Booking> getStaleBookings({Duration? maxAge});

  /// Stream of booking update errors. Subscribe to this to show error
  /// notifications to the user when optimistic updates fail to persist.
  Stream<BookingUpdateError> get bookingUpdateErrors;

  // Availability & conflict checking methods
  List<Booking> getBookingsForListing(String listingId);
  List<Booking> getActiveBookingsForListing(String listingId);
  bool isTimeSlotAvailable({
    required String listingId,
    required DateTime checkIn,
    required DateTime checkOut,
  });
  List<Booking> getConflictingBookings({
    required String listingId,
    required DateTime checkIn,
    required DateTime checkOut,
  });

  /// Landmarks (hospitals, exam centers, universities, …) for purpose-based
  /// search. [type] filters to one landmark type; [query] matches name/area/city.
  Future<List<Landmark>> searchLandmarks({String? query, String? type});

  /// Landmarks closest to a coordinate (e.g. a listing's pin), nearest first,
  /// each carrying its distance. Used for the host "what's nearby" preview.
  Future<List<Landmark>> nearbyLandmarks({
    required double latitude,
    required double longitude,
    int limit,
    String? type,
  });

  /// The signed-in user's own payment history (payments they made as a guest),
  /// most recent first. Backed by the `payments` table's own-row RLS.
  Future<List<PaymentRecord>> fetchUserPayments(String userId);

  // ── Payout methods (migration 100) ─────────────────────────────────────────
  //
  // Where the user wants to be paid: host earnings, or a guest refund. Every
  // write goes through a SECURITY DEFINER RPC rather than a table write —
  // `payout_methods` has no INSERT/UPDATE/DELETE policy at all, because a
  // silently repointed payout is the most expensive thing that can happen to
  // an account here.

  /// The signed-in user's live payout methods, default first. Retired ones are
  /// excluded: they exist only so past disbursements still name a real
  /// account.
  Future<List<PayoutMethod>> fetchPayoutMethods(String userId);

  /// Adds a payout method. It lands as `pending` and cannot receive money
  /// until an admin verifies it.
  ///
  /// Returns null on success, or a human-readable reason it was refused —
  /// duplicate account, channel not currently accepted, malformed number. The
  /// caller shows that string; there is nothing useful to do with a thrown
  /// PostgrestException at the UI layer.
  Future<String?> addPayoutMethod({
    required PayoutChannel channel,
    required String accountName,
    required String accountNumber,
    String? bankName,
    String? branchName,
    String? routingNumber,
  });

  /// Makes [payoutMethodId] the destination for future payouts.
  Future<String?> setDefaultPayoutMethod(String payoutMethodId);

  /// Retires a method. It stops being usable but is never deleted, so the
  /// disbursements pointing at it keep their meaning.
  Future<String?> retirePayoutMethod(String payoutMethodId);

  /// Money the platform has actually paid out to this user — host payouts and
  /// guest refunds — most recent first, each with the destination account it
  /// went to.
  Future<List<Disbursement>> fetchDisbursements(String userId);

  /// Authoritative, server-side availability check for a listing/interval.
  ///
  /// Unlike [getConflictingBookings] (which only sees the local cache — and due
  /// to RLS a guest's cache never contains OTHER guests' bookings), this hits
  /// the `is_booking_available` RPC, which sees every booking. Use it to decide
  /// whether a slot is genuinely free before letting a guest confirm.
  Future<bool> isBookingAvailable({
    required String listingId,
    required DateTime checkIn,
    required DateTime checkOut,
  });

  /// Check if user has any active booking during the given time period
  List<Booking> getUserConflictingBookings({
    required String userId,
    required DateTime checkIn,
    required DateTime checkOut,
    String? excludeListingId,
  });

  /// Check if user can book during the given time period
  bool canUserBookDuring({
    required String userId,
    required DateTime checkIn,
    required DateTime checkOut,
  });

  /// Get completed bookings that the user hasn't reviewed yet
  List<Booking> getUnreviewedCompletedBookings(String userId);

  /// Refresh all data from the data source
  Future<void> refresh();

  // ============== Pagination ==============

  /// Whether there are more listings to load
  bool get hasMoreListings;

  /// Whether listings are currently being loaded
  bool get isLoadingListings;

  /// Fetch the next page of listings (10 items)
  /// Returns the newly fetched listings
  Future<List<Listing>> fetchNextListingsPage();

  /// Reset pagination and fetch fresh first page
  /// Call this when filters change or on pull-to-refresh
  Future<void> resetListingsPagination();

  // ============== Booking Pagination ==============

  /// Whether there are more bookings to load for the current user
  bool get hasMoreBookings;

  /// Whether bookings are currently being loaded
  bool get isLoadingBookings;

  /// Fetch the next page of bookings for a user (10 items)
  /// Returns the newly fetched bookings
  Future<List<Booking>> fetchNextBookingsPage(String userId);

  /// Reset booking pagination and fetch fresh first page
  /// Call this on pull-to-refresh or when switching users
  Future<void> resetBookingsPagination(String userId);

  // ============== Booking Counts ==============

  /// Get total booking counts for a user (upcoming, current, past)
  /// Returns a map with keys: 'upcoming', 'current', 'past'
  Future<Map<String, int>> getBookingCounts(String userId);

  /// Cached booking counts (updated by getBookingCounts)
  Map<String, int>? get cachedBookingCounts;
}
