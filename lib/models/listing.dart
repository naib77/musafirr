import '../core/currency/currency.dart';
import '../core/currency/money.dart';
import 'facility.dart';
import 'listing_type.dart';
import 'rental_plan.dart';

class Listing {
  Listing({
    required this.id,
    required this.ownerName,
    required this.title,
    required this.address,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.hourlyRate,
    this.dailyRate,
    this.monthlyRate,
    required this.facilities,
    required this.available,
    this.hostAvailable = true,
    // New fields for marketplace
    this.hostId,
    this.hostAvatarUrl,
    this.description,
    this.city,
    this.country,
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

  /// Per-plan rates. `null` means the host does not offer that booking plan.
  /// At least one of these is non-null for a bookable listing.
  final double? hourlyRate;
  final double? dailyRate;
  final double? monthlyRate;

  final List<Facility> facilities;
  bool available;

  /// Whether the listing's host is currently accepting bookings (mirror of
  /// the host's profile availability). Guests don't see listings where this is
  /// false; the host's own management views ignore it.
  final bool hostAvailable;

  // New marketplace fields
  final String? hostId;
  final String? hostAvatarUrl;
  final String? description;
  final String? city;
  final String? country;
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

  // Money-typed getters for type-safe currency handling.
  // Null when the corresponding plan is not offered.
  Money? get hourlyRateMoney =>
      hourlyRate != null ? Money(hourlyRate!, currency) : null;
  Money? get dailyRateMoney =>
      dailyRate != null ? Money(dailyRate!, currency) : null;
  Money? get monthlyRateMoney =>
      monthlyRate != null ? Money(monthlyRate!, currency) : null;

  /// Rate for a given plan, or null if that plan is not offered.
  double? rateFor(DurationType plan) => switch (plan) {
        DurationType.hourly => hourlyRate,
        DurationType.daily => dailyRate,
        DurationType.monthly => monthlyRate,
      };

  /// Money-typed rate for a plan, or null if that plan is not offered.
  Money? moneyFor(DurationType plan) {
    final rate = rateFor(plan);
    return rate != null ? Money(rate, currency) : null;
  }

  /// Plans this listing offers, in ascending unit order (hourly → daily → monthly).
  List<DurationType> get offeredPlans => [
        if (hourlyRate != null) DurationType.hourly,
        if (dailyRate != null) DurationType.daily,
        if (monthlyRate != null) DurationType.monthly,
      ];

  /// The cheapest offered plan by rate. Null only when no plan is offered.
  ///
  /// Rates are constrained hourly < daily < monthly, so this is normally the
  /// shortest offered unit, but we compute by actual rate to stay correct.
  DurationType? get cheapestPlan {
    final plans = offeredPlans;
    if (plans.isEmpty) return null;
    return plans.reduce((a, b) => rateFor(a)! <= rateFor(b)! ? a : b);
  }

  /// Money-typed cheapest offered rate, or null if no plan is offered.
  Money? get cheapestRateMoney {
    final plan = cheapestPlan;
    return plan != null ? moneyFor(plan) : null;
  }

  // Computed display price = cheapest offered rate (double - backward compatible).
  double get displayPrice {
    final plan = cheapestPlan;
    return plan != null ? rateFor(plan)! : 0;
  }

  // Money-typed display price (cheapest offered rate).
  Money get displayPriceMoney => cheapestRateMoney ?? Money.zero(currency);

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
    bool? hostAvailable,
    String? hostId,
    String? hostAvatarUrl,
    String? description,
    String? city,
    String? country,
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
      hostAvailable: hostAvailable ?? this.hostAvailable,
      hostId: hostId ?? this.hostId,
      hostAvatarUrl: hostAvatarUrl ?? this.hostAvatarUrl,
      description: description ?? this.description,
      city: city ?? this.city,
      country: country ?? this.country,
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

  /// Returns a copy with the three plan rates replaced wholesale.
  ///
  /// Pass `null` for a plan the host does not offer. Use this (not [copyWith])
  /// when saving the pricing section, because [copyWith] cannot clear a rate
  /// back to null.
  Listing withPlanRates({
    required double? hourlyRate,
    required double? dailyRate,
    required double? monthlyRate,
  }) {
    return Listing(
      id: id,
      ownerName: ownerName,
      title: title,
      address: address,
      type: type,
      latitude: latitude,
      longitude: longitude,
      hourlyRate: hourlyRate,
      dailyRate: dailyRate,
      monthlyRate: monthlyRate,
      facilities: facilities,
      available: available,
      hostAvailable: hostAvailable,
      hostId: hostId,
      hostAvatarUrl: hostAvatarUrl,
      description: description,
      city: city,
      country: country,
      imageUrls: imageUrls,
      maxGuests: maxGuests,
      bedrooms: bedrooms,
      beds: beds,
      bathrooms: bathrooms,
      rating: rating,
      reviewCount: reviewCount,
      isSuperhost: isSuperhost,
      currency: currency,
    );
  }
}
