/// Clock times as the host *types* them, and as the time picker writes them.
///
/// Two spellings coexist on purpose and this is the only place that knows
/// both:
///
///  * **Labels** — `"2:30 PM"`. `listings.check_in_time` / `check_out_time`
///    and the hotel's copies are free text printed verbatim into guest
///    messages and the listing page (053, 153), so a picker must write the
///    same kind of string a host would have typed. Kept as text rather than a
///    `time` column (decided 2026-10-07): every reader prints it as-is, and
///    hotels copy it onto their rooms as-is; a typed column would have to be
///    re-rendered in each of those places for no gain in behaviour.
///  * **24-hour `HH:MM`** — what the `hourly_window_start/end` `time` columns
///    want (148), handled by `parseClockMinutes` / `formatClockMinutes` in
///    `booking/hourly_policy.dart`. The picker shows AM/PM but the field
///    stores `HH:MM`; `24:00` (end of day) has no 12-hour spelling, so that
///    field stays typeable.
///
/// Everything here is minutes-after-midnight in and out so the widget layer
/// never does clock arithmetic.
library;

import 'package:flutter/material.dart' show TimeOfDay;

final RegExp _label = RegExp(
  r'^(\d{1,2})(?::(\d{2}))?\s*([AaPp])\.?\s*[Mm]?\.?$',
);
final RegExp _twentyFour = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$');

/// `"2:30 PM"`, `"2:30pm"`, `"2 PM"`, `"14:30"` → minutes after midnight.
/// Null when [text] is blank or not a clock time; the caller keeps whatever
/// the host typed in that case, since a label is allowed to be prose
/// ("after 2 PM, ask at reception").
int? parseClockLabelMinutes(String? text) {
  final t = text?.trim();
  if (t == null || t.isEmpty) return null;
  final m = _label.firstMatch(t);
  if (m != null) {
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2) ?? '0');
    if (h < 1 || h > 12 || min > 59) return null;
    final pm = m.group(3)!.toLowerCase() == 'p';
    return (h % 12 + (pm ? 12 : 0)) * 60 + min;
  }
  final n = _twentyFour.firstMatch(t);
  if (n != null) {
    final h = int.parse(n.group(1)!);
    final min = int.parse(n.group(2)!);
    if (h > 23 || min > 59) return null;
    return h * 60 + min;
  }
  return null;
}

/// Minutes after midnight → `"2:30 PM"`. Midnight is `"12:00 AM"`, noon
/// `"12:00 PM"`, matching what the forms' defaults have always said.
String formatClockLabel(int minutes) {
  final h24 = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  final suffix = h24 < 12 ? 'AM' : 'PM';
  return '$h12:${m.toString().padLeft(2, '0')} $suffix';
}

TimeOfDay timeOfDayFromMinutes(int minutes) =>
    TimeOfDay(hour: (minutes ~/ 60) % 24, minute: minutes % 60);

int minutesFromTimeOfDay(TimeOfDay t) => t.hour * 60 + t.minute;
