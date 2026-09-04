import 'package:flutter/material.dart' show DayPeriod, TimeOfDay;
import 'package:intl/intl.dart';

import '../../models/search_filters.dart';

/// What the desktop header's search pill shows in its three segments.
///
/// A null field means "nothing chosen" — the pill renders its placeholder
/// ("Search destinations" / "Add dates" / "Add guests") rather than a value,
/// which is what makes an untouched pill read as an invitation instead of as a
/// filter that is already narrowing the feed.
class SearchPillSummary {
  const SearchPillSummary({this.where, this.when, this.who});

  final String? where;
  final String? when;
  final String? who;

  /// True when at least one segment carries a value, i.e. the pill is
  /// describing a search rather than inviting one. Drives whether the header
  /// offers a "clear" affordance.
  bool get hasAny => where != null || when != null || who != null;
}

/// Renders [filters] into the pill's three labels.
///
/// A pure function on purpose. The pill is the only place in the app that
/// summarises a whole [SearchFilters] into one line, and the interesting part
/// is the formatting decisions below — which are exactly the things a widget
/// test cannot pin without pumping the entire shell.
SearchPillSummary searchPillSummaryFor(SearchFilters filters) {
  return SearchPillSummary(
    where: _where(filters),
    when: _when(filters),
    who: _who(filters),
  );
}

/// A landmark beats a place name: searching "near Dhaka Medical College" is
/// the more specific of the two, and [SearchFilters.location] is often the
/// city the landmark merely sits in.
String? _where(SearchFilters filters) {
  final landmark = filters.landmark?.name.trim();
  if (landmark != null && landmark.isNotEmpty) return landmark;
  final location = filters.location?.trim();
  if (location != null && location.isNotEmpty) return location;
  return null;
}

String? _when(SearchFilters filters) {
  if (filters.dateMode == SearchDateMode.dateRange) {
    final start = filters.checkIn;
    final end = filters.checkOut;
    if (start == null || end == null) return null;
    // "12 – 15 Sep" when one month covers both ends, "29 Sep – 2 Oct" when it
    // does not. Repeating the month on both sides of every range would push
    // the segment past its width for no information.
    final day = DateFormat('d');
    final dayMonth = DateFormat('d MMM');
    return start.month == end.month && start.year == end.year
        ? '${day.format(start)} – ${dayMonth.format(end)}'
        : '${dayMonth.format(start)} – ${dayMonth.format(end)}';
  }

  // Hourly mode: one date plus a window. Both halves are required — a date
  // with no hours is not yet a searchable window (see searchDateWindowFor).
  final date = filters.singleDate;
  final start = filters.startTime;
  final end = filters.endTime;
  if (date == null || start == null || end == null) return null;
  return '${DateFormat('d MMM').format(date)}, '
      '${_clock(start)}–${_clock(end)}';
}

/// 12-hour clock without the space before the meridiem ("2PM"), because the
/// segment is narrow and the range already carries a dash.
String _clock(TimeOfDay time) {
  final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
  final meridiem = time.period == DayPeriod.am ? 'AM' : 'PM';
  if (time.minute == 0) return '$hour$meridiem';
  return '$hour:${time.minute.toString().padLeft(2, '0')}$meridiem';
}

/// Only a deliberate choice shows. [SearchFilters.guestCount] defaults to 1 and
/// `hasActiveFilters` agrees that 1 is not a filter, so showing "1 guest" would
/// make every untouched pill look like it had been narrowed.
String? _who(SearchFilters filters) {
  final guests = filters.guestCount;
  if (guests <= 1) return null;
  return '$guests guests';
}
