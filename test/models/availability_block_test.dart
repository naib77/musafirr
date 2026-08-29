import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/availability_block.dart';
import 'package:musafir/screens/host/listing_availability_screen.dart';

AvailabilityBlock _block(DateTime start, DateTime end, {String? note}) =>
    AvailabilityBlock(
      id: 'b1',
      listingId: 'l1',
      startsAt: start,
      endsAt: end,
      note: note,
    );

void main() {
  group('AvailabilityBlock.overlaps', () {
    final block = _block(DateTime(2026, 9, 2), DateTime(2026, 9, 10));

    test('a stay inside the block collides', () {
      expect(
        block.overlaps(DateTime(2026, 9, 3), DateTime(2026, 9, 5)),
        isTrue,
      );
    });

    test('a stay straddling either edge collides', () {
      expect(
        block.overlaps(DateTime(2026, 9, 1), DateTime(2026, 9, 3)),
        isTrue,
      );
      expect(
        block.overlaps(DateTime(2026, 9, 9), DateTime(2026, 9, 12)),
        isTrue,
      );
    });

    test('a stay that merely touches an edge does NOT collide', () {
      // The half-open '[)' rule the whole schema uses. Getting this wrong is
      // not a rounding error: it would make a block ending on checkout day eat
      // the next guest's check-in, and a block starting on checkout day
      // reject a stay that ends exactly as the block begins.
      expect(
        block.overlaps(DateTime(2026, 9, 10), DateTime(2026, 9, 12)),
        isFalse,
        reason: 'stay starts exactly when the block ends',
      );
      expect(
        block.overlaps(DateTime(2026, 8, 30), DateTime(2026, 9, 2)),
        isFalse,
        reason: 'stay ends exactly when the block starts',
      );
    });

    test('a stay wholly before or after does not collide', () {
      expect(
        block.overlaps(DateTime(2026, 8, 1), DateTime(2026, 8, 5)),
        isFalse,
      );
      expect(
        block.overlaps(DateTime(2026, 10, 1), DateTime(2026, 10, 5)),
        isFalse,
      );
    });
  });

  group('AvailabilityBlock.fromJson', () {
    test('parses the row shape the RPC and the table both return', () {
      final b = AvailabilityBlock.fromJson({
        'id': 'abc',
        'listing_id': 'lst',
        'starts_at': '2026-09-02T00:00:00+00:00',
        'ends_at': '2026-09-10T00:00:00+00:00',
        'note': 'Family visit',
      });
      expect(b.id, 'abc');
      expect(b.listingId, 'lst');
      expect(b.note, 'Family visit');
      expect(b.startsAt.isUtc, isFalse, reason: 'converted to local');
      expect(b.endsAt.difference(b.startsAt), const Duration(days: 8));
    });

    test('a null note is allowed — the note is optional', () {
      final b = AvailabilityBlock.fromJson({
        'id': 'abc',
        'listing_id': 'lst',
        'starts_at': '2026-09-02T00:00:00Z',
        'ends_at': '2026-09-03T00:00:00Z',
        'note': null,
      });
      expect(b.note, isNull);
    });
  });

  group('formatAvailabilityRange', () {
    test('whole-day ranges read as the last OCCUPIED day, not the end bound',
        () {
      // 2 Sep 00:00 -> 10 Sep 00:00 is a block over 2..9 Sep; 10 Sep is
      // bookable. Showing "2-10 Sep" would tell the host they have lost a day
      // they still have.
      expect(
        formatAvailabilityRange(DateTime(2026, 9, 2), DateTime(2026, 9, 10)),
        '2–9 Sep 2026',
      );
    });

    test('a single blocked day collapses to one date', () {
      expect(
        formatAvailabilityRange(DateTime(2026, 9, 21), DateTime(2026, 9, 22)),
        '21 Sep 2026',
      );
    });

    test('a range spanning months spells both ends out', () {
      expect(
        formatAvailabilityRange(DateTime(2026, 9, 28), DateTime(2026, 10, 3)),
        '28 Sep 2026 – 2 Oct 2026',
      );
    });

    test('an hourly booking keeps its real endpoints and shows times', () {
      // The whole-day convention subtracts a day. Applied to a 10:00-15:00
      // booking that yields "1 Oct - 30 Sep": a range running backwards.
      expect(
        formatAvailabilityRange(
          DateTime(2026, 10, 1, 10),
          DateTime(2026, 10, 1, 15),
        ),
        '1 Oct 2026, 10:00–15:00',
      );
    });

    test('a multi-day sub-day-aligned range shows both dates and times', () {
      expect(
        formatAvailabilityRange(
          DateTime(2026, 10, 1, 22),
          DateTime(2026, 10, 3, 6, 30),
        ),
        '1 Oct 2026 22:00 – 3 Oct 2026 06:30',
      );
    });
  });
}
