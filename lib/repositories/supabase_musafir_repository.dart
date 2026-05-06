import '../models/booking.dart';
import '../models/booking_duration.dart';
import '../models/listing.dart';
import '../models/owner_registration_draft.dart';
import '../models/review.dart';
import '../models/search_filters.dart';
import '../models/user.dart';
import 'musafir_repository.dart';

class SupabaseMusafirRepository implements MusafirRepository {
  @override
  int get availableCount =>
      throw UnimplementedError('Replace with Supabase query');

  @override
  List<Booking> get bookings =>
      throw UnimplementedError('Replace with Supabase query');

  @override
  List<Listing> get listings =>
      throw UnimplementedError('Replace with Supabase query');

  @override
  int get ownerCount => throw UnimplementedError('Replace with Supabase query');

  @override
  Booking createBooking({
    required Listing listing,
    required String tenantName,
    required BookingDuration duration,
  }) {
    throw UnimplementedError('Implement booking insert with conflict checks');
  }

  @override
  void registerOwnerListing(OwnerRegistrationDraft draft) {
    throw UnimplementedError('Implement listing insert');
  }

  @override
  List<Listing> searchByArea({
    required double centerLat,
    required double centerLng,
    required double delta,
  }) {
    throw UnimplementedError('Implement PostGIS-based area query');
  }

  // New marketplace methods

  @override
  User? getUserById(String id) {
    throw UnimplementedError('Implement Supabase user query');
  }

  @override
  User? getUserByEmail(String email) {
    throw UnimplementedError('Implement Supabase user query by email');
  }

  @override
  void addUser(User user) {
    throw UnimplementedError('Implement Supabase user insert');
  }

  @override
  Listing? getListingById(String id) {
    throw UnimplementedError('Implement Supabase listing query');
  }

  @override
  List<Listing> searchListings(SearchFilters filters) {
    throw UnimplementedError('Implement Supabase filtered listing search');
  }

  @override
  List<Listing> getFeaturedListings({int limit = 10}) {
    throw UnimplementedError('Implement Supabase featured listings query');
  }

  @override
  List<Listing> getListingsByHost(String hostId) {
    throw UnimplementedError('Implement Supabase host listings query');
  }

  @override
  void addListing(Listing listing) {
    throw UnimplementedError('Implement Supabase listing insert');
  }

  @override
  void updateListing(Listing listing) {
    throw UnimplementedError('Implement Supabase listing update');
  }

  @override
  void deleteListing(String listingId) {
    throw UnimplementedError('Implement Supabase listing delete');
  }

  @override
  List<Review> getReviewsForListing(String listingId) {
    throw UnimplementedError('Implement Supabase reviews query');
  }

  @override
  void addReview(Review review) {
    throw UnimplementedError('Implement Supabase review insert');
  }

  @override
  double getAverageRating(String listingId) {
    throw UnimplementedError('Implement Supabase rating aggregation');
  }

  @override
  List<Booking> getBookingsForUser(String userId) {
    throw UnimplementedError('Implement Supabase user bookings query');
  }

  @override
  List<Booking> getUpcomingBookings(String userId) {
    throw UnimplementedError('Implement Supabase upcoming bookings query');
  }

  @override
  List<Booking> getPastBookings(String userId) {
    throw UnimplementedError('Implement Supabase past bookings query');
  }

  @override
  Booking? getBookingById(String id) {
    throw UnimplementedError('Implement Supabase booking query');
  }

  @override
  Booking createMarketplaceBooking({
    required String listingId,
    required String userId,
    required String userName,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guestCount,
  }) {
    throw UnimplementedError('Implement Supabase marketplace booking insert');
  }

  @override
  void cancelBooking(String bookingId) {
    throw UnimplementedError('Implement Supabase booking cancellation');
  }
}
