import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/search_filters.dart';
import 'package:musafir/services/search/search_date_window.dart';

void main() {
  group('searchDateWindowFor', () {
    test('an undated search has no window, so nothing is filtered out', () {
      expect(searchDateWindowFor(const SearchFilters()), isNull);
    });

    test('a date range becomes the window', () {
      final window = searchDateWindowFor(SearchFilters(
        checkIn: DateTime(2026, 9, 10),
        checkOut: DateTime(2026, 9, 15),
      ));

      expect(window, isNotNull);
      expect(window!.startsAt, DateTime(2026, 9, 10));
      expect(window.endsAt, DateTime(2026, 9, 15));
    });

    // Half a range cannot exclude anything: "from the 10th" says nothing about
    // when the stay ends, so there is no interval to test a listing against.
    // Guarded because the explore sheet reports the first tap immediately.
    test('half a range is not a window', () {
      expect(
        searchDateWindowFor(SearchFilters(checkIn: DateTime(2026, 9, 10))),
        isNull,
      );
      expect(
        searchDateWindowFor(SearchFilters(checkOut: DateTime(2026, 9, 15))),
        isNull,
      );
    });

    test('hourly mode folds the date and the two times into one window', () {
      final window = searchDateWindowFor(SearchFilters(
        dateMode: SearchDateMode.singleDateWithTime,
        singleDate: DateTime(2026, 9, 10),
        startTime: const TimeOfDay(hour: 10, minute: 0),
        endTime: const TimeOfDay(hour: 14, minute: 30),
      ));

      expect(window, isNotNull);
      expect(window!.startsAt, DateTime(2026, 9, 10, 10, 0));
      expect(window.endsAt, DateTime(2026, 9, 10, 14, 30));
    });

    test('hourly mode without its times is not a window', () {
      expect(
        searchDateWindowFor(SearchFilters(
          dateMode: SearchDateMode.singleDateWithTime,
          singleDate: DateTime(2026, 9, 10),
        )),
        isNull,
      );
    });

    // The RPC builds tstzrange(p_check_in, p_check_out); lower > upper raises
    // 22000 and takes the whole search down, so a reversed selection must never
    // reach it. Reachable in hourly mode, where the two times are picked
    // independently and the app's own pricing refuses to cross midnight.
    test('a reversed window is dropped rather than sent', () {
      expect(
        searchDateWindowFor(SearchFilters(
          dateMode: SearchDateMode.singleDateWithTime,
          singleDate: DateTime(2026, 9, 10),
          startTime: const TimeOfDay(hour: 22, minute: 0),
          endTime: const TimeOfDay(hour: 2, minute: 0),
        )),
        isNull,
      );
    });

    test('a zero-length window is dropped', () {
      expect(
        searchDateWindowFor(SearchFilters(
          checkIn: DateTime(2026, 9, 10),
          checkOut: DateTime(2026, 9, 10),
        )),
        isNull,
      );
    });

    // A naive local string would be read by the timestamptz parameter as UTC,
    // shifting a Bangladesh (UTC+6) search six hours and filtering the wrong
    // day at the edges.
    test('the wire format is UTC', () {
      final window = searchDateWindowFor(SearchFilters(
        checkIn: DateTime.utc(2026, 9, 10, 6),
        checkOut: DateTime.utc(2026, 9, 15, 6),
      ))!;

      expect(window.startsAtIso, '2026-09-10T06:00:00.000Z');
      expect(window.endsAtIso, '2026-09-15T06:00:00.000Z');
    });
  });
}
