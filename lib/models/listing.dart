import '../core/currency/currency.dart';
import '../core/currency/money.dart';
import 'facility.dart';
import 'listing_type.dart';

class Listing {
  Listing({
    required this.id,
    required this.ownerName,
    required this.title,
    required this.address,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.hourlyRate,
    required this.dailyRate,
    required this.monthlyRate,
    required this.facilities,
    required this.available,
    // New fields for marketplace
    this.hostId,
    this.hostAvatarUrl,
    this.description,
    this.city,
    this.country,
    this.pricePerNight,
    this.imageUrls = const [],
    this.maxGuests = 2,
    this.bedrooms = 1,
    this.beds = 1,
    this.bathrooms = 1,
    this.rating,
    this.reviewCount = 0,
    this.isSuperhost = false,
    // Currency
    this.currency = Currency.BDT,
  });

  final String id;
  final String ownerName;
  final String title;
  final String address;
  final ListingType type;
  final double latitude;
  final double longitude;
  final double hourlyRate;
  final double dailyRate;
  final double monthlyRate;
  final List<Facility> facilities;
  bool available;

  // New marketplace fields
  final String? hostId;
  final String? hostAvatarUrl;
  final String? description;
  final String? city;
  final String? country;
  final double? pricePerNight;
  final List<String> imageUrls;
  final int maxGuests;
  final int bedrooms;
  final int beds;
  final int bathrooms;
  final double? rating;
  final int reviewCount;
  final bool isSuperhost;

  // Currency for all prices
  final Currency currency;

  // Money-typed getters for type-safe currency handling
  Money get hourlyRateMoney => Money(hourlyRate, currency);
  Money get dailyRateMoney => Money(dailyRate, currency);
  Money get monthlyRateMoney => Money(monthlyRate, currency);
  Money? get pricePerNightMoney =>
      pricePerNight != null ? Money(pricePerNight!, currency) : null;

  // Computed property for display price (double - backward compatible)
  double get displayPrice => pricePerNight ?? dailyRate;

  // Money-typed display price
  Money get displayPriceMoney => Money(displayPrice, currency);

  // Get amenity names from facilities
  List<String> get amenityNames => facilities.map((f) => f.name).toList();

  // Primary image for cards
  String? get primaryImage => imageUrls.isNotEmpty ? imageUrls.first : null;

  Listing copyWith({
    String? id,
    String? ownerName,
    String? title,
    String? address,
    ListingType? type,
    double? latitude,
    double? longitude,
    double? hourlyRate,
    double? dailyRate,
    double? monthlyRate,
    List<Facility>? facilities,
    bool? available,
    String? hostId,
    String? hostAvatarUrl,
    String? description,
    String? city,
    String? country,
    double? pricePerNight,
    List<String>? imageUrls,
    int? maxGuests,
    int? bedrooms,
    int? beds,
    int? bathrooms,
    double? rating,
    int? reviewCount,
    bool? isSuperhost,
    Currency? currency,
  }) {
    return Listing(
      id: id ?? this.id,
      ownerName: ownerName ?? this.ownerName,
      title: title ?? this.title,
      address: address ?? this.address,
      type: type ?? this.type,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      dailyRate: dailyRate ?? this.dailyRate,
      monthlyRate: monthlyRate ?? this.monthlyRate,
      facilities: facilities ?? this.facilities,
      available: available ?? this.available,
      hostId: hostId ?? this.hostId,
      hostAvatarUrl: hostAvatarUrl ?? this.hostAvatarUrl,
      description: description ?? this.description,
      city: city ?? this.city,
      country: country ?? this.country,
      pricePerNight: pricePerNight ?? this.pricePerNight,
      imageUrls: imageUrls ?? this.imageUrls,
      maxGuests: maxGuests ?? this.maxGuests,
      bedrooms: bedrooms ?? this.bedrooms,
      beds: beds ?? this.beds,
      bathrooms: bathrooms ?? this.bathrooms,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      isSuperhost: isSuperhost ?? this.isSuperhost,
      currency: currency ?? this.currency,
    );
  }
}
