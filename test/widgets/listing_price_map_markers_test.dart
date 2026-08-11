import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:musafir/models/listing.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/widgets/listing_price_map.dart';

/// Asserts the user-visible symptom directly: a price marker reaches the map
/// for every listing. The platform view never renders in a test, but the
/// marker set handed to [GoogleMap] is exactly what the map would draw.
void main() {
  // A widget test has no real platform view, so the map's view-creation call
  // would throw MissingPluginException and mask what we're actually asserting.
  final mapChannels = [
    for (var i = 0; i < 4; i++)
      MethodChannel('plugins.flutter.io/google_maps_$i'),
  ];

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async => 0,
    );
    // The plugin's own channel is equally absent; without this its
    // waitForMap call throws and drowns out the assertions below.
    for (final channel in mapChannels) {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
    }
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in mapChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  Listing listingOf(String id, double lat, double lng, double rate) {
    return Listing(
      id: id,
      ownerName: 'Host',
      title: 'A place',
      address: 'Road 1, Dhaka',
      type: ListingType.room,
      latitude: lat,
      longitude: lng,
      hourlyRate: rate,
      facilities: const [],
      available: true,
      city: 'Dhaka',
    );
  }

  /// Mounts [child] and lets the price pills finish rasterising.
  ///
  /// The pump itself has to happen inside `runAsync`: the pills are painted
  /// with real `toImage`/`toByteData` calls, and a future created in the
  /// fake-async zone of an ordinary `pumpWidget` never completes — no amount of
  /// pumping afterwards will drive it.
  Future<void> mountAndSettle(WidgetTester tester, Widget child) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(child);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
  }

  Future<Set<Marker>> pumpMap(
    WidgetTester tester,
    List<Listing> listings,
  ) async {
    await mountAndSettle(
      tester,
      MaterialApp(
        home: Scaffold(
          body: ListingPriceMap(
            listings: listings,
            onListingTap: (_) {},
          ),
        ),
      ),
    );
    return tester.widget<GoogleMap>(find.byType(GoogleMap)).markers;
  }

  testWidgets('a price marker is placed for every listing', (tester) async {
    final markers = await pumpMap(tester, [
      listingOf('a', 23.8103, 90.4125, 150),
      listingOf('b', 23.7806, 90.4193, 500),
    ]);

    expect(tester.takeException(), isNull);
    expect(markers.map((m) => m.markerId.value).toSet(), {'a', 'b'});
    for (final marker in markers) {
      expect(marker.icon, isNot(BitmapDescriptor.defaultMarker),
          reason: 'should be a painted price pill, not a stock pin');
    }
  });

  // Not covered here: markers refreshing when the result set changes while the
  // map is already mounted. Updating a live GoogleMap makes the plugin call
  // platform methods (updateGroundOverlays) that the method-channel
  // implementation leaves unimplemented off-device, and the error surfaces in
  // a real async zone where the test binding cannot capture it. There is no
  // seam for it short of a device test.
}
