import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/widgets/search/date_calendar.dart';

/// A Saturday, so "this weekend" starts today and the weekday maths is being
/// exercised at its edge rather than in the easy middle of a week.
final _today = DateTime(2026, 9, 5);

void main() {
  group('dateShortcutRange', () {
    // Every shortcut has to be a RANGE. A stay needs a check-out, and a
    // zero-length tstzrange matches nothing — "Today" meaning one night is
    // also what a guest tapping it at 9pm means.
    test('Today is tonight, not a single day', () {
      final range = dateShortcutRange(DateShortcut.today, _today);
      expect(range.start, DateTime(2026, 9, 5));
      expect(range.end, DateTime(2026, 9, 6));
      expect(range.end.isAfter(range.start), isTrue);
    });

    test('Tomorrow is the night after', () {
      final range = dateShortcutRange(DateShortcut.tomorrow, _today);
      expect(range.start, DateTime(2026, 9, 6));
      expect(range.end, DateTime(2026, 9, 7));
    });

    test('on a Saturday, this weekend starts today', () {
      final range = dateShortcutRange(DateShortcut.thisWeekend, _today);
      expect(range.start, DateTime(2026, 9, 5));
      expect(range.end, DateTime(2026, 9, 6));
    });

    test('midweek, this weekend is the coming Saturday', () {
      // Wednesday 9 September 2026.
      final range =
          dateShortcutRange(DateShortcut.thisWeekend, DateTime(2026, 9, 9));
      expect(range.start, DateTime(2026, 9, 12));
      expect(range.end, DateTime(2026, 9, 13));
    });

    // The weekend has effectively gone; rolling forward beats offering a range
    // that starts yesterday and would be refused as a past date.
    test('on a Sunday, it rolls to the next weekend', () {
      final range =
          dateShortcutRange(DateShortcut.thisWeekend, DateTime(2026, 9, 6));
      expect(range.start, DateTime(2026, 9, 12));
      expect(range.start.isBefore(DateTime(2026, 9, 6)), isFalse);
    });

    test('the time of day never leaks into a shortcut', () {
      final range = dateShortcutRange(
        DateShortcut.today,
        DateTime(2026, 9, 5, 21, 47),
      );
      expect(range.start, DateTime(2026, 9, 5));
    });
  });

  group('DateCalendar', () {
    // Holds the reported range so a test can assert on what the calendar
    // actually emitted, not on what it drew.
    late DateTimeRange? reported;

    Future<void> pumpCalendar(
      WidgetTester tester, {
      DateTimeRange? initial,
      DateTime? today,
    }) async {
      reported = initial;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DateCalendar(
              today: today ?? _today,
              range: reported,
              onRangeChanged: (range) => setState(() => reported = range),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('opens on the current month', (tester) async {
      await pumpCalendar(tester);
      expect(find.text('September 2026'), findsOneWidget);
    });

    // Reopening the panel to look at a booked November and landing on
    // September is the sort of small wrongness that makes a calendar feel
    // broken.
    testWidgets('opens on the month the selection is in', (tester) async {
      await pumpCalendar(
        tester,
        initial: DateTimeRange(
          start: DateTime(2026, 11, 3),
          end: DateTime(2026, 11, 6),
        ),
      );
      expect(find.text('November 2026'), findsOneWidget);
    });

    testWidgets('two taps make a range', (tester) async {
      await pumpCalendar(tester);
      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();

      final range = reported;
      expect(range!.start, DateTime(2026, 9, 12));
      expect(range.end, DateTime(2026, 9, 15));
    });

    // An inverted window reaches tstzrange(lower > upper) and aborts the whole
    // search with 22000, so a backwards second tap must restart rather than
    // silently swap the ends.
    testWidgets('a backwards second tap restarts instead of inverting',
        (tester) async {
      await pumpCalendar(tester);
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();

      final range = reported;
      expect(range!.start, DateTime(2026, 9, 12));
      expect(range.end, DateTime(2026, 9, 12));
      expect(range.end.isBefore(range.start), isFalse);
    });

    testWidgets('a third tap starts a new range', (tester) async {
      await pumpCalendar(tester);
      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();

      final range = reported;
      expect(range!.start, DateTime(2026, 9, 20));
      expect(range.end, DateTime(2026, 9, 20));
    });

    testWidgets('a past date refuses selection', (tester) async {
      await pumpCalendar(tester, today: DateTime(2026, 9, 10));
      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();
      expect(reported, isNull);
    });

    testWidgets('today itself is selectable', (tester) async {
      await pumpCalendar(tester, today: DateTime(2026, 9, 10));
      await tester.tap(find.text('10'));
      await tester.pumpAndSettle();
      expect(reported!.start, DateTime(2026, 9, 10));
    });

    testWidgets('pages forward a month', (tester) async {
      await pumpCalendar(tester);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
    });

    // There is nothing selectable behind today, so the control has to be off
    // rather than paging to a month of struck-through numbers.
    testWidgets('cannot page behind the current month', (tester) async {
      await pumpCalendar(tester);
      final back = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.chevron_left),
          matching: find.byType(IconButton),
        ),
      );
      expect(back.onPressed, isNull);
    });

    testWidgets('a half-made range survives paging', (tester) async {
      await pumpCalendar(tester);
      await tester.tap(find.text('28'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      // October 2nd — closing the range across the month boundary.
      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();

      final range = reported;
      expect(range!.start, DateTime(2026, 9, 28));
      expect(range.end, DateTime(2026, 10, 2));
    });
  });
}
