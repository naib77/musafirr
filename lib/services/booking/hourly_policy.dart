/// The hourly booking policy: what durations a guest may book by the hour,
/// and the rule that decides whether a selection is allowed.
///
/// ## One rule, two enforcers
///
/// The **database** is the enforcer: `hourly_booking_check` (migration 148)
/// runs inside `create_marketplace_booking` and refuses anything outside the
/// policy with a `22023` the guest sees verbatim. Nothing here can let a
/// booking through. What Dart needs the rule for is the *picker* — the chips
/// and stepper a guest chooses from, and the host form's floor — which must
/// agree with the server or the UI offers an hour the RPC then refuses.
///
/// So this file mirrors 148 exactly, in the same order, and
/// `test/services/hourly_policy_test.dart` feeds it the same fixture table
/// as `supabase/tests/148_hourly_policy_test.sql`. 055's `coalesce(v_min, 1)`
/// / `minFor`'s `?? 1` pairing had to be documented as a trap; this is the
/// same pairing made explicit.
///
/// Two layers:
///
///   * **platform** — `app_settings.hourly_policy`, JSON with one object per
///     listing type: `{"enabled", "min_hours", "slots"}`. Parsed by
///     [HourlyPolicy.fromRaw], fail-open per type to [HourlyPolicy.defaults].
///   * **host** — `min_hours` / `max_hours` / `hourly_slots` and the day-use
///     window on the listing ([BookingLimits]). The host narrows the
///     platform's offer and never widens it: the floor is the greater of the
///     two minimums, and a host slot list replaces the platform's outright.
///
/// Pricing is unchanged by any of this: `hourly_rate × hours`.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../../models/listing.dart';
import '../../models/listing_type.dart';

/// What the platform allows for one listing type.
class HourlyTypePolicy {
  const HourlyTypePolicy({
    required this.enabled,
    required this.minHours,
    this.slots,
  });

  /// May this type be booked by the hour at all. A listing with an
  /// `hourly_rate` on a disabled type is simply not offered hourly.
  final bool enabled;

  /// The floor. A host's own `min_hours` is clamped *up* to it.
  final int minHours;

  /// The only durations a guest may book, ascending, or null for any whole
  /// number of hours from [minHours].
  final List<int>? slots;

  /// The loosest policy there is — what an unknown type resolves to, so a
  /// listing type this build has never heard of is bookable rather than
  /// broken. The server does the same.
  static const HourlyTypePolicy loosest =
      HourlyTypePolicy(enabled: true, minHours: 1);
}

/// The platform layer, one entry per listing type.
class HourlyPolicy {
  const HourlyPolicy._(this._byType);

  /// Keyed by the enum's wire name (`fullHouse`, not `full_house`): the JSON
  /// keys are the `listing_type` labels, which is also why
  /// `AppSettingsService` hands this the *raw* cell — lowercasing it would
  /// turn `fullHouse` into a key nothing matches.
  final Map<String, HourlyTypePolicy> _byType;

  /// Copied verbatim from `hourly_policy_defaults()` in 148. Changing one
  /// side without the other means the app and the database disagree about the
  /// floor until the next settings load — a test pins the two together.
  static const HourlyPolicy defaults = HourlyPolicy._({
    'seat': HourlyTypePolicy(enabled: true, minHours: 1),
    'room': HourlyTypePolicy(enabled: true, minHours: 1),
    'fullHouse': HourlyTypePolicy(enabled: true, minHours: 3),
    'turf': HourlyTypePolicy(enabled: true, minHours: 1),
    'hotel': HourlyTypePolicy(enabled: true, minHours: 6, slots: [6, 12]),
  });

  /// The validator's bounds. Mirrored so a row written before 148's guard
  /// existed degrades the same way it would on the server: an unreadable
  /// entry is replaced by its default, never trusted and never thrown on.
  static const int maxHours = 168;

  /// Reads the raw `hourly_policy` cell. Absent, blank, not JSON, or not an
  /// object → [defaults]. A type that is missing or malformed → that type's
  /// default; the others are kept. Same resolution as `hourly_policy_for`.
  factory HourlyPolicy.fromRaw(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return defaults;
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return defaults;
    }
    if (decoded is! Map) return defaults;
    final parsed = <String, HourlyTypePolicy>{};
    for (final entry in decoded.entries) {
      final key = entry.key.toString();
      final policy = _parseEntry(entry.value);
      if (policy != null) parsed[key] = policy;
    }
    return HourlyPolicy._({...defaults._byType, ...parsed});
  }

  static HourlyTypePolicy? _parseEntry(Object? value) {
    if (value is! Map) return null;
    final enabled = value['enabled'];
    final min = value['min_hours'];
    if (enabled is! bool || min is! int || min < 1 || min > maxHours) {
      return null;
    }
    final rawSlots = value['slots'];
    List<int>? slots;
    if (rawSlots != null) {
      if (rawSlots is! List || rawSlots.isEmpty) return null;
      slots = <int>[];
      for (final s in rawSlots) {
        // Ascending and distinct, like the validator demands, so the chips
        // render in order and no duration is offered twice.
        if (s is! int || s < min || s > maxHours) return null;
        if (slots.isNotEmpty && s <= slots.last) return null;
        slots.add(s);
      }
    }
    return HourlyTypePolicy(
      enabled: enabled,
      minHours: min,
      slots: slots == null ? null : List.unmodifiable(slots),
    );
  }

  /// The platform entry for [type].
  HourlyTypePolicy forType(ListingType type) =>
      _byType[type.name] ?? HourlyTypePolicy.loosest;

  /// The platform entry by wire name — for the host form, which may be
  /// editing a type as a string before it is a [ListingType].
  HourlyTypePolicy forTypeName(String name) =>
      _byType[name] ?? HourlyTypePolicy.loosest;
}

/// Why a selection was refused, in the order the server checks them. The
/// server's `hint` carries the same names (`hourly_disabled`, `hourly_min`,
/// …), so a message built here and one raised there say the same thing.
enum HourlyRefusal { disabled, min, max, slot, window }

/// The effective rule for one listing: platform policy and host limits
/// combined. Built by [resolveHourlyRule]; read by the guest picker, the
/// host form and the submit validation.
class HourlyRule {
  const HourlyRule({
    required this.enabled,
    required this.minHours,
    required this.maxHours,
    required this.slots,
    required this.windowStartMinutes,
    required this.windowEndMinutes,
  });

  final bool enabled;

  /// `greatest(policy.min_hours, coalesce(listing.min_hours, 1))`.
  final int minHours;

  /// The host's cap, or null for none. Applied *after* slots on the server
  /// too, so a host slot above their own max is dead — [options] drops it.
  final int? maxHours;

  /// `coalesce(listing.hourly_slots, policy.slots)`, or null for free hours.
  final List<int>? slots;

  /// Day-use window as minutes after local midnight, both set or both null.
  /// `1440` is "24:00": a stay may end exactly at midnight of the day it
  /// started and still be inside the window. An end before the start wraps
  /// past midnight (22:00-02:00, 161).
  final int? windowStartMinutes;
  final int? windowEndMinutes;

  bool get hasWindow => windowStartMinutes != null && windowEndMinutes != null;

  /// What the stepper tops out at when the host set no cap: the pre-148
  /// picker's limit, kept so a free-hours listing does not suddenly offer a
  /// week. Never below the floor, so a 24-hour floor still has one option.
  static const int defaultStepperMax = 12;

  /// Every duration a guest may pick, ascending. Empty when nothing can be
  /// booked — hourly disabled, or every slot sits above the host's max — in
  /// which case the hourly plan is not offered at all.
  List<int> get options {
    if (!enabled) return const [];
    final cap = maxHours;
    final s = slots;
    if (s != null) {
      return List.unmodifiable(
        s.where((h) => h >= minHours && (cap == null || h <= cap)),
      );
    }
    final top = cap ?? math.max(defaultStepperMax, minHours);
    if (top < minHours) return const [];
    return List.unmodifiable(
      List<int>.generate(top - minHours + 1, (i) => minHours + i),
    );
  }

  /// Whether the hourly plan should be offered at all.
  bool get bookable => options.isNotEmpty;

  /// Why [hours] from [start] would be refused, or null if the server would
  /// accept it. Same order as `hourly_booking_check`: disabled, floor, cap,
  /// slot, window — so a 1-hour stay at 07:00 is told about the floor, not
  /// the window, exactly as the RPC would tell it.
  ///
  /// [start] is wall-clock local time. The server reads Asia/Dhaka; for a
  /// guest in Bangladesh they agree, and for anyone else the server's answer
  /// is the one that counts — this is a courtesy, not a gate.
  HourlyRefusal? refusalFor(int hours, {required DateTime start}) {
    if (!enabled) return HourlyRefusal.disabled;
    if (hours < minHours) return HourlyRefusal.min;
    final cap = maxHours;
    if (cap != null && hours > cap) return HourlyRefusal.max;
    final s = slots;
    if (s != null && !s.contains(hours)) return HourlyRefusal.slot;
    if (hasWindow) {
      // 161's arithmetic, minute for minute: the window runs forwards from
      // its start to the next occurrence of its end, so 22:00-02:00 is 240
      // minutes across midnight. The offset is taken mod a day, which puts a
      // start before the window past its end.
      final ws = windowStartMinutes!;
      final we = windowEndMinutes!;
      final length = we > ws ? we - ws : 1440 - ws + we;
      final offset = (start.hour * 60 + start.minute - ws + 1440) % 1440;
      if (offset + hours * 60 > length) return HourlyRefusal.window;
    }
    return null;
  }

  /// The sentence the server would raise for [refusal] — kept identical so
  /// the pre-check banner and a refusal that slipped past it read the same.
  String messageFor(HourlyRefusal refusal) => switch (refusal) {
        HourlyRefusal.disabled =>
          'Hourly bookings are not offered for this kind of listing',
        HourlyRefusal.min => 'Minimum booking is $minHours hour'
            '${minHours == 1 ? '' : 's'}',
        HourlyRefusal.max => 'Maximum booking is $maxHours hour'
            '${maxHours == 1 ? '' : 's'}',
        HourlyRefusal.slot =>
          'Choose one of the offered durations: ${slots!.join(', ')} hours',
        HourlyRefusal.window => 'Hourly stays here run between '
            '${formatClockMinutes(windowStartMinutes!)} and '
            '${formatClockMinutes(windowEndMinutes!)}',
      };

  /// [refusalFor] rendered, or null when allowed.
  String? check(int hours, {required DateTime start}) {
    final refusal = refusalFor(hours, start: start);
    return refusal == null ? null : messageFor(refusal);
  }
}

/// Combines the platform entry for [type] with the host's [limits].
HourlyRule resolveHourlyRule({
  required ListingType type,
  required HourlyPolicy policy,
  required BookingLimits limits,
}) {
  final platform = policy.forType(type);
  return HourlyRule(
    enabled: platform.enabled,
    minHours: math.max(platform.minHours, limits.minHours ?? 1),
    maxHours: limits.maxHours,
    slots: limits.hourlySlots ?? platform.slots,
    windowStartMinutes: parseClockMinutes(limits.hourlyWindowStart),
    windowEndMinutes: parseClockMinutes(limits.hourlyWindowEnd),
  );
}

/// `"09:00"`, `"9:00"`, `"09:00:00"` (how Postgres renders a `time`) and
/// `"24:00"` → minutes after midnight; anything else → null. `24:00` is
/// accepted because the window's *end* may be midnight.
int? parseClockMinutes(String? text) {
  final t = text?.trim();
  if (t == null || t.isEmpty) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(t);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (min > 59) return null;
  if (h == 24) return min == 0 ? 1440 : null;
  if (h > 23) return null;
  return h * 60 + min;
}

/// Minutes after midnight → `HH:MM`, with `1440` as `24:00`.
String formatClockMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// `"HH:MM"` for the database `time` column, or null when [text] is not a
/// clock time. The host types this; the column refuses "9am", so it is
/// normalised here rather than sent as typed.
String? normalizeClockText(String? text) {
  final minutes = parseClockMinutes(text);
  return minutes == null ? null : formatClockMinutes(minutes);
}

/// The host's slot list as typed — `"6, 12"` — to what `hourly_slots`
/// stores: ascending, distinct, whole hours in 1..168. Blank → null, meaning
/// "inherit the platform's". Junk tokens are dropped rather than failing the
/// whole save, so "6, 12," still means [6, 12].
List<int>? parseHourlySlotsText(String? text) {
  final t = text?.trim();
  if (t == null || t.isEmpty) return null;
  final set = <int>{};
  for (final token in t.split(RegExp(r'[,\s]+'))) {
    final n = int.tryParse(token.trim());
    if (n != null && n >= 1 && n <= HourlyPolicy.maxHours) set.add(n);
  }
  if (set.isEmpty) return null;
  final sorted = set.toList()..sort();
  return sorted;
}

/// What the host form says under the hourly fields, so the floor and the
/// platform's slots are visible while they type rather than discovered as a
/// refusal at booking time.
String hourlyPolicyHelperText(ListingType type, HourlyPolicy policy) {
  final p = policy.forType(type);
  if (!p.enabled) {
    return 'Hourly bookings are switched off for ${type.title.toLowerCase()} '
        'listings at the moment.';
  }
  final floor = 'Minimum ${p.minHours} hour${p.minHours == 1 ? '' : 's'} '
      'for ${type.title.toLowerCase()} listings';
  final slots = p.slots;
  if (slots == null) return '$floor; any whole number of hours above that.';
  return '$floor, sold in blocks of ${slots.join(', ')} hours unless you '
      'narrow the list below.';
}

/// A host minimum below the platform floor is stored as the floor: the
/// server clamps anyway, and a form that saved "1" while the guest is shown
/// "3" would send the host chasing a bug that is not there. An unset minimum
/// stays unset — the server's `coalesce` handles it.
int? clampHostMinHours(int? typed, HourlyTypePolicy platform) {
  if (typed == null) return null;
  return math.max(typed, platform.minHours);
}

/// Why the hourly host fields cannot be saved, or null. Checked alongside
/// `validatePlanRates`, and only when the hourly plan is on.
String? hourlyHostFieldsError({
  required bool hourlyEnabled,
  required String windowStartText,
  required String windowEndText,
  required String slotsText,
  required String maxHoursText,
}) {
  if (!hourlyEnabled) return null;
  final startBlank = windowStartText.trim().isEmpty;
  final endBlank = windowEndText.trim().isEmpty;
  if (startBlank != endBlank) {
    return 'Set both ends of the hourly window, or leave both empty.';
  }
  if (!startBlank) {
    final start = parseClockMinutes(windowStartText);
    final end = parseClockMinutes(windowEndText);
    if (start == null || end == null) {
      return 'Hourly window times must look like 09:00 (24-hour clock).';
    }
    // An end before the start is a window across midnight (161); only
    // an empty window and a 24:00 start are meaningless.
    if (start == end) {
      return 'The hourly window cannot start and end at the same time.';
    }
    if (start == 1440) {
      return 'The hourly window cannot start at 24:00; use 00:00.';
    }
  }
  if (slotsText.trim().isNotEmpty && parseHourlySlotsText(slotsText) == null) {
    return 'Offered durations must be whole hours, like 6, 12.';
  }
  final slots = parseHourlySlotsText(slotsText);
  final max = int.tryParse(maxHoursText.trim());
  if (slots != null && max != null && slots.every((s) => s > max)) {
    return 'Every offered duration is above your maximum of $max hours.';
  }
  return null;
}
