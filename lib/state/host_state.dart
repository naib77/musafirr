import 'package:flutter/foundation.dart';
import '../core/state/safe_notifier.dart';

class HostStateNotifier extends ChangeNotifier with SafeNotifier {
  bool _isHostMode = false;
  bool _isLoading = false;
  String? _error;

  bool get isHostMode => _isHostMode;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void enterHostMode() {
    _isHostMode = true;
    notifyListeners();
  }

  void exitHostMode() {
    _isHostMode = false;
    notifyListeners();
  }

  void toggleHostMode() {
    _isHostMode = !_isHostMode;
    notifyListeners();
  }

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setError(String? error) {
    _error = error;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

/// Data class for creating a new listing
class CreateListingData {
  CreateListingData({
    this.title = '',
    this.description = '',
    this.propertyType,
    this.address = '',
    this.city = '',
    this.latitude,
    this.longitude,
    this.pricePerNight = 0,
    this.maxGuests = 1,
    this.bedrooms = 1,
    this.beds = 1,
    this.bathrooms = 1,
    this.amenities = const [],
    this.imageUrls = const [],
  });

  String title;
  String description;
  String? propertyType;
  String address;
  String city;
  double? latitude;
  double? longitude;
  double pricePerNight;
  int maxGuests;
  int bedrooms;
  int beds;
  int bathrooms;
  List<String> amenities;
  List<String> imageUrls;

  bool get isBasicsComplete => title.isNotEmpty && propertyType != null;

  bool get isLocationComplete =>
      address.isNotEmpty &&
      city.isNotEmpty &&
      latitude != null &&
      longitude != null;

  bool get isDetailsComplete =>
      maxGuests > 0 && bedrooms > 0 && beds > 0 && bathrooms > 0;

  bool get isPricingComplete => pricePerNight > 0;

  bool get isComplete =>
      isBasicsComplete &&
      isLocationComplete &&
      isDetailsComplete &&
      isPricingComplete;

  CreateListingData copyWith({
    String? title,
    String? description,
    String? propertyType,
    String? address,
    String? city,
    double? latitude,
    double? longitude,
    double? pricePerNight,
    int? maxGuests,
    int? bedrooms,
    int? beds,
    int? bathrooms,
    List<String>? amenities,
    List<String>? imageUrls,
  }) {
    return CreateListingData(
      title: title ?? this.title,
      description: description ?? this.description,
      propertyType: propertyType ?? this.propertyType,
      address: address ?? this.address,
      city: city ?? this.city,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      pricePerNight: pricePerNight ?? this.pricePerNight,
      maxGuests: maxGuests ?? this.maxGuests,
      bedrooms: bedrooms ?? this.bedrooms,
      beds: beds ?? this.beds,
      bathrooms: bathrooms ?? this.bathrooms,
      amenities: amenities ?? this.amenities,
      imageUrls: imageUrls ?? this.imageUrls,
    );
  }
}
