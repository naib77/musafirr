import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';

/// Strips a [DateTime] to its calendar day, so two days can be compared without
/// a stray time-of-day making them unequal.
DateTime dayOf(DateTime value) => DateTime(value.year, value.month, value.day);

/// The named ranges offered beside the calendar.
enum DateShortcut { today, tomorrow, thisWeekend }

/// What a tap on the grid means.
enum DateCalendarMode {
  /// Two taps make a stay. The default, and what a nightly search wants.
  range,

  /// One tap picks one day, reported as a start == end range.
  ///
  /// Hourly search is a single date plus two clock times, so there is no second
  /// endpoint to collect. Before this existed the hourly grid was driven as a
  /// degenerate range and simply took `range.start`, which meant tapping the
  /// 5th and then the 8th silently kept the 5th — the second tap did nothing
  /// visible and the guest had no way to tell.
  singleDay,
}

/// What a shortcut actually selects.
///
/// Every one produces a **range**, not a day, because a stay needs a check-out:
/// `search_listings` builds a `tstzrange` from the two, and a zero-length
/// window matches nothing. So "Today" means tonight — today to tomorrow — which
/// is also what a guest tapping it at 9pm means.
///
/// "This weekend" is the next Saturday on or after [today], through the Sunday
/// after it. On a Saturday that is today and tomorrow; on a Sunday the weekend
/// in question has effectively gone, so it rolls to the next one rather than
/// offering a range that starts in the past.
DateTimeRange dateShortcutRange(DateShortcut shortcut, DateTime today) {
  final start = dayOf(today);
  switch (shortcut) {
    case DateShortcut.today:
      return DateTimeRange(
          start: start, end: start.add(const Duration(days: 1)));
    case DateShortcut.tomorrow:
      final tomorrow = start.add(const Duration(days: 1));
      return DateTimeRange(
        start: tomorrow,
        end: tomorrow.add(const Duration(days: 1)),
      );
    case DateShortcut.thisWeekend:
      // DateTime.saturday == 6; the modulo lands on 0 when today IS Saturday.
      final untilSaturday = (DateTime.saturday - start.weekday) % 7;
      final saturday = start.add(Duration(days: untilSaturday));
      return DateTimeRange(
        start: saturday,
        end: saturday.add(const Duration(days: 1)),
      );
  }
}

/// The inline month grid behind the "When" segment.
///
/// ## Why this is not `showDateRangePicker`
///
/// The sheet this replaces opens Flutter's dialog, which is a full-screen modal
/// on a phone and a fixed 340px card on desktop, with its own header, its own
/// Cancel/Save and its own idea of typography. Inside a popover that is a
/// dialog on top of a dropdown — two layers of chrome for one decision. An
/// inline grid is the whole point of the Airbnb bar: you tap the segment and
/// the calendar is simply *there*.
///
/// ## Selection rules
///
/// Two taps make a range. The third starts over, rather than extending or
/// inverting the existing one — which matters more than it looks: a reversed
/// window reaches `tstzrange(lower > upper)` and aborts the entire search with
/// `22000` (see CLAUDE.md on `search_listings`). Restarting is also what a
/// guest means by tapping a third date.
///
/// Deliberately knows nothing about `SearchDraft`: it takes a range and reports
/// a range, so it can be tested on its own without a search anywhere near it.
class DateCalendar extends StatefulWidget {
  const DateCalendar({
    super.key,
    required this.range,
    required this.onRangeChanged,
    required this.today,
    this.monthsShown = 1,
    this.mode = DateCalendarMode.range,
  });

  /// The current selection, or null for none. A range whose start and end are
  /// the same day is how a half-made selection is represented — the first tap.
  final DateTimeRange? range;

  final ValueChanged<DateTimeRange?> onRangeChanged;

  /// Injected rather than read from the clock, so "past dates are refused" and
  /// the shortcuts are testable without waiting for a particular date.
  final DateTime today;

  /// How many months to lay out side by side. One fits the panel; two is the
  /// wider desktop treatment if the panel ever grows.
  final int monthsShown;

  /// Whether a tap collects an endpoint or a whole answer. See
  /// [DateCalendarMode].
  final DateCalendarMode mode;

  @override
  State<DateCalendar> createState() => _DateCalendarState();
}

class _DateCalendarState extends State<DateCalendar> {
  late DateTime _visibleMonth;

  /// The first tap of a new range, before a second one closes it. Held
  /// separately from `widget.range` so a half-made selection can be shown
  /// without ever reporting an invalid (start == end) range upwards.
  DateTime? _anchor;

  @override
  void initState() {
    super.initState();
    // Open on the month the selection is in, not on today — reopening the
    // panel to look at a booked November and landing on September is the sort
    // of small wrongness that makes a calendar feel broken.
    _visibleMonth = _monthOf(widget.range?.start ?? widget.today);
  }

  @override
  void didUpdateWidget(DateCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A range cleared from outside (the panel's own Clear, or a re-seeded
    // draft) must not leave a dangling first tap behind.
    if (widget.range == null && oldWidget.range != null) {
      _anchor = null;
    }
  }

  static DateTime _monthOf(DateTime value) => DateTime(value.year, value.month);

  DateTime get _firstAllowedDay => dayOf(widget.today);

  bool get _canGoBack =>
      _visibleMonth.isAfter(_monthOf(_firstAllowedDay)) ||
      _visibleMonth == _monthOf(_firstAllowedDay);

  void _pageBy(int months) {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + months);
    // Never page behind the current month; there is nothing selectable there.
    if (next.isBefore(_monthOf(_firstAllowedDay))) return;
    setState(() => _visibleMonth = next);
  }

  void _tap(DateTime day) {
    if (widget.mode == DateCalendarMode.singleDay) {
      // No anchor to keep: every tap is a complete answer, and the previous
      // one is simply replaced. Reported as start == end so the caller reads
      // one field either way.
      setState(() => _anchor = null);
      widget.onRangeChanged(DateTimeRange(start: day, end: day));
      return;
    }
    final anchor = _anchor;
    if (anchor == null) {
      // First tap: remember it and show it as a single selected day.
      setState(() => _anchor = day);
      widget.onRangeChanged(DateTimeRange(start: day, end: day));
      return;
    }
    if (!day.isAfter(anchor)) {
      // Tapping the anchor again, or a day before it, restarts rather than
      // producing an inverted range. See the class doc: an inverted window
      // fails the whole search server-side.
      setState(() => _anchor = day);
      widget.onRangeChanged(DateTimeRange(start: day, end: day));
      return;
    }
    setState(() => _anchor = null);
    widget.onRangeChanged(DateTimeRange(start: anchor, end: day));
  }

  /// Gap between side-by-side months, when there is more than one.
  static const _monthGap = 24.0;

  @override
  Widget build(BuildContext context) {
    // Measured HERE and not inside the grid. The grid sits in a Row, and a Row
    // lays out a non-flexible child with UNBOUNDED width — a LayoutBuilder down
    // there is handed infinity and learns nothing, which is exactly how the
    // first attempt at this still overflowed a 240px column by 40px. The Column
    // below passes the parent's width straight through.
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final perMonth = available.isFinite
            ? (available - _monthGap * (widget.monthsShown - 1)) /
                widget.monthsShown
            : double.infinity;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.monthsShown; i++) ...[
                  if (i > 0) const SizedBox(width: _monthGap),
                  _MonthGrid(
                    month:
                        DateTime(_visibleMonth.year, _visibleMonth.month + i),
                    cell: _MonthGrid.cellFor(perMonth),
                    range: widget.range,
                    halfMade: _anchor != null,
                    firstAllowedDay: _firstAllowedDay,
                    today: dayOf(widget.today),
                    onTap: _tap,
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _header() {
    final label = widget.monthsShown == 1
        ? DateFormat('MMMM yyyy').format(_visibleMonth)
        : '${DateFormat('MMM').format(_visibleMonth)} – '
            '${DateFormat('MMM yyyy').format(DateTime(_visibleMonth.year, _visibleMonth.month + widget.monthsShown - 1))}';

    return Row(
      children: [
        _PageButton(
          icon: Icons.chevron_left,
          tooltip: 'Previous month',
          onTap: _canGoBack && _visibleMonth.isAfter(_monthOf(_firstAllowedDay))
              ? () => _pageBy(-1)
              : null,
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
        _PageButton(
          icon: Icons.chevron_right,
          tooltip: 'Next month',
          onTap: () => _pageBy(1),
        ),
      ],
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      color: AppColors.ink,
      disabledColor: AppColors.outline,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.cell,
    required this.range,
    required this.halfMade,
    required this.firstAllowedDay,
    required this.today,
    required this.onTap,
  });

  final DateTime month;

  /// Edge length of one day, decided by [DateCalendar] from the width it was
  /// actually given.
  final double cell;

  final DateTimeRange? range;

  /// True while only the first tap has landed — the span tint is suppressed so
  /// a one-day "range" does not render as a filled bar.
  final bool halfMade;

  final DateTime firstAllowedDay;
  final DateTime today;
  final ValueChanged<DateTime> onTap;

  /// The comfortable cell size. Cells shrink below this when the grid is
  /// given less than seven of them, and never grow above it — a 56px day on a
  /// tablet would read as a button, not a date.
  static const _cell = 40.0;

  /// The cell size for a month handed [available] pixels.
  ///
  /// The grid used to be a hard 280px, fine in the desktop popover and 40px too
  /// wide for a 320px phone once the sheet's padding and the card's are taken
  /// out. An overflow here is not cosmetic: the same fixed width is what
  /// overflowed the desktop panel by 45px during a cross-fade (see CLAUDE.md),
  /// so the cell adapts rather than each caller guessing a width that fits.
  static double cellFor(double available) =>
      available.isFinite && available < _cell * 7 ? available / 7 : _cell;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // DateTime.weekday is 1=Mon..7=Sun; the grid starts on Sunday, so Sunday
    // (7) has to fold back to column 0.
    final leadingBlanks = first.weekday % 7;
    final cells = leadingBlanks + daysInMonth;
    final rows = (cells / 7).ceil();

    return SizedBox(
      width: cell * 7,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (final label in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                SizedBox(
                  width: cell,
                  height: 28,
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          for (var row = 0; row < rows; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  _cellAt(row * 7 + col - leadingBlanks, daysInMonth, cell),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cellAt(int dayIndex, int daysInMonth, double cell) {
    if (dayIndex < 0 || dayIndex >= daysInMonth) {
      return SizedBox(width: cell, height: cell);
    }
    final day = DateTime(month.year, month.month, dayIndex + 1);
    final selection = range;

    final isPast = day.isBefore(firstAllowedDay);
    final isStart = selection != null && dayOf(selection.start) == day;
    final isEnd = selection != null && dayOf(selection.end) == day;
    final inSpan = selection != null &&
        !halfMade &&
        day.isAfter(dayOf(selection.start)) &&
        day.isBefore(dayOf(selection.end));

    return _DayCell(
      day: day,
      size: cell,
      enabled: !isPast,
      isEndpoint: isStart || isEnd,
      inSpan: inSpan,
      // Only meaningful on the two ends, and only once a real range exists:
      // it is what rounds the span's outer corners.
      spanSide:
          !halfMade && selection != null && selection.start != selection.end
              ? (isStart
                  ? _SpanSide.start
                  : (isEnd ? _SpanSide.end : _SpanSide.none))
              : _SpanSide.none,
      isToday: day == today,
      onTap: () => onTap(day),
    );
  }
}

enum _SpanSide { none, start, end }

class _DayCell extends StatefulWidget {
  const _DayCell({
    required this.day,
    required this.size,
    required this.enabled,
    required this.isEndpoint,
    required this.inSpan,
    required this.spanSide,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final double size;
  final bool enabled;
  final bool isEndpoint;
  final bool inSpan;
  final _SpanSide spanSide;
  final bool isToday;
  final VoidCallback onTap;

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.brand.withValues(alpha: 0.10);

    // The span's background is a rectangle so adjacent days join up with no
    // gaps, with the outer corners rounded on the two ends.
    BoxDecoration? spanDecoration;
    if (widget.inSpan) {
      spanDecoration = BoxDecoration(color: tint);
    } else if (widget.spanSide == _SpanSide.start) {
      spanDecoration = BoxDecoration(
        color: tint,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
      );
    } else if (widget.spanSide == _SpanSide.end) {
      spanDecoration = BoxDecoration(
        color: tint,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
      );
    }

    final Color textColor;
    if (!widget.enabled) {
      // Struck through as well as dimmed, because "grey" alone reads as a
      // theme choice rather than as unavailable.
      textColor = AppColors.outline;
    } else if (widget.isEndpoint) {
      textColor = Colors.white;
    } else {
      textColor = AppColors.ink;
    }

    return Semantics(
      button: widget.enabled,
      enabled: widget.enabled,
      selected: widget.isEndpoint || widget.inSpan,
      label: DateFormat('EEEE d MMMM').format(widget.day),
      excludeSemantics: true,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.enabled ? widget.onTap : null,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: spanDecoration,
            alignment: Alignment.center,
            child: Container(
              width: widget.size - 4,
              height: widget.size - 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isEndpoint
                    ? AppColors.brand
                    : (_hovered && widget.enabled
                        ? AppColors.surfaceMuted
                        : null),
                border: widget.isToday && !widget.isEndpoint
                    ? Border.all(color: AppColors.inkMuted, width: 1)
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                '${widget.day.day}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      widget.isEndpoint ? FontWeight.w700 : FontWeight.w500,
                  color: textColor,
                  decoration: widget.enabled
                      ? TextDecoration.none
                      : TextDecoration.lineThrough,
                  decorationColor: AppColors.outline,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
