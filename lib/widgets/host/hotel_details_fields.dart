import 'package:flutter/material.dart';

import '../../models/hotel_details.dart';
import 'turf_details_fields.dart';

/// Stars / front desk / ID at check-in, what a hotel states about itself
/// (migration 150).
///
/// Shared by the create wizard and the edit screen for the reason
/// [TurfDetailsFields] is: the wire values are pinned by check constraints,
/// and two copies would drift. Every answer is optional and re-tapping the
/// selected chip takes it back, because all three columns are nullable.
class HotelDetailsFields extends StatelessWidget {
  const HotelDetailsFields({
    super.key,
    required this.details,
    required this.onChanged,
  });

  final HotelDetails details;
  final ValueChanged<HotelDetails> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TurfChoiceField<int>(
          label: 'Star rating',
          hint: 'The class the hotel is registered or known as.',
          values: const [1, 2, 3, 4, 5],
          selected: details.starRating,
          labelOf: (v) => '$v★',
          onChanged: (v) => onChanged(
              details.copyWith(starRating: v, clearStarRating: v == null)),
        ),
        const SizedBox(height: 20),
        TurfChoiceField<bool>(
          label: '24-hour front desk',
          hint: 'Can a guest check in at 2am?',
          values: const [true, false],
          selected: details.frontDesk24h,
          labelOf: _yesNo,
          onChanged: (v) => onChanged(
              details.copyWith(frontDesk24h: v, clearFrontDesk24h: v == null)),
        ),
        const SizedBox(height: 20),
        TurfChoiceField<bool>(
          label: 'ID at check-in',
          hint: 'Do guests need to show an NID or passport?',
          values: const [true, false],
          selected: details.idRequired,
          labelOf: _yesNo,
          onChanged: (v) => onChanged(
              details.copyWith(idRequired: v, clearIdRequired: v == null)),
        ),
      ],
    );
  }
}

String _yesNo(bool v) => v ? 'Yes' : 'No';

/// Size / bathroom / toilet (150), for any stay.
///
/// Stateful only to own the size field's controller: re-creating it from
/// [facts] on every rebuild would move the cursor to the end mid-typing. Text
/// that does not parse reaches [onChanged] as "not stated" (never as a number
/// the size constraint would refuse with 23514) while the field shows why.
class RoomFactsFields extends StatefulWidget {
  const RoomFactsFields({
    super.key,
    required this.facts,
    required this.onChanged,
  });

  final RoomFacts facts;
  final ValueChanged<RoomFacts> onChanged;

  @override
  State<RoomFactsFields> createState() => _RoomFactsFieldsState();
}

class _RoomFactsFieldsState extends State<RoomFactsFields> {
  late final TextEditingController _size =
      TextEditingController(text: widget.facts.sizeSqft?.toString() ?? '');

  @override
  void dispose() {
    _size.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final facts = widget.facts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _size,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Room size (sq ft, optional)',
            helperText: 'The floor area of one room.',
            errorText: RoomFacts.sizeError(_size.text),
          ),
          onChanged: (text) {
            final n = RoomFacts.parseSize(text);
            setState(() {}); // refresh errorText
            widget.onChanged(
                facts.copyWith(sizeSqft: n, clearSizeSqft: n == null));
          },
        ),
        const SizedBox(height: 20),
        TurfChoiceField<BathroomKind>(
          label: 'Bathroom',
          hint: 'Private to the room, or down the hall?',
          values: BathroomKind.values,
          selected: facts.bathroom,
          labelOf: (v) => v.label,
          onChanged: (v) => widget
              .onChanged(facts.copyWith(bathroom: v, clearBathroom: v == null)),
        ),
        const SizedBox(height: 20),
        TurfChoiceField<ToiletKind>(
          label: 'Toilet',
          hint: 'Matters to elderly and foreign guests.',
          values: ToiletKind.values,
          selected: facts.toilet,
          labelOf: (v) => v.label,
          onChanged: (v) => widget
              .onChanged(facts.copyWith(toilet: v, clearToilet: v == null)),
        ),
      ],
    );
  }
}
