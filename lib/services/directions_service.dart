import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'polyline_codec.dart';

/// Fetches driving/walking routes for the in-app map.
///
/// The request is proxied through the `google-directions` Supabase Edge
/// Function so the Google Maps key stays a server-side secret and never ships in
/// the app (web or native). The function returns Google's raw Directions JSON,
/// which we parse here into a [DirectionsResult]. Works identically on all
/// platforms — the browser calls the function too (it sets CORS headers),
/// avoiding the CORS block that hitting Google's REST API directly would cause.
class DirectionsService {
  /// Get directions between two points, or null if no route / not configured.
  static Future<DirectionsResult?> getDirections({
    required LatLng origin,
    required LatLng destination,
    String mode = 'driving', // driving, walking, bicycling, transit
  }) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'google-directions',
        body: {
          'origin': '${origin.latitude},${origin.longitude}',
          'destination': '${destination.latitude},${destination.longitude}',
          'mode': mode,
        },
      );

      final data = res.data;
      if (data is! Map) {
        debugPrint('Directions: unexpected response: $data');
        return null;
      }
      if (data['status'] != 'OK') {
        debugPrint(
            'Directions error: ${data['status'] ?? data['error'] ?? 'unknown'}');
        return null;
      }

      final routes = data['routes'] as List;
      if (routes.isEmpty) return null;
      final route = (routes[0] as Map).cast<String, dynamic>();
      final legs = route['legs'] as List;
      final leg = (legs[0] as Map).cast<String, dynamic>();

      // Overview polyline for the route line.
      final polyline = (route['overview_polyline'] as Map)['points'] as String;
      final points = decodePolyline(polyline);

      final distance = (leg['distance'] as Map)['text'] as String;
      final duration = (leg['duration'] as Map)['text'] as String;

      final bounds = (route['bounds'] as Map).cast<String, dynamic>();
      final northeast = (bounds['northeast'] as Map).cast<String, dynamic>();
      final southwest = (bounds['southwest'] as Map).cast<String, dynamic>();

      return DirectionsResult(
        points: points,
        distance: distance,
        duration: duration,
        bounds: LatLngBounds(
          northeast: LatLng(
            (northeast['lat'] as num).toDouble(),
            (northeast['lng'] as num).toDouble(),
          ),
          southwest: LatLng(
            (southwest['lat'] as num).toDouble(),
            (southwest['lng'] as num).toDouble(),
          ),
        ),
      );
    } catch (e) {
      // Non-2xx from the function (misconfig, no route) throws — degrade to null
      // so callers fall back to showing both pins + "Open in Google Maps".
      debugPrint('Error fetching directions: $e');
      return null;
    }
  }
}

class DirectionsResult {
  final List<LatLng> points;
  final String distance;
  final String duration;
  final LatLngBounds bounds;

  DirectionsResult({
    required this.points,
    required this.distance,
    required this.duration,
    required this.bounds,
  });
}
