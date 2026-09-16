import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/core/theme/app_colors.dart';
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
            cities: (q, types) =>
                const [CitySuggestion(city: 'Dhaka', count: 4)],
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

  group('travel between segments', () {
    /// Where [label] sits inside the card, so the card's own movement does not
    /// confound the measurement.
    double offsetInPanel(WidgetTester tester, String label) =>
        tester.getTopLeft(find.text(label)).dx - tester.getTopLeft(panel()).dx;

    // The card itself barely moves: Where to When is 89px and When to Who is
    // 24px at 1440px, so position alone cannot carry the change and a plain
    // cross-fade was the whole of what a switch looked like. The contents
    // travel instead — in from the side being moved towards, out by the other
    // — which is what makes it read as going from one tab to the next.
    testWidgets('slides the contents in from the side it is moving from',
        (tester) async {
      await pumpPill(tester);
      await open(tester, 'Who');
      final adultsAtRest = offsetInPanel(tester, 'Adults');

      // Who (2) to When (1) is leftwards.
      await tester.tap(find.text('When'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      expect(offsetInPanel(tester, 'Adults'), greaterThan(adultsAtRest + 8),
          reason: 'the outgoing panel should leave to the right');
      final whenArriving = offsetInPanel(tester, 'September 2026');

      await tester.pumpAndSettle();
      expect(offsetInPanel(tester, 'September 2026'),
          greaterThan(whenArriving + 8),
          reason: 'the incoming panel should arrive from the left');
    });

    // The other direction, or a single hard-coded offset would pass the test
    // above while sending both panels the same way whichever tab was tapped.
    testWidgets('reverses when the move is rightwards', (tester) async {
      await pumpPill(tester);
      await open(tester, 'Where');
      final whereAtRest = offsetInPanel(tester, 'Suggested destinations');

      // Where (0) to Who (2) is rightwards.
      await tester.tap(find.text('Who'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      expect(offsetInPanel(tester, 'Suggested destinations'),
          lessThan(whereAtRest - 8),
          reason: 'the outgoing panel should leave to the left');
      expect(offsetInPanel(tester, 'Adults'), greaterThan(0),
          reason: 'the incoming panel should still be right of its place');
      final adultsArriving = offsetInPanel(tester, 'Adults');

      await tester.pumpAndSettle();
      expect(offsetInPanel(tester, 'Adults'), lessThan(adultsArriving - 8));
    });

    // Opening and closing have no direction; borrowing the last switch's would
    // make a panel arrive sideways for no reason.
    testWidgets('opens straight, without a sideways drift', (tester) async {
      await pumpPill(tester);
      await open(tester, 'Where');
      await open(tester, 'Who');
      await tester.tap(find.byKey(const ValueKey('search-scrim')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('When'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final arriving = offsetInPanel(tester, 'September 2026');
      await tester.pumpAndSettle();

      expect(offsetInPanel(tester, 'September 2026'), closeTo(arriving, 0.5),
          reason: 'an open should not inherit the last switch\'s direction');
    });
  });

  group('hover and lift', () {
    /// The colour the segment behind [label] is painting right now, flattened
    /// against white.
    ///
    /// Flattening first is the whole point: `computeLuminance()` reads only
    /// r/g/b, so a half-transparent near-black reports as black-ish either way
    /// — but a *translucent* colour has to be composited before the number
    /// means what it looks like. Same trap as the chip-contrast test.
    double paintedLuminance(WidgetTester tester, String label) {
      final box = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final colour = (box.decoration as BoxDecoration).color!;
      return Color.alphaBlend(colour, Colors.white).computeLuminance();
    }

    Future<TestGesture> hover(WidgetTester tester, String label) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.text(label)));
      await tester.pump();
      return gesture;
    }

    // The bug this exists for: the resting colour was `Colors.transparent`,
    // which is transparent *black*. `Color.lerp` walks r/g/b and alpha
    // independently, so half way through the 180ms fade the segment painted a
    // half-opaque near-black — a dark pill that flashed and then lightened
    // into the real hover grey. Filmed in Chrome at 1440px with the cursor
    // parked: 244 → 179 → 225 in luminance, entirely between two light greys.
    //
    // The floor is the darker of the two ends. Passing through anything below
    // it is a flash, whatever colour it is.
    testWidgets('hovering never passes through a colour darker than both ends',
        (tester) async {
      await pumpPill(tester);
      final floor = Color.alphaBlend(AppColors.surfaceMuted, Colors.white)
          .computeLuminance();

      await hover(tester, 'Where');
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(
          paintedLuminance(tester, 'Where'),
          greaterThanOrEqualTo(floor - 0.01),
          reason: 'the hover fade darkened past the colour it ends on',
        );
      }
      await tester.pumpAndSettle();
      expect(paintedLuminance(tester, 'Where'), closeTo(floor, 0.01));
    });

    // The same lerp runs when a segment lifts into the open state, and it is
    // the more visible of the two: the card is going to *white*, so a dark
    // frame in the middle reads as the bar blinking as the panel opens.
    testWidgets('lifting a segment never flashes dark', (tester) async {
      await pumpPill(tester);
      final floor = Color.alphaBlend(AppColors.surfaceMuted, Colors.white)
          .computeLuminance();

      await tester.tap(find.text('When'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(
          paintedLuminance(tester, 'When'),
          greaterThanOrEqualTo(floor - 0.01),
          reason: 'the segment darkened on its way to white',
        );
      }
      await tester.pumpAndSettle();
    });
  });

  group('opening and closing', () {
    /// The opacity the panel is currently drawn at.
    double panelOpacity(WidgetTester tester) => tester
        .widget<FadeTransition>(
          find
              .ancestor(of: panel(), matching: find.byType(FadeTransition))
              .first,
        )
        .opacity
        .value;

    // Sliding *between* segments animated from the start; arriving and leaving
    // did not. The panel was mounted at full opacity in the frame of the tap
    // and unmounted in the frame of the dismissal, so the same interaction was
    // smooth in the middle and a cut at both ends.
    testWidgets('fades the panel in rather than mounting it whole',
        (tester) async {
      await pumpPill(tester);
      await tester.tap(find.text('Where'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(panel(), findsOneWidget);
      expect(panelOpacity(tester), lessThan(0.9),
          reason: 'the panel was already fully opaque one frame in');

      await tester.pumpAndSettle();
      expect(panelOpacity(tester), 1);
    });

    // Closing needs the outgoing segment remembered, or the overlay child sees
    // a null `_open` and renders nothing in the very frame the fade begins.
    testWidgets('fades the panel out rather than dropping it', (tester) async {
      await pumpPill(tester);
      await open(tester, 'Where');

      await tester.tap(find.byKey(const ValueKey('search-scrim')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(panel(), findsOneWidget,
          reason: 'the panel vanished in the frame of the dismissal');
      expect(panelOpacity(tester), lessThan(1));

      await tester.pumpAndSettle();
      expect(panel(), findsNothing);
    });

    // The fading card sits over the bar's left half. Leaving it hit-testable
    // would eat the click that is dismissing it.
    testWidgets('stops taking clicks the moment it starts closing',
        (tester) async {
      await pumpPill(tester);
      await open(tester, 'Where');
      await tester.tap(find.byKey(const ValueKey('search-scrim')));
      await tester.pump();

      final ignoring = tester.widgetList<IgnorePointer>(
        find.ancestor(of: panel(), matching: find.byType(IgnorePointer)),
      );
      expect(ignoring.any((w) => w.ignoring), isTrue);
      await tester.pumpAndSettle();
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
