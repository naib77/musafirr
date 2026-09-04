import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/landmark.dart';
import 'package:musafir/models/search_filters.dart';
import 'package:musafir/services/search/search_summary.dart';

void main() {
  group('searchPillSummaryFor', () {
    test('an untouched search fills no segment', () {
      final summary = searchPillSummaryFor(const SearchFilters());
      expect(summary.where, isNull);
      expect(summary.when, isNull);
      expect(summary.who, isNull);
      expect(summary.hasAny, isFalse);
    });

    test('shows the place that was searched', () {
      final summary =
          searchPillSummaryFor(const SearchFilters(location: 'Uttara, Dhaka'));
      expect(summary.where, 'Uttara, Dhaka');
      expect(summary.hasAny, isTrue);
    });

    // A landmark search is the more specific of the two — `location` is often
    // just the city the landmark sits in.
    test('a landmark wins over the location', () {
      final summary = searchPillSummaryFor(SearchFilters(
        location: 'Dhaka',
        landmark: const Landmark(
          id: 'l1',
          name: 'Dhaka Medical College',
          type: 'hospital',
          latitude: 23.72,
          longitude: 90.39,
        ),
      ));
      expect(summary.where, 'Dhaka Medical College');
    });

    test('blank strings are not values', () {
      expect(searchPillSummaryFor(const SearchFilters(location: '   ')).where,
          isNull);
    });

    group('dates', () {
      test('one month prints the month once', () {
        final summary = searchPillSummaryFor(SearchFilters(
          checkIn: DateTime(2026, 9, 12),
          checkOut: DateTime(2026, 9, 15),
        ));
        expect(summary.when, '12 – 15 Sep');
      });

      test('a range across months prints both', () {
        final summary = searchPillSummaryFor(SearchFilters(
          checkIn: DateTime(2026, 9, 29),
          checkOut: DateTime(2026, 10, 2),
        ));
        expect(summary.when, '29 Sep – 2 Oct');
      });

      // Same day-of-month either side of a year boundary must not collapse to
      // the short form, or "28 Dec – 3 Jan" would read as three days in one
      // month.
      test('a range across years prints both', () {
        final summary = searchPillSummaryFor(SearchFilters(
          checkIn: DateTime(2026, 9, 12),
          checkOut: DateTime(2027, 9, 15),
        ));
        expect(summary.when, '12 Sep – 15 Sep');
      });

      test('half a range is not a range', () {
        expect(
          searchPillSummaryFor(SearchFilters(checkIn: DateTime(2026, 9, 12)))
              .when,
          isNull,
        );
      });

      test('single-date mode shows the date and the window', () {
        final summary = searchPillSummaryFor(SearchFilters(
          dateMode: SearchDateMode.singleDateWithTime,
          singleDate: DateTime(2026, 9, 12),
          startTime: const TimeOfDay(hour: 14, minute: 0),
          endTime: const TimeOfDay(hour: 17, minute: 30),
        ));
        expect(summary.when, '12 Sep, 2PM–5:30PM');
      });

      test('single-date midnight reads as 12AM, not 0AM', () {
        final summary = searchPillSummaryFor(SearchFilters(
          dateMode: SearchDateMode.singleDateWithTime,
          singleDate: DateTime(2026, 9, 12),
          startTime: const TimeOfDay(hour: 0, minute: 0),
          endTime: const TimeOfDay(hour: 12, minute: 0),
        ));
        expect(summary.when, '12 Sep, 12AM–12PM');
      });

      // In single-date mode the range fields are irrelevant, and reading them would
      // describe a window the search is not running.
      test('single-date mode ignores a leftover check-in/check-out', () {
        final summary = searchPillSummaryFor(SearchFilters(
          dateMode: SearchDateMode.singleDateWithTime,
          checkIn: DateTime(2026, 9, 12),
          checkOut: DateTime(2026, 9, 15),
        ));
        expect(summary.when, isNull);
      });
    });

    group('guests', () {
      // 1 is the default and `hasActiveFilters` agrees it is not a filter, so
      // showing it would make every untouched pill look narrowed.
      test('the default guest count is not a value', () {
        expect(searchPillSummaryFor(const SearchFilters(guestCount: 1)).who,
            isNull);
        expect(searchPillSummaryFor(const SearchFilters()).who, isNull);
      });

      test('more than one guest shows', () {
        expect(searchPillSummaryFor(const SearchFilters(guestCount: 4)).who,
            '4 guests');
      });
    });
  });
}
