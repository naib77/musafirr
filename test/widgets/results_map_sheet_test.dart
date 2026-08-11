import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/widgets/results_map_sheet.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// The results sheet has to move when the guest drags it — including by its
/// grab handle — and it has to keep its gestures to itself, so the map
/// underneath does not pan or zoom under a drag aimed at the sheet.
///
/// The map is a stand-in here: the real one is a platform view, and none of
/// this behaviour depends on it.
void main() {
  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResultsMapSheet(
            map: const ColoredBox(color: Colors.green),
            slivers: [
              SliverList.builder(
                itemCount: 30,
                itemBuilder: (context, i) => SizedBox(
                  height: 80,
                  child: Text('result $i'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double sheetTop(WidgetTester tester) =>
      tester.getRect(find.byKey(ResultsMapSheet.surfaceKey)).top;

  group('the guest can drag the sheet', () {
    testWidgets('dragging the grab handle up expands it', (tester) async {
      await pumpSheet(tester);
      final before = sheetTop(tester);

      // The handle is the affordance that says "drag me", so dragging it has
      // to work. A DraggableScrollableSheet is moved by its scrollable and
      // nothing else, and the handle used to sit outside it.
      await tester.drag(
          find.byKey(ResultsMapSheet.handleKey), const Offset(0, -250));
      await tester.pumpAndSettle();

      expect(sheetTop(tester), lessThan(before - 100));
    });

    testWidgets('dragging the grab handle down collapses it', (tester) async {
      await pumpSheet(tester);
      final before = sheetTop(tester);

      await tester.drag(
          find.byKey(ResultsMapSheet.handleKey), const Offset(0, 250));
      await tester.pumpAndSettle();

      expect(sheetTop(tester), greaterThan(before + 100));
    });

    testWidgets('dragging the results themselves still expands it',
        (tester) async {
      await pumpSheet(tester);
      final before = sheetTop(tester);

      await tester.drag(find.text('result 0'), const Offset(0, -250));
      await tester.pumpAndSettle();

      expect(sheetTop(tester), lessThan(before - 100));
    });

    testWidgets('it comes to rest at one of the three heights', (tester) async {
      await pumpSheet(tester);
      final height = tester.getSize(find.byType(ResultsMapSheet)).height;

      // Nudged a little way, it snaps rather than stopping wherever the finger
      // left it.
      await tester.drag(
          find.byKey(ResultsMapSheet.handleKey), const Offset(0, -60));
      await tester.pumpAndSettle();

      final fraction = (height - sheetTop(tester)) / height;
      expect(
        [
          ResultsMapSheet.minSize,
          ResultsMapSheet.initialSize,
          ResultsMapSheet.maxSize,
        ].any((s) => (fraction - s).abs() < 0.02),
        isTrue,
        reason: 'rested at ${fraction.toStringAsFixed(3)} of the height',
      );
    });
  });

  testWidgets('the handle stays put as the results scroll', (tester) async {
    await pumpSheet(tester);
    final handleBefore = tester.getRect(find.byKey(ResultsMapSheet.handleKey));

    await tester.drag(find.text('result 1'), const Offset(0, -400));
    await tester.pumpAndSettle();

    // Pinned: the sheet grows and the list scrolls, but the handle keeps
    // sitting at the sheet's top edge where it can be grabbed again.
    expect(tester.getRect(find.byKey(ResultsMapSheet.handleKey)).top,
        closeTo(sheetTop(tester), 1));
    expect(handleBefore.height,
        tester.getRect(find.byKey(ResultsMapSheet.handleKey)).height);
  });

  testWidgets('the sheet holds pointer events back from the map',
      (tester) async {
    await pumpSheet(tester);

    // On web the map is a DOM element that wins the browser's hit-test even
    // where Flutter paints the sheet over it, so a drag or a wheel aimed at
    // the sheet reached Google Maps as well — the map panned and zoomed while
    // the sheet stayed still. PointerInterceptor puts a real DOM blocker in
    // front of the map, which is the only fix for it; this asserts the sheet
    // is behind one. Whether the browser then behaves can only be confirmed
    // in a browser.
    expect(
      find.ancestor(
        of: find.byKey(ResultsMapSheet.surfaceKey),
        matching: find.byType(PointerInterceptor),
      ),
      findsOneWidget,
    );
  });
}
