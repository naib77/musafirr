import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geocoding/geocoding.dart' as geo;
import 'package:supabase_flutter/supabase_flutter.dart';

/// A place name resolved to coordinates, ready to center a proximity search.
class GeocodeResult {
  const GeocodeResult({
    required this.latitude,
    required this.longitude,
    this.label,
  });

  final double latitude;
  final double longitude;

  /// Human-readable resolved name (e.g. "Dakshin Khan, Dhaka 1230"), when the
  /// resolver provides one.
  final String? label;
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
    if (kIsWeb) return _geocodeViaEdgeFunction(q);
    try {
      // Same Bangladesh bias the edge function applies via the components
      // filter — the marketplace is BD-only.
      final locations = await geo.locationFromAddress('$q, Bangladesh');
      if (locations.isEmpty) return _geocodeViaEdgeFunction(q);
      final loc = locations.first;
      return GeocodeResult(
        latitude: loc.latitude,
        longitude: loc.longitude,
        label: q,
      );
    } catch (_) {
      return _geocodeViaEdgeFunction(q);
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
      );
    } catch (_) {
      return null;
    }
  }
}
