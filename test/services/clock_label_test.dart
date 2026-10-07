import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/clock_label.dart';

/// The picker writes what a host would have typed, and reads back whatever
/// a host did type — the check-in columns are free text (053) printed
/// verbatim, so both directions must agree on the label spelling.
void main() {
  group('parseClockLabelMinutes', () {
    test('reads the forms\' defaults and common spellings', () {
      expect(parseClockLabelMinutes('2:00 PM'), 14 * 60);
      expect(parseClockLabelMinutes('11:00 AM'), 11 * 60);
      expect(parseClockLabelMinutes('12:00 PM'), 12 * 60);
      expect(parseClockLabelMinutes('12:00 AM'), 0);
      expect(parseClockLabelMinutes('2:30pm'), 14 * 60 + 30);
      expect(parseClockLabelMinutes('2 PM'), 14 * 60);
      expect(parseClockLabelMinutes(' 9:05 a.m. '), 9 * 60 + 5);
    });

    test('also reads 24-hour text', () {
      expect(parseClockLabelMinutes('14:30'), 14 * 60 + 30);
      expect(parseClockLabelMinutes('00:00'), 0);
    });

    test('prose and junk are null, never a wrong time', () {
      expect(parseClockLabelMinutes(null), isNull);
      expect(parseClockLabelMinutes(''), isNull);
      expect(parseClockLabelMinutes('after 2, ask reception'), isNull);
      expect(parseClockLabelMinutes('13:00 PM'), isNull);
      expect(parseClockLabelMinutes('0:30 AM'), isNull);
      expect(parseClockLabelMinutes('2:60 PM'), isNull);
      expect(parseClockLabelMinutes('24:00'), isNull);
    });
  });

  group('formatClockLabel', () {
    test('writes the label the defaults have always used', () {
      expect(formatClockLabel(14 * 60), '2:00 PM');
      expect(formatClockLabel(11 * 60), '11:00 AM');
      expect(formatClockLabel(12 * 60), '12:00 PM');
      expect(formatClockLabel(0), '12:00 AM');
      expect(formatClockLabel(23 * 60 + 59), '11:59 PM');
      expect(formatClockLabel(9 * 60 + 5), '9:05 AM');
    });

    test('round-trips every minute of the day', () {
      for (var m = 0; m < 24 * 60; m++) {
        expect(parseClockLabelMinutes(formatClockLabel(m)), m);
      }
    });
  });

  test('TimeOfDay bridge', () {
    expect(timeOfDayFromMinutes(14 * 60 + 30),
        const TimeOfDay(hour: 14, minute: 30));
    expect(minutesFromTimeOfDay(const TimeOfDay(hour: 0, minute: 1)), 1);
  });
}
