import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/listing.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/services/booking/hourly_policy.dart';

/// The Dart mirror of `hourly_booking_check` (migration 148), fed the same
/// rule table as `supabase/tests/148_hourly_policy_test.sql` §3. If a case
/// here needs changing, the SQL case needs changing too — the two must agree
/// or the picker offers an hour the RPC refuses.
void main() {
  // A start time comfortably inside any window, on a day with no DST.
  final noon = DateTime(2026, 12, 1, 12);
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 12, 1, hour, minute);

  HourlyRule rule({
    ListingType type = ListingType.seat,
    HourlyPolicy? policy,
    int? minHours,
    int? maxHours,
    List<int>? slots,
    String? windowStart,
    String? windowEnd,
  }) =>
      resolveHourlyRule(
        type: type,
        policy: policy ?? HourlyPolicy.defaults,
        limits: BookingLimits(
          minHours: minHours,
          maxHours: maxHours,
          hourlySlots: slots,
          hourlyWindowStart: windowStart,
          hourlyWindowEnd: windowEnd,
        ),
      );

  HourlyPolicy policyOf(Map<String, Object?> doc) =>
      HourlyPolicy.fromRaw(jsonEncode(doc));

  group('defaults', () {
    test('match hourly_policy_defaults() in migration 148 byte for byte', () {
      // Pinned to the SQL source so a change on one side fails here instead
      // of as a floor the app and the database disagree about.
      final sql =
          File('supabase/migrations/148_hourly_policy.sql').readAsStringSync();
      final match = RegExp(
        r"hourly_policy_defaults\(\)[\s\S]*?select '(\{[\s\S]*?\})'::jsonb",
      ).firstMatch(sql);
      expect(match, isNotNull, reason: 'defaults literal not found in 148');
      final doc = jsonDecode(match!.group(1)!) as Map<String, dynamic>;

      expect(doc.keys.toSet(), {'seat', 'room', 'fullHouse', 'turf', 'hotel'});
      for (final entry in doc.entries) {
        final dart = HourlyPolicy.defaults.forTypeName(entry.key);
        final sqlEntry = entry.value as Map<String, dynamic>;
        expect(dart.enabled, sqlEntry['enabled'], reason: entry.key);
        expect(dart.minHours, sqlEntry['min_hours'], reason: entry.key);
        expect(dart.slots, sqlEntry['slots'], reason: entry.key);
      }
    });

    test('hotel is the only slotted type and fullHouse the only raised floor',
        () {
      final d = HourlyPolicy.defaults;
      expect(d.forTypeName('hotel').slots, [6, 12]);
      expect(d.forTypeName('hotel').minHours, 6);
      expect(d.forType(ListingType.fullHouse).minHours, 3);
      for (final t in [ListingType.seat, ListingType.room, ListingType.turf]) {
        expect(d.forType(t).minHours, 1, reason: t.name);
        expect(d.forType(t).slots, isNull, reason: t.name);
      }
    });
  });

  group('fromRaw — fail-open, per type, like hourly_policy_for', () {
    test('absent, blank, junk and non-object → defaults', () {
      for (final raw in [null, '', '   ', 'nope', '[1,2]', '42']) {
        final p = HourlyPolicy.fromRaw(raw);
        expect(p.forType(ListingType.fullHouse).minHours, 3, reason: '$raw');
        expect(p.forTypeName('hotel').slots, [6, 12], reason: '$raw');
      }
    });

    test('a partial document keeps the defaults for the types it omits', () {
      final p = policyOf({
        'seat': {'enabled': true, 'min_hours': 2, 'slots': null},
      });
      expect(p.forType(ListingType.seat).minHours, 2);
      expect(p.forType(ListingType.fullHouse).minHours, 3);
      expect(p.forTypeName('hotel').slots, [6, 12]);
    });

    test('a malformed entry falls back to its own default only', () {
      // Each of these is a shape fn_validate_setting_hourly_policy refuses.
      final bad = <String, Object?>{
        'enabled not boolean': {'enabled': 'yes', 'min_hours': 1},
        'min missing': {'enabled': true},
        'min zero': {'enabled': true, 'min_hours': 0},
        'min above 168': {'enabled': true, 'min_hours': 169},
        'min fractional': {'enabled': true, 'min_hours': 1.5},
        'slots empty': {'enabled': true, 'min_hours': 1, 'slots': <int>[]},
        'slots not ascending': {
          'enabled': true,
          'min_hours': 1,
          'slots': [12, 6]
        },
        'slots duplicate': {
          'enabled': true,
          'min_hours': 1,
          'slots': [6, 6]
        },
        'slot below min': {
          'enabled': true,
          'min_hours': 6,
          'slots': [3, 6]
        },
        'slot above 168': {
          'enabled': true,
          'min_hours': 1,
          'slots': [6, 200]
        },
        'not an object': 7,
      };
      for (final entry in bad.entries) {
        final p = policyOf({
          'hotel': entry.value,
          'seat': {'enabled': false, 'min_hours': 1},
        });
        expect(p.forTypeName('hotel').minHours, 6, reason: entry.key);
        expect(p.forTypeName('hotel').slots, [6, 12], reason: entry.key);
        // The well-formed sibling survives.
        expect(p.forType(ListingType.seat).enabled, isFalse, reason: entry.key);
      }
    });

    test('a well-formed entry is read whole', () {
      final p = policyOf({
        'room': {
          'enabled': true,
          'min_hours': 2,
          'slots': [6, 12]
        },
      });
      final room = p.forType(ListingType.room);
      expect(room.enabled, isTrue);
      expect(room.minHours, 2);
      expect(room.slots, [6, 12]);
    });
  });

  group('rule table — shared with 148_hourly_policy_test.sql §3', () {
    test('seat: 1 h allowed, 13 h over the host max of 12', () {
      final r = rule(minHours: 1, maxHours: 12);
      expect(r.check(1, start: noon), isNull);
      expect(r.refusalFor(13, start: noon), HourlyRefusal.max);
      expect(r.check(13, start: noon), 'Maximum booking is 12 hours');
    });

    test('platform floor 2 clamps a host minimum of 1', () {
      final p = policyOf({
        'seat': {'enabled': true, 'min_hours': 2},
      });
      final r = rule(policy: p, minHours: 1, maxHours: 12);
      expect(r.minHours, 2);
      expect(r.refusalFor(1, start: noon), HourlyRefusal.min);
      expect(r.check(1, start: noon), 'Minimum booking is 2 hours');
      expect(r.check(2, start: noon), isNull);
    });

    test('a host minimum of 4 beats a floor of 1', () {
      final r = rule(type: ListingType.room, minHours: 4);
      expect(r.refusalFor(3, start: noon), HourlyRefusal.min);
      expect(r.check(3, start: noon), 'Minimum booking is 4 hours');
      expect(r.check(4, start: noon), isNull);
    });

    test('fullHouse: 2 h under the default floor of 3, 3 h allowed', () {
      final r = rule(type: ListingType.fullHouse);
      expect(r.check(2, start: noon), 'Minimum booking is 3 hours');
      expect(r.check(3, start: noon), isNull);
    });

    test('a disabled type refuses everything and offers nothing', () {
      final p = policyOf({
        'turf': {'enabled': false, 'min_hours': 1},
      });
      final r = rule(type: ListingType.turf, policy: p, minHours: 1);
      expect(r.refusalFor(1, start: noon), HourlyRefusal.disabled);
      expect(r.check(1, start: noon),
          'Hourly bookings are not offered for this kind of listing');
      expect(r.options, isEmpty);
      expect(r.bookable, isFalse);
    });

    test('platform slots [6, 12]: 7 h is not a slot, 6 and 12 are', () {
      final p = policyOf({
        'room': {
          'enabled': true,
          'min_hours': 1,
          'slots': [6, 12]
        },
      });
      final r = rule(type: ListingType.room, policy: p);
      expect(r.refusalFor(7, start: noon), HourlyRefusal.slot);
      expect(r.check(7, start: noon),
          'Choose one of the offered durations: 6, 12 hours');
      expect(r.check(6, start: noon), isNull);
      expect(r.check(12, start: noon), isNull);
      expect(r.options, [6, 12]);
    });

    test('host slots replace the platform list — {6} drops 12', () {
      final p = policyOf({
        'room': {
          'enabled': true,
          'min_hours': 1,
          'slots': [6, 12]
        },
      });
      final r = rule(type: ListingType.room, policy: p, slots: [6]);
      expect(r.check(12, start: noon),
          'Choose one of the offered durations: 6 hours');
      expect(r.check(6, start: noon), isNull);
      expect(r.options, [6]);
    });

    test('host slots {2, 4} on a free-hours type make it slotted', () {
      final r = rule(minHours: 1, maxHours: 12, slots: [2, 4]);
      expect(r.refusalFor(3, start: noon), HourlyRefusal.slot);
      expect(r.check(2, start: noon), isNull);
      expect(r.check(4, start: noon), isNull);
      expect(r.options, [2, 4]);
    });

    test('a slot above the host max is refused as max, and hidden', () {
      final r = rule(minHours: 1, maxHours: 12, slots: [6, 24]);
      expect(r.refusalFor(24, start: noon), HourlyRefusal.max);
      expect(r.options, [6]);
    });

    test('every slot above the host max leaves nothing to offer', () {
      final r = rule(minHours: 1, maxHours: 4, slots: [6, 12]);
      expect(r.options, isEmpty);
      expect(r.bookable, isFalse);
    });

    group('window 09:00–21:00', () {
      final r = rule(
        type: ListingType.room,
        minHours: 1,
        windowStart: '09:00',
        windowEnd: '21:00',
      );

      test('starting before the window is refused', () {
        expect(r.refusalFor(2, start: at(8)), HourlyRefusal.window);
        expect(r.check(2, start: at(8)),
            'Hourly stays here run between 09:00 and 21:00');
      });

      test('ending after the window is refused', () {
        expect(r.refusalFor(2, start: at(20)), HourlyRefusal.window);
      });

      test('exactly filling the window is allowed', () {
        expect(r.check(12, start: at(9)), isNull);
        expect(r.check(1, start: at(20)), isNull);
      });

      test('minutes count', () {
        expect(r.refusalFor(1, start: at(8, 59)), HourlyRefusal.window);
        expect(r.refusalFor(1, start: at(20, 1)), HourlyRefusal.window);
        expect(r.check(1, start: at(9, 30)), isNull);
      });
    });

    test('a window ending at 24:00 admits a stay that ends at midnight', () {
      final r = rule(
        type: ListingType.room,
        minHours: 1,
        windowStart: '18:00',
        windowEnd: '24:00',
      );
      expect(r.hasWindow, isTrue);
      expect(r.check(6, start: at(18)), isNull);
      // Past midnight is the next calendar day: never inside the window.
      expect(r.refusalFor(7, start: at(18)), HourlyRefusal.window);
    });

    group('window 22:00–02:00 runs past midnight (161)', () {
      final r = rule(
        type: ListingType.room,
        minHours: 1,
        windowStart: '22:00',
        windowEnd: '02:00',
      );

      test('a stay across midnight inside the window is allowed', () {
        expect(r.check(4, start: at(22)), isNull);
        expect(r.check(2, start: at(23)), isNull);
      });

      test('a stay starting after midnight belongs to the window', () {
        expect(r.check(1, start: at(1)), isNull);
        expect(r.check(2, start: at(0)), isNull);
      });

      test('outside either end is refused', () {
        expect(r.refusalFor(1, start: at(21)), HourlyRefusal.window);
        expect(r.refusalFor(2, start: at(1)), HourlyRefusal.window);
        expect(r.refusalFor(5, start: at(22)), HourlyRefusal.window);
        expect(r.refusalFor(1, start: noon), HourlyRefusal.window);
        expect(r.check(1, start: at(21)),
            'Hourly stays here run between 22:00 and 02:00');
      });
    });

    test('with no window, a stay may cross midnight', () {
      final r = rule(type: ListingType.room, minHours: 1);
      expect(r.check(6, start: at(22)), isNull);
    });

    test('floor is checked before window — the message names the floor', () {
      final r = rule(
        type: ListingType.fullHouse,
        windowStart: '09:00',
        windowEnd: '21:00',
      );
      // 1 h at 07:00 breaks both rules; the server raises hourly_min.
      expect(r.refusalFor(1, start: at(7)), HourlyRefusal.min);
    });

    test('max is checked before slot', () {
      final r = rule(minHours: 1, maxHours: 12, slots: [6, 24]);
      expect(r.refusalFor(24, start: noon), HourlyRefusal.max);
      expect(r.refusalFor(7, start: noon), HourlyRefusal.slot);
    });

    test('a half-formed window on the listing is ignored, not enforced', () {
      // The column constraint forbids this; if it ever arrives, the Dart side
      // must not invent a one-sided window the server does not have.
      final r = rule(minHours: 1, windowStart: '09:00');
      expect(r.hasWindow, isFalse);
      expect(r.check(2, start: at(6)), isNull);
    });
  });

  group('options — what the picker offers', () {
    test('free hours: floor..max, or floor..12 when the host set no max', () {
      expect(rule(minHours: 1).options, List.generate(12, (i) => i + 1));
      expect(rule(minHours: 3, maxHours: 5).options, [3, 4, 5]);
      expect(rule(type: ListingType.fullHouse).options,
          List.generate(10, (i) => i + 3));
    });

    test('a floor above 12 still gets one option', () {
      expect(rule(minHours: 24).options, [24]);
    });

    test('host max under the floor leaves nothing', () {
      expect(rule(type: ListingType.fullHouse, maxHours: 2).options, isEmpty);
    });

    test('platform slots are offered in order', () {
      // Hotel's default shape, on a type that exists before 149 lands.
      final p = policyOf({
        'room': {
          'enabled': true,
          'min_hours': 6,
          'slots': [6, 12]
        },
      });
      final r = rule(type: ListingType.room, policy: p);
      expect(r.options, [6, 12]);
      expect(r.slots, [6, 12]);
    });
  });

  group('clock parsing', () {
    test('accepts HH:MM, H:MM, HH:MM:SS and 24:00', () {
      expect(parseClockMinutes('09:00'), 540);
      expect(parseClockMinutes('9:00'), 540);
      expect(parseClockMinutes('09:00:00'), 540);
      expect(parseClockMinutes(' 21:30 '), 1290);
      expect(parseClockMinutes('24:00'), 1440);
      expect(parseClockMinutes('00:00'), 0);
    });

    test('rejects what the time column would reject', () {
      for (final bad in [
        null,
        '',
        '9',
        '9am',
        '24:01',
        '25:00',
        '09:60',
        '9:0',
        'noon'
      ]) {
        expect(parseClockMinutes(bad), isNull, reason: '$bad');
      }
    });

    test('formats back to HH:MM with 24:00 for midnight-end', () {
      expect(formatClockMinutes(540), '09:00');
      expect(formatClockMinutes(1290), '21:30');
      expect(formatClockMinutes(1440), '24:00');
      expect(normalizeClockText('9:00'), '09:00');
      expect(normalizeClockText('09:00:00'), '09:00');
      expect(normalizeClockText('9am'), isNull);
      expect(normalizeClockText(''), isNull);
    });
  });

  group('parseHourlySlotsText', () {
    test('blank → null (inherit the platform list)', () {
      expect(parseHourlySlotsText(null), isNull);
      expect(parseHourlySlotsText(''), isNull);
      expect(parseHourlySlotsText('  ,  '), isNull);
    });

    test('sorts, dedupes and tolerates loose separators', () {
      expect(parseHourlySlotsText('12, 6'), [6, 12]);
      expect(parseHourlySlotsText('6,6,12,'), [6, 12]);
      expect(parseHourlySlotsText('3 6 9'), [3, 6, 9]);
    });

    test('drops junk and out-of-range tokens rather than failing the save', () {
      expect(parseHourlySlotsText('6, abc, 12'), [6, 12]);
      expect(parseHourlySlotsText('0, 6, 200'), [6]);
      expect(parseHourlySlotsText('abc'), isNull);
    });
  });

  group('host form helpers', () {
    test('clampHostMinHours raises to the floor, leaves unset unset', () {
      final floor3 = HourlyPolicy.defaults.forType(ListingType.fullHouse);
      expect(clampHostMinHours(1, floor3), 3);
      expect(clampHostMinHours(5, floor3), 5);
      expect(clampHostMinHours(null, floor3), isNull);
    });

    test('hourlyHostFieldsError is silent when hourly is off', () {
      expect(
        hourlyHostFieldsError(
          hourlyEnabled: false,
          windowStartText: '09:00',
          windowEndText: '',
          slotsText: 'junk',
          maxHoursText: '',
        ),
        isNull,
      );
    });

    test('window must be both ends, parseable, and non-empty', () {
      String? err(String start, String end) => hourlyHostFieldsError(
            hourlyEnabled: true,
            windowStartText: start,
            windowEndText: end,
            slotsText: '',
            maxHoursText: '',
          );
      expect(err('09:00', ''),
          'Set both ends of the hourly window, or leave both empty.');
      expect(err('', '21:00'),
          'Set both ends of the hourly window, or leave both empty.');
      expect(err('9am', '21:00'),
          'Hourly window times must look like 09:00 (24-hour clock).');
      // An end before the start wraps past midnight (161).
      expect(err('22:00', '02:00'), isNull);
      expect(err('21:00', '09:00'), isNull);
      expect(err('09:00', '09:00'),
          'The hourly window cannot start and end at the same time.');
      expect(err('24:00', '02:00'),
          'The hourly window cannot start at 24:00; use 00:00.');
      expect(err('09:00', '21:00'), isNull);
      expect(err('18:00', '24:00'), isNull);
      expect(err('', ''), isNull);
    });

    test('slots must parse, and not all sit above the max', () {
      String? err(String slots, String max) => hourlyHostFieldsError(
            hourlyEnabled: true,
            windowStartText: '',
            windowEndText: '',
            slotsText: slots,
            maxHoursText: max,
          );
      expect(
          err('abc', ''), 'Offered durations must be whole hours, like 6, 12.');
      expect(err('6, 12', '4'),
          'Every offered duration is above your maximum of 4 hours.');
      expect(err('6, 12', '6'), isNull);
      expect(err('6, 12', ''), isNull);
      expect(err('', '4'), isNull);
    });
  });

  group('hourlyPolicyHelperText', () {
    test('names the floor and the platform slots', () {
      final slotted = policyOf({
        'room': {
          'enabled': true,
          'min_hours': 6,
          'slots': [6, 12]
        },
      });
      expect(
        hourlyPolicyHelperText(ListingType.room, slotted),
        contains('blocks of 6, 12 hours'),
      );
      expect(
        hourlyPolicyHelperText(ListingType.fullHouse, HourlyPolicy.defaults),
        startsWith('Minimum 3 hours'),
      );
      expect(
        hourlyPolicyHelperText(ListingType.seat, HourlyPolicy.defaults),
        startsWith('Minimum 1 hour '),
      );
    });

    test('says so when the type is switched off', () {
      final p = policyOf({
        'turf': {'enabled': false, 'min_hours': 1},
      });
      expect(hourlyPolicyHelperText(ListingType.turf, p),
          contains('switched off'));
    });
  });
}
