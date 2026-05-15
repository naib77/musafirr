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
