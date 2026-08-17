import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Decodes Google's [encoded polyline algorithm][spec] into map points.
///
/// [spec]: https://developers.google.com/maps/documentation/utilities/polylinealgorithm
///
/// Kept free of bitwise `~`. Dart's integer bitwise operators do not agree
/// across platforms: on the VM `int` is 64-bit two's complement, so `~5` is
/// `-6`, while dart2js evaluates bitwise operations as UNSIGNED 32-bit, making
/// `~5` equal `4294967290`. The encoding stores negative deltas as
/// complemented values, so a `~`-based decoder silently produced garbage
/// coordinates on web only — a route whose distance and duration were correct
/// but whose line shot off the map — while Android and iOS were fine.
/// `-(x) - 1` is the same one's complement, computed arithmetically, and
/// therefore identical everywhere.
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  int index = 0;
  int lat = 0;
  int lng = 0;

  while (index < encoded.length) {
    lat += _decodeValue(encoded, index, (next) => index = next);
    lng += _decodeValue(encoded, index, (next) => index = next);
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }

  return points;
}

/// Reads one varint-style delta starting at [index], reporting where it ended
/// through [advance].
int _decodeValue(String encoded, int index, void Function(int) advance) {
  int shift = 0;
  int result = 0;
  int byte;

  do {
    byte = encoded.codeUnitAt(index++) - 63;
    result |= (byte & 0x1f) << shift;
    shift += 5;
  } while (byte >= 0x20);

  advance(index);
  // Odd values are negative and stored one's-complemented; see the note above
  // on why this is arithmetic rather than `~(result >> 1)`.
  return (result & 1) != 0 ? -(result >> 1) - 1 : result >> 1;
}
