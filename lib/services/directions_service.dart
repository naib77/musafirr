import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../config/api_keys.dart';

class DirectionsService {
  static String get _apiKey => googleMapsApiKey;

  /// Get directions between two points
  /// Returns a list of LatLng points for the route polyline
  static Future<DirectionsResult?> getDirections({
    required LatLng origin,
    required LatLng destination,
    String mode = 'driving', // driving, walking, bicycling, transit
  }) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${origin.latitude},${origin.longitude}'
      '&destination=${destination.latitude},${destination.longitude}'
      '&mode=$mode'
      '&key=$_apiKey',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        if (data['status'] == 'OK') {
          final routes = data['routes'] as List;
          if (routes.isNotEmpty) {
            final route = routes[0] as Map<String, dynamic>;
            final legs = route['legs'] as List;
            final leg = legs[0] as Map<String, dynamic>;

            // Get overview polyline
            final polyline = route['overview_polyline']['points'] as String;
            final points = _decodePolyline(polyline);

            // Get distance and duration
            final distance = leg['distance']['text'] as String;
            final duration = leg['duration']['text'] as String;

            // Get bounds
            final bounds = route['bounds'] as Map<String, dynamic>;
            final northeast = bounds['northeast'] as Map<String, dynamic>;
            final southwest = bounds['southwest'] as Map<String, dynamic>;

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
          }
        } else {
          debugPrint('Directions API error: ${data['status']}');
        }
      }
    } catch (e) {
      debugPrint('Error fetching directions: $e');
    }

    return null;
  }

  /// Decode Google's encoded polyline string into a list of LatLng points
  static List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      // Decode latitude
      int shift = 0;
      int result = 0;
      int byte;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      // Decode longitude
      shift = 0;
      result = 0;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
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
