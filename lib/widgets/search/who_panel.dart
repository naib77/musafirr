import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/search_filters.dart';
import 'search_draft.dart';
import 'search_popover.dart';

/// The "Who" panel: adults, children and infants.
///
/// The app has always searched with a single guest number, and it still does —
/// `guestCount` is what reaches `search_listings` and gets compared against a
/// listing's `max_guests`. These three are the breakdown behind it, collected
/// the way every travel site collects it, with infants excluded from the total.
///
/// The split is **search state only**: a booking still carries one number, so a
/// stay found as "2 adults, 1 child, 1 infant" is booked as 3 guests. That is a
/// deliberate scope line, not an oversight — carrying it through would mean a
/// migration plus the booking sheet, the price breakdown and the host's
/// reservation list.
class WhoPanel extends StatelessWidget {
  const WhoPanel({super.key, required this.draft});

  final SearchDraft draft;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: draft,
      // Read INSIDE the builder. Computing the party outside it would capture
      // the value from the build that mounted the panel, so the caps would stop
      // moving the moment the panel stopped being rebuilt from above.
      builder: (context, _) => _body(draft.adults + draft.children),
    );
  }

  Widget _body(int party) {
    // The cap applies to the party, not to each row: adults + children is what
    // becomes guestCount, so the +'s have to stop together.
    final headroom = maxSearchGuests - party;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SearchStepperRow(
            label: 'Adults',
            description: 'Ages 13 or above',
            value: draft.adults,
            // At least one adult: a stay booked by nobody is not a search,
            // and guestCountFor floors at 1 anyway — better to show the floor
            // than to let the number drop and be silently corrected later.
            min: 1,
            max: draft.adults + (headroom > 0 ? headroom : 0),
            onChanged: (v) => draft.edit(() => draft.adults = v),
          ),
          Divider(height: 1, color: AppColors.outline),
          SearchStepperRow(
            label: 'Children',
            description: 'Ages 2 – 12',
            value: draft.children,
            min: 0,
            max: draft.children + (headroom > 0 ? headroom : 0),
            onChanged: (v) => draft.edit(() => draft.children = v),
          ),
          Divider(height: 1, color: AppColors.outline),
          SearchStepperRow(
            label: 'Infants',
            description: 'Under 2 · not counted towards the guest limit',
            value: draft.infants,
            min: 0,
            max: 5,
            onChanged: (v) => draft.edit(() => draft.infants = v),
          ),
          if (party >= maxSearchGuests) ...[
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
