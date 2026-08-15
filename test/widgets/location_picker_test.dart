import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/places_service.dart';
import 'package:musafir/widgets/location_picker.dart';
import 'package:musafir/widgets/map_place_search_bar.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// The host's "Pick on Map" screen. The real GoogleMap is a platform view, so
/// the map is injected — every assertion here is about the picker's own
/// behaviour: search moves the pin, and Confirm returns where the pin is.
void main() {
  Widget stubMap(LocationPickerMapSpec spec) =>
      const ColoredBox(color: Color(0xFFCCE0CC));

  Future<LocationPickerResult?> pumpPicker(
    WidgetTester tester, {
    PlaceSuggestFn? suggest,
    PlaceLocateFn? locate,
    Future<String?> Function(double, double)? addressOf,
  }) async {
    LocationPickerResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context)
                      .push<LocationPickerResult>(MaterialPageRoute(
                    builder: (_) => LocationPicker(
                      initialLatitude: 23.8103,
                      initialLongitude: 90.4125,
                      mapBuilder: stubMap,
                      suggest: suggest ?? (_) async => const [],
                      locate: locate,
                      addressOf: addressOf ?? (lat, lng) async => 'Road 27',
                    ),
                  ));
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  String coordinates(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(LocationPicker.coordinatesKey)).data!;

  testWidgets('opens on the coordinates it was given', (tester) async {
    await pumpPicker(tester);

    expect(coordinates(tester), '23.810300, 90.412500');
    expect(find.text('Road 27'), findsOneWidget);
  });

  testWidgets('searching a place moves the picked location to it',
      (tester) async {
    await pumpPicker(
      tester,
      suggest: (q) async => const [
        PlaceSuggestion(
          placeId: 'pid-1',
          name: 'Banani Bridge',
          label: 'Banani, Dhaka',
        ),
      ],
      locate: (s) async => const PlaceLocation(
        name: 'Banani Bridge',
        label: 'Banani, Dhaka',
        latitude: 23.7925,
        longitude: 90.4078,
      ),
    );

    await tester.enterText(
        find.byKey(MapPlaceSearchBar.fieldKey), 'banani bridge');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banani Bridge').last);
    await tester.pumpAndSettle();

    // The pin — and so what Confirm will return — is now on the searched place,
    // named from Google rather than reverse-geocoded again.
    expect(coordinates(tester), '23.792500, 90.407800');
    expect(find.text('Banani Bridge, Banani, Dhaka'), findsOneWidget);
  });

  testWidgets('Confirm returns the location the pin is on', (tester) async {
    LocationPickerResult? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                captured = await Navigator.of(context)
                    .push<LocationPickerResult>(MaterialPageRoute(
                  builder: (_) => LocationPicker(
                    initialLatitude: 23.8103,
                    initialLongitude: 90.4125,
                    mapBuilder: stubMap,
                    suggest: (q) async => const [
                      PlaceSuggestion(
                        placeId: 'pid-1',
                        name: 'Banani Bridge',
                        label: 'Banani, Dhaka',
                      ),
                    ],
                    locate: (s) async => const PlaceLocation(
                      name: 'Banani Bridge',
                      label: 'Banani, Dhaka',
                      latitude: 23.7925,
                      longitude: 90.4078,
                    ),
                    addressOf: (lat, lng) async => 'Road 27',
                  ),
                ));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(MapPlaceSearchBar.fieldKey), 'banani');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banani Bridge').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(LocationPicker.confirmKey));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.latitude, 23.7925);
    expect(captured!.longitude, 90.4078);
    expect(captured!.address, 'Banani Bridge, Banani, Dhaka');
  });

  testWidgets('every control over the map is pointer-intercepted',
      (tester) async {
    // On web the map is a DOM element that wins the browser hit-test, so an
    // un-intercepted control cannot be tapped at all — which is exactly how
    // the host lost the ability to confirm a location.
    await pumpPicker(tester);

    for (final control in <Finder>[
      find.byKey(LocationPicker.confirmKey),
      find.byKey(MapPlaceSearchBar.fieldKey),
      find.byIcon(Icons.my_location),
      find.byType(AppBar),
    ]) {
      expect(
        find.ancestor(of: control, matching: find.byType(PointerInterceptor)),
        findsAtLeast(1),
        reason: 'control needs a PointerInterceptor to be tappable on web',
      );
    }
  });

  testWidgets('the centre pin never swallows a map gesture', (tester) async {
    await pumpPicker(tester);

    expect(
      find.ancestor(
        of: find.byIcon(Icons.location_pin).first,
        matching: find.byType(IgnorePointer),
      ),
      findsAtLeast(1),
    );
  });
}
