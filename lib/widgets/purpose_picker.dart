import 'package:flutter/material.dart';

import '../models/listing_purpose.dart';

/// Purpose pills ("Any purpose", Medical, Exam, …) — what the stay is *for*.
///
/// Excludes [ListingPurpose.general]: that is a host default, not a guest
/// search intent, and "Any purpose" already means no filter.
///
/// ## Why it wraps rather than scrolls
///
/// It was a horizontal `ListView`, and both of its call sites sit inside a
/// padded card — the mobile search sheet's Where section and the desktop
/// filters panel. A horizontal scroller inside a padded container clips at the
/// padding, not at the card edge, so the last pill was sliced mid-word with a
/// clear gap after it: it read as broken rather than as "there is more, scroll
/// me". Bleeding it to the edge would mean the card handing its own inset back
/// out to a child.
///
/// Wrapping sidesteps that and is better anyway. There are six pills, they fit
/// in two or three rows at any width either caller offers, and every one is
/// visible without a gesture — which also removes a horizontal drag nested
/// inside the sheet's vertical scroll.
class PurposePicker extends StatelessWidget {
  const PurposePicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final ListingPurpose? selected;
  final ValueChanged<ListingPurpose?> onSelected;

  static final _purposes =
      ListingPurpose.values.where((p) => p != ListingPurpose.general).toList();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _PurposePill(
          icon: Icons.tune_rounded,
          label: 'Any purpose',
          isSelected: selected == null,
          onTap: () => onSelected(null),
        ),
        ..._purposes.map((p) => _PurposePill(
              icon: p.icon,
              label: p.label,
              isSelected: selected == p,
              onTap: () => onSelected(p),
            )),
      ],
    );
  }
}

class _PurposePill extends StatelessWidget {
  const _PurposePill({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = isSelected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant;
    // No margin of its own any more: the Wrap owns the gaps, and a trailing
    // inset here would double them and unbalance the last pill in each row.
    return SizedBox(
      height: 40,
      child: Material(
        color: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              // Load-bearing in a Wrap and irrelevant in the horizontal
              // ListView this used to be: a Wrap hands its children the full
              // line width, so a Row without this expands to fill it and every
              // pill becomes its own full-width bar.
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
