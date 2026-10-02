import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/availability_block.dart';
import 'package:musafir/models/listing_unit.dart';

ListingUnit _u(String id, {String? label, bool active = true}) =>
    ListingUnit(id: id, listingId: 'l1', label: label, isActive: active);

void main() {
  group('listingUnitName', () {
    final rooms = [
      _u('a'),
      _u('b', label: ' 201 '),
      _u('c'),
      _u('d', active: false)
    ];

    test('a labelled room shows its label, trimmed', () {
      expect(listingUnitName(rooms[1], rooms), '201');
    });

    test('an unlabelled room is named by its place in the list', () {
      expect(listingUnitName(rooms[0], rooms), 'Room 1');
      expect(listingUnitName(rooms[2], rooms), 'Room 3');
    });

    test('a blank label falls back to the position', () {
      final blank = _u('e', label: '   ');
      expect(listingUnitName(blank, [blank]), 'Room 1');
    });

    test('a room missing from the list is just "Room"', () {
      expect(listingUnitName(_u('zz'), rooms), 'Room');
    });
  });

  test('ListingUnit.fromJson reads the four columns', () {
    final u = ListingUnit.fromJson(const {
      'id': 'u1',
      'listing_id': 'l1',
      'label': null,
      'is_active': false,
    });
    expect((u.id, u.listingId, u.label, u.isActive), ('u1', 'l1', null, false));
  });

  test('AvailabilityBlock.fromJson keeps unit_id, null meaning the listing',
      () {
    Map<String, dynamic> row(String? unit) => {
          'id': 'b1',
          'listing_id': 'l1',
          'starts_at': '2026-10-02T00:00:00Z',
          'ends_at': '2026-10-03T00:00:00Z',
          'unit_id': unit,
        };
    expect(AvailabilityBlock.fromJson(row('u1')).unitId, 'u1');
    expect(AvailabilityBlock.fromJson(row(null)).unitId, isNull);
  });

  group('roomMoveRefusalMessage', () {
    // Keyed by hint: the SQL suite (151) pins these hints, not the text.
    test('every 151 hint has its own sentence', () {
      const hints = [
        'unit_taken',
        'unit_blocked',
        'unit_mismatch',
        'booking_not_live',
        'not_listing_owner',
      ];
      final messages = hints.map(roomMoveRefusalMessage).toSet();
      expect(messages, hasLength(hints.length));
      expect(messages, isNot(contains(roomMoveRefusalMessage(null))));
    });

    test('an unknown hint gets the generic retry line', () {
      expect(roomMoveRefusalMessage('something_new'),
          roomMoveRefusalMessage(null));
    });
  });
}
