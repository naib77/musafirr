/// Human-friendly distance label: metres under ~1 km, else one-decimal km.
String formatDistanceMeters(double meters) {
  if (meters < 950) return '${meters.round()} m away';
  return '${(meters / 1000).toStringAsFixed(1)} km away';
}

/// Distance label relative to a named landmark, e.g. "1.2 km from Dhaka Medical".
String formatDistanceFrom(double meters, String landmarkName) {
  final d = meters < 950
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';
  return '$d from $landmarkName';
}
