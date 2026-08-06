import 'package:flutter/material.dart';

import '../models/listing_purpose.dart';

/// Horizontal purpose pills on Explore ("Any purpose", Medical, Exam, …).
/// Excludes [ListingPurpose.general] — that's a host default, not a guest
/// search intent; "Any purpose" already means no filter.
class PurposeScroll extends StatelessWidget {
  const PurposeScroll({
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
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
      ),
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
    return Padding(
      padding: const EdgeInsets.only(right: 8),
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
