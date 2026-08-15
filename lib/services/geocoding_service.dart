import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geocoding/geocoding.dart' as geo;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/geo_bounds.dart';

/// A place name resolved to coordinates, ready to center a proximity search.
class GeocodeResult {
  const GeocodeResult({
    required this.latitude,
    required this.longitude,
    this.label,
    this.bounds,
  });

  final double latitude;
  final double longitude;

  /// Human-readable resolved name (e.g. "Dakshin Khan, Dhaka 1230"), when the
  /// resolver provides one.
  final String? label;

  /// The place's true extent, when the resolver provides one (the web/edge
  /// path does; the on-device platform geocoder does not). Present → the search
  /// covers exactly this box instead of a fixed radius ring.
  final GeoBounds? bounds;
}

/// Resolves a typed place name ("dakshinkhan") to coordinates.
///
/// Mobile uses the platform geocoder (free, on-device API). Web has no
/// platform geocoder, so it calls the `geocode` edge function — Google's
/// Geocoding API behind the server-side key, biased to Bangladesh. The edge
/// function is also the mobile fallback when the platform geocoder fails.
class GeocodingService {
  static final GeocodingService _instance = GeocodingService._internal();
  factory GeocodingService() => _instance;
  GeocodingService._internal();

  Future<GeocodeResult?> geocode(String query) async {
    final q = query.trim();
    if (q.isEmpty) return null;
    // Edge function FIRST on every platform: it returns the place's bounds
    // (its `viewport`/`bounds` box), which the search needs to frame and filter
    // to the place's real extent — "Dhaka" to Dhaka, not the sprawl north into
    // Tongi/Gazipur. The on-device geocoder returns a bare point (no box), so
    // it's only a fallback for when the edge call fails.
    final viaEdge = await _geocodeViaEdgeFunction(q);
    if (viaEdge != null) return viaEdge;
    if (kIsWeb) return null;
    try {
      // Same Bangladesh bias the edge function applies via the components
      // filter — the marketplace is BD-only.
      final locations = await geo.locationFromAddress('$q, Bangladesh');
      if (locations.isEmpty) return null;
      final loc = locations.first;
      return GeocodeResult(
        latitude: loc.latitude,
        longitude: loc.longitude,
        label: q,
      );
    } catch (_) {
      return null;
    }
  }

  /// The other direction: coordinates → a readable address, for the pin the
  /// host drops on the map. Same split as [geocode] — platform geocoder on
  /// mobile, `geocode` edge function on web and as the mobile fallback.
  Future<String?> reverse(double latitude, double longitude) async {
    if (kIsWeb) return _reverseViaEdgeFunction(latitude, longitude);
    try {
      final placemarks = await geo.placemarkFromCoordinates(
        latitude,
        longitude,
      );
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        // Country is left off: the marketplace is Bangladesh-only, so
        // ", Bangladesh" on every address is noise.
        final parts = <String>[
          if (place.street?.isNotEmpty == true) place.street!,
          if (place.subLocality?.isNotEmpty == true) place.subLocality!,
          if (place.locality?.isNotEmpty == true) place.locality!,
        ];
        if (parts.isNotEmpty) return parts.join(', ');
      }
    } catch (_) {
      // Fall through to the server-side geocoder.
    }
    return _reverseViaEdgeFunction(latitude, longitude);
  }

  Future<String?> _reverseViaEdgeFunction(double lat, double lng) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'geocode',
        body: {'lat': lat, 'lng': lng},
      );
      final data = res.data;
      if (data is! Map || data['found'] != true) return null;
      final label = data['label'] as String?;
      return (label != null && label.isNotEmpty) ? label : null;
    } catch (_) {
      return null;
    }
  }

  Future<GeocodeResult?> _geocodeViaEdgeFunction(String q) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'geocode',
        body: {'query': q},
      );
      final data = res.data;
      if (data is! Map || data['found'] != true) return null;
      return GeocodeResult(
        latitude: (data['lat'] as num).toDouble(),
        longitude: (data['lng'] as num).toDouble(),
        label: data['label'] as String?,
        bounds: GeoBounds.fromJson(data['bounds']),
      );
    } catch (_) {
      return null;
    }
  }
}
