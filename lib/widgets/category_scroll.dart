import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../models/listing_type.dart';

/// Compact, colorful category pill row on the Explore tab. Each type keeps
/// its brand color (matching the badges on the listing cards): soft tint
/// when idle, solid fill when selected.
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
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          _CategoryPill(
            icon: Icons.grid_view_rounded,
            label: 'All',
            // Neutral ink — fullHouse already owns the brand teal.
            color: AppColors.ink,
            isSelected: selectedType == null,
            onTap: () => onTypeSelected(null),
          ),
          _CategoryPill(
            icon: Icons.meeting_room_rounded,
            label: 'Rooms',
            color: AppColors.room,
            isSelected: selectedType == ListingType.room,
            onTap: () => onTypeSelected(ListingType.room),
          ),
          _CategoryPill(
            icon: Icons.home_rounded,
            label: 'Full House',
            color: AppColors.fullHouse,
            isSelected: selectedType == ListingType.fullHouse,
            onTap: () => onTypeSelected(ListingType.fullHouse),
          ),
          _CategoryPill(
            icon: Icons.event_seat_rounded,
            label: 'Seats',
            color: AppColors.seat,
            isSelected: selectedType == ListingType.seat,
            onTap: () => onTypeSelected(ListingType.seat),
          ),
        ],
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? color : color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? Colors.white : color,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
