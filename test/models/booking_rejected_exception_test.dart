import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/booking_rejected_exception.dart';

void main() {
  group('isGuestFacingBookingRefusal', () {
    test('accepts the three SQLSTATEs the booking RPC refuses with', () {
      // 22023: capacity, dates, duration, missing rate, rejected coupon.
      expect(isGuestFacingBookingRefusal('22023'), isTrue);
      // P0002: the listing was deleted while the booking sheet was open.
      expect(isGuestFacingBookingRefusal('P0002'), isTrue);
      // 42501: the session expired mid-booking.
      expect(isGuestFacingBookingRefusal('42501'), isTrue);
    });

    test('rejects the conflict code, which has its own typed exception', () {
      // 23P01 must keep flowing to BookingConflictException — surfacing the raw
      // exclusion-constraint text would show the guest "bookings_no_overlap".
      expect(isGuestFacingBookingRefusal('23P01'), isFalse);
    });

    test('rejects faults, so their text never reaches a guest', () {
      for (final code in ['42P01', '23505', '23502', '08006', 'XX000']) {
        expect(isGuestFacingBookingRefusal(code), isFalse,
            reason: '$code is a fault, not a refusal');
      }
    });

    test('a missing code is not a refusal', () {
      // An offline drop has no SQLSTATE at all; it must not be treated as a
      // message worth showing.
      expect(isGuestFacingBookingRefusal(null), isFalse);
      expect(isGuestFacingBookingRefusal(''), isFalse);
    });
  });

  test('carries the server sentence through unchanged', () {
    // The whole point: the guest reads the server's words, not ours.
    const e = BookingRejectedException('This place hosts up to 4 guests',
        code: '22023');
    expect(e.message, 'This place hosts up to 4 guests');
    expect(e.code, '22023');
    expect(e.toString(), contains('This place hosts up to 4 guests'));
  });
}
