import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/listing.dart';
import 'package:musafir/models/rental_plan.dart';

void main() {
  group('BookingLimits.minFor', () {
    test('defaults to 1 when a plan minimum is unset', () {
      const limits = BookingLimits();
      expect(limits.minFor(DurationType.hourly), 1);
      expect(limits.minFor(DurationType.daily), 1);
      expect(limits.minFor(DurationType.monthly), 1);
    });

    test('returns the configured minimum per plan', () {
      const limits = BookingLimits(minHours: 2, minNights: 3, minMonths: 6);
      expect(limits.minFor(DurationType.hourly), 2);
      expect(limits.minFor(DurationType.daily), 3);
      expect(limits.minFor(DurationType.monthly), 6);
    });
  });

  group('BookingLimits.maxFor', () {
    test('returns null (no cap) when unset', () {
      const limits = BookingLimits();
      expect(limits.maxFor(DurationType.hourly), isNull);
      expect(limits.maxFor(DurationType.daily), isNull);
      expect(limits.maxFor(DurationType.monthly), isNull);
    });

    test('returns the configured maximum per plan', () {
      const limits = BookingLimits(maxHours: 8, maxNights: 14, maxMonths: 12);
      expect(limits.maxFor(DurationType.hourly), 8);
      expect(limits.maxFor(DurationType.daily), 14);
      expect(limits.maxFor(DurationType.monthly), 12);
    });
  });
}
