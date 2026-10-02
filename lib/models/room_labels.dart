import 'listing_unit.dart';

/// What [parseRoomLabels] made of the host's room-name field.
class RoomLabelParse {
  const RoomLabelParse(this.labels, this.errors);

  /// In the order typed, ranges expanded, duplicates dropped.
  final List<String> labels;

  /// One line per problem, already worded for the host. Non-empty means the
  /// form must not save: the RPC would refuse the same input anyway, and
  /// refusing here names the token at fault.
  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

/// The most rooms one range may expand to. A typo like "101-1010" should be
/// an error, not 910 rooms.
const kRoomRangeMax = 100;

/// `add_listing_units` takes at most this many labels per call.
const kRoomLabelsPerCall = 200;

/// Parses what a host types for a room type's rooms (plan §8, step 3):
/// names separated by commas, semicolons or new lines, where `101-110` or
/// `A1-A5` is a range. Zero padding is kept (`01-03` gives 01, 02, 03), and
/// both ends of a range must share the prefix (`A1-B5` is an error, not a
/// guess). Anything that is not a range is one name as typed, so `G-1` or
/// `Garden room` work.
///
/// Duplicates compare the way 153's `fn_unit_label_unique_in_property`
/// does -- ignoring case and surrounding spaces -- so the form refuses
/// exactly what the database would.
RoomLabelParse parseRoomLabels(String input) {
  final labels = <String>[];
  final seen = <String>{};
  final errors = <String>[];
  final dupes = <String>{};

  void add(String label) {
    final key = label.trim().toLowerCase();
    if (!seen.add(key)) {
      dupes.add(label);
      return;
    }
    labels.add(label);
  }

  for (final raw in input.split(RegExp(r'[,;\n]'))) {
    final token = raw.trim();
    if (token.isEmpty) continue;

    final range = _range.firstMatch(token);
    if (range != null) {
      final prefix = range.group(1)!;
      final startText = range.group(2)!;
      final otherPrefix = range.group(3)!;
      final endText = range.group(4)!;
      final start = int.parse(startText);
      final end = int.parse(endText);
      if (otherPrefix.isNotEmpty &&
          otherPrefix.trim().toLowerCase() != prefix.trim().toLowerCase()) {
        errors.add('"$token": both ends of a range need the same prefix.');
        continue;
      }
      if (end < start) {
        errors.add('"$token": the range runs backwards.');
        continue;
      }
      if (end - start + 1 > kRoomRangeMax) {
        errors.add('"$token": a range can cover at most $kRoomRangeMax '
            'rooms.');
        continue;
      }
      // Pad to the start's width only when it was written padded ("01"),
      // so "9-11" gives 9, 10, 11 rather than 09.
      final width = startText.startsWith('0') ? startText.length : 0;
      for (var n = start; n <= end; n++) {
        final label = '$prefix${n.toString().padLeft(width, '0')}';
        if (label.length > kRoomLabelMaxLength) {
          errors.add('"$token": names can be at most $kRoomLabelMaxLength '
              'characters.');
          break;
        }
        add(label);
      }
      continue;
    }

    if (token.length > kRoomLabelMaxLength) {
      errors.add('"$token": names can be at most $kRoomLabelMaxLength '
          'characters.');
      continue;
    }
    add(token);
  }

  if (dupes.isNotEmpty) {
    errors.add('Listed more than once: ${dupes.join(', ')}.');
  }
  if (labels.length > kRoomLabelsPerCall) {
    errors.add('Add at most $kRoomLabelsPerCall rooms at a time.');
  }
  return RoomLabelParse(List.unmodifiable(labels), List.unmodifiable(errors));
}

/// prefix, start digits, optional repeated prefix, end digits. The prefix is
/// lazy and digit-free so `101-110` has an empty one, and a hyphen inside a
/// name with no digits after it (`G-A`) is not a range.
final _range = RegExp(r'^(\D*?)(\d+)\s*-\s*(\D*?)(\d+)$');
