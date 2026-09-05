import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/landmark.dart';
import 'package:musafir/models/search_filters.dart';
import 'package:musafir/services/places_service.dart';
import 'package:musafir/widgets/map_place_search_bar.dart'
    show PlaceLocateFn, PlaceSuggestFn;
import 'package:musafir/widgets/search/search_pill.dart';
import 'package:musafir/widgets/search/where_panel.dart';

final _today = DateTime(2026, 9, 5);

void main() {
  /// Everything the bar committed, in order. The length of this list is the
  /// assertion that matters most in this file.
  late List<SearchFilters> committed;

  Future<void> pumpPill(
    WidgetTester tester, {
    SearchFilters filters = const SearchFilters(),
    List<CitySuggestion> cities = const [],
    PlaceSuggestFn? suggest,
    PlaceLocateFn? locate,
    CurrentLocationFn? currentLocation,
    GeocodeFn? geocode,
    VoidCallback? onClear,
    Future<Landmark?> Function()? landmark,
  }) async {
    committed = [];
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var live = filters;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Align(
            alignment: Alignment.topCenter,
            child: SearchPill(
              filters: live,
              today: _today,
              cities: (query) => cities,
              suggest: suggest,
              locate: locate,
              currentLocation: currentLocation,
              geocode: geocode,
              onClear: onClear,
              onPickLandmark: (context, {required type, required title}) =>
                  landmark?.call() ?? Future.value(null),
              onCommit: (next) => setState(() {
                committed.add(next);
                live = next;
              }),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openSegment(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  group('the bar', () {
    testWidgets('shows placeholders for an untouched search', (tester) async {
      await pumpPill(tester);
      expect(find.text('Where'), findsOneWidget);
      expect(find.text('Search destinations'), findsOneWidget);
      expect(find.text('Add dates'), findsOneWidget);
      expect(find.text('Add guests'), findsOneWidget);
    });

    testWidgets('describes the search that is running', (tester) async {
      await pumpPill(
        tester,
        filters: SearchFilters(
          location: 'Uttara, Dhaka',
          checkIn: DateTime(2026, 9, 12),
          checkOut: DateTime(2026, 9, 15),
          guestCount: 3,
          adults: 2,
          children: 1,
        ),
      );
      expect(find.text('Uttara, Dhaka'), findsOneWidget);
      expect(find.text('12 – 15 Sep'), findsOneWidget);
      expect(find.text('3 guests'), findsOneWidget);
    });

    testWidgets('offers no clear button when nothing is running',
        (tester) async {
      await pumpPill(tester);
      expect(find.byTooltip('Clear search'), findsNothing);
    });

    testWidgets('clears when asked', (tester) async {
      var cleared = false;
      await pumpPill(tester, onClear: () => cleared = true);
      await tester.tap(find.byTooltip('Clear search'));
      expect(cleared, isTrue);
    });
  });

  group('panels', () {
    testWidgets('each segment opens its own panel', (tester) async {
      await pumpPill(tester);

      await openSegment(tester, 'Where');
      expect(find.text('Area, address or place — e.g. Dakshinkhan'),
          findsOneWidget);

      await openSegment(tester, 'When');
      expect(find.text('September 2026'), findsOneWidget);

      await openSegment(tester, 'Who');
      expect(find.text('Adults'), findsOneWidget);
      expect(find.text('Children'), findsOneWidget);
      expect(find.text('Infants'), findsOneWidget);
    });

    // Two panels at once would overlap, and the greyed bar could only mark one
    // of them as active.
    testWidgets('opening one closes the other', (tester) async {
      await pumpPill(tester);
      await openSegment(tester, 'Who');
      expect(find.text('Adults'), findsOneWidget);
      await openSegment(tester, 'When');
      expect(find.text('Adults'), findsNothing);
      expect(find.text('September 2026'), findsOneWidget);
    });

    testWidgets('tapping the open segment again closes it', (tester) async {
      await pumpPill(tester);
      await openSegment(tester, 'Who');
      expect(find.text('Adults'), findsOneWidget);
      await openSegment(tester, 'Who');
      expect(find.text('Adults'), findsNothing);
    });

    testWidgets('the scrim dismisses', (tester) async {
      await pumpPill(tester);
      await openSegment(tester, 'Who');
      expect(find.text('Adults'), findsOneWidget);
      // Well below the bar, where only the scrim can be.
      await tester.tapAt(const Offset(200, 700));
      await tester.pumpAndSettle();
      expect(find.text('Adults'), findsNothing);
    });

    testWidgets('escape dismisses', (tester) async {
      await pumpPill(tester);
      await openSegment(tester, 'Who');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Adults'), findsNothing);
    });

    testWidgets('the Filters button opens its own panel', (tester) async {
      await pumpPill(tester);
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      expect(find.text('Type of place'), findsOneWidget);
      expect(find.text('What the stay is for'), findsOneWidget);
    });
  });

  // The entire reason the draft exists. Every SearchStateNotifier mutator runs
  // a search immediately, so three panels committing on close would be three
  // round trips for one search.
  group('commits exactly once', () {
    testWidgets('editing three panels still commits once', (tester) async {
      await pumpPill(
        tester,
        cities: const [CitySuggestion(city: 'Dhaka', count: 4)],
      );

      await openSegment(tester, 'Where');
      await tester.tap(find.text('Dhaka'));
      await tester.pumpAndSettle();

      await openSegment(tester, 'When');
      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();

      await openSegment(tester, 'Who');
      await tester.tap(find.byTooltip('One more Adults'));
      await tester.pumpAndSettle();

      // Nothing has run yet — the panels only wrote to the draft.
      expect(committed, isEmpty);

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      expect(committed, hasLength(1));
      expect(committed.single.location, 'Dhaka');
      expect(committed.single.checkIn, DateTime(2026, 9, 12));
      expect(committed.single.checkOut, DateTime(2026, 9, 15));
      expect(committed.single.adults, 2);
      expect(committed.single.guestCount, 2);
    });

    testWidgets('closing a panel commits nothing', (tester) async {
      await pumpPill(tester);
      await openSegment(tester, 'Who');
      await tester.tap(find.byTooltip('One more Children'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(committed, isEmpty);
    });
  });

  group('the draft', () {
    // The bar rebuilds on every unrelated repaint. A draft that re-seeded each
    // time would erase what the guest was in the middle of choosing.
    testWidgets('survives a rebuild with unchanged filters', (tester) async {
      await pumpPill(tester);
      await openSegment(tester, 'Who');
      await tester.tap(find.byTooltip('One more Adults'));
      await tester.pumpAndSettle();
      // Force a parent rebuild without changing the filters.
      await tester.pump();
      expect(find.text('2'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('2 guests'), findsOneWidget);
    });

    testWidgets('the segments follow the draft before it is committed',
        (tester) async {
      await pumpPill(tester);
      expect(find.text('Add guests'), findsOneWidget);
      await openSegment(tester, 'Who');
      await tester.tap(find.byTooltip('One more Adults'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('2 guests'), findsOneWidget);
      expect(committed, isEmpty);
    });
  });

  group('resolving a typed place', () {
    testWidgets('geocodes text that no prediction was tapped for',
        (tester) async {
      var asked = '';
      await pumpPill(
        tester,
        geocode: (query) async {
          asked = query;
          return const ResolvedPlace(latitude: 23.87, longitude: 90.39);
        },
      );

      await openSegment(tester, 'Where');
      await tester.enterText(find.byType(TextField), 'Dakshinkhan');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      expect(asked, 'Dakshinkhan');
      expect(committed.single.latitude, 23.87);
      expect(committed.single.location, 'Dakshinkhan');
    });

    // A failed resolve is not an error — the text search still runs.
    testWidgets('a geocode that finds nothing still searches', (tester) async {
      await pumpPill(tester, geocode: (_) async => null);
      await openSegment(tester, 'Where');
      await tester.enterText(find.byType(TextField), 'Nowhere at all');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      expect(committed, hasLength(1));
      expect(committed.single.location, 'Nowhere at all');
      expect(committed.single.latitude, isNull);
    });

    testWidgets('a picked prediction is not geocoded again', (tester) async {
      var geocodes = 0;
      await pumpPill(
        tester,
        cities: const [CitySuggestion(city: 'Dhaka', count: 4)],
        suggest: (_) async => const [
          PlaceSuggestion(
            placeId: 'p1',
            name: 'Dakshinkhan',
            label: 'Dhaka, Bangladesh',
          ),
        ],
        locate: (_) async => const PlaceLocation(
          name: 'Dakshinkhan',
          latitude: 23.87,
          longitude: 90.39,
        ),
        geocode: (_) async {
          geocodes++;
          return null;
        },
      );

      await openSegment(tester, 'Where');
      await tester.enterText(find.byType(TextField), 'Dakshin');
      // Past the 300ms debounce.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dakshinkhan'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      expect(geocodes, 0);
      expect(committed.single.latitude, 23.87);
    });
  });
}
