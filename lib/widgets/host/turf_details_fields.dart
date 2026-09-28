import 'package:flutter/material.dart';

import '../../models/turf_details.dart';

/// Sport / format / surface, the three things a turf states about itself
/// (migration 121).
///
/// Rendered by BOTH host surfaces — the create wizard's turf page and the edit
/// screen's inline form — for the same reason [GuestPartyFields] is shared
/// between the mobile sheet and the desktop Who panel: the moment one of them
/// grows a fourth field or changes a vocabulary, the other has to agree, and
/// the wire values here are pinned by check constraints in the database. Two
/// copies would drift into one screen offering a sport the other refuses.
///
/// Stateless over a [TurfDetails] and a callback, which is the one shape a
/// wizard holding form state and a plain `setState` can both supply.
class TurfDetailsFields extends StatelessWidget {
  const TurfDetailsFields({
    super.key,
    required this.details,
    required this.onChanged,
  });

  final TurfDetails details;
  final ValueChanged<TurfDetails> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TurfChoiceField<TurfSport>(
          label: 'Sport',
          hint: 'What is the ground marked for?',
          values: TurfSport.values,
          selected: details.sport,
          labelOf: (v) => v.label,
          // Tapping the selected chip again clears it: all three of these are
          // nullable in 121 and a host must be able to take a statement back
          // off, not merely change it to a different wrong answer. Same
          // reasoning as PartyLimits' "Any" floor.
          onChanged: (v) =>
              onChanged(details.copyWith(sport: v, clearSport: v == null)),
        ),
        const SizedBox(height: 20),
        TurfChoiceField<TurfFormat>(
          label: 'Format',
          hint: 'How big a side does it take?',
          values: TurfFormat.values,
          selected: details.format,
          labelOf: (v) => v.label,
          onChanged: (v) =>
              onChanged(details.copyWith(format: v, clearFormat: v == null)),
        ),
        const SizedBox(height: 20),
        TurfChoiceField<TurfSurface>(
          label: 'Surface',
          hint: 'What is it made of?',
          values: TurfSurface.values,
          selected: details.surface,
          labelOf: (v) => v.label,
          onChanged: (v) =>
              onChanged(details.copyWith(surface: v, clearSurface: v == null)),
        ),
      ],
    );
  }
}

/// A labelled row of single-select chips over an enum, where re-tapping the
/// selected chip clears the answer back to "not stated".
class TurfChoiceField<T> extends StatelessWidget {
  const TurfChoiceField({
    super.key,
    required this.label,
    required this.hint,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final List<T> values;
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Text(
              'Optional',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          hint,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values.map((v) {
            final isSelected = v == selected;
            return ChoiceChip(
              selected: isSelected,
              label: Text(labelOf(v)),
              onSelected: (_) => onChanged(isSelected ? null : v),
            );
          }).toList(),
        ),
      ],
    );
  }
}
