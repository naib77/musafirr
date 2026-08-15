/// A geographic bounding box — the real extent of a searched place.
///
/// Google's Geocoding and Place Details responses tag every result with a
/// `viewport` (and, for areas, a tighter `bounds`): the south-west and
/// north-east corners of the box that actually contains the place. "Uttara"
/// comes back as a small neighbourhood box; "Dhaka" as a whole-city box. That
/// is exactly what a proximity search should cover, and it's what a fixed
/// radius ring cannot express — so we carry the box through the search pipeline
/// and both filter listings to it and frame the map to it.
///
/// Kept free of Flutter/Maps imports so it can live in the model layer and the
/// search filters; the map widget converts it to a `LatLngBounds` at the edge.
class GeoBounds {
  const GeoBounds({
    required this.swLat,
    required this.swLng,
    required this.neLat,
    required this.neLng,
  });

  final double swLat;
  final double swLng;
  final double neLat;
  final double neLng;

  double get centerLat => (swLat + neLat) / 2;
  double get centerLng => (swLng + neLng) / 2;

  /// Guards against a degenerate or inverted box (a nonsense API payload):
  /// north-east must actually sit north-east of south-west.
  bool get isValid => neLat > swLat && neLng > swLng;

  /// Parses the `{ ne_lat, ne_lng, sw_lat, sw_lng }` shape the edge functions
  /// send. Returns null unless all four corners are finite numbers and the box
  /// is valid.
  static GeoBounds? fromJson(Object? json) {
    if (json is! Map) return null;
    final neLat = (json['ne_lat'] as num?)?.toDouble();
    final neLng = (json['ne_lng'] as num?)?.toDouble();
    final swLat = (json['sw_lat'] as num?)?.toDouble();
    final swLng = (json['sw_lng'] as num?)?.toDouble();
    if (neLat == null || neLng == null || swLat == null || swLng == null) {
      return null;
    }
    final bounds =
        GeoBounds(swLat: swLat, swLng: swLng, neLat: neLat, neLng: neLng);
    return bounds.isValid ? bounds : null;
  }
}
