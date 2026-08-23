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
