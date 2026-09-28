/// How long a host has to answer a booking request, and how that is counted
/// down to the guest.
///
/// ## One rule, two enforcers
///
/// The **database** is the enforcer: `expire_stale_bookings()` runs on a cron
/// and rejects anything still pending past the window. Nothing in Dart cancels
/// a real booking. What Dart needs the window for is the countdown a guest
/// watches on their trip — and that has to agree with the job, or the app says
/// "4h left" for a request the server has already thrown away.
///
/// So the number lives in `app_settings.booking_accept_window_hours`, both
/// sides read it, and the parsing below mirrors migration 119's validator
/// exactly. A value this file would clamp is a value that validator would have
/// refused at the keystroke, so clamping is for rows written before the guard
/// existed, not for ordinary input.
library;

/// What the window was before it was configurable, and what an unreadable or
/// unset row still means. Changing this changes the app's behaviour only where
/// the settings table cannot be read at all.
const Duration kDefaultBookingAcceptWindow = Duration(hours: 24);

/// Floor of one hour. Zero would expire a request in the same cron tick that
/// created it — the host would be declining bookings they were never shown.
const Duration kMinBookingAcceptWindow = Duration(hours: 1);

/// Ceiling of seven days. Past that a guest's own dates have usually come and
/// gone, so the request is dead of old age rather than of the host's silence.
const Duration kMaxBookingAcceptWindow = Duration(hours: 168);

/// Reads the raw `booking_accept_window_hours` cell.
///
/// Absent, blank, non-numeric or out of range all fall back to
/// [kDefaultBookingAcceptWindow] rather than throwing: `AppSettingsService`
/// fails open by design, and a malformed row must not stop a trip screen
/// rendering.
Duration bookingAcceptWindowFromRaw(String? raw) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return kDefaultBookingAcceptWindow;
  final hours = int.tryParse(text);
  if (hours == null) return kDefaultBookingAcceptWindow;
  final window = Duration(hours: hours);
  if (window < kMinBookingAcceptWindow) return kMinBookingAcceptWindow;
  if (window > kMaxBookingAcceptWindow) return kMaxBookingAcceptWindow;
  return window;
}

/// How long is left for the host to answer, or null when there is nothing to
/// count down from.
///
/// Negative means the window has closed — the caller decides whether to say
/// "expired", because the cron may not have run yet and the booking is still
/// `pending` on screen for up to a quarter of an hour afterwards.
Duration? bookingAcceptRemaining({
  required DateTime? createdAt,
  required Duration window,
  DateTime? now,
}) {
  if (createdAt == null) return null;
  return createdAt.add(window).difference(now ?? DateTime.now());
}

/// "2d 3h", "3h 20m", "12m", "under a minute".
///
/// Extracted because the two places that showed this — the trips list hint and
/// the booking detail banner — formatted it differently, and one of them
/// printed a bare `${inHours}h` that read as "0h 0m" for anything under a
/// minute. Days appear only once the window is long enough to need them; at 24
/// hours or less it is always hours and minutes, which is what a guest waiting
/// on a reply actually wants to read.
String formatBookingAcceptRemaining(Duration remaining) {
  if (remaining.isNegative) return 'expired';
  if (remaining.inMinutes < 1) return 'under a minute';
  if (remaining.inHours < 1) return '${remaining.inMinutes}m';
  if (remaining.inHours < 48) {
    return '${remaining.inHours}h ${remaining.inMinutes % 60}m';
  }
  final days = remaining.inDays;
  return '${days}d ${remaining.inHours - days * 24}h';
}
