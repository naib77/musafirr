import '../models/booking.dart';
import '../models/booking_duration.dart';
import '../models/listing.dart';
import '../models/owner_registration_draft.dart';
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
  int get ownerCount =>
      throw UnimplementedError('Replace with Supabase query');

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
}
