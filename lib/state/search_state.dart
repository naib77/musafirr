import '../core/state/safe_notifier.dart';
import 'package:flutter/material.dart';

import '../models/listing.dart';
import '../models/listing_type.dart';
import '../models/search_filters.dart';
import '../repositories/musafir_repository.dart' show ListingSearchResult;

/// Drives Explore search. Filtering and ranking happen server-side (the
/// `search_listings` RPC via [attachSearcher]) so search covers the FULL
/// catalog, not just the listings already paginated into memory. When no filter
/// is active, [results] is empty and Explore falls back to the default feed.
class SearchStateNotifier extends ChangeNotifier with SafeNotifier {
  SearchFilters _filters = const SearchFilters();
  List<Listing> _results = [];
  bool _isSearching = false;
  String? _error;
  int? _matchedRadiusMeters;
  bool _usedNearestFallback = false;

  /// Full-catalog search backend, injected at startup
  /// (repository.searchListingsFromDb).
  Future<ListingSearchResult> Function(SearchFilters filters)? _searcher;

  /// Guards against out-of-order responses: only the newest search may write.
  int _searchToken = 0;

  SearchFilters get filters => _filters;
  List<Listing> get results => _results;
  bool get isSearching => _isSearching;
  String? get error => _error;
  bool get hasResults => _results.isNotEmpty;

  /// The radius tier (meters) the current proximity results came from, or
  /// null when the search wasn't a proximity search (or fell back to nearest).
  int? get matchedRadiusMeters => _matchedRadiusMeters;

  /// True when no radius tier matched and [results] are simply the nearest
  /// stays to the searched point.
  bool get usedNearestFallback => _usedNearestFallback;

  /// Wire the server-side searcher. Called once during app startup.
  void attachSearcher(
      Future<ListingSearchResult> Function(SearchFilters filters) searcher) {
    _searcher = searcher;
  }

  // Update filters
  void updateFilters(SearchFilters newFilters) {
    _filters = newFilters;
    _runSearch();
  }

  // Update location filter. Passing no coordinates makes this a text-only
  // search — any previously resolved center point is dropped, not kept.
  void updateLocation({
    required String location,
    double? latitude,
    double? longitude,
  }) {
    _filters = _filters.copyWith(
      location: location,
      latitude: latitude,
      longitude: longitude,
      clearCoordinates: latitude == null || longitude == null,
    );
    _runSearch();
  }

  // Update date range
  void updateDates({DateTime? checkIn, DateTime? checkOut}) {
    _filters = _filters.copyWith(
      checkIn: checkIn,
      checkOut: checkOut,
      dateMode: SearchDateMode.dateRange,
    );
    _runSearch();
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
    _runSearch();
  }

  // Update date mode
  void updateDateMode(SearchDateMode mode) {
    _filters = _filters.copyWith(dateMode: mode);
    _runSearch();
  }

  // Clear time selection
  void clearTime() {
    _filters = _filters.copyWith(clearTime: true);
    _runSearch();
  }

  // Update guest count
  void updateGuestCount(int count) {
    _filters = _filters.copyWith(guestCount: count.clamp(1, 16));
    _runSearch();
  }

  // Update price range
  void updatePriceRange({double? minPrice, double? maxPrice}) {
    _filters = _filters.copyWith(
      minPrice: minPrice,
      maxPrice: maxPrice,
    );
    _runSearch();
  }

  // Update property types
  void updatePropertyTypes(List<ListingType> types) {
    _filters = _filters.copyWith(propertyTypes: types);
    _runSearch();
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
    _runSearch();
  }

  // Update amenities
  void updateAmenities(List<String> amenities) {
    _filters = _filters.copyWith(amenities: amenities);
    _runSearch();
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
    _runSearch();
  }

  // Clear all filters
  void clearFilters() {
    _filters = const SearchFilters();
    // No filters → drop results so Explore shows the default ranked feed.
    _searchToken++;
    _results = [];
    _error = null;
    _isSearching = false;
    _matchedRadiusMeters = null;
    _usedNearestFallback = false;
    notifyListeners();
  }

  // Clear specific filter categories
  void clearLocation() {
    _filters = _filters.copyWith(clearLocation: true);
    _runSearch();
  }

  void clearDates() {
    _filters = _filters.copyWith(clearDates: true);
    _runSearch();
  }

  void clearPriceRange() {
    _filters = _filters.copyWith(clearPriceRange: true);
    _runSearch();
  }

  /// Re-run the current search. Public entry point kept for callers that want
  /// to explicitly (re)trigger it.
  Future<void> search() => _runSearch();

  Future<void> _runSearch() async {
    final searcher = _searcher;
    // Nothing to filter by, or no backend wired → clear results; Explore then
    // shows the default feed.
    if (!_filters.hasActiveFilters || searcher == null) {
      _searchToken++;
      _results = [];
      _error = null;
      _isSearching = false;
      _matchedRadiusMeters = null;
      _usedNearestFallback = false;
      notifyListeners();
      return;
    }

    final token = ++_searchToken;
    _isSearching = true;
    _error = null;
    notifyListeners();

    try {
      final result = await searcher(_filters);
      if (token != _searchToken) return; // a newer search superseded this one
      _results = result.listings;
      _matchedRadiusMeters = result.matchedRadiusMeters;
      _usedNearestFallback = result.usedNearestFallback;
      _error = null;
    } catch (e) {
      if (token != _searchToken) return;
      _results = [];
      _matchedRadiusMeters = null;
      _usedNearestFallback = false;
      _error = e.toString();
    }

    if (token != _searchToken) return;
    _isSearching = false;
    notifyListeners();
  }
}
