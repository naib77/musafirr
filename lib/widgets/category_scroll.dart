import 'package:flutter/material.dart';

import '../models/listing_type.dart';

class CategoryScroll extends StatelessWidget {
  const CategoryScroll({
    super.key,
    required this.selectedType,
    required this.onTypeSelected,
  });

  final ListingType? selectedType;
  final ValueChanged<ListingType?> onTypeSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 80,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _CategoryChip(
            icon: Icons.grid_view_rounded,
            label: 'All',
            isSelected: selectedType == null,
            onTap: () => onTypeSelected(null),
            theme: theme,
          ),
          _CategoryChip(
            icon: Icons.bed_outlined,
            label: 'Rooms',
            isSelected: selectedType == ListingType.room,
            onTap: () => onTypeSelected(ListingType.room),
            theme: theme,
          ),
          _CategoryChip(
            icon: Icons.home_outlined,
            label: 'Full House',
            isSelected: selectedType == ListingType.fullHouse,
            onTap: () => onTypeSelected(ListingType.fullHouse),
            theme: theme,
          ),
          _CategoryChip(
            icon: Icons.chair_outlined,
            label: 'Seats',
            isSelected: selectedType == ListingType.seat,
            onTap: () => onTypeSelected(ListingType.seat),
            theme: theme,
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? Border.all(
                        color: theme.colorScheme.primary,
                        width: 2,
                      )
                    : null,
              ),
              child: Icon(
                icon,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
