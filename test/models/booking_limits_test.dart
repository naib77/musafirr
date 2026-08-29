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

  // Until migration 111 these limits were enforced in the booking form ONLY —
  // create_marketplace_booking never read min_nights/max_nights, so a guest
  // could book below the host's stated minimum. 111 added the server-side
  // check, which means there are now two implementations of the same rule and
  // they have to agree.
  //
  // The subtle half is the default. `minFor` returns `?? 1`; the server says
  // `coalesce(v_min, 1)`. If either side ever changes that (to 0, or to "no
  // minimum"), the form and the server disagree about the floor and the guest
  // gets refused for a duration the UI happily let them pick — a dead end with
  // no way out except guessing. These cases pin the contract.
  group('BookingLimits parity with create_marketplace_booking (111)', () {
    test('an unset minimum is 1, not 0 — matching coalesce(v_min, 1)', () {
      const limits = BookingLimits();
      for (final plan in DurationType.values) {
        expect(limits.minFor(plan), 1, reason: '${plan.name}: unset min is 1');
      }
    });

    test('an unset maximum is uncapped — matching `v_max is not null`', () {
      const limits = BookingLimits();
      for (final plan in DurationType.values) {
        expect(limits.maxFor(plan), isNull, reason: '${plan.name}: no cap');
      }
    });

    test('the boundary values the server accepts are accepted here too', () {
      // Server: refuses `v_qty < coalesce(v_min, 1)` and `v_qty > v_max`. So
      // exactly-min and exactly-max are both legal, on both sides.
      const limits = BookingLimits(minHours: 4, maxHours: 12);
      expect(4 < limits.minFor(DurationType.hourly), isFalse);
      expect(12 > limits.maxFor(DurationType.hourly)!, isFalse);
      expect(3 < limits.minFor(DurationType.hourly), isTrue);
      expect(13 > limits.maxFor(DurationType.hourly)!, isTrue);
    });
  });
}
