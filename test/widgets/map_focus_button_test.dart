import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:musafir/models/listing.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/widgets/listing_price_map.dart';
import 'package:musafir/widgets/map_focus_button.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// The focus control exists because a guest who pans and pinches a map can lose
/// the only pin that mattered — the host's address, or their own position on the
/// directions map — with no way back. These tests cover the two things that
/// silently break it: a target too small to hit with a thumb, and a control that
/// on web sits over a DOM map and therefore never receives the tap at all.
void main() {
  Widget host(Widget child, {double width = 390}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Scaffold(body: Center(child: child)),
      ),
    );
  }

  group('MapFocusButton', () {
    testWidgets('is at least a 44dp target on a phone, larger on a tablet',
        (tester) async {
      await tester.pumpWidget(host(
        MapFocusButton(icon: Icons.my_location, label: 'Go', onPressed: () {}),
      ));
      expect(tester.getSize(find.byType(MapFocusButton)), const Size(44, 44));

      await tester.pumpWidget(host(
        MapFocusButton(icon: Icons.my_location, label: 'Go', onPressed: () {}),
        width: 900,
      ));
      expect(tester.getSize(find.byType(MapFocusButton)), const Size(48, 48));
    });

    testWidgets('an icon-only control still has a name to read out',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(
        MapFocusButton(
          icon: Icons.my_location,
          label: 'Center on my location',
          onPressed: () {},
        ),
      ));

      expect(find.bySemanticsLabel('Center on my location'), findsOne);
      handle.dispose();
    });

    testWidgets('a busy control shows progress and refuses further taps',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(
        MapFocusButton(
          icon: Icons.my_location,
          label: 'Go',
          busy: true,
          onPressed: () => taps++,
        ),
      ));

      expect(find.byType(CircularProgressIndicator), findsOne);
      await tester.tap(find.byType(MapFocusButton));
      expect(taps, 0, reason: 'a second GPS request while one is in flight');
    });

    testWidgets('stacked controls keep 8dp of clear space between them',
        (tester) async {
      await tester.pumpWidget(host(
        MapFocusControls(
          children: [
            MapFocusButton(icon: Icons.place, label: 'A', onPressed: () {}),
            MapFocusButton(
                icon: Icons.my_location, label: 'B', onPressed: () {}),
          ],
        ),
      ));

      final buttons = find.byType(MapFocusButton);
      final gap = tester.getTopLeft(buttons.at(1)).dy -
          tester.getBottomLeft(buttons.at(0)).dy;
      expect(gap, 8);
    });

    testWidgets('controls are pointer-intercepted so web taps land on them',
        (tester) async {
      // On web the map is a DOM element that wins the browser's hit-test over
      // anything Flutter paints above it. Without an interceptor the tap goes to
      // the map and the button is simply dead.
      await tester.pumpWidget(host(
        MapFocusControls(
          children: [
            MapFocusButton(icon: Icons.place, label: 'A', onPressed: () {}),
          ],
        ),
      ));

      expect(
        find.ancestor(
          of: find.byType(MapFocusButton),
          matching: find.byType(PointerInterceptor),
        ),
        findsAtLeast(1),
      );
    });
  });

  group('framePoints', () {
    test('nothing to frame yields no camera move', () {
      expect(framePoints(const []), isNull);
    });

    // The concrete CameraUpdate subclasses aren't re-exported by
    // google_maps_flutter, so these assert on the payload the plugin would send
    // to the platform — which is the thing that actually decides what happens.
    test('a lone pin gets a fixed street zoom, not an absurd bounds fit', () {
      // A bounds fit on a zero-area box zooms past the last tile the SDK has,
      // landing the guest on blank grey. The fixed zoom is the whole point.
      expect(
        framePoints([const LatLng(23.8103, 90.4125)])?.toJson(),
        [
          'newLatLngZoom',
          [23.8103, 90.4125],
          15.0
        ],
      );
    });

    test('several pins at one address are treated as one', () {
      // Two units in the same building: metres apart, no meaningful spread.
      final update = framePoints(const [
        LatLng(23.8103, 90.4125),
        LatLng(23.81035, 90.41255),
      ]);
      expect((update!.toJson() as List<Object>).first, 'newLatLngZoom');
    });

    test('pins spread across a city are framed by bounds', () {
      final update = framePoints(
        const [LatLng(23.8103, 90.4125), LatLng(23.7106, 90.4074)],
        padding: 24,
      );
      expect(update?.toJson(), [
        'newLatLngBounds',
        [
          [23.7106, 90.4074], // southwest
          [23.8103, 90.4125], // northeast
        ],
        24.0,
      ]);
    });
  });

  group('ListingPriceMap focus control', () {
    // A widget test has no real platform view, so the map's view-creation call
    // would throw MissingPluginException and mask what we're asserting.
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

    Listing listingOf(String id, double lat, double lng) => Listing(
          id: id,
          ownerName: 'Host',
          title: 'A place',
          address: 'Road 1, Dhaka',
          type: ListingType.room,
          latitude: lat,
          longitude: lng,
          hourlyRate: 150,
          facilities: const [],
          available: true,
          city: 'Dhaka',
        );

    /// The pills are painted with real `toImage`/`toByteData` calls, so the
    /// pump has to happen inside `runAsync` or those futures never complete.
    Future<void> pumpMap(
      WidgetTester tester, {
      required bool interactive,
      double bottomInset = 0,
    }) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ListingPriceMap(
              listings: [
                listingOf('a', 23.8103, 90.4125),
                listingOf('b', 23.7806, 90.4193),
              ],
              onListingTap: (_) {},
              height: interactive ? null : 240,
              interactive: interactive,
              bottomInset: bottomInset,
            ),
          ),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
    }

    testWidgets('both the inline and the full-screen map can be re-framed',
        (tester) async {
      // Zoom gestures are live on the inline map too, so the pins can be lost
      // there as easily as on the full-screen one.
      for (final interactive in [false, true]) {
        await pumpMap(tester, interactive: interactive);
        expect(
          find.bySemanticsLabel('Show all 2 stays'),
          findsOne,
          reason: 'interactive: $interactive',
        );
      }
    });

    testWidgets('the control sits above whatever overlaps the map',
        (tester) async {
      // The results sheet covers the bottom of the search map; a control pinned
      // to bottom: 10 would sit underneath it, out of reach.
      const inset = 200.0;
      await pumpMap(tester, interactive: true, bottomInset: inset);

      final controls = tester.getRect(find.byType(MapFocusControls));
      final map = tester.getRect(find.byType(ListingPriceMap));
      expect(controls.bottom, lessThanOrEqualTo(map.bottom - inset));
    });

    testWidgets('a sheet dragged over the whole map takes the control with it',
        (tester) async {
      // The results sheet goes to full height. Riding above it would put the
      // control off the top of the map and over the sheet's own content — and
      // there'd be no map left to re-frame anyway.
      await pumpMap(tester, interactive: true, bottomInset: 580);

      expect(find.byType(MapFocusButton), findsNothing);
      expect(tester.takeException(), isNull, reason: 'nothing overflowed');
    });
  });
}
