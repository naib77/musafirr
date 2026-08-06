import 'package:flutter/material.dart';

import '../models/listing_purpose.dart';

/// Multi-select chips for a listing's [ListingPurpose] tags. Used by the host
/// create/edit flows. Purpose is what the place is good for (medical, exam, …)
/// and powers the guest "stay near a hospital / exam center" search.
class PurposeSelector extends StatelessWidget {
  const PurposeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Set<ListingPurpose> selected;
  final ValueChanged<Set<ListingPurpose>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "What's this place good for?",
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Guests can search to stay near a hospital, exam center and more. '
          'Pick all that apply — an accurate map pin makes these matches work.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ListingPurpose.values.map((p) {
            final isSel = selected.contains(p);
            return FilterChip(
              avatar: Icon(
                p.icon,
                size: 18,
                color: isSel
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.primary,
              ),
              label: Text(p.label),
              selected: isSel,
              onSelected: (v) {
                final next = Set<ListingPurpose>.from(selected);
                if (v) {
                  next.add(p);
                } else {
                  next.remove(p);
                }
                onChanged(next);
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}
