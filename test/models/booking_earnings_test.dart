import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/booking.dart';
import 'package:musafir/models/booking_status.dart';

void main() {
  Booking booking({
    required BookingStatus status,
    String paymentStatus = 'unpaid',
  }) {
    final now = DateTime(2026, 1, 1);
    return Booking(
      id: 'b1',
      listingId: 'l1',
      tenantName: 'Guest',
      startAt: now,
      endAt: now.add(const Duration(days: 1)),
      totalPrice: 100,
      unitLabel: 'night',
      userId: 'u1',
      status: status,
      createdAt: now,
      paymentStatus: paymentStatus,
    );
  }

  group('Booking.isEarnedRevenue (payment-driven realized earnings)', () {
    test('paid + confirmed counts as earned (the reported bug)', () {
      final b = booking(status: BookingStatus.confirmed, paymentStatus: 'paid');
      expect(b.isEarnedRevenue, isTrue);
      expect(b.isPendingPayout, isFalse);
    });

    test('paid + active counts as earned', () {
      final b = booking(status: BookingStatus.active, paymentStatus: 'paid');
      expect(b.isEarnedRevenue, isTrue);
      expect(b.isPendingPayout, isFalse);
    });

    test('completed counts as earned even when unpaid (legacy stays)', () {
      final b = booking(status: BookingStatus.completed);
      expect(b.isEarnedRevenue, isTrue);
      expect(b.isPendingPayout, isFalse);
    });

    test('completed + paid counts as earned', () {
      final b = booking(status: BookingStatus.completed, paymentStatus: 'paid');
      expect(b.isEarnedRevenue, isTrue);
    });

    test('confirmed + unpaid is pending, not earned', () {
      final b = booking(status: BookingStatus.confirmed);
      expect(b.isEarnedRevenue, isFalse);
      expect(b.isPendingPayout, isTrue);
    });

    test('active + unpaid is pending, not earned', () {
      final b = booking(status: BookingStatus.active);
      expect(b.isEarnedRevenue, isFalse);
      expect(b.isPendingPayout, isTrue);
    });

    test('cancelled/rejected/refunded never count, even if once paid', () {
      expect(
        booking(status: BookingStatus.cancelled, paymentStatus: 'paid')
            .isEarnedRevenue,
        isFalse,
      );
      expect(booking(status: BookingStatus.rejected).isEarnedRevenue, isFalse);
      expect(
        booking(status: BookingStatus.confirmed, paymentStatus: 'refunded')
            .isEarnedRevenue,
        isFalse,
      );
      // ...and none of them sit in pending either.
      expect(
        booking(status: BookingStatus.cancelled, paymentStatus: 'paid')
            .isPendingPayout,
        isFalse,
      );
    });

    test('pending request is neither earned nor pending payout', () {
      final b = booking(status: BookingStatus.pending);
      expect(b.isEarnedRevenue, isFalse);
      expect(b.isPendingPayout, isFalse);
    });
  });
}
