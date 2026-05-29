enum BookingStatus {
  pending,
  confirmed,
  rejected,
  active,
  completed,
  cancelled,
}

extension BookingStatusLabel on BookingStatus {
  String get title => switch (this) {
        BookingStatus.pending => 'Pending',
        BookingStatus.confirmed => 'Confirmed',
        BookingStatus.rejected => 'Declined',
        BookingStatus.active => 'Checked In',
        BookingStatus.completed => 'Completed',
        BookingStatus.cancelled => 'Cancelled',
      };

  /// Returns true if the booking is in an active state (not finalized).
  /// Active states: pending, confirmed, active (checked-in).
  bool get isActive =>
      this == BookingStatus.pending ||
      this == BookingStatus.confirmed ||
      this == BookingStatus.active;

  /// Returns true if the booking has reached a terminal state.
  /// Past states: completed, cancelled, rejected.
  bool get isPast =>
      this == BookingStatus.completed ||
      this == BookingStatus.cancelled ||
      this == BookingStatus.rejected;

  /// Returns true if host can still take action on this booking.
  bool get isPending => this == BookingStatus.pending;

  /// Returns true if guest has checked in.
  bool get isCheckedIn => this == BookingStatus.active;

  /// Returns true if booking was declined by host or expired.
  bool get isRejected => this == BookingStatus.rejected;
}
