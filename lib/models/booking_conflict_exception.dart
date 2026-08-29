import 'booking.dart';

/// Type of booking conflict
enum ConflictType {
  /// The listing/room is already booked during this time
  listing,

  /// The user already has another booking during this time
  user,
}

/// Exception thrown when a booking conflict is detected
class BookingConflictException implements Exception {
  BookingConflictException(
    this.message, {
    required this.conflictType,
    required this.conflictingBookings,
  });

  final String message;
  final ConflictType conflictType;
  final List<Booking> conflictingBookings;

  @override
  String toString() => message;
}

/// Which kind of conflict SQLSTATE 23P01 represents, from what PostgREST hands
/// back.
///
/// The server raises 23P01 for four different situations and the guest needs
/// two different sentences out of them, so something has to tell them apart.
/// That used to be `message.contains('already have a booking')` — English prose
/// written in a SQL file, matched in Dart, with no test on either side. Reword
/// the `raise exception` in a migration and the guest silently starts getting
/// the wrong message; nothing fails, nothing warns.
///
/// So migration 111 tags both manual raises with a stable [hint] and this
/// function reads that first. The remaining branches are fallbacks, in
/// descending order of trustworthiness:
///
///  * the exclusion constraints (`bookings_no_overlap`,
///    `bookings_no_tenant_overlap`) raise with no hint at all — they're the
///    database, not our `raise` — but Postgres names the violated constraint in
///    the message, which is just as stable;
///  * the legacy prose, so a client running against a pre-111 server keeps
///    behaving as it did rather than regressing to the wrong branch.
///
/// Unknown input resolves to [ConflictType.listing]: it is by far the more
/// common conflict, and "someone just took this slot" is the safer thing to
/// tell a guest who is in fact double-booking themselves than the reverse.
ConflictType bookingConflictTypeFrom({String? hint, String? message}) {
  switch (hint) {
    case 'tenant_overlap':
      return ConflictType.user;
    case 'listing_overlap':
      return ConflictType.listing;
  }

  final text = (message ?? '').toLowerCase();

  // Tenant first: `bookings_no_tenant_overlap` does not contain
  // `bookings_no_overlap` as a substring, but ordering it this way means it
  // still can't be shadowed if either name is ever changed.
  if (text.contains('bookings_no_tenant_overlap')) return ConflictType.user;
  if (text.contains('bookings_no_overlap')) return ConflictType.listing;

  if (text.contains('already have a booking')) return ConflictType.user;

  return ConflictType.listing;
}
