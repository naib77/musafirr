import '../../models/booking.dart';
import '../../models/booking_status.dart';
import 'booking_rules.dart';

/// Exception thrown when a booking is not found.
class BookingNotFoundException implements Exception {
  BookingNotFoundException(this.bookingId);
  final String bookingId;

  @override
  String toString() => 'Booking not found: $bookingId';
}

/// Exception thrown when an operation is invalid for the current booking state.
class InvalidBookingStateException implements Exception {
  InvalidBookingStateException(this.message, {this.booking});
  final String message;
  final Booking? booking;

  @override
  String toString() => message;
}

/// Abstract interface for booking storage operations.
/// Allows the service to be tested with different storage implementations.
abstract class BookingStore {
  Booking? getBookingById(String id);
  void updateBooking(Booking booking);
}

/// Service that manages booking lifecycle transitions.
///
/// This service encapsulates all booking state machine logic,
/// ensuring valid transitions and recording timestamps.
class BookingLifecycleService {
  BookingLifecycleService({
    required this.store,
    required this.rules,
  });

  final BookingStore store;
  final BookingRules rules;

  /// Accept a pending booking request.
  /// Transitions: pending → confirmed
  ///
  /// [bookingId] The booking to accept.
  /// [message] Optional welcome message from host.
  ///
  /// Throws [BookingNotFoundException] if booking doesn't exist.
  /// Throws [InvalidBookingStateException] if booking is not pending.
  Booking acceptBooking(String bookingId, {String? message}) {
    final booking = _getBookingOrThrow(bookingId);

    if (!rules.canAccept(booking)) {
      throw InvalidBookingStateException(
        'Cannot accept booking in ${booking.status.title} state',
        booking: booking,
      );
    }

    final updated = booking.copyWith(
      status: BookingStatus.confirmed,
      confirmedAt: DateTime.now(),
      hostMessage: message,
    );

    store.updateBooking(updated);
    return updated;
  }

  /// Reject a pending booking request.
  /// Transitions: pending → rejected
  ///
  /// [bookingId] The booking to reject.
  /// [reason] Optional reason for rejection.
  ///
  /// Throws [BookingNotFoundException] if booking doesn't exist.
  /// Throws [InvalidBookingStateException] if booking is not pending.
  Booking rejectBooking(String bookingId, {String? reason}) {
    final booking = _getBookingOrThrow(bookingId);

    if (!rules.canReject(booking)) {
      throw InvalidBookingStateException(
        'Cannot reject booking in ${booking.status.title} state',
        booking: booking,
      );
    }

    final updated = booking.copyWith(
      status: BookingStatus.rejected,
      rejectionReason: reason,
    );

    store.updateBooking(updated);
    return updated;
  }

  /// Mark guest as checked in (arrived).
  /// Transitions: confirmed → active
  ///
  /// [bookingId] The booking to check in.
  /// [now] Optional current time (for testing).
  ///
  /// Throws [BookingNotFoundException] if booking doesn't exist.
  /// Throws [InvalidBookingStateException] if booking is not confirmed
  /// or if current time is before start date.
  Booking checkInGuest(String bookingId, {DateTime? now}) {
    final booking = _getBookingOrThrow(bookingId);

    if (!rules.canCheckIn(booking, now: now)) {
      if (booking.status != BookingStatus.confirmed) {
        throw InvalidBookingStateException(
          'Cannot check in booking in ${booking.status.title} state',
          booking: booking,
        );
      } else {
        throw InvalidBookingStateException(
          'Cannot check in before start date',
          booking: booking,
        );
      }
    }

    final checkInTime = now ?? DateTime.now();
    final updated = booking.copyWith(
      status: BookingStatus.active,
      actualCheckIn: checkInTime,
    );

    store.updateBooking(updated);
    return updated;
  }

  /// Mark service as complete (check out).
  /// Transitions: active → completed
  ///
  /// [bookingId] The booking to complete.
  /// [now] Optional current time (for testing).
  ///
  /// Throws [BookingNotFoundException] if booking doesn't exist.
  /// Throws [InvalidBookingStateException] if booking is not active.
  Booking completeService(String bookingId, {DateTime? now}) {
    final booking = _getBookingOrThrow(bookingId);

    if (!rules.canComplete(booking)) {
      throw InvalidBookingStateException(
        'Cannot complete booking in ${booking.status.title} state',
        booking: booking,
      );
    }

    final completionTime = now ?? DateTime.now();
    final updated = booking.copyWith(
      status: BookingStatus.completed,
      completedAt: completionTime,
    );

    store.updateBooking(updated);
    return updated;
  }

  /// Cancel a booking.
  /// Transitions: pending/confirmed → cancelled (guest)
  /// Transitions: confirmed → cancelled (host)
  ///
  /// [bookingId] The booking to cancel.
  /// [cancelledBy] User ID of who is cancelling.
  /// [isHost] Whether the canceller is the host.
  /// [now] Optional current time (for testing).
  ///
  /// Throws [BookingNotFoundException] if booking doesn't exist.
  /// Throws [InvalidBookingStateException] if cancellation is not allowed.
  Booking cancelBooking(
    String bookingId, {
    required String cancelledBy,
    required bool isHost,
    DateTime? now,
  }) {
    final booking = _getBookingOrThrow(bookingId);

    final canCancel = isHost
        ? rules.canHostCancel(booking)
        : rules.canGuestCancel(booking);

    if (!canCancel) {
      final role = isHost ? 'Host' : 'Guest';
      throw InvalidBookingStateException(
        '$role cannot cancel booking in ${booking.status.title} state',
        booking: booking,
      );
    }

    final cancellationTime = now ?? DateTime.now();
    final updated = booking.copyWith(
      status: BookingStatus.cancelled,
      cancelledBy: cancelledBy,
      cancelledAt: cancellationTime,
    );

    store.updateBooking(updated);
    return updated;
  }

  /// Expire stale pending bookings that haven't been responded to.
  /// Transitions: pending → rejected (for bookings older than 24 hours)
  ///
  /// Returns list of bookings that were expired.
  List<Booking> expireStaleBookings(List<Booking> bookings, {DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    final expired = <Booking>[];

    for (final booking in bookings) {
      if (rules.isExpired(booking, now: currentTime)) {
        final updated = booking.copyWith(
          status: BookingStatus.rejected,
          rejectionReason: 'Expired - host did not respond within 24 hours',
        );
        store.updateBooking(updated);
        expired.add(updated);
      }
    }

    return expired;
  }

  Booking _getBookingOrThrow(String bookingId) {
    final booking = store.getBookingById(bookingId);
    if (booking == null) {
      throw BookingNotFoundException(bookingId);
    }
    return booking;
  }
}
