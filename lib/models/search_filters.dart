import 'package:flutter/material.dart';

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
    this.dateMode = SearchDateMode.dateRange,
    this.singleDate,
    this.startTime,
    this.endTime,
    this.purposeTags = const [],
    this.landmark,
    this.radiusMeters,
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
    bool clearLocation = false,
    bool clearDates = false,
    bool clearPriceRange = false,
    bool clearTime = false,
    bool clearLandmark = false,
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
