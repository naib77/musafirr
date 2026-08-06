/// A point of interest (hospital, exam center, university, tourist spot,
/// business hub) that anchors purpose-based search. Backed by the `landmarks`
/// table; read via the `search_landmarks` / `nearby_landmarks` RPCs.
class Landmark {
  const Landmark({
    required this.id,
    required this.name,
    required this.type,
    this.city,
    this.area,
    required this.latitude,
    required this.longitude,
    this.distanceMeters,
  });

  final String id;
  final String name;

  /// 'hospital' | 'exam_center' | 'university' | 'tourist_spot' | 'business_hub'
  final String type;
  final String? city;
  final String? area;
  final double latitude;
  final double longitude;

  /// Distance from a reference point, when returned by `nearby_landmarks`.
  final double? distanceMeters;

  /// "Dhaka · Shahbagh" style subtitle.
  String get locationLabel => [if (area != null) area, if (city != null) city]
      .whereType<String>()
      .join(' · ');

  factory Landmark.fromJson(Map<String, dynamic> json) {
    return Landmark(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      city: json['city'] as String?,
      area: json['area'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      distanceMeters: (json['distance_m'] as num?)?.toDouble(),
    );
  }
}
