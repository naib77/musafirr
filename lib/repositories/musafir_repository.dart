import '../models/booking.dart';
import '../models/booking_duration.dart';
import '../models/listing.dart';
import '../models/owner_registration_draft.dart';
import '../models/review.dart';
import '../models/search_filters.dart';
import '../models/user.dart';

abstract class MusafirRepository {
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

  // Listing methods
  Listing? getListingById(String id);
  List<Listing> searchListings(SearchFilters filters);
  List<Listing> getFeaturedListings({int limit = 10});
  List<Listing> getListingsByHost(String hostId);
  void addListing(Listing listing);
  void updateListing(Listing listing);
  void deleteListing(String listingId);

  // Review methods
  List<Review> getReviewsForListing(String listingId);
  void addReview(Review review);
  double getAverageRating(String listingId);

  // Booking methods
  List<Booking> getBookingsForUser(String userId);
  List<Booking> getUpcomingBookings(String userId);
  List<Booking> getPastBookings(String userId);
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
}
