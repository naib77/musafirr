/// Category ratings for guest reviews of listings/hosts.
///
/// Based on Airbnb's standard rating categories.
class GuestReviewRatings {
  const GuestReviewRatings({
    required this.overall,
    required this.cleanliness,
    required this.accuracy,
    required this.communication,
    required this.location,
    required this.value,
  });

  /// Overall experience rating (1-5)
  final double overall;

  /// Cleanliness of the property (1-5)
  final double cleanliness;

  /// How accurately the listing matched its description (1-5)
  final double accuracy;

  /// Host's communication and responsiveness (1-5)
  final double communication;

  /// Location quality and convenience (1-5)
  final double location;

  /// Value for money (1-5)
  final double value;

  /// Calculate the average of all categories
  double get average =>
      (overall + cleanliness + accuracy + communication + location + value) / 6;

  /// Validate that all ratings are within range
  bool get isValid =>
      _inRange(overall) &&
      _inRange(cleanliness) &&
      _inRange(accuracy) &&
      _inRange(communication) &&
      _inRange(location) &&
      _inRange(value);

  bool _inRange(double rating) => rating >= 1.0 && rating <= 5.0;

  Map<String, double> toMap() => {
        'overall': overall,
        'cleanliness': cleanliness,
        'accuracy': accuracy,
        'communication': communication,
        'location': location,
        'value': value,
      };

  factory GuestReviewRatings.fromMap(Map<String, dynamic> map) {
    return GuestReviewRatings(
      overall: (map['overall'] as num).toDouble(),
      cleanliness: (map['cleanliness'] as num).toDouble(),
      accuracy: (map['accuracy'] as num).toDouble(),
      communication: (map['communication'] as num).toDouble(),
      location: (map['location'] as num).toDouble(),
      value: (map['value'] as num).toDouble(),
    );
  }

  GuestReviewRatings copyWith({
    double? overall,
    double? cleanliness,
    double? accuracy,
    double? communication,
    double? location,
    double? value,
  }) {
    return GuestReviewRatings(
      overall: overall ?? this.overall,
      cleanliness: cleanliness ?? this.cleanliness,
      accuracy: accuracy ?? this.accuracy,
      communication: communication ?? this.communication,
      location: location ?? this.location,
      value: value ?? this.value,
    );
  }
}
