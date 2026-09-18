/// A booking the server refused for a reason the guest can act on.
///
/// `create_marketplace_booking` raises with sentences written for guests —
/// "This place hosts up to 4 guests", "This listing is no longer available",
/// "Booking must be at least one day", and whatever `validate_coupon` says
/// about a bad code. Those are deliberate: the server is the only party that
/// knows the authoritative rates, capacity and coupon state, so it is the only
/// party that can explain a refusal accurately.
///
/// Without a type to carry them, every one of those sentences collapses into a
/// generic "Booking failed. Please try again." — which is how a guest ends up
/// retrying the same impossible booking instead of changing the one field that
/// would make it succeed. Same reasoning as [BookingConflictException], for the
/// non-conflict refusals.
class BookingRejectedException implements Exception {
  const BookingRejectedException(this.message, {this.code});

  /// Server-authored text, safe to show a guest verbatim.
  final String message;

  /// The SQLSTATE the server raised with, kept for logs.
  final String? code;

  @override
  String toString() => 'BookingRejectedException($code): $message';
}

/// The SQLSTATEs `create_marketplace_booking` raises with when it is refusing
/// a booking rather than failing at one.
///
///   * `22023` invalid_parameter_value — capacity, dates, duration, a pricing
///     unit the listing has no rate for, or a coupon `validate_coupon` refused.
///   * `P0002` no_data_found — the listing was deleted while the sheet was open.
///   * `42501` insufficient_privilege — the session expired mid-booking.
///
/// Deliberately a closed set. A new SQLSTATE showing up means either the server
/// grew a refusal nobody taught the client about, or something actually broke —
/// and defaulting the unknown case to "show the guest the raw error" would leak
/// constraint names and internals into a banner. Unknown stays generic.
const Set<String> guestFacingBookingSqlStates = {'22023', 'P0002', '42501'};

/// Whether [sqlState] is a refusal whose server-authored message is safe and
/// useful to show a guest verbatim.
bool isGuestFacingBookingRefusal(String? sqlState) =>
    sqlState != null && guestFacingBookingSqlStates.contains(sqlState);

/// The SQLSTATEs that mean "the database gave up on this transaction, try it
/// again", not "no".
///
///   * `40001` serialization_failure
///   * `40P01` deadlock_detected
///
/// This exists because of what several guests racing for one slot actually
/// look like. `bookings_no_overlap` (078) is an exclusion constraint and it
/// does its job perfectly — exactly one booking survived every race in QA,
/// at two, three, four and eight concurrent guests. But **what the losers are
/// told depends on how many of them there were.** With two guests the loser
/// gets `23P01` and the sentence written for them. With three or more,
/// Postgres frequently raises from inside the exclusion check itself:
///
///     ERROR:  deadlock detected
///     CONTEXT: while checking exclusion constraint on tuple (1,25)
///              in relation "bookings"
///
/// The client handled `23P01` only, so under the load this feature exists for
/// — a popular slot — most losing guests saw an unexplained failure instead of
/// "this time slot was just booked by someone else". Measured across six
/// four-racer runs: two runs had all three losers deadlock (QA report
/// 2026-09-18, N6).
///
/// A deadlock rolls the whole transaction back, so retrying is safe: there is
/// no half-written booking to clean up, and `create_marketplace_booking` is
/// one statement.
const Set<String> retryableBookingSqlStates = {'40001', '40P01'};

/// Whether [sqlState] is a transient database failure worth one more attempt.
bool isRetryableBookingFailure(String? sqlState) =>
    sqlState != null && retryableBookingSqlStates.contains(sqlState);
