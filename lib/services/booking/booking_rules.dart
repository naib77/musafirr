import '../../models/booking.dart';
import '../../models/booking_status.dart';

/// Deep module encapsulating all booking lifecycle validation rules.
///
/// This class provides a single, testable interface for determining
/// what actions are allowed on a booking at any given time.
class BookingRules {
  /// Duration after which a pending booking auto-expires if host doesn't respond.
  static const Duration expirationDuration = Duration(hours: 24);

  /// Duration after service completion during which reviews can be submitted.
  static const Duration reviewWindowDuration = Duration(days: 14);

  /// Duration after which reviews are revealed if not both submitted.
  static const Duration reviewRevealDuration = Duration(days: 14);

  /// Returns true if host can accept this booking.
  /// Only pending bookings can be accepted.
  bool canAccept(Booking booking) {
    return booking.status == BookingStatus.pending;
  }

  /// Returns true if host can reject this booking.
  /// Only pending bookings can be rejected.
  bool canReject(Booking booking) {
    return booking.status == BookingStatus.pending;
  }

  /// Returns true if host can mark guest as checked in.
  /// Requires:
  /// - Booking is confirmed
  /// - Current time is on or after the start date
  bool canCheckIn(Booking booking, {DateTime? now}) {
    if (booking.status != BookingStatus.confirmed) {
      return false;
    }

    final currentTime = now ?? DateTime.now();
    final startDate = _startOfDay(booking.effectiveCheckIn);
    final today = _startOfDay(currentTime);

    return !today.isBefore(startDate);
  }

  /// Returns true if host can mark service as complete.
  /// Only active (checked-in) bookings can be completed.
  bool canComplete(Booking booking) {
    return booking.status == BookingStatus.active;
  }

  /// Returns true if guest can cancel this booking.
  /// Guest can cancel while pending or confirmed, but not after check-in.
  bool canGuestCancel(Booking booking) {
    return booking.status == BookingStatus.pending ||
        booking.status == BookingStatus.confirmed;
  }

  /// Returns true if host can cancel this booking.
  /// Host can cancel confirmed bookings, but should reject pending ones.
  /// Cannot cancel after check-in.
  bool canHostCancel(Booking booking) {
    return booking.status == BookingStatus.confirmed;
  }

  /// Returns true if the booking has expired due to host non-response.
  /// A pending booking expires 24 hours after creation.
  bool isExpired(Booking booking, {DateTime? now}) {
    if (booking.status != BookingStatus.pending) {
      return false;
    }

    final createdAt = booking.createdAt;
    if (createdAt == null) {
      return false;
    }

    final currentTime = now ?? DateTime.now();
    final expirationTime = createdAt.add(expirationDuration);

    return currentTime.isAfter(expirationTime);
  }

  /// Returns true if a review can be submitted for this booking.
  /// Requires:
  /// - Booking is completed
  /// - Within 14 days of completion
  bool canSubmitReview(
    Booking booking, {
    required DateTime completedAt,
    DateTime? now,
  }) {
    if (booking.status != BookingStatus.completed) {
      return false;
    }

    final currentTime = now ?? DateTime.now();
    final reviewDeadline = completedAt.add(reviewWindowDuration);

    return currentTime.isBefore(reviewDeadline) ||
        currentTime.isAtSameMomentAs(reviewDeadline);
  }

  /// Returns true if reviews should be revealed for this booking.
  /// Reviews are revealed when:
  /// - Both guest and host have submitted reviews, OR
  /// - 14 days have passed since service completion
  bool shouldRevealReviews({
    required bool guestReviewSubmitted,
    required bool hostReviewSubmitted,
    required DateTime completedAt,
    DateTime? now,
  }) {
    // Reveal if both submitted
    if (guestReviewSubmitted && hostReviewSubmitted) {
      return true;
    }

    // Reveal if 14 days have passed
    final currentTime = now ?? DateTime.now();
    final revealTime = completedAt.add(reviewRevealDuration);

    return currentTime.isAfter(revealTime);
  }

  /// Helper to get start of day for date comparisons.
  DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }
}
