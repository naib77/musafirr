enum BookingStatus {
  pending,
  confirmed,
  rejected,
  active,
  completed,
  cancelled,

  /// The host reported that the guest never arrived (migrations 139/140).
  /// Terminal, like cancelled; opens no review window and, under the refund
  /// policy, returns nothing. Spelled `no_show` in the database — see [wire].
  noShow,
}

/// The `booking_status` enum label the database uses for each value.
///
/// `.name` used to be sent straight to PostgREST, which worked only because
/// every label happened to be a single lowercase word. `noShow` is the first
/// value whose Dart name and enum label differ, so the mapping is explicit in
/// BOTH directions here and nowhere else — the repository reads and writes
/// through it.
extension BookingStatusWire on BookingStatus {
  String get wire => switch (this) {
        BookingStatus.pending => 'pending',
        BookingStatus.confirmed => 'confirmed',
        BookingStatus.rejected => 'rejected',
        BookingStatus.active => 'active',
        BookingStatus.completed => 'completed',
        BookingStatus.cancelled => 'cancelled',
        BookingStatus.noShow => 'no_show',
      };

  /// The inverse of [wire]. Unknown labels — a client older than the enum
  /// value that produced them — are read as [BookingStatus.pending] rather
  /// than thrown, because a booking the model cannot name is still a booking
  /// the screen has to draw.
  static BookingStatus fromWire(String? label) {
    for (final s in BookingStatus.values) {
      if (s.wire == label) return s;
    }
    return BookingStatus.pending;
  }
}

extension BookingStatusLabel on BookingStatus {
  String get title => switch (this) {
        BookingStatus.pending => 'Pending',
        BookingStatus.confirmed => 'Confirmed',
        BookingStatus.rejected => 'Declined',
        BookingStatus.active => 'Checked In',
        BookingStatus.completed => 'Completed',
        BookingStatus.cancelled => 'Cancelled',
        BookingStatus.noShow => 'No-show',
      };

  /// Returns true if the booking is in an active state (not finalized).
  /// Active states: pending, confirmed, active (checked-in).
  bool get isActive =>
      this == BookingStatus.pending ||
      this == BookingStatus.confirmed ||
      this == BookingStatus.active;

  /// Returns true if the booking has reached a terminal state.
  /// Past states: completed, cancelled, rejected, no-show.
  bool get isPast =>
      this == BookingStatus.completed ||
      this == BookingStatus.cancelled ||
      this == BookingStatus.rejected ||
      this == BookingStatus.noShow;

  /// Returns true if host can still take action on this booking.
  bool get isPending => this == BookingStatus.pending;

  /// Returns true if guest has checked in.
  bool get isCheckedIn => this == BookingStatus.active;

  /// Returns true if booking was declined by host or expired.
  bool get isRejected => this == BookingStatus.rejected;
}
