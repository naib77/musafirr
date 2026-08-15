import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/geo_bounds.dart';
import '../models/landmark.dart';

/// A Google Places Autocomplete prediction — a name to show in the picker.
/// Has no coordinates yet; call [PlacesService.resolve] on selection.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.name,
    required this.label,
  });

  final String placeId;
  final String name;

  /// Secondary line ("Garib-E-Newaz Avenue, Dhaka").
  final String label;
}

/// A chosen prediction resolved to coordinates — enough to move a map there.
class PlaceLocation {
  const PlaceLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.label,
    this.bounds,
  });

  final String name;

  /// Secondary line ("Garib-E-Newaz Avenue, Dhaka"), when Google gives one.
  final String? label;

  final double latitude;
  final double longitude;

  /// The place's extent, when it's an area (a thana, a residential block)
  /// rather than a precise point. Present → the search bar covers exactly this
  /// area instead of a fixed radius ring around its center.
  final GeoBounds? bounds;
}

/// Google-Maps-style type-ahead for the landmark picker (via the
/// `places-search` edge function): three letters of "lub" already suggest
/// Lubana General Hospital — guests aren't limited to seeded `landmarks` rows.
///
/// Two steps, matching Google's API shape: [suggest] returns name-only
/// predictions as the guest types; [resolve] fetches coordinates for the
/// chosen one and packages it as a [Landmark] (synthetic `google:<place_id>`
/// id) so it flows through the same search pipe as seeded landmarks.
class PlacesService {
  static final PlacesService _instance = PlacesService._internal();
  factory PlacesService() => _instance;
  PlacesService._internal();

  /// [establishmentsOnly] limits predictions to POIs (landmark picker); the
  /// main search bar passes false so areas and addresses predict too.
  ///
  /// [category] is the landmark category being picked (`hospital`,
  /// `exam_center`, `university`, `tourist_spot`, `business_hub`) and limits
  /// suggestions to places of that kind — a Medical search never suggests
  /// restaurants. Which Google place types each category means is decided by
  /// the `places-search` function, so it can be corrected without an app
  /// release; the client only names the category.
  Future<List<PlaceSuggestion>> suggest(
    String query, {
    bool establishmentsOnly = true,
    String? category,
  }) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'places-search',
        body: {
          'query': q,
          if (!establishmentsOnly) 'scope': 'all',
          if (category != null && category.isNotEmpty) 'category': category,
        },
      );
      final data = res.data;
      if (data is! Map || data['results'] is! List) return const [];
      return (data['results'] as List)
          .whereType<Map>()
          .where((r) => r['name'] is String && r['place_id'] is String)
          .map((r) => PlaceSuggestion(
                placeId: r['place_id'] as String,
                name: r['name'] as String,
                label: r['label'] as String? ?? '',
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Coordinates for a chosen prediction. The picker on the host's listing
  /// form needs only this much; [resolve] wraps it as a searchable [Landmark].
  Future<PlaceLocation?> locate(PlaceSuggestion s) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'places-search',
        body: {'place_id': s.placeId},
      );
      final data = res.data;
      if (data is! Map || data['found'] != true) return null;
      return PlaceLocation(
        name: (data['name'] as String?)?.isNotEmpty == true
            ? data['name'] as String
            : s.name,
        label: (data['label'] as String?)?.isNotEmpty == true
            ? data['label'] as String?
            : (s.label.isEmpty ? null : s.label),
        latitude: (data['lat'] as num).toDouble(),
        longitude: (data['lng'] as num).toDouble(),
        bounds: GeoBounds.fromJson(data['bounds']),
      );
    } catch (_) {
      return null;
    }
  }

  Future<Landmark?> resolve(PlaceSuggestion s, {required String type}) async {
    final place = await locate(s);
    if (place == null) return null;
    return Landmark(
      id: 'google:${s.placeId}',
      name: place.name,
      type: type,
      area: place.label,
      latitude: place.latitude,
      longitude: place.longitude,
    );
  }
}
