import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/booking/booking_accept_window.dart';

void main() {
  group('bookingAcceptWindowFromRaw', () {
    // AppSettingsService fails open by design, and this is read on the trips
    // screen — a malformed row must not stop a guest seeing their bookings.
    test('an absent or blank row keeps the default', () {
      expect(bookingAcceptWindowFromRaw(null), kDefaultBookingAcceptWindow);
      expect(bookingAcceptWindowFromRaw(''), kDefaultBookingAcceptWindow);
      expect(bookingAcceptWindowFromRaw('   '), kDefaultBookingAcceptWindow);
    });

    test('nonsense keeps the default rather than throwing', () {
      expect(bookingAcceptWindowFromRaw('soon'), kDefaultBookingAcceptWindow);
      expect(bookingAcceptWindowFromRaw('6h'), kDefaultBookingAcceptWindow);
      expect(bookingAcceptWindowFromRaw('2.5'), kDefaultBookingAcceptWindow);
    });

    test('reads a configured number of hours', () {
      expect(bookingAcceptWindowFromRaw('6'), const Duration(hours: 6));
      expect(bookingAcceptWindowFromRaw(' 48 '), const Duration(hours: 48));
    });

    // The database validator refuses these at the keystroke, so clamping here
    // is for rows written before that guard existed — not for ordinary input.
    test('clamps to the same range the database enforces', () {
      expect(bookingAcceptWindowFromRaw('0'), kMinBookingAcceptWindow);
      expect(bookingAcceptWindowFromRaw('-4'), kMinBookingAcceptWindow);
      expect(bookingAcceptWindowFromRaw('1000'), kMaxBookingAcceptWindow);
    });

    test('the edges the validator allows survive unclamped', () {
      expect(bookingAcceptWindowFromRaw('1'), kMinBookingAcceptWindow);
      expect(bookingAcceptWindowFromRaw('168'), kMaxBookingAcceptWindow);
    });
  });

  group('bookingAcceptRemaining', () {
    final created = DateTime(2026, 9, 10, 9);

    test('counts down from creation, not from now', () {
      expect(
        bookingAcceptRemaining(
          createdAt: created,
          window: const Duration(hours: 6),
          now: DateTime(2026, 9, 10, 11),
        ),
        const Duration(hours: 4),
      );
    });

    // The window is the admin's number, so a shorter one must genuinely leave
    // less time — this is the behaviour the whole setting exists for.
    test('a shorter window leaves less time', () {
      final short = bookingAcceptRemaining(
        createdAt: created,
        window: const Duration(hours: 2),
        now: DateTime(2026, 9, 10, 10),
      )!;
      final long = bookingAcceptRemaining(
        createdAt: created,
        window: const Duration(hours: 24),
        now: DateTime(2026, 9, 10, 10),
      )!;
      expect(short, const Duration(hours: 1));
      expect(long, const Duration(hours: 23));
    });

    // Negative rather than clamped: the cron sweeps every 15 minutes, so a
    // booking is legitimately still `pending` for a while after zero and the
    // caller needs to know which side of it we are on.
    test('goes negative once the window has closed', () {
      final remaining = bookingAcceptRemaining(
        createdAt: created,
        window: const Duration(hours: 2),
        now: DateTime(2026, 9, 10, 12),
      )!;
      expect(remaining.isNegative, isTrue);
    });

    test('a booking with no creation time has nothing to count down', () {
      expect(
        bookingAcceptRemaining(
          createdAt: null,
          window: const Duration(hours: 6),
        ),
        isNull,
      );
    });
  });

  group('formatBookingAcceptRemaining', () {
    test('hours and minutes inside two days', () {
      expect(
        formatBookingAcceptRemaining(const Duration(hours: 3, minutes: 20)),
        '3h 20m',
      );
      expect(
        formatBookingAcceptRemaining(const Duration(hours: 47, minutes: 5)),
        '47h 5m',
      );
    });

    test('minutes alone under an hour', () {
      expect(formatBookingAcceptRemaining(const Duration(minutes: 12)), '12m');
    });

    // The banner used to print a bare "${inHours}h ${m}m", which read as
    // "0h 0m" through the last minute of the window.
    test('the last minute says something, not "0h 0m"', () {
      expect(
        formatBookingAcceptRemaining(const Duration(seconds: 30)),
        'under a minute',
      );
    });

    // 168 hours is arithmetic; 7 days is English. Only reachable once an admin
    // sets a window longer than two days.
    test('days once the window is long enough to need them', () {
      expect(
        formatBookingAcceptRemaining(const Duration(hours: 50)),
        '2d 2h',
      );
      expect(formatBookingAcceptRemaining(const Duration(hours: 168)), '7d 0h');
    });

    test('a closed window is expired, never a negative clock', () {
      expect(
        formatBookingAcceptRemaining(const Duration(hours: -3)),
        'expired',
      );
    });
  });
}
