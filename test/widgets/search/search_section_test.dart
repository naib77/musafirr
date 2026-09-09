import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/widgets/search/search_section.dart';

Future<void> _pump(
  WidgetTester tester, {
  String label = 'When',
  String? summary,
  String placeholder = 'Add dates',
  required bool expanded,
  VoidCallback? onTap,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SearchSection(
          label: label,
          summary: summary,
          placeholder: placeholder,
          expanded: expanded,
          onTap: onTap ?? () {},
          child: const Text('SECTION BODY'),
        ),
      ),
    ),
  );
}

void main() {
  group('collapsed', () {
    // The whole point of folding: a closed row is not a hidden control, it is
    // a statement of the current answer.
    testWidgets('shows the label and what the step holds', (tester) async {
      await _pump(tester, summary: '12 – 15 Sep', expanded: false);
      expect(find.text('When'), findsOneWidget);
      expect(find.text('12 – 15 Sep'), findsOneWidget);
    });

    testWidgets('falls back to the placeholder when nothing is chosen',
        (tester) async {
      await _pump(tester, expanded: false);
      expect(find.text('Add dates'), findsOneWidget);
    });

    // A collapsed month grid still laying itself out is wasted work, and on
    // the phone it was three screens of controls that made folding necessary.
    testWidgets('does not build its child', (tester) async {
      await _pump(tester, expanded: false);
      expect(find.text('SECTION BODY'), findsNothing);
    });

    testWidgets('asks the parent to open it when tapped', (tester) async {
      var taps = 0;
      await _pump(tester, expanded: false, onTap: () => taps++);
      await tester.tap(find.text('Add dates'));
      expect(taps, 1);
    });

    // Label and value are one announcement, not two unrelated ones.
    testWidgets('reads as a single button to a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, summary: 'Uttara', label: 'Where', expanded: false);
      expect(
        find.bySemanticsLabel('Where, Uttara. Tap to change.'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('expanded', () {
    testWidgets('asks the question and shows the controls', (tester) async {
      await _pump(tester, expanded: true);
      expect(find.text('When?'), findsOneWidget);
      expect(find.text('SECTION BODY'), findsOneWidget);
    });

    // The summary belongs to the closed state. Repeating it above the controls
    // that produce it is noise.
    testWidgets('does not repeat the summary', (tester) async {
      await _pump(tester, summary: '12 – 15 Sep', expanded: true);
      expect(find.text('12 – 15 Sep'), findsNothing);
    });

    // Tapping the open card's heading would collapse the sheet into nothing
    // open, which has no way back except another tap.
    testWidgets('the open card is not a button', (tester) async {
      var taps = 0;
      await _pump(tester, expanded: true, onTap: () => taps++);
      await tester.tap(find.text('When?'));
      await tester.pump();
      expect(taps, 0);
    });
  });

  // Growing and shrinking is what makes this read as one sheet rearranging
  // rather than as two different sheets.
  testWidgets('animates between the two states', (tester) async {
    await _pump(tester, summary: 'Uttara', expanded: false);
    final closed = tester.getSize(find.byType(SearchSection)).height;

    await _pump(tester, summary: 'Uttara', expanded: true);
    await tester.pump(const Duration(milliseconds: 60));
    final midway = tester.getSize(find.byType(SearchSection)).height;
    await tester.pumpAndSettle();
    final open = tester.getSize(find.byType(SearchSection)).height;

    expect(open, greaterThan(closed));
    expect(midway, lessThan(open), reason: 'it must not snap open');
  });
}
