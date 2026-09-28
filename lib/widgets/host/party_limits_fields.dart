import 'package:flutter/material.dart';

import '../../models/listing.dart';

/// The host's side of the guest "Who" panel: optional caps per guest type.
///
/// ## Why these are optional, and how "optional" is spelled
///
/// [PartyLimits] is null-per-field, and null is a *meaning* — "I did not set a
/// separate limit here" — not a missing value. Every listing that existed
/// before migration 118 is null on all four, and a null field drops out of the
/// search predicate entirely rather than defaulting to zero. So the control has
/// to be able to express null, and to get back to it.
///
/// Rather than a switch above a group of steppers, each row simply steps down
/// past its floor into **"Any"**. One control, one axis, and no way to reach
/// the confusing state a separate toggle allows (limits typed in, switch off).
///
/// ## Why it is a widget and not written into the two screens
///
/// Hosts reach these fields from `CreateListingScreen` and from
/// `EditListingScreen`, which are two hand-written forms over the same model.
/// Anything living in only one of them is a field a host can set but never
/// change, or change but never set. Both screens render this.
///
/// Pets are deliberately **not** here — see [MaxPetsField].
class PartyLimitsFields extends StatelessWidget {
  const PartyLimitsFields({
    super.key,
    required this.limits,
    required this.maxGuests,
    required this.onChanged,
  });

  final PartyLimits limits;

  /// The listing's total capacity, used only as each row's ceiling. A sub-cap
  /// above the total would be unreachable — the total rejects the party first.
  final int maxGuests;

  final ValueChanged<PartyLimits> onChanged;

  /// Infants do not count towards `max_guests`, so their ceiling cannot come
  /// from it the way the other two do.
  static const int infantCeiling = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Guest types', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Optional. Leave these on “Any” unless your place needs a separate '
          'limit — the total above already applies.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        OptionalCounterRow(
          label: 'Adults',
          description: 'Ages 13 or above',
          value: limits.adults,
          // A listing admitting zero adults is not a stay; it is a slip that
          // would silently remove the place from every search.
          min: 1,
          max: maxGuests,
          onChanged: (v) =>
              onChanged(limits.copyWith(adults: v, clearAdults: v == null)),
        ),
        OptionalCounterRow(
          label: 'Children',
          description: 'Ages 2 – 12',
          value: limits.children,
          // Zero is meaningful here and different from "Any": an adults-only
          // place says nought children, and must still be findable by adults.
          min: 0,
          max: maxGuests,
          onChanged: (v) =>
              onChanged(limits.copyWith(children: v, clearChildren: v == null)),
        ),
        OptionalCounterRow(
          label: 'Infants',
          description: 'Under 2 · never counted in the total above',
          value: limits.infants,
          min: 0,
          max: infantCeiling,
          onChanged: (v) =>
              onChanged(limits.copyWith(infants: v, clearInfants: v == null)),
        ),
      ],
    );
  }
}

/// How many pets, asked only of a host who allows them at all.
///
/// Separate from [PartyLimitsFields] because pets are the one category with a
/// pre-existing switch — `pets_allowed` (053) — and the number is meaningless
/// without it. The caller renders this directly beneath that toggle, so the
/// question arrives in the place the host just answered "yes" and nowhere else.
///
/// Null here means "allowed, no stated number", **not** "none": the toggle
/// already carries "none". That is why the row reads "Any" rather than "0"
/// when unset, and why turning the toggle back off does not have to clear it —
/// search checks `pets_allowed` before it ever looks at the number.
class MaxPetsField extends StatelessWidget {
  const MaxPetsField({
    super.key,
    required this.petsAllowed,
    required this.maxPets,
    required this.onChanged,
  });

  final bool petsAllowed;
  final int? maxPets;
  final ValueChanged<int?> onChanged;

  static const int ceiling = 5;

  @override
  Widget build(BuildContext context) {
    // Hidden rather than disabled: a greyed-out number under an off switch
    // invites the host to wonder what it would do, and the answer is nothing.
    if (!petsAllowed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: OptionalCounterRow(
        label: 'Maximum pets',
        description: 'Leave on “Any” for no stated number',
        value: maxPets,
        min: 1,
        max: ceiling,
        onChanged: onChanged,
      ),
    );
  }
}

/// A stepper whose floor is **"Any"** rather than a number.
///
/// Stepping down from [min] yields null, and stepping up from null yields
/// [min]. That makes "no limit" a position on the same axis as the numbers
/// instead of a second control beside them, which is what lets a host set a cap
/// and then genuinely take it back off — the thing a plain `int` stepper cannot
/// express and the reason these columns are nullable in the first place.
class OptionalCounterRow extends StatelessWidget {
  const OptionalCounterRow({
    super.key,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
  });

  final String label;
  final String description;
  final int? value;
  final ValueChanged<int?> onChanged;

  /// The lowest real number. One step below it is "Any", not [min] - 1.
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = value;
    // Never disabled: from null the only way is up, from min the only way down
    // is back to null, and in between both directions are live.
    final onDecrement = current == null
        ? null
        : () => onChanged(current <= min ? null : current - 1);
    final onIncrement = current == null
        ? () => onChanged(min)
        : (current < max ? () => onChanged(current + 1) : null);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: theme.textTheme.bodyLarge),
                Text(
                  description,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: onDecrement,
            tooltip: 'Fewer $label',
          ),
          SizedBox(
            width: 48,
            child: Text(
              current == null ? 'Any' : '$current',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                // "Any" is the unset state and should not read as a value the
                // host chose; the numbers beside it should.
                color: current == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: onIncrement,
            tooltip: 'More $label',
          ),
        ],
      ),
    );
  }
}
