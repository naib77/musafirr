import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/widgets/search/search_sheet_footer.dart';

/// The mobile sheet's footer. Extracted from `_SearchSheet` precisely so it
/// could be asserted on — nothing pumps `ExploreScreen`, so a footer left
/// inline in that file had no test seam at all.
void main() {
  Future<void> pumpFooter(
    WidgetTester tester, {
    VoidCallback? onClear,
    VoidCallback? onSearch,
    bool busy = false,
    Size size = const Size(390, 720),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          // Bottom-aligned, the way it sits under the sheet's scroll area.
          body: Column(
            children: [
              const Spacer(),
              SearchSheetFooter(
                onClearAll: onClear ?? () {},
                onSearch: onSearch,
                busy: busy,
              ),
            ],
          ),
        ),
      ),
    ));
  }

  testWidgets('shows both actions side by side', (tester) async {
    await pumpFooter(tester, onSearch: () {});
    expect(find.text('Clear all'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);

    // Clear all on the left, Search on the right — the reference layout, and
    // the order that keeps the destructive action away from the thumb's
    // resting position on the primary one.
    final clear = tester.getCenter(find.text('Clear all')).dx;
    final search = tester.getCenter(find.text('Search')).dx;
    expect(clear, lessThan(search));
  });

  // A loose Flexible on the left sized itself to the label and left the slack
  // after the row's last child, which parked Search mid-bar. The two actions
  // have to sit at opposite ends: Clear all against the left padding, Search
  // against the right.
  testWidgets('Search is flush right and Clear all flush left', (tester) async {
    const width = 390.0;
    await pumpFooter(tester, onSearch: () {}, size: const Size(width, 720));
    const pad = 20.0; // the footer's own horizontal padding

    final searchRight = tester.getBottomRight(find.byType(FilledButton)).dx;
    expect(searchRight, closeTo(width - pad, 1),
        reason: 'the Search button should reach the right padding');

    final clearLeft = tester.getTopLeft(find.byType(TextButton)).dx;
    expect(clearLeft, closeTo(pad, 1),
        reason: 'Clear all should start at the left padding');

    // And a real gap between them, not two buttons touching.
    final clearRight = tester.getBottomRight(find.text('Clear all')).dx;
    final searchLeft = tester.getTopLeft(find.byType(FilledButton)).dx;
    expect(searchLeft - clearRight, greaterThan(24),
        reason: 'the two actions should read as opposite ends of a bar');
  });

  testWidgets('each action reports its own tap', (tester) async {
    var cleared = 0;
    var searched = 0;
    await pumpFooter(
      tester,
      onClear: () => cleared++,
      onSearch: () => searched++,
    );

    await tester.tap(find.text('Clear all'));
    await tester.pump();
    expect(cleared, 1);
    expect(searched, 0, reason: 'clearing must not run a search');

    await tester.tap(find.text('Search'));
    await tester.pump();
    expect(searched, 1);
    expect(cleared, 1);
  });

  testWidgets('a null onSearch disables the button while a place resolves',
      (tester) async {
    await pumpFooter(tester, onSearch: null, busy: true);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    // Says what it is waiting on rather than just spinning.
    expect(find.text('Finding place…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Search'), findsNothing);
  });

  testWidgets('Clear all stays available even with nothing entered',
      (tester) async {
    // Deliberate: the alternative is a second definition of "is anything set"
    // beside hasActiveFilters and SearchDraft.hasAnyInput, and those drifting
    // is a worse bug than a no-op tap.
    await pumpFooter(tester, onSearch: () {});
    final button = tester.widget<TextButton>(find.byType(TextButton));
    expect(button.onPressed, isNotNull);
  });

  group('does not overflow', () {
    // The footer is a Row with a fixed primary button, so a long label or a
    // big text scale is exactly what would break it. The Clear all label
    // ellipsizes; the Search button must stay whole.
    for (final scale in [1.0, 1.3, 2.0]) {
      for (final width in [320.0, 390.0]) {
        testWidgets('at ${width.toInt()}px and ${scale}x text', (tester) async {
          await pumpFooter(
            tester,
            onSearch: () {},
            size: Size(width, 720),
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Search'), findsOneWidget);
        });
      }
    }
  });

  testWidgets('both targets clear 44px', (tester) async {
    await pumpFooter(tester, onSearch: () {});
    expect(tester.getSize(find.byType(TextButton)).height,
        greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(44));
  });
}
