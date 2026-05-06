enum BookingStatus {
  pending,
  confirmed,
  completed,
  cancelled,
}

extension BookingStatusLabel on BookingStatus {
  String get title => switch (this) {
        BookingStatus.pending => 'Pending',
        BookingStatus.confirmed => 'Confirmed',
        BookingStatus.completed => 'Completed',
        BookingStatus.cancelled => 'Cancelled',
      };

  bool get isActive =>
      this == BookingStatus.pending || this == BookingStatus.confirmed;

  bool get isPast =>
      this == BookingStatus.completed || this == BookingStatus.cancelled;
}
