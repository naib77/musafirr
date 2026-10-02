import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/room_labels.dart';

void main() {
  group('parseRoomLabels', () {
    test('plain names, any separator, blanks skipped', () {
      final r = parseRoomLabels('106, 107;\n206 ,, 207\n');
      expect(r.labels, ['106', '107', '206', '207']);
      expect(r.isValid, isTrue);
    });

    test('numeric range', () {
      expect(parseRoomLabels('101-105').labels,
          ['101', '102', '103', '104', '105']);
    });

    test('ranges and names mix (the Sea Crown deluxe floor)', () {
      final r = parseRoomLabels('101-105, 201-203, Garden room');
      expect(r.labels, [
        '101', '102', '103', '104', '105', //
        '201', '202', '203', 'Garden room',
      ]);
    });

    test('prefixed range, prefix on both ends or only the first', () {
      expect(parseRoomLabels('A1-A3').labels, ['A1', 'A2', 'A3']);
      expect(parseRoomLabels('A1-3').labels, ['A1', 'A2', 'A3']);
      expect(parseRoomLabels('Room 1 - Room 2').labels, ['Room 1', 'Room 2']);
    });

    test('zero padding is kept only when written', () {
      expect(parseRoomLabels('08-10').labels, ['08', '09', '10']);
      expect(parseRoomLabels('9-11').labels, ['9', '10', '11']);
    });

    test('a hyphen without digits after it is a name', () {
      expect(parseRoomLabels('G-A, North-wing').labels, ['G-A', 'North-wing']);
    });

    test('mismatched prefixes are refused, not guessed', () {
      final r = parseRoomLabels('A1-B5');
      expect(r.isValid, isFalse);
      expect(r.labels, isEmpty);
    });

    test('backwards range is refused', () {
      expect(parseRoomLabels('110-101').isValid, isFalse);
    });

    test('a range over the cap is refused (typo guard)', () {
      final r = parseRoomLabels('101-1010');
      expect(r.isValid, isFalse);
      expect(r.labels, isEmpty);
      expect(parseRoomLabels('1-100').labels, hasLength(100));
    });

    test('duplicates compare like the database: case and spaces ignored', () {
      final r = parseRoomLabels('101-103, 102, suite, Suite ');
      expect(r.labels, ['101', '102', '103', 'suite']);
      expect(r.isValid, isFalse);
      expect(r.errors.single, contains('102'));
    });

    test('names over 40 characters are refused', () {
      final long = 'x' * 41;
      final r = parseRoomLabels('101, $long');
      expect(r.labels, ['101']);
      expect(r.isValid, isFalse);
      expect(parseRoomLabels('x' * 40).isValid, isTrue);
    });

    test('more than one call can take is refused', () {
      final r = parseRoomLabels('1-100, 101-200, 201');
      expect(r.labels, hasLength(201));
      expect(r.isValid, isFalse);
    });

    test('empty input is valid and empty (count-only rooms)', () {
      final r = parseRoomLabels('  \n ');
      expect(r.labels, isEmpty);
      expect(r.isValid, isTrue);
    });
  });
}
