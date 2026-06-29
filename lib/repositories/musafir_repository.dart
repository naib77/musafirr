import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/booking.dart';
import '../models/booking_duration.dart';
import '../models/leaderboard_entry.dart';
import '../models/listing.dart';
import '../models/owner_registration_draft.dart';
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
  List<Listing> searchListings(SearchFilters filters);
  List<Listing> getFeaturedListings({int limit = 10});
  List<Listing> getListingsByHost(String hostId);
  void addListing(Listing listing);
  void updateListing(Listing listing);
  void deleteListing(String listingId);

  // Review methods (legacy - for simple listing reviews)
  List<Review> getReviewsForListing(String listingId);
  void addReview(Review review);
  double getAverageRating(String listingId);

  // Bidirectional review methods
  List<Review> getReviewsForBooking(String bookingId);
  List<Review> getRevealedReviewsForListing(String listingId);
  List<Review> getRevealedReviewsForGuest(String guestId);
  void saveReview(Review review);
  void updateReview(Review review);

  // Booking methods
  List<Booking> getBookingsForUser(String userId);
  List<Booking> getUpcomingBookings(String userId);
  List<Booking> getPastBookings(String userId);
  @override
  Booking? getBookingById(String id);
  Booking createMarketplaceBooking({
    required String listingId,
    required String userId,
    required String userName,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guestCount,
    required double totalPrice,
    required String unitLabel,
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
