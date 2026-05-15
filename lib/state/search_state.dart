import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/listing.dart';
import '../models/listing_type.dart';
import '../models/search_filters.dart';

class SearchStateNotifier extends ChangeNotifier {
  SearchFilters _filters = const SearchFilters();
  List<Listing> _results = [];
  List<Listing> _allListings = [];
  bool _isSearching = false;
  String? _error;

  SearchFilters get filters => _filters;
  List<Listing> get results => _results;
  bool get isSearching => _isSearching;
  String? get error => _error;
  bool get hasResults => _results.isNotEmpty;

  // Set the source listings (called when repository data changes)
  void setListings(List<Listing> listings) {
    _allListings = listings;
    _applyFilters();
  }

  // Update filters
  void updateFilters(SearchFilters newFilters) {
    _filters = newFilters;
    _applyFilters();
  }

  // Update location filter
  void updateLocation({
    required String location,
    double? latitude,
    double? longitude,
  }) {
    _filters = _filters.copyWith(
      location: location,
      latitude: latitude,
      longitude: longitude,
    );
    _applyFilters();
  }

  // Update date range
  void updateDates({DateTime? checkIn, DateTime? checkOut}) {
    _filters = _filters.copyWith(
      checkIn: checkIn,
      checkOut: checkOut,
      dateMode: SearchDateMode.dateRange,
    );
    _applyFilters();
  }

  // Update single date with time range
  void updateSingleDateWithTime({
    DateTime? date,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
  }) {
    _filters = _filters.copyWith(
      singleDate: date,
      startTime: startTime,
      endTime: endTime,
      dateMode: SearchDateMode.singleDateWithTime,
    );
    _applyFilters();
  }

  // Update date mode
  void updateDateMode(SearchDateMode mode) {
    _filters = _filters.copyWith(dateMode: mode);
    _applyFilters();
  }

  // Clear time selection
  void clearTime() {
    _filters = _filters.copyWith(clearTime: true);
    _applyFilters();
  }

  // Update guest count
  void updateGuestCount(int count) {
    _filters = _filters.copyWith(guestCount: count.clamp(1, 16));
    _applyFilters();
  }

  // Update price range
  void updatePriceRange({double? minPrice, double? maxPrice}) {
    _filters = _filters.copyWith(
      minPrice: minPrice,
      maxPrice: maxPrice,
    );
    _applyFilters();
  }

  // Update property types
  void updatePropertyTypes(List<ListingType> types) {
    _filters = _filters.copyWith(propertyTypes: types);
    _applyFilters();
  }

  // Toggle property type
  void togglePropertyType(ListingType type) {
    final types = List<ListingType>.from(_filters.propertyTypes);
    if (types.contains(type)) {
      types.remove(type);
    } else {
      types.add(type);
    }
    _filters = _filters.copyWith(propertyTypes: types);
    _applyFilters();
  }

  // Update amenities
  void updateAmenities(List<String> amenities) {
    _filters = _filters.copyWith(amenities: amenities);
    _applyFilters();
  }

  // Toggle amenity
  void toggleAmenity(String amenity) {
    final amenities = List<String>.from(_filters.amenities);
    if (amenities.contains(amenity)) {
      amenities.remove(amenity);
    } else {
      amenities.add(amenity);
    }
    _filters = _filters.copyWith(amenities: amenities);
    _applyFilters();
  }

  // Clear all filters
  void clearFilters() {
    _filters = const SearchFilters();
    _applyFilters();
  }

  // Clear specific filter categories
  void clearLocation() {
    _filters = _filters.copyWith(clearLocation: true);
    _applyFilters();
  }

  void clearDates() {
    _filters = _filters.copyWith(clearDates: true);
    _applyFilters();
  }

  void clearPriceRange() {
    _filters = _filters.copyWith(clearPriceRange: true);
    _applyFilters();
  }

  // Perform search with simulated delay
  Future<void> search() async {
    _isSearching = true;
    _error = null;
    notifyListeners();

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 300));

    _applyFilters();

    _isSearching = false;
    notifyListeners();
  }

  // Apply filters to listings
  void _applyFilters() {
    _results = _allListings.where((listing) {
      // Filter by availability
      if (!listing.available) return false;

      // Filter by property type
      if (_filters.propertyTypes.isNotEmpty &&
          !_filters.propertyTypes.contains(listing.type)) {
        return false;
      }

      // Filter by guest count
      if (listing.maxGuests < _filters.guestCount) {
        return false;
      }

      // Filter by price range
      final price = listing.displayPrice;
      if (_filters.minPrice != null && price < _filters.minPrice!) {
        return false;
      }
      if (_filters.maxPrice != null && price > _filters.maxPrice!) {
        return false;
      }

      // Filter by amenities
      if (_filters.amenities.isNotEmpty) {
        final listingAmenities = listing.amenityNames;
        for (final amenity in _filters.amenities) {
          if (!listingAmenities.contains(amenity)) {
            return false;
          }
        }
      }

      // Filter by location (simple text match for now)
      if (_filters.location != null && _filters.location!.isNotEmpty) {
        final searchLower = _filters.location!.toLowerCase();
        final matchesCity =
            listing.city?.toLowerCase().contains(searchLower) ?? false;
        final matchesAddress =
            listing.address.toLowerCase().contains(searchLower);
        final matchesTitle = listing.title.toLowerCase().contains(searchLower);
        if (!matchesCity && !matchesAddress && !matchesTitle) {
          return false;
        }
      }

      return true;
    }).toList();

    // Sort by rating (highest first), then by review count
    _results.sort((a, b) {
      final ratingA = a.rating ?? 0;
      final ratingB = b.rating ?? 0;
      if (ratingA != ratingB) {
        return ratingB.compareTo(ratingA);
      }
      return b.reviewCount.compareTo(a.reviewCount);
    });

    notifyListeners();
  }
}
