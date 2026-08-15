import 'package:flutter/gestures.dart' show PointerDeviceKind;
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
            mapBuilder: (context, bottomInset) =>
                const ColoredBox(color: Colors.green),
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

    testWidgets('scrolling the results up drives it to full screen',
        (tester) async {
      await pumpSheet(tester);
      final height = tester.getSize(find.byType(ResultsMapSheet)).height;

      // A long scroll on the content drives the sheet continuously to full —
      // no snap pulls it back partway (which is what defeated a mouse wheel,
      // whose many small scroll events each got snapped back).
      await tester.drag(find.text('result 0'), const Offset(0, -600),
          warnIfMissed: false);
      await tester.pumpAndSettle();

      final fraction = (height - sheetTop(tester)) / height;
      expect(
        fraction,
        greaterThan(0.9),
        reason: 'should reach ~full, was ${fraction.toStringAsFixed(3)}',
      );
    });
  });

  testWidgets('dragged to full, the Map button brings the map back',
      (tester) async {
    await pumpSheet(tester);

    // Drag the sheet all the way up — it now covers the map to the top.
    await tester.drag(
        find.byKey(ResultsMapSheet.handleKey), const Offset(0, -600));
    await tester.pumpAndSettle();
    final full = sheetTop(tester);

    // Tapping the floating Map button slides the sheet back down so the map is
    // visible again. (When the map is already visible the button is ignoring
    // pointers, so a working tap here is itself proof it only acts when full.)
    await tester.tap(find.byKey(ResultsMapSheet.mapButtonKey));
    await tester.pumpAndSettle();

    expect(sheetTop(tester), greaterThan(full + 100));
  });

  testWidgets('a mouse-wheel scroll expands the sheet toward full',
      (tester) async {
    await pumpSheet(tester);
    final before = sheetTop(tester);

    // Simulate a mouse wheel over the sheet — several downward ticks, as a
    // guest scrolling to see more listings.
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final spot = tester.getCenter(find.byKey(ResultsMapSheet.surfaceKey));
    await tester.sendEventToBinding(pointer.hover(spot));
    for (var i = 0; i < 6; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 140)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // Expected (Airbnb-style): the sheet grew toward full, not just the list.
    expect(sheetTop(tester), lessThan(before - 100));
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
