import 'package:flutter/material.dart';

import 'geo_bounds.dart';
import 'landmark.dart';
import 'listing_purpose.dart';
import 'listing_type.dart';

/// Search mode for date/time selection
enum SearchDateMode {
  /// Search for date range (e.g., Jan 1 - Jan 5)
  dateRange,

  /// Search for single date with time range (e.g., Jan 1, 10:00 AM - 2:00 PM)
  singleDateWithTime,
}

/// Upper bound on a search's guest count. Mirrors the clamp the single guest
/// counter has always used, so splitting it into adults/children cannot start
/// asking for a party no listing could hold.
const int maxSearchGuests = 16;

/// The one place [SearchFilters.guestCount] is derived from a Who breakdown.
///
/// Infants are excluded — the convention every travel site uses — and the floor
/// is 1, because a search for nobody is not a search and this number is
/// compared against a listing's `max_guests`. A single function rather than a
/// sum at each call site: the two fields and the count they imply have to stay
/// in step, and one of them is what actually reaches the database.
int guestCountFor({required int adults, required int children}) {
  final total = adults + children;
  if (total < 1) return 1;
  if (total > maxSearchGuests) return maxSearchGuests;
  return total;
}

class SearchFilters {
  const SearchFilters({
    this.location,
    this.latitude,
    this.longitude,
    this.checkIn,
    this.checkOut,
    this.guestCount = 1,
    this.adults = 1,
    this.children = 0,
    this.infants = 0,
    this.minPrice,
    this.maxPrice,
    this.propertyTypes = const [],
    this.amenities = const [],
    this.dateMode = SearchDateMode.dateRange,
    this.singleDate,
    this.startTime,
    this.endTime,
    this.purposeTags = const [],
    this.landmark,
    this.radiusMeters,
    this.bounds,
  });

  final String? location;
  final double? latitude;
  final double? longitude;

  /// The searched place's true extent (a geocoded/Places viewport). When set,
  /// the search covers exactly this box — "Uttara" stays within Uttara — and
  /// the results map frames to it, instead of an expanding radius ring that
  /// spills into neighbouring areas. Null → the point + radius path.
  final GeoBounds? bounds;
  final DateTime? checkIn;
  final DateTime? checkOut;

  /// How many people the search must fit — the number that actually reaches
  /// `search_listings` and gets compared against a listing's `max_guests`.
  ///
  /// Kept as its own stored field rather than derived from [adults] + [children]
  /// so that every existing construction site keeps working unchanged. The two
  /// are held in step in exactly one place, [guestCountFor], which is what the
  /// search UI uses when it builds filters from a draft.
  final int guestCount;

  /// The breakdown behind [guestCount], as the desktop "Who" panel collects it.
  ///
  /// This is **search state only**. It narrows which listings are shown and
  /// nothing more: a booking still carries one guest number, so a stay searched
  /// as "2 adults, 1 child, 1 infant" is booked as 3 guests. Carrying the split
  /// through would mean a migration plus the booking sheet, the price
  /// breakdown and the host's reservation list — deliberately not done here.
  ///
  /// They exist so that reopening the panel shows the split the guest actually
  /// chose, instead of re-splitting a sum into "N adults".
  final int adults;
  final int children;

  /// Infants never count towards [guestCount] — the same convention every
  /// travel site uses, and the reason [guestCountFor] exists rather than a
  /// plain sum at each call site.
  final int infants;

  final double? minPrice;
  final double? maxPrice;
  final List<ListingType> propertyTypes;
  final List<String> amenities;

  // Time-based search fields
  final SearchDateMode dateMode;
  final DateTime? singleDate;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;

  // Purpose-based search: what the stay is for, and (optionally) a landmark to
  // rank by distance to (e.g. a specific hospital / exam center).
  final List<ListingPurpose> purposeTags;
  final Landmark? landmark;
  final int? radiusMeters;

  /// True when a place extent is available to search within — a valid box
  /// takes precedence over the radius-ring path.
  bool get hasBounds => bounds != null && bounds!.isValid;

  bool get hasActiveFilters =>
      location != null ||
      checkIn != null ||
      checkOut != null ||
      singleDate != null ||
      guestCount > 1 ||
      minPrice != null ||
      maxPrice != null ||
      propertyTypes.isNotEmpty ||
      amenities.isNotEmpty ||
      purposeTags.isNotEmpty ||
      landmark != null;

  bool get hasDateSelection {
    if (dateMode == SearchDateMode.dateRange) {
      return checkIn != null && checkOut != null;
    } else {
      return singleDate != null && startTime != null && endTime != null;
    }
  }

  int get numberOfNights {
    if (checkIn == null || checkOut == null) return 1;
    return checkOut!.difference(checkIn!).inDays;
  }

  int get numberOfHours {
    if (startTime == null || endTime == null) return 1;
    final startMinutes = startTime!.hour * 60 + startTime!.minute;
    final endMinutes = endTime!.hour * 60 + endTime!.minute;
    return ((endMinutes - startMinutes) / 60).ceil().clamp(1, 24);
  }

  /// Get effective check-in datetime based on mode
  DateTime? get effectiveCheckIn {
    if (dateMode == SearchDateMode.dateRange) {
      return checkIn;
    } else if (singleDate != null && startTime != null) {
      return DateTime(
        singleDate!.year,
        singleDate!.month,
        singleDate!.day,
        startTime!.hour,
        startTime!.minute,
      );
    }
    return null;
  }

  /// Get effective check-out datetime based on mode
  DateTime? get effectiveCheckOut {
    if (dateMode == SearchDateMode.dateRange) {
      return checkOut;
    } else if (singleDate != null && endTime != null) {
      return DateTime(
        singleDate!.year,
        singleDate!.month,
        singleDate!.day,
        endTime!.hour,
        endTime!.minute,
      );
    }
    return null;
  }

  SearchFilters copyWith({
    String? location,
    double? latitude,
    double? longitude,
    DateTime? checkIn,
    DateTime? checkOut,
    int? guestCount,
    int? adults,
    int? children,
    int? infants,
    double? minPrice,
    double? maxPrice,
    List<ListingType>? propertyTypes,
    List<String>? amenities,
    SearchDateMode? dateMode,
    DateTime? singleDate,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    List<ListingPurpose>? purposeTags,
    Landmark? landmark,
    int? radiusMeters,
    GeoBounds? bounds,
    bool clearLocation = false,
    bool clearDates = false,
    bool clearPriceRange = false,
    bool clearTime = false,
    bool clearLandmark = false,
    bool clearCoordinates = false,
    bool clearBounds = false,
  }) {
    return SearchFilters(
      location: clearLocation ? null : (location ?? this.location),
      // clearCoordinates drops a previously resolved center point while
      // keeping the location text — needed when a new search resolves to
      // text-only (otherwise the old point would silently keep applying).
      latitude: (clearLocation || clearCoordinates)
          ? null
          : (latitude ?? this.latitude),
      longitude: (clearLocation || clearCoordinates)
          ? null
          : (longitude ?? this.longitude),
      // The box is INDEPENDENT of the center point: a city or area resolves to
      // a box with no center at all, so clearCoordinates must NOT wipe it (that
      // was the bug where "Dhaka" fell back to marker-fit). Callers that resolve
      // a new place always pass an explicit `bounds` (+ `clearBounds` when the
      // new place has none), so a stale box can never leak into the next search.
      bounds: (clearLocation || clearBounds) ? null : (bounds ?? this.bounds),
      checkIn: clearDates ? null : (checkIn ?? this.checkIn),
      checkOut: clearDates ? null : (checkOut ?? this.checkOut),
      guestCount: guestCount ?? this.guestCount,
      // Carried, or a Who edit would not survive the next Where edit — every
      // panel commits through one copyWith over the current filters.
      adults: adults ?? this.adults,
      children: children ?? this.children,
      infants: infants ?? this.infants,
      minPrice: clearPriceRange ? null : (minPrice ?? this.minPrice),
      maxPrice: clearPriceRange ? null : (maxPrice ?? this.maxPrice),
      propertyTypes: propertyTypes ?? this.propertyTypes,
      amenities: amenities ?? this.amenities,
      dateMode: dateMode ?? this.dateMode,
      singleDate: clearDates ? null : (singleDate ?? this.singleDate),
      startTime: clearTime ? null : (startTime ?? this.startTime),
      endTime: clearTime ? null : (endTime ?? this.endTime),
      purposeTags: purposeTags ?? this.purposeTags,
      landmark: clearLandmark ? null : (landmark ?? this.landmark),
      radiusMeters: clearLandmark ? null : (radiusMeters ?? this.radiusMeters),
    );
  }

  SearchFilters clear() {
    return const SearchFilters();
  }
}
