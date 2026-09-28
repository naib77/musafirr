import '../../models/listing.dart';

/// One line describing the per-category caps a host set, or null when they set
/// none.
///
/// ## Why this exists at all
///
/// Since migration 118 these caps decide which searches a listing appears in.
/// A limit that silently removes a place from someone's results but is nowhere
/// on the page is the kind of thing a guest discovers by messaging the host, so
/// whatever the host stated gets said out loud.
///
/// ## Why it is a pure function
///
/// The interesting part is entirely in the wording, and the wording has cases:
/// "0" has to become "no children" rather than "at most 0 children", a single
/// child must not be "1 children", and a permissive pets toggle with no number
/// must say nothing rather than "at most null pets". None of that is reachable
/// from a widget test without building a listing page.
///
/// Returns null when there is nothing to say, so the caller can omit the whole
/// row rather than render an empty one — which is the common case by far.
String? partyLimitsSentence(PartyLimits limits, {required bool petsAllowed}) {
  final parts = <String>[];

  void add(int? value, String singular, String plural) {
    if (value == null) return;
    // Zero is a real answer and a different one: "no children" is a rule, and
    // reading it as "at most 0" would be technically true and unsayable.
    parts.add(
        value == 0 ? 'no $plural' : '$value ${value == 1 ? singular : plural}');
  }

  add(limits.adults, 'adult', 'adults');
  add(limits.children, 'child', 'children');
  add(limits.infants, 'infant', 'infants');

  // Pets only when the host allows them at all. A number under a closed toggle
  // is stale data that search never reads, so the page must not read it either
  // — otherwise a host who set 2 and then switched pets off would still be
  // advertising "at most 2 pets".
  if (petsAllowed) add(limits.pets, 'pet', 'pets');

  if (parts.isEmpty) return null;
  return 'At most ${parts.join(' · ')}';
}
