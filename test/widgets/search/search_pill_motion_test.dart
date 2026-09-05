import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/search_filters.dart';
import 'package:musafir/widgets/search/search_pill.dart';
import 'package:musafir/widgets/search/where_panel.dart';

/// How the panel behaves *between* states, which is the whole of what the user
/// sees as "flicking" versus "swift like scrolling".
///
/// These assert on motion, not on end state — `search_pill_test.dart` already
/// covers where things end up. A settled screenshot cannot see a flicker by
/// construction, and neither can a settled assertion.
void main() {
  Future<void> pumpPill(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SearchPill(
            filters: const SearchFilters(),
            today: DateTime(2026, 9, 5),
            cities: (q) => const [CitySuggestion(city: 'Dhaka', count: 4)],
            onPickLandmark: (c, {required type, required title}) async => null,
            onCommit: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The panel's own card, wherever it currently is.
  Finder panel() => find.byKey(const ValueKey('search-panel'));

  Future<void> open(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  group('switching segments', () {
    // The bug: the panel jumped position, width and contents in a single frame.
    // Airbnb's slides. One frame after the tap it must not already be at its
    // destination.
    testWidgets('slides rather than jumping to the new segment',
        (tester) async {
      await pumpPill(tester);
      await open(tester, 'Where');
      final fromLeft = tester.getTopLeft(panel()).dx;

      await tester.tap(find.text('Who'));
      await tester.pump(); // the frame the tap lands on
      await tester.pump(const Duration(milliseconds: 16));
      final midLeft = tester.getTopLeft(panel()).dx;

      await tester.pumpAndSettle();
      final toLeft = tester.getTopLeft(panel()).dx;

      // The two segments are far enough apart that any real animation shows.
      expect((toLeft - fromLeft).abs(), greaterThan(100),
          reason: 'Where and Who should anchor well apart');
      expect(midLeft, isNot(closeTo(toLeft, 1)),
          reason: 'one frame in, the panel had already arrived — it jumped');
      expect(midLeft, closeTo(fromLeft, 60),
          reason: 'the panel should still be near where it started');
    });

    // Every panel is the same width, and that is load-bearing rather than
    // lazy. The cross-fade lays BOTH panels out during the transition, so a
    // card that animated between two widths would lay the calendar out at the
    // Who panel's width — its month grid is 7 fixed 40px cells beside a 132px
    // rail, and it overflowed by 45 pixels, striping the panel.
    testWidgets('keeps one width, so neither panel is ever squeezed',
        (tester) async {
      await pumpPill(tester);
      await open(tester, 'When');
      final whenWidth = tester.getSize(panel()).width;

      await tester.tap(find.text('Who'));
      // Straight through the cross-fade, where both are laid out at once.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        expect(tester.takeException(), isNull,
            reason: 'a panel overflowed mid-transition');
      }
      await tester.pumpAndSettle();

      expect(tester.getSize(panel()).width, whenWidth);
    });

    // A hard cut between two different panels is the "flick": the old content
    // vanishes and the new appears in the same frame.
    testWidgets('cross-fades its contents', (tester) async {
      await pumpPill(tester);
      await open(tester, 'Who');
      expect(find.text('Adults'), findsOneWidget);

      await tester.tap(find.text('When'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // Mid-transition BOTH are on screen, one fading out and one in.
      expect(find.text('Adults'), findsOneWidget,
          reason: 'the outgoing panel was removed in a single frame');
      expect(find.text('September 2026'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('Adults'), findsNothing);
    });
  });

  group('the scrim', () {
    // The scrim used to be positioned from a layout measurement taken during
    // build. Reading layout mid-build is the classic way to get a stale or
    // throwing value — and a throw here paints a full-screen dark red
    // ErrorWidget, since the overlay child covers the window.
    testWidgets('never moves while a counter is being changed', (tester) async {
      await pumpPill(tester);
      await open(tester, 'Who');

      final before =
          tester.getTopLeft(find.byKey(const ValueKey('search-scrim')));
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('One more Adults'));
        await tester.pump();
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('search-scrim'))),
          before,
          reason: 'the scrim jumped mid-interaction',
        );
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // It must start below the bar, or the header greys out with it and the
    // whole thing reads as disabled.
    testWidgets('starts below the bar, not at the top of the window',
        (tester) async {
      await pumpPill(tester);
      await open(tester, 'Who');
      final barBottom =
          tester.getBottomLeft(find.byKey(const ValueKey('search-bar'))).dy;
      final scrimTop =
          tester.getTopLeft(find.byKey(const ValueKey('search-scrim'))).dy;
      expect(scrimTop, greaterThanOrEqualTo(barBottom));
    });
  });
}
