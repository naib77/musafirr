import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/search_filters.dart';
import 'search_popover.dart';

/// The party a guest is searching for: who is coming, and what is coming with
/// them.
///
/// A value type rather than four loose ints because the four are not
/// independent — [guestCount] is derived from two of them and capped across
/// both, so anything that edits one has to be able to see the others. Every
/// mutation goes through [copyWith], which keeps that arithmetic in one place.
@immutable
class GuestParty {
  const GuestParty({
    this.adults = 1,
    this.children = 0,
    this.infants = 0,
    this.pets = 0,
  });

  /// The party currently being searched for, read off live filters.
  GuestParty.from(SearchFilters filters)
      : adults = filters.adults,
        children = filters.children,
        infants = filters.infants,
        pets = filters.pets;

  final int adults;
  final int children;
  final int infants;
  final int pets;

  /// What actually reaches `search_listings` and is compared against a
  /// listing's `max_guests`. Infants and pets are excluded — see
  /// [guestCountFor], which is the single place that rule lives.
  int get guestCount => guestCountFor(adults: adults, children: children);

  /// Adults + children, uncapped and unfloored. The cap has to be applied to
  /// the pair, not to either row, so the two `+` buttons stop together.
  int get countedTotal => adults + children;

  GuestParty copyWith({int? adults, int? children, int? infants, int? pets}) {
    return GuestParty(
      adults: adults ?? this.adults,
      children: children ?? this.children,
      infants: infants ?? this.infants,
      pets: pets ?? this.pets,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GuestParty &&
      other.adults == adults &&
      other.children == children &&
      other.infants == infants &&
      other.pets == pets;

  @override
  int get hashCode => Object.hash(adults, children, infants, pets);
}

/// The four stepper rows behind "Who" — adults, children, infants, pets.
///
/// ## Why this is a widget and not just part of the panel
///
/// There are two search surfaces and they are not the same code: the desktop
/// bar's WhoPanel writes to a `SearchDraft`, while mobile's `_SearchSheet`
/// keeps plain `setState` fields and commits them itself. CLAUDE.md has been
/// carrying a note that the sheet is "a second implementation of each control"
/// and that the two will drift; the guest counter is the first one to actually
/// be paid for, because the sheet's version was a single number and could not
/// express any of this.
///
/// So the rows live here, stateless, over a value and a callback — the one
/// shape both a draft and a `setState` can hold. Neither surface knows how many
/// rows there are or what the caps are, which is the whole point: adding a
/// fifth category later is one edit, not two.
///
/// The rows are deliberately NOT individually capped at [maxSearchGuests].
/// Adults and children share one budget because their sum is what becomes
/// `guestCount`; infants and pets have their own ceilings because they are
/// counted separately by the database and by nobody's idea of a headcount.
class GuestPartyFields extends StatelessWidget {
  const GuestPartyFields({
    super.key,
    required this.party,
    required this.onChanged,
    this.padding = const EdgeInsets.fromLTRB(24, 8, 24, 12),
  });

  final GuestParty party;
  final ValueChanged<GuestParty> onChanged;
  final EdgeInsetsGeometry padding;

  /// Sane ceilings for the two uncounted categories. Not database limits —
  /// `max_infants` / `max_pets` are per listing and may be lower — just the
  /// point past which the control stops being a control.
  static const int maxInfants = 5;
  static const int maxPets = 5;

  @override
  Widget build(BuildContext context) {
    // Whatever is left of the shared adults+children budget. Computed once and
    // added to each row's own value, so a row can always come back down even
    // if the party is somehow already over (a filter restored from a wider
    // cap, say) — a `max` below `value` would strand the guest at a number
    // they cannot reduce.
    final headroom = maxSearchGuests - party.countedTotal;
    final spare = headroom > 0 ? headroom : 0;
    final full = party.countedTotal >= maxSearchGuests;

    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SearchStepperRow(
            label: 'Adults',
            description: 'Ages 13 or above',
            value: party.adults,
            // At least one adult. A stay booked by nobody is not a search, and
            // guestCountFor floors at 1 regardless — better to show the floor
            // than to let the number drop and be silently corrected later.
            min: 1,
            max: party.adults + spare,
            onChanged: (v) => onChanged(party.copyWith(adults: v)),
          ),
          Divider(height: 1, color: AppColors.outline),
          SearchStepperRow(
            label: 'Children',
            description: 'Ages 2 – 12',
            value: party.children,
            min: 0,
            max: party.children + spare,
            onChanged: (v) => onChanged(party.copyWith(children: v)),
          ),
          Divider(height: 1, color: AppColors.outline),
          SearchStepperRow(
            label: 'Infants',
            description: 'Under 2 · not counted in the total',
            value: party.infants,
            min: 0,
            max: maxInfants,
            onChanged: (v) => onChanged(party.copyWith(infants: v)),
          ),
          Divider(height: 1, color: AppColors.outline),
          SearchStepperRow(
            label: 'Pets',
            // Worth spelling out, because this row narrows harder than any
            // other in the panel: a listing that has not opted into pets is
            // excluded outright, not merely capped (see migration 118).
            description: 'Pet-friendly places only',
            value: party.pets,
            min: 0,
            max: maxPets,
            onChanged: (v) => onChanged(party.copyWith(pets: v)),
          ),
          if (full) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Up to $maxSearchGuests guests per stay.',
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
