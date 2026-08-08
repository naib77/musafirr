import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<List<PlaceSuggestion>> suggest(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'places-search',
        body: {'query': q},
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

  Future<Landmark?> resolve(PlaceSuggestion s, {required String type}) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'places-search',
        body: {'place_id': s.placeId},
      );
      final data = res.data;
      if (data is! Map || data['found'] != true) return null;
      return Landmark(
        id: 'google:${s.placeId}',
        name: (data['name'] as String?)?.isNotEmpty == true
            ? data['name'] as String
            : s.name,
        type: type,
        area: (data['label'] as String?)?.isNotEmpty == true
            ? data['label'] as String?
            : (s.label.isEmpty ? null : s.label),
        latitude: (data['lat'] as num).toDouble(),
        longitude: (data['lng'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}
