import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/places_service.dart';
import 'package:musafir/widgets/map_place_search_bar.dart';

/// Searching for a place over a map: type, see predictions, tap one, and the
/// caller is handed coordinates to move the camera to.
void main() {
  PlaceSuggestion suggestion(String name, {String label = 'Dhaka'}) =>
      PlaceSuggestion(placeId: 'pid-$name', name: name, label: label);

  Future<void> pumpBar(
    WidgetTester tester, {
    required PlaceSuggestFn suggest,
    PlaceLocateFn? locate,
    required void Function(PlaceLocation) onPicked,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapPlaceSearchBar(
            onPlacePicked: onPicked,
            suggest: suggest,
            locate: locate ??
                (s) async => PlaceLocation(
                      name: s.name,
                      label: s.label,
                      latitude: 23.79,
                      longitude: 90.41,
                    ),
            // Tests drive the clock themselves; no need to wait 300ms.
            debounce: Duration.zero,
          ),
        ),
      ),
    );
  }

  testWidgets('typing three letters asks for predictions and lists them',
      (tester) async {
    final queries = <String>[];
    await pumpBar(
      tester,
      suggest: (q) async {
        queries.add(q);
        return [suggestion('Lubana General Hospital', label: 'Uttara, Dhaka')];
      },
      onPicked: (_) {},
    );

    await tester.enterText(find.byKey(MapPlaceSearchBar.fieldKey), 'lub');
    await tester.pump();
    await tester.pumpAndSettle();

    expect(queries, ['lub']);
    expect(find.text('Lubana General Hospital'), findsOneWidget);
    expect(find.text('Uttara, Dhaka'), findsOneWidget);
  });

  testWidgets('one or two letters search nothing', (tester) async {
    var calls = 0;
    await pumpBar(
      tester,
      suggest: (q) async {
        calls++;
        return const [];
      },
      onPicked: (_) {},
    );

    await tester.enterText(find.byKey(MapPlaceSearchBar.fieldKey), 'lu');
    await tester.pumpAndSettle();

    expect(calls, 0);
  });

  testWidgets('tapping a prediction hands back its coordinates',
      (tester) async {
    PlaceLocation? picked;
    await pumpBar(
      tester,
      suggest: (q) async => [suggestion('Banani Bridge')],
      locate: (s) async => PlaceLocation(
        name: s.name,
        label: 'Banani, Dhaka',
        latitude: 23.7925,
        longitude: 90.4078,
      ),
      onPicked: (p) => picked = p,
    );

    await tester.enterText(find.byKey(MapPlaceSearchBar.fieldKey), 'banani');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banani Bridge'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.latitude, 23.7925);
    expect(picked!.longitude, 90.4078);
    // The picked place stays in the field, and the list gets out of the way.
    expect(find.text('Banani, Dhaka'), findsNothing);
  });

  testWidgets('a search with no matches says so instead of sitting silent',
      (tester) async {
    // The old picker used the mobile-only `geocoding` package, which threw on
    // web into a swallowed catch: the field looked broken for every query.
    await pumpBar(
      tester,
      suggest: (q) async => const [],
      onPicked: (_) {},
    );

    await tester.enterText(find.byKey(MapPlaceSearchBar.fieldKey), 'qqqqqq');
    await tester.pumpAndSettle();

    expect(find.text('No places found'), findsOneWidget);
  });

  testWidgets('a place that will not resolve tells the host, and stays put',
      (tester) async {
    var picks = 0;
    await pumpBar(
      tester,
      suggest: (q) async => [suggestion('Somewhere')],
      locate: (_) async => null,
      onPicked: (_) => picks++,
    );

    await tester.enterText(find.byKey(MapPlaceSearchBar.fieldKey), 'somewhere');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Somewhere'));
    await tester.pumpAndSettle();

    expect(picks, 0);
    expect(find.textContaining('try again'), findsOneWidget);
    expect(find.text('Somewhere'), findsOneWidget);
  });

  testWidgets('a slow first response cannot overwrite a newer one',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapPlaceSearchBar(
            onPlacePicked: (_) {},
            debounce: Duration.zero,
            suggest: (q) async {
              if (q == 'ban') {
                await Future<void>.delayed(const Duration(seconds: 2));
                return [suggestion('Stale result')];
              }
              return [suggestion('Fresh result')];
            },
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(MapPlaceSearchBar.fieldKey), 'ban');
    await tester.pump();
    await tester.enterText(find.byKey(MapPlaceSearchBar.fieldKey), 'banani');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Fresh result'), findsOneWidget);
    expect(find.text('Stale result'), findsNothing);
  });

  testWidgets('clearing the field clears the predictions', (tester) async {
    await pumpBar(
      tester,
      suggest: (q) async => [suggestion('Banani Bridge')],
      onPicked: (_) {},
    );

    await tester.enterText(find.byKey(MapPlaceSearchBar.fieldKey), 'banani');
    await tester.pumpAndSettle();
    expect(find.text('Banani Bridge'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    expect(find.text('Banani Bridge'), findsNothing);
  });
}
