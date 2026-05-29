import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/booking.dart';
import 'package:musafir/models/booking_status.dart';
import 'package:musafir/services/booking/booking_rules.dart';

void main() {
  late BookingRules rules;

  setUp(() {
    rules = BookingRules();
  });

  Booking createBooking({
    BookingStatus status = BookingStatus.pending,
    DateTime? startAt,
    DateTime? endAt,
    String? userId,
    String? listingId,
  }) {
    final now = DateTime.now();
    return Booking(
      id: 'booking_1',
      listingId: listingId ?? 'listing_1',
      tenantName: 'Test User',
      startAt: startAt ?? now.add(const Duration(days: 1)),
      endAt: endAt ?? now.add(const Duration(days: 2)),
      totalPrice: 100.0,
      unitLabel: 'night',
      userId: userId ?? 'user_1',
      status: status,
      createdAt: now,
    );
  }

  group('BookingRules.canAccept', () {
    test('returns true for pending booking', () {
      final booking = createBooking(status: BookingStatus.pending);
      expect(rules.canAccept(booking), isTrue);
    });

    test('returns false for confirmed booking', () {
      final booking = createBooking(status: BookingStatus.confirmed);
      expect(rules.canAccept(booking), isFalse);
    });

    test('returns false for rejected booking', () {
      final booking = createBooking(status: BookingStatus.rejected);
      expect(rules.canAccept(booking), isFalse);
    });

    test('returns false for active booking', () {
      final booking = createBooking(status: BookingStatus.active);
      expect(rules.canAccept(booking), isFalse);
    });

    test('returns false for completed booking', () {
      final booking = createBooking(status: BookingStatus.completed);
      expect(rules.canAccept(booking), isFalse);
    });

    test('returns false for cancelled booking', () {
      final booking = createBooking(status: BookingStatus.cancelled);
      expect(rules.canAccept(booking), isFalse);
    });
  });

  group('BookingRules.canReject', () {
    test('returns true for pending booking', () {
      final booking = createBooking(status: BookingStatus.pending);
      expect(rules.canReject(booking), isTrue);
    });

    test('returns false for confirmed booking', () {
      final booking = createBooking(status: BookingStatus.confirmed);
      expect(rules.canReject(booking), isFalse);
    });

    test('returns false for already rejected booking', () {
      final booking = createBooking(status: BookingStatus.rejected);
      expect(rules.canReject(booking), isFalse);
    });
  });

  group('BookingRules.canCheckIn', () {
    test('returns true for confirmed booking on start date', () {
      final now = DateTime.now();
      final booking = createBooking(
        status: BookingStatus.confirmed,
        startAt: now.subtract(const Duration(hours: 1)),
      );
      expect(rules.canCheckIn(booking, now: now), isTrue);
    });

    test('returns true for confirmed booking after start date', () {
      final now = DateTime.now();
      final booking = createBooking(
        status: BookingStatus.confirmed,
        startAt: now.subtract(const Duration(days: 1)),
      );
      expect(rules.canCheckIn(booking, now: now), isTrue);
    });

    test('returns false for confirmed booking before start date', () {
      final now = DateTime.now();
      final booking = createBooking(
        status: BookingStatus.confirmed,
        startAt: now.add(const Duration(days: 1)),
      );
      expect(rules.canCheckIn(booking, now: now), isFalse);
    });

    test('returns false for pending booking', () {
      final booking = createBooking(status: BookingStatus.pending);
      expect(rules.canCheckIn(booking), isFalse);
    });

    test('returns false for already active booking', () {
      final booking = createBooking(status: BookingStatus.active);
      expect(rules.canCheckIn(booking), isFalse);
    });

    test('returns false for completed booking', () {
      final booking = createBooking(status: BookingStatus.completed);
      expect(rules.canCheckIn(booking), isFalse);
    });
  });

  group('BookingRules.canComplete', () {
    test('returns true for active booking', () {
      final booking = createBooking(status: BookingStatus.active);
      expect(rules.canComplete(booking), isTrue);
    });

    test('returns false for confirmed booking (not checked in)', () {
      final booking = createBooking(status: BookingStatus.confirmed);
      expect(rules.canComplete(booking), isFalse);
    });

    test('returns false for pending booking', () {
      final booking = createBooking(status: BookingStatus.pending);
      expect(rules.canComplete(booking), isFalse);
    });

    test('returns false for already completed booking', () {
      final booking = createBooking(status: BookingStatus.completed);
      expect(rules.canComplete(booking), isFalse);
    });
  });

  group('BookingRules.canGuestCancel', () {
    test('returns true for pending booking', () {
      final booking = createBooking(status: BookingStatus.pending);
      expect(rules.canGuestCancel(booking), isTrue);
    });

    test('returns true for confirmed booking', () {
      final booking = createBooking(status: BookingStatus.confirmed);
      expect(rules.canGuestCancel(booking), isTrue);
    });

    test('returns false for active booking (already checked in)', () {
      final booking = createBooking(status: BookingStatus.active);
      expect(rules.canGuestCancel(booking), isFalse);
    });

    test('returns false for completed booking', () {
      final booking = createBooking(status: BookingStatus.completed);
      expect(rules.canGuestCancel(booking), isFalse);
    });

    test('returns false for cancelled booking', () {
      final booking = createBooking(status: BookingStatus.cancelled);
      expect(rules.canGuestCancel(booking), isFalse);
    });
  });

  group('BookingRules.canHostCancel', () {
    test('returns true for confirmed booking', () {
      final booking = createBooking(status: BookingStatus.confirmed);
      expect(rules.canHostCancel(booking), isTrue);
    });

    test('returns false for pending booking (should reject instead)', () {
      final booking = createBooking(status: BookingStatus.pending);
      expect(rules.canHostCancel(booking), isFalse);
    });

    test('returns false for active booking (already checked in)', () {
      final booking = createBooking(status: BookingStatus.active);
      expect(rules.canHostCancel(booking), isFalse);
    });

    test('returns false for completed booking', () {
      final booking = createBooking(status: BookingStatus.completed);
      expect(rules.canHostCancel(booking), isFalse);
    });
  });

  group('BookingRules.isExpired', () {
    test('returns true for pending booking older than 24 hours', () {
      final now = DateTime.now();
      final booking = createBooking(status: BookingStatus.pending);
      // Simulate booking created 25 hours ago
      final createdAt = now.subtract(const Duration(hours: 25));
      final oldBooking = Booking(
        id: booking.id,
        listingId: booking.listingId,
        tenantName: booking.tenantName,
        startAt: booking.startAt,
        endAt: booking.endAt,
        totalPrice: booking.totalPrice,
        unitLabel: booking.unitLabel,
        userId: booking.userId,
        status: BookingStatus.pending,
        createdAt: createdAt,
      );
      expect(rules.isExpired(oldBooking, now: now), isTrue);
    });

    test('returns false for pending booking less than 24 hours old', () {
      final now = DateTime.now();
      final createdAt = now.subtract(const Duration(hours: 23));
      final booking = Booking(
        id: 'booking_1',
        listingId: 'listing_1',
        tenantName: 'Test User',
        startAt: now.add(const Duration(days: 1)),
        endAt: now.add(const Duration(days: 2)),
        totalPrice: 100.0,
        unitLabel: 'night',
        userId: 'user_1',
        status: BookingStatus.pending,
        createdAt: createdAt,
      );
      expect(rules.isExpired(booking, now: now), isFalse);
    });

    test('returns false for confirmed booking regardless of age', () {
      final now = DateTime.now();
      final createdAt = now.subtract(const Duration(hours: 48));
      final booking = Booking(
        id: 'booking_1',
        listingId: 'listing_1',
        tenantName: 'Test User',
        startAt: now.add(const Duration(days: 1)),
        endAt: now.add(const Duration(days: 2)),
        totalPrice: 100.0,
        unitLabel: 'night',
        userId: 'user_1',
        status: BookingStatus.confirmed,
        createdAt: createdAt,
      );
      expect(rules.isExpired(booking, now: now), isFalse);
    });
  });

  group('BookingRules.canSubmitReview', () {
    test('returns true for completed booking within 14 days', () {
      final now = DateTime.now();
      final completedAt = now.subtract(const Duration(days: 7));
      final booking = createBooking(status: BookingStatus.completed);
      expect(rules.canSubmitReview(booking, completedAt: completedAt, now: now), isTrue);
    });

    test('returns false for completed booking after 14 days', () {
      final now = DateTime.now();
      final completedAt = now.subtract(const Duration(days: 15));
      final booking = createBooking(status: BookingStatus.completed);
      expect(rules.canSubmitReview(booking, completedAt: completedAt, now: now), isFalse);
    });

    test('returns false for non-completed booking', () {
      final now = DateTime.now();
      final booking = createBooking(status: BookingStatus.confirmed);
      expect(rules.canSubmitReview(booking, completedAt: now, now: now), isFalse);
    });
  });
}
