import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../models/search_filters.dart';
import 'date_calendar.dart';
import 'search_draft.dart';

/// The "When" panel: a shortcut rail, the month grid, and the hourly mode.
///
/// The mode toggle is kept from the sheet this replaces — Musaafir searches
/// both whole nights and hours of a single day, and the hourly listings are a
/// real part of the marketplace, not a corner case.
///
/// **Hourly keeps its native time pickers.** A two-thumb time control is its own
/// build, and dates are what the segmented bar is actually about; the date half
/// of hourly mode gets the same inline grid as the range mode, so the dialog is
/// only ever reached for the two clock times.
class WhenPanel extends StatelessWidget {
  const WhenPanel({
    super.key,
    required this.draft,
    required this.today,
  });

  final SearchDraft draft;

  /// Injected so "no past dates" and the shortcuts are testable without
  /// depending on the day the suite happens to run.
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: SegmentedButton<SearchDateMode>(
                segments: const [
                  ButtonSegment(
                    value: SearchDateMode.dateRange,
                    label: Text('Dates'),
                    icon: Icon(Icons.calendar_month_outlined, size: 17),
                  ),
                  ButtonSegment(
                    value: SearchDateMode.singleDateWithTime,
                    label: Text('By the hour'),
                    icon: Icon(Icons.schedule, size: 17),
                  ),
                ],
                selected: {draft.dateMode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    draft.edit(() => draft.dateMode = selection.first),
              ),
            ),
            const SizedBox(height: 14),
            if (draft.dateMode == SearchDateMode.dateRange)
              _rangeMode(context)
            else
              _hourlyMode(context),
          ],
        ),
      ),
    );
  }

  Widget _rangeMode(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ShortcutRail(
          today: today,
          selected: draft.dateRange,
          onPick: (range) => draft.edit(() => draft.dateRange = range),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DateCalendar(
                today: today,
                range: draft.dateRange,
                onRangeChanged: (range) =>
                    draft.edit(() => draft.dateRange = range),
              ),
              if (draft.dateRange != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => draft.edit(() => draft.dateRange = null),
                    child: const Text('Clear dates'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _hourlyMode(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: DateCalendar(
            today: today,
            // Hourly is one day, so the grid is driven as a degenerate range
            // whose start is the chosen day. Reusing the same widget keeps one
            // calendar in the app rather than two that drift.
            range: draft.singleDate == null
                ? null
                : DateTimeRange(
                    start: draft.singleDate!, end: draft.singleDate!),
            onRangeChanged: (range) =>
                draft.edit(() => draft.singleDate = range?.start),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _TimeCard(
                label: 'From',
                time: draft.startTime,
                onPick: (t) => draft.edit(() => draft.startTime = t),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TimeCard(
                label: 'Until',
                time: draft.endTime,
                onPick: (t) => draft.edit(() => draft.endTime = t),
              ),
            ),
          ],
        ),
        // Both halves are required before this is a searchable window —
        // searchDateWindowFor drops anything less, so say so rather than
        // letting Search quietly ignore the date.
        if (draft.singleDate != null &&
            (draft.startTime == null || draft.endTime == null)) ...[
          const SizedBox(height: 8),
          Text(
            'Pick both a start and an end time.',
            style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
        ],
      ],
    );
  }
}

class _ShortcutRail extends StatelessWidget {
  const _ShortcutRail({
    required this.today,
    required this.selected,
    required this.onPick,
  });

  final DateTime today;
  final DateTimeRange? selected;
  final ValueChanged<DateTimeRange> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final shortcut in DateShortcut.values) ...[
            _ShortcutCard(
              title: switch (shortcut) {
                DateShortcut.today => 'Today',
                DateShortcut.tomorrow => 'Tomorrow',
                DateShortcut.thisWeekend => 'This weekend',
              },
              range: dateShortcutRange(shortcut, today),
              selected: selected != null &&
                  dayOf(selected!.start) ==
                      dayOf(dateShortcutRange(shortcut, today).start) &&
                  dayOf(selected!.end) ==
                      dayOf(dateShortcutRange(shortcut, today).end),
              onTap: () => onPick(dateShortcutRange(shortcut, today)),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.title,
    required this.range,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final DateTimeRange range;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Spelled out rather than left as a bare name: "Today" for a stay means
    // tonight — today to tomorrow — and the subtitle is what makes that plain
    // instead of surprising at checkout.
    final subtitle = range.start.month == range.end.month
        ? '${DateFormat('d').format(range.start)} – '
            '${DateFormat('d MMM').format(range.end)}'
        : '${DateFormat('d MMM').format(range.start)} – '
            '${DateFormat('d MMM').format(range.end)}';

    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $subtitle',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: selected ? AppColors.brand.withValues(alpha: 0.08) : null,
              border: Border.all(
                color: selected ? AppColors.brand : AppColors.outline,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeCard extends StatelessWidget {
  const _TimeCard({
    required this.label,
    required this.time,
    required this.onPick,
  });

  final String label;
  final TimeOfDay? time;
  final ValueChanged<TimeOfDay> onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time ?? const TimeOfDay(hour: 10, minute: 0),
        );
        if (picked != null) onPick(picked);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              time == null ? 'Pick a time' : time!.format(context),
              style: TextStyle(
                fontSize: 13.5,
                color: time == null ? AppColors.inkMuted : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
