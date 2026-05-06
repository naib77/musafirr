import 'listing_type.dart';

class SearchFilters {
  const SearchFilters({
    this.location,
    this.latitude,
    this.longitude,
    this.checkIn,
    this.checkOut,
    this.guestCount = 1,
    this.minPrice,
    this.maxPrice,
    this.propertyTypes = const [],
    this.amenities = const [],
  });

  final String? location;
  final double? latitude;
  final double? longitude;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final int guestCount;
  final double? minPrice;
  final double? maxPrice;
  final List<ListingType> propertyTypes;
  final List<String> amenities;

  bool get hasActiveFilters =>
      location != null ||
      checkIn != null ||
      checkOut != null ||
      guestCount > 1 ||
      minPrice != null ||
      maxPrice != null ||
      propertyTypes.isNotEmpty ||
      amenities.isNotEmpty;

  int get numberOfNights {
    if (checkIn == null || checkOut == null) return 1;
    return checkOut!.difference(checkIn!).inDays;
  }

  SearchFilters copyWith({
    String? location,
    double? latitude,
    double? longitude,
    DateTime? checkIn,
    DateTime? checkOut,
    int? guestCount,
    double? minPrice,
    double? maxPrice,
    List<ListingType>? propertyTypes,
    List<String>? amenities,
    bool clearLocation = false,
    bool clearDates = false,
    bool clearPriceRange = false,
  }) {
    return SearchFilters(
      location: clearLocation ? null : (location ?? this.location),
      latitude: clearLocation ? null : (latitude ?? this.latitude),
      longitude: clearLocation ? null : (longitude ?? this.longitude),
      checkIn: clearDates ? null : (checkIn ?? this.checkIn),
      checkOut: clearDates ? null : (checkOut ?? this.checkOut),
      guestCount: guestCount ?? this.guestCount,
      minPrice: clearPriceRange ? null : (minPrice ?? this.minPrice),
      maxPrice: clearPriceRange ? null : (maxPrice ?? this.maxPrice),
      propertyTypes: propertyTypes ?? this.propertyTypes,
      amenities: amenities ?? this.amenities,
    );
  }

  SearchFilters clear() {
    return const SearchFilters();
  }
}
