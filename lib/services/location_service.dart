import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  /// How long to wait for a position before giving up.
  ///
  /// Enforced here rather than left to [LocationSettings.timeLimit], because on
  /// web that limit is never applied: `geolocator_web` forwards it to the
  /// browser's `PositionOptions.timeout` in MICROseconds, so ten seconds is
  /// sent as ~2h46m (and an absent limit as ~24 days). A browser whose location
  /// provider never answers — desktop with location services off, no GPS, weak
  /// network positioning — therefore left callers awaiting a future that could
  /// not complete, which is what hung the directions screen on "Getting
  /// directions…" forever.
  static const Duration _positionTimeout = Duration(seconds: 10);

  /// How long to wait for the user to answer the permission dialog. Generous —
  /// this one is human time, not machine time — but still bounded, since on web
  /// [Geolocator.requestPermission] IS a position request and hangs just the
  /// same when the prompt is ignored.
  static const Duration _permissionTimeout = Duration(seconds: 60);

  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<Position?> getCurrentLocation() async {
    final hasPermission = await requestPermission()
        .timeout(_permissionTimeout, onTimeout: () => false);
    if (!hasPermission) {
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _positionTimeout,
        ),
      ).timeout(_positionTimeout);
    } catch (e) {
      return null;
    }
  }

  Future<String?> getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final parts = <String>[
          if (place.street?.isNotEmpty == true) place.street!,
          if (place.subLocality?.isNotEmpty == true) place.subLocality!,
          if (place.locality?.isNotEmpty == true) place.locality!,
          if (place.country?.isNotEmpty == true) place.country!,
        ];
        return parts.join(', ');
      }
    } catch (e) {
      // Geocoding failed
    }
    return null;
  }

  Future<List<Location>> searchAddress(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }
    try {
      return await locationFromAddress(query);
    } catch (e) {
      return [];
    }
  }
}
