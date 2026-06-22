import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/booking.dart';
import 'package:musafir/models/booking_categorizer.dart';
import 'package:musafir/models/booking_status.dart';

/// Fixed reference "now" so every case is deterministic.
final _now = DateTime(2026, 6, 22, 12, 0);

Booking _booking({
  required BookingStatus status,
  required DateTime checkIn,
  required DateTime checkOut,
  String id = 'b',
}) {
  return Booking(
    id: id,
    listingId: 'l',
    tenantName: 'Guest',
    startAt: checkIn,
    endAt: checkOut,
    checkIn: checkIn,
    checkOut: checkOut,
    totalPrice: 100,
    unitLabel: 'night',
    status: status,
  );
}

void main() {
  // Three date windows relative to _now.
  final futureIn = _now.add(const Duration(days: 3));
  final futureOut = _now.add(const Duration(days: 5));

  final ongoingIn = _now.subtract(const Duration(days: 1));
  final ongoingOut = _now.add(const Duration(days: 2));

  final elapsedIn = _now.subtract(const Duration(days: 5));
  final elapsedOut = _now.subtract(const Duration(days: 2));

  group('Booking categorization — single bucket invariant', () {
    // Every (status, window) combination must land in EXACTLY ONE of
    // upcoming / ongoing / past. This is the core contract the three
    // reservation views depend on.
    final windows = {
      'future': (futureIn, futureOut),
      'ongoing': (ongoingIn, ongoingOut),
      'elapsed': (elapsedIn, elapsedOut),
    };

    for (final status in BookingStatus.values) {
      for (final entry in windows.entries) {
        test('${status.name} / ${entry.key} → exactly one bucket', () {
          final (ci, co) = entry.value;
          final b = _booking(status: status, checkIn: ci, checkOut: co);
          final flags = [
            b.isUpcomingAt(_now),
            b.isOngoingAt(_now),
            b.isPastAt(_now),
          ];
          final trueCount = flags.where((f) => f).length;
          expect(trueCount, 1,
              reason:
                  '${status.name}/${entry.key} should be in exactly one bucket, '
                  'got upcoming=${flags[0]} ongoing=${flags[1]} past=${flags[2]}');
        });
      }
    }
  });

  group('Booking categorization — host workflow expectations', () {
    // The model is STATUS-driven (date-independent) so that all three host/guest
    // reservation views agree regardless of whether a booking's date has slipped:
    //   pending + confirmed  -> Upcoming
    //   active (checked-in)  -> Current/Ongoing
    //   completed/cancelled/rejected -> Past
    test('pending request with a FUTURE date is Upcoming (host can act)', () {
      final b = _booking(
          status: BookingStatus.pending, checkIn: futureIn, checkOut: futureOut);
      expect(b.isUpcomingAt(_now), isTrue);
      expect(b.isPastAt(_now), isFalse);
    });

    test('pending request whose date already ELAPSED is still Upcoming, '
        'never buried in Past (this was the reported bug)', () {
      final b = _booking(
          status: BookingStatus.pending, checkIn: elapsedIn, checkOut: elapsedOut);
      expect(b.isUpcomingAt(_now), isTrue);
      expect(b.isPastAt(_now), isFalse);
      expect(b.isOngoingAt(_now), isFalse);
    });

    test('confirmed future booking is Upcoming', () {
      final b = _booking(
          status: BookingStatus.confirmed, checkIn: futureIn, checkOut: futureOut);
      expect(b.isUpcomingAt(_now), isTrue);
    });

    test('confirmed booking is Upcoming regardless of date — it only becomes '
        'Current when the host checks the guest in (status -> active). This is '
        'what keeps the dashboard and the Reservations tab in agreement.', () {
      // check-in date arrived but host has not checked the guest in yet
      final arrived = _booking(
          status: BookingStatus.confirmed, checkIn: ongoingIn, checkOut: ongoingOut);
      expect(arrived.isUpcomingAt(_now), isTrue);
      expect(arrived.isOngoingAt(_now), isFalse);

      // stay window fully elapsed but never checked in / completed — still a live
      // reservation the host must resolve, NOT silently filed under Past.
      final elapsed = _booking(
          status: BookingStatus.confirmed, checkIn: elapsedIn, checkOut: elapsedOut);
      expect(elapsed.isUpcomingAt(_now), isTrue);
      expect(elapsed.isPastAt(_now), isFalse);
    });

    test('checked-in (active) booking is Current/Ongoing so host can mark '
        'complete, even after checkout time passes', () {
      final b = _booking(
          status: BookingStatus.active, checkIn: elapsedIn, checkOut: elapsedOut);
      expect(b.isOngoingAt(_now), isTrue);
      expect(b.isPastAt(_now), isFalse);
      expect(b.isUpcomingAt(_now), isFalse);
    });

    test('terminal statuses are always Past regardless of dates', () {
      for (final status in [
        BookingStatus.completed,
        BookingStatus.cancelled,
        BookingStatus.rejected,
      ]) {
        final b = _booking(status: status, checkIn: futureIn, checkOut: futureOut);
        expect(b.isPastAt(_now), isTrue,
            reason: '${status.name} with future dates must still be Past');
        expect(b.isUpcomingAt(_now), isFalse);
        expect(b.isOngoingAt(_now), isFalse);
      }
    });
  });

  group('BookingCategorizer grouping', () {
    test('splits a mixed list into the three buckets without overlap', () {
      final bookings = [
        _booking(
            id: 'pending-future',
            status: BookingStatus.pending,
            checkIn: futureIn,
            checkOut: futureOut),
        _booking(
            id: 'pending-elapsed',
            status: BookingStatus.pending,
            checkIn: elapsedIn,
            checkOut: elapsedOut),
        _booking(
            id: 'confirmed-ongoing',
            status: BookingStatus.confirmed,
            checkIn: ongoingIn,
            checkOut: ongoingOut),
        _booking(
            id: 'active',
            status: BookingStatus.active,
            checkIn: ongoingIn,
            checkOut: ongoingOut),
        _booking(
            id: 'completed',
            status: BookingStatus.completed,
            checkIn: elapsedIn,
            checkOut: elapsedOut),
        _booking(
            id: 'rejected',
            status: BookingStatus.rejected,
            checkIn: futureIn,
            checkOut: futureOut),
      ];

      final c = BookingCategorizer(bookings, currentTime: _now);

      // confirmed-ongoing is a confirmed booking the host hasn't checked in yet,
      // so it is Upcoming (not Current) until status flips to active.
      expect(c.upcoming.map((b) => b.id),
          containsAll(['pending-future', 'pending-elapsed', 'confirmed-ongoing']));
      expect(c.current.map((b) => b.id), containsAll(['active']));
      expect(c.past.map((b) => b.id), containsAll(['completed', 'rejected']));

      // No booking appears in more than one bucket.
      final total = c.upcoming.length + c.current.length + c.past.length;
      expect(total, bookings.length);
    });

    test('upcoming is sorted by soonest check-in first', () {
      final bookings = [
        _booking(
            id: 'later',
            status: BookingStatus.confirmed,
            checkIn: _now.add(const Duration(days: 10)),
            checkOut: _now.add(const Duration(days: 12))),
        _booking(
            id: 'sooner',
            status: BookingStatus.confirmed,
            checkIn: _now.add(const Duration(days: 2)),
            checkOut: _now.add(const Duration(days: 4))),
      ];
      final c = BookingCategorizer(bookings, currentTime: _now);
      expect(c.upcoming.map((b) => b.id).toList(), ['sooner', 'later']);
    });
  });
}
