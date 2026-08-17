import '../core/currency/currency.dart';
import '../core/currency/money.dart';
import 'facility.dart';
import 'listing_purpose.dart';
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
    // Structured (Airbnb-style) address parts. `address` remains the composed
    // display string; these hold the individual components for editing.
    this.flatFloor,
    this.houseNo,
    this.street,
    this.area,
    this.postalCode,
    this.landmark,
    this.imageUrls = const [],
    this.maxGuests = 2,
    this.bedrooms = 1,
    this.beds = 1,
    this.bathrooms = 1,
    this.rating,
    this.reviewCount = 0,
    this.isSuperhost = false,
    // Per-plan min/max booking duration.
    this.bookingLimits = const BookingLimits(),
    // House rules (shown publicly on the listing page).
    this.houseRules = const HouseRules(),
    // Sensitive check-in access details. Null unless loaded for the host who
    // owns the listing; never exposed to guests via the listing row.
    this.checkInDetails,
    // Currency
    this.currency = Currency.bdt,
    // When the listing was created (server timestamp). Used to surface
    // "Newly available" stays. Null for locally-built/mock listings.
    this.createdAt,
    // What this place is good for (medical/exam/tourism/…). Separate from [type]
    // (the unit). Empty means untagged.
    this.purposeTags = const [],
    // Distance in metres from a searched landmark, when the listing came from a
    // proximity search. Null otherwise. Not persisted — a per-search value.
    this.distanceMeters,
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

  /// Structured address components (Bangladesh convention). [address] is the
  /// composed display string built from these; use [composeAddress] to build it.
  final String? flatFloor;
  final String? houseNo;
  final String? street;
  final String? area;
  final String? postalCode;
  final String? landmark;

  final List<String> imageUrls;
  final int maxGuests;
  final int bedrooms;
  final int beds;
  final int bathrooms;
  final double? rating;
  final int reviewCount;
  final bool isSuperhost;

  /// Server creation timestamp; null for locally-built/mock listings.
  final DateTime? createdAt;

  /// What this place is good for (medical/exam/tourism/…). Separate from [type].
  final List<ListingPurpose> purposeTags;

  /// Distance in metres from a searched landmark (proximity search only).
  final double? distanceMeters;

  /// Per-plan minimum/maximum booking duration.
  final BookingLimits bookingLimits;

  /// Publicly-visible house rules (check-in/out times, smoking/pets/parties…).
  final HouseRules houseRules;

  /// Sensitive check-in access (directions, Wi-Fi, door code). Only populated
  /// when the listing is loaded for its owner; guests receive these via the
  /// pre-check-in message, never directly.
  final CheckInDetails? checkInDetails;

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

  /// The first two offered plans, in ascending unit order — what a card shows
  /// so a guest can compare a short and a longer stay at a glance. All three
  /// offered → hourly + daily; no daily → hourly + monthly; no hourly →
  /// daily + monthly. A listing with a single plan yields just that one.
  List<DurationType> get headlinePlans => offeredPlans.take(2).toList();

  /// Whether this listing reads as a guest favourite. Derived, because there
  /// is no such column yet: a high rating alone isn't enough — one five-star
  /// review must not earn the badge — so a meaningful number of reviews is
  /// required too. Move this to the database if the bar ever needs tuning per
  /// market or campaign.
  bool get isGuestFavorite => (rating ?? 0) >= 4.8 && reviewCount >= 5;

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

  /// Builds a single human-readable address line from the structured parts
  /// (Bangladesh order: house, flat/floor, road, area — city/postal appended).
  /// Empty parts are skipped. Used to keep [address] as a display string.
  static String composeAddress({
    String? houseNo,
    String? flatFloor,
    String? street,
    String? area,
    String? city,
    String? postalCode,
  }) {
    final parts = <String>[
      if (houseNo != null && houseNo.trim().isNotEmpty) houseNo.trim(),
      if (flatFloor != null && flatFloor.trim().isNotEmpty) flatFloor.trim(),
      if (street != null && street.trim().isNotEmpty) street.trim(),
      if (area != null && area.trim().isNotEmpty) area.trim(),
    ];
    var line = parts.join(', ');
    final cityPostal = [
      if (city != null && city.trim().isNotEmpty) city.trim(),
      if (postalCode != null && postalCode.trim().isNotEmpty) postalCode.trim(),
    ].join(' ');
    if (cityPostal.isNotEmpty) {
      line = line.isEmpty ? cityPostal : '$line, $cityPostal';
    }
    return line;
  }

  /// The address with everything that identifies a specific door taken out —
  /// house number, flat/floor, road — leaving the area and city. What a guest
  /// gets before the host has accepted their booking, and what a search result
  /// shows at all times.
  ///
  /// Falls back to the city, then to a generic label, but never to [address]:
  /// a listing whose structured parts were never saved must not leak the whole
  /// line just because we can't tell which segment is the house number.
  ///
  /// This is only the string. Which viewers see it is [ListingLocation]'s
  /// decision, and the map and directions follow the same one.
  String get approximateAddress {
    final composed = composeAddress(area: area, city: city);
    if (composed.isNotEmpty) return composed;
    final fallback = city?.trim();
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return 'Approximate location';
  }

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
    String? flatFloor,
    String? houseNo,
    String? street,
    String? area,
    String? postalCode,
    String? landmark,
    List<String>? imageUrls,
    int? maxGuests,
    int? bedrooms,
    int? beds,
    int? bathrooms,
    double? rating,
    int? reviewCount,
    bool? isSuperhost,
    BookingLimits? bookingLimits,
    HouseRules? houseRules,
    CheckInDetails? checkInDetails,
    Currency? currency,
    DateTime? createdAt,
    List<ListingPurpose>? purposeTags,
    double? distanceMeters,
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
      flatFloor: flatFloor ?? this.flatFloor,
      houseNo: houseNo ?? this.houseNo,
      street: street ?? this.street,
      area: area ?? this.area,
      postalCode: postalCode ?? this.postalCode,
      landmark: landmark ?? this.landmark,
      imageUrls: imageUrls ?? this.imageUrls,
      maxGuests: maxGuests ?? this.maxGuests,
      bedrooms: bedrooms ?? this.bedrooms,
      beds: beds ?? this.beds,
      bathrooms: bathrooms ?? this.bathrooms,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      isSuperhost: isSuperhost ?? this.isSuperhost,
      bookingLimits: bookingLimits ?? this.bookingLimits,
      houseRules: houseRules ?? this.houseRules,
      checkInDetails: checkInDetails ?? this.checkInDetails,
      currency: currency ?? this.currency,
      createdAt: createdAt ?? this.createdAt,
      purposeTags: purposeTags ?? this.purposeTags,
      distanceMeters: distanceMeters ?? this.distanceMeters,
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
      flatFloor: flatFloor,
      houseNo: houseNo,
      street: street,
      area: area,
      postalCode: postalCode,
      landmark: landmark,
      imageUrls: imageUrls,
      maxGuests: maxGuests,
      bedrooms: bedrooms,
      beds: beds,
      bathrooms: bathrooms,
      rating: rating,
      reviewCount: reviewCount,
      isSuperhost: isSuperhost,
      bookingLimits: bookingLimits,
      houseRules: houseRules,
      checkInDetails: checkInDetails,
      currency: currency,
      createdAt: createdAt,
    );
  }
}

/// Per-plan minimum/maximum booking duration. Units are hours (hourly plan),
/// nights (daily plan), and months (monthly plan). A null minimum means 1;
/// a null maximum means no cap.
class BookingLimits {
  const BookingLimits({
    this.minHours,
    this.maxHours,
    this.minNights,
    this.maxNights,
    this.minMonths,
    this.maxMonths,
  });

  final int? minHours;
  final int? maxHours;
  final int? minNights;
  final int? maxNights;
  final int? minMonths;
  final int? maxMonths;

  /// Minimum units for [plan] (defaults to 1 when unset).
  int minFor(DurationType plan) => switch (plan) {
        DurationType.hourly => minHours ?? 1,
        DurationType.daily => minNights ?? 1,
        DurationType.monthly => minMonths ?? 1,
      };

  /// Maximum units for [plan], or null for no cap.
  int? maxFor(DurationType plan) => switch (plan) {
        DurationType.hourly => maxHours,
        DurationType.daily => maxNights,
        DurationType.monthly => maxMonths,
      };

  BookingLimits copyWith({
    int? minHours,
    int? maxHours,
    int? minNights,
    int? maxNights,
    int? minMonths,
    int? maxMonths,
  }) {
    return BookingLimits(
      minHours: minHours ?? this.minHours,
      maxHours: maxHours ?? this.maxHours,
      minNights: minNights ?? this.minNights,
      maxNights: maxNights ?? this.maxNights,
      minMonths: minMonths ?? this.minMonths,
      maxMonths: maxMonths ?? this.maxMonths,
    );
  }
}

/// Publicly-visible house rules for a listing.
class HouseRules {
  const HouseRules({
    this.checkInTime,
    this.checkOutTime,
    this.smokingAllowed = false,
    this.petsAllowed = false,
    this.partiesAllowed = false,
    this.quietHours,
    this.additionalRules,
  });

  /// Free-text time labels (e.g. "2:00 PM", "11:00 AM") — kept as strings so
  /// the host isn't forced into a rigid picker and they render straight into
  /// messages.
  final String? checkInTime;
  final String? checkOutTime;
  final bool smokingAllowed;
  final bool petsAllowed;
  final bool partiesAllowed;
  final String? quietHours;
  final String? additionalRules;

  bool get hasAny =>
      (checkInTime?.isNotEmpty ?? false) ||
      (checkOutTime?.isNotEmpty ?? false) ||
      smokingAllowed ||
      petsAllowed ||
      partiesAllowed ||
      (quietHours?.isNotEmpty ?? false) ||
      (additionalRules?.isNotEmpty ?? false);

  HouseRules copyWith({
    String? checkInTime,
    String? checkOutTime,
    bool? smokingAllowed,
    bool? petsAllowed,
    bool? partiesAllowed,
    String? quietHours,
    String? additionalRules,
  }) {
    return HouseRules(
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      smokingAllowed: smokingAllowed ?? this.smokingAllowed,
      petsAllowed: petsAllowed ?? this.petsAllowed,
      partiesAllowed: partiesAllowed ?? this.partiesAllowed,
      quietHours: quietHours ?? this.quietHours,
      additionalRules: additionalRules ?? this.additionalRules,
    );
  }
}

/// Sensitive check-in access details. Host-only; delivered to guests via the
/// pre-check-in message, never exposed on the public listing row.
class CheckInDetails {
  const CheckInDetails({
    this.directions,
    this.wifiName,
    this.wifiPassword,
    this.accessCode,
  });

  final String? directions;
  final String? wifiName;
  final String? wifiPassword;
  final String? accessCode;

  bool get isEmpty =>
      (directions?.isEmpty ?? true) &&
      (wifiName?.isEmpty ?? true) &&
      (wifiPassword?.isEmpty ?? true) &&
      (accessCode?.isEmpty ?? true);
}
