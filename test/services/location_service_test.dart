import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:musafir/services/location_service.dart';

/// A platform that grants permission and then never answers — what a browser
/// does when the OS location provider cannot resolve a position (desktop with
/// location services off, no GPS, weak network positioning), and what
/// `geolocator_web` leaves us with because it does not enforce
/// [LocationSettings.timeLimit]: it forwards the limit to the browser's
/// `PositionOptions.timeout` in MICROseconds, so a 10s limit is sent as
/// ~2h46m and no timeout ever fires.
class _StalledGeolocator extends GeolocatorPlatform {
  final positionRequests = <LocationSettings?>[];

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    positionRequests.add(locationSettings);
    return Completer<Position>().future; // never completes
  }
}

/// A platform stuck on the permission prompt: the user has neither allowed nor
/// blocked, so the request never resolves. On web `requestPermission()` is
/// itself a `getCurrentPosition()` call, so this hangs in the same way.
class _UnansweredPromptGeolocator extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied; // web reports 'prompt' as denied

  @override
  Future<LocationPermission> requestPermission() =>
      Completer<LocationPermission>().future; // user never answers
}

void main() {
  final original = GeolocatorPlatform.instance;

  tearDown(() => GeolocatorPlatform.instance = original);

  test('gives up when the location provider never answers', () {
    final platform = _StalledGeolocator();
    GeolocatorPlatform.instance = platform;

    fakeAsync((async) {
      Object? result = #pending;
      LocationService().getCurrentLocation().then((p) => result = p);

      async.elapse(const Duration(seconds: 9));
      expect(result, #pending, reason: 'should still be waiting at 9s');

      async.elapse(const Duration(seconds: 2));
      expect(result, isNull,
          reason: 'a stalled provider must resolve to null, not hang forever');

      expect(platform.positionRequests.single?.timeLimit,
          const Duration(seconds: 10));
    });
  });

  test('gives up when the permission prompt is never answered', () {
    GeolocatorPlatform.instance = _UnansweredPromptGeolocator();

    fakeAsync((async) {
      Object? result = #pending;
      LocationService().getCurrentLocation().then((p) => result = p);

      // The user gets a generous window to read and answer the browser dialog…
      async.elapse(const Duration(seconds: 59));
      expect(result, #pending, reason: 'must not cut the user off mid-dialog');

      // …but an unanswered prompt still has to end somewhere.
      async.elapse(const Duration(seconds: 2));
      expect(result, isNull);
    });
  });
}
