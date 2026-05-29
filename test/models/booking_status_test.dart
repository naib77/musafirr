import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/booking_status.dart';

void main() {
  group('BookingStatus', () {
    test('has all expected status values', () {
      expect(BookingStatus.values, containsAll([
        BookingStatus.pending,
        BookingStatus.confirmed,
        BookingStatus.rejected,
        BookingStatus.active,
        BookingStatus.completed,
        BookingStatus.cancelled,
      ]));
    });

    group('isActive', () {
      test('pending is active', () {
        expect(BookingStatus.pending.isActive, isTrue);
      });

      test('confirmed is active', () {
        expect(BookingStatus.confirmed.isActive, isTrue);
      });

      test('active (checked-in) is active', () {
        expect(BookingStatus.active.isActive, isTrue);
      });

      test('rejected is not active', () {
        expect(BookingStatus.rejected.isActive, isFalse);
      });

      test('completed is not active', () {
        expect(BookingStatus.completed.isActive, isFalse);
      });

      test('cancelled is not active', () {
        expect(BookingStatus.cancelled.isActive, isFalse);
      });
    });

    group('isPast', () {
      test('completed is past', () {
        expect(BookingStatus.completed.isPast, isTrue);
      });

      test('cancelled is past', () {
        expect(BookingStatus.cancelled.isPast, isTrue);
      });

      test('rejected is past', () {
        expect(BookingStatus.rejected.isPast, isTrue);
      });

      test('pending is not past', () {
        expect(BookingStatus.pending.isPast, isFalse);
      });

      test('confirmed is not past', () {
        expect(BookingStatus.confirmed.isPast, isFalse);
      });

      test('active is not past', () {
        expect(BookingStatus.active.isPast, isFalse);
      });
    });

    group('title', () {
      test('all statuses have display titles', () {
        for (final status in BookingStatus.values) {
          expect(status.title, isNotEmpty);
        }
      });

      test('rejected has correct title', () {
        expect(BookingStatus.rejected.title, equals('Declined'));
      });

      test('active has correct title', () {
        expect(BookingStatus.active.title, equals('Checked In'));
      });
    });
  });
}
