import 'booking.dart';

/// Groups a flat list of [Booking]s into the three reservation buckets shown
/// across the app: upcoming, current (ongoing), and past.
///
/// This is the single shared seam for reservation categorization — the guest
/// "My Trips" screen, the host "Reservations" tabs, and the host dashboard all
/// consume it so a booking can never appear in different buckets depending on
/// which screen you open. The actual bucket rules live on [Booking]
/// (`isUpcomingAt` / `isOngoingAt` / `isPastAt`); this class only fans a list
/// out across them and applies each bucket's display sort order.
class BookingCategorizer {
  BookingCategorizer(this.allBookings, {DateTime? currentTime})
      : now = currentTime ?? DateTime.now();

  final List<Booking> allBookings;
  final DateTime now;

  /// Active-status bookings that have not started yet — including pending
  /// requests the host still needs to respond to (these are surfaced here even
  /// if their requested date has slipped, so they are never lost in Past).
  /// Sorted soonest check-in first.
  List<Booking> get upcoming => allBookings
      .where((b) => b.isUpcomingAt(now))
      .toList()
    ..sort((a, b) => a.effectiveCheckIn.compareTo(b.effectiveCheckIn));

  /// Bookings the guest is currently in: checked-in stays, plus confirmed
  /// bookings whose check-in date has arrived. Stay actionable until the host
  /// marks them complete. Sorted by soonest checkout first.
  List<Booking> get current => allBookings
      .where((b) => b.isOngoingAt(now))
      .toList()
    ..sort((a, b) => a.effectiveCheckOut.compareTo(b.effectiveCheckOut));

  /// Finished bookings: completed, cancelled, rejected, or a confirmed stay
  /// whose window fully elapsed without check-in. Sorted most recent first.
  List<Booking> get past => allBookings
      .where((b) => b.isPastAt(now))
      .toList()
    ..sort((a, b) => b.effectiveCheckIn.compareTo(a.effectiveCheckIn));
}
