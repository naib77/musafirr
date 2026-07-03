import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/message.dart';

void main() {
  BookingCardMetadata metadata({
    String? durationLabel,
    DateTime? checkIn,
    DateTime? checkOut,
  }) {
    return BookingCardMetadata(
      bookingId: 'b1',
      listingName: 'cozy room 1',
      checkIn: checkIn ?? DateTime(2026, 7, 3, 10),
      checkOut: checkOut ?? DateTime(2026, 7, 3, 12),
      totalPrice: 500,
      currency: 'BDT',
      status: 'confirmed',
      durationLabel: durationLabel,
    );
  }

  group('BookingCardMetadata.displayDuration', () {
    test('uses the booking-provided label verbatim when present', () {
      expect(metadata(durationLabel: '2 hours').displayDuration, '2 hours');
      expect(metadata(durationLabel: '1 month').displayDuration, '1 month');
    });

    test('falls back to hours for same-day spans — never "0 nights"', () {
      expect(metadata().displayDuration, '2 hours');
      expect(
        metadata(
          checkIn: DateTime(2026, 7, 3, 10),
          checkOut: DateTime(2026, 7, 3, 10, 30),
        ).displayDuration,
        '1 hour',
      );
    });

    test('falls back to nights for multi-day spans', () {
      expect(
        metadata(
          checkIn: DateTime(2026, 7, 3),
          checkOut: DateTime(2026, 7, 5),
        ).displayDuration,
        '2 nights',
      );
    });

    test('round-trips duration_label through JSON', () {
      final json = metadata(durationLabel: '3 hours').toJson();
      expect(BookingCardMetadata.fromJson(json).displayDuration, '3 hours');
    });
  });

  group('BookingCardMetadata.dateRange', () {
    test('same-day booking shows date with time range', () {
      // intl separates time and AM/PM with a narrow no-break space, so
      // assert the pieces rather than the exact string.
      final range = metadata().dateRange;
      expect(range, contains('Jul 3'));
      expect(range, contains('10:00'));
      expect(range, contains('AM'));
      expect(range, contains('12:00'));
      expect(range, contains('PM'));
    });

    test('multi-day booking shows both dates', () {
      final range = metadata(
        checkIn: DateTime(2026, 6, 30),
        checkOut: DateTime(2026, 7, 7),
      ).dateRange;
      expect(range, 'Jun 30 – Jul 7');
    });
  });
}
