import 'package:flutter/material.dart';

import 'guest_party_fields.dart';
import 'search_draft.dart';

/// The desktop bar's "Who" segment: adults, children, infants and pets.
///
/// Thin on purpose. The rows, the caps and the arithmetic between them live in
/// [GuestPartyFields], which mobile's search sheet renders from the same source
/// — this class is only the adapter between that widget's value/callback shape
/// and the draft the desktop panels edit.
///
/// ## What reaches the database
///
/// `guestCount` (adults + children, floored at 1) is compared against a
/// listing's `max_guests`, as it always has been. The breakdown is not
/// decoration behind it: migration 118 gave listings optional `max_adults`,
/// `max_children`, `max_infants` and `max_pets`, so each row can narrow on its
/// own. Pets narrow hardest — a listing that never set `pets_allowed` is
/// excluded outright.
///
/// The split remains **search state only**. A booking still carries one number,
/// so a stay found as "2 adults, 1 child, 1 infant" is booked as 3 guests —
/// a deliberate scope line, restated in migration 118's own header.
class WhoPanel extends StatelessWidget {
  const WhoPanel({super.key, required this.draft});

  final SearchDraft draft;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: draft,
      // Read INSIDE the builder. Building the party outside it would capture
      // the values from the build that mounted the panel, so the caps would
      // stop moving the moment the panel stopped being rebuilt from above.
      builder: (context, _) => GuestPartyFields(
        party: GuestParty(
          adults: draft.adults,
          children: draft.children,
          infants: draft.infants,
          pets: draft.pets,
        ),
        onChanged: (party) => draft.edit(() {
          draft.adults = party.adults;
          draft.children = party.children;
          draft.infants = party.infants;
          draft.pets = party.pets;
        }),
      ),
    );
  }
}
