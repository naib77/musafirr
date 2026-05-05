import '../models/booking.dart';
import '../models/booking_duration.dart';
import '../models/listing.dart';
import '../models/owner_registration_draft.dart';

abstract class MusafirRepository {
  List<Listing> get listings;
  List<Booking> get bookings;
  int get availableCount;
  int get ownerCount;

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
}
