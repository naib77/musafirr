import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../models/booking.dart';
import '../models/booking_status.dart';

/// Compact controls row for the Trips / Reservations lists: a date-sort toggle
/// (soonest ↔ latest) and a status filter. Shared so the guest and host lists
/// behave and look identical.
///
/// [availableStatuses] is derived from the bookings actually present in the
/// current tab, so the filter only ever offers statuses that exist there.
class BookingFilterBar extends StatelessWidget {
  const BookingFilterBar({
    super.key,
    required this.sortDescending,
    required this.statusFilter,
    required this.availableStatuses,
    required this.onSortChanged,
    required this.onStatusChanged,
  });

  /// false → soonest/oldest first (ascending), true → latest first (descending).
  final bool sortDescending;

  /// Currently selected status, or null for "All".
  final BookingStatus? statusFilter;

  /// Distinct statuses present in the current list (drives the filter menu).
  final List<BookingStatus> availableStatuses;

  final ValueChanged<bool> onSortChanged;
  final ValueChanged<BookingStatus?> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          // Date sort toggle
          _ControlChip(
            icon: sortDescending
                ? Icons.south_rounded
                : Icons.north_rounded,
            label: sortDescending ? 'Latest first' : 'Soonest first',
            onTap: () => onSortChanged(!sortDescending),
          ),
          const SizedBox(width: 8),

          // Status filter — only meaningful when more than one status exists.
          if (availableStatuses.length > 1)
            PopupMenuButton<BookingStatus?>(
              tooltip: 'Filter by status',
              position: PopupMenuPosition.under,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: onStatusChanged,
              itemBuilder: (context) => [
                _menuItem(theme, null, 'All statuses'),
                for (final s in availableStatuses)
                  _menuItem(theme, s, s.title),
              ],
              child: _ControlChip(
                icon: Icons.filter_list_rounded,
                label: statusFilter?.title ?? 'All statuses',
                active: statusFilter != null,
                trailing: Icons.arrow_drop_down_rounded,
              ),
            ),
        ],
      ),
    );
  }

  PopupMenuItem<BookingStatus?> _menuItem(
    ThemeData theme,
    BookingStatus? value,
    String label,
  ) {
    final selected = value == statusFilter;
    return PopupMenuItem<BookingStatus?>(
      value: value,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 18,
            color: selected ? AppColors.brand : theme.colorScheme.outline,
          ),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }
}

class _ControlChip extends StatelessWidget {
  const _ControlChip({
    required this.icon,
    required this.label,
    this.trailing,
    this.active = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final IconData? trailing;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = active ? AppColors.brand : AppColors.ink;

    return Material(
      color: active
          ? AppColors.brand.withValues(alpha: 0.10)
          : AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
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
              if (trailing != null)
                Icon(trailing, size: 18, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Applies a [BookingFilterBar]'s state to a list: filter by [statusFilter]
/// (null = all), then sort by check-in date. Shared by both screens so the
/// behaviour can't drift.
List<Booking> applyBookingFilterSort(
  List<Booking> bookings, {
  required BookingStatus? statusFilter,
  required bool sortDescending,
}) {
  final result = statusFilter == null
      ? List<Booking>.of(bookings)
      : bookings.where((b) => b.status == statusFilter).toList();
  result.sort((a, b) => sortDescending
      ? b.effectiveCheckIn.compareTo(a.effectiveCheckIn)
      : a.effectiveCheckIn.compareTo(b.effectiveCheckIn));
  return result;
}

/// Distinct statuses present in [bookings], in the enum's canonical order, so
/// the filter menu lists them consistently.
List<BookingStatus> distinctStatuses(List<Booking> bookings) {
  final present = bookings.map((b) => b.status).toSet();
  return BookingStatus.values.where(present.contains).toList();
}
