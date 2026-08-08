import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/landmark.dart';

/// Free-text place search (Google Places, via the `places-search` edge
/// function) so guests can anchor a purpose search on ANY hospital / exam
/// center / attraction by name — not just the seeded `landmarks` rows.
///
/// Results come back as [Landmark]s with a synthetic `google:<place_id>` id;
/// the listing search only uses the landmark's coordinates, so they flow
/// through the same pipe as seeded landmarks.
class PlacesService {
  static final PlacesService _instance = PlacesService._internal();
  factory PlacesService() => _instance;
  PlacesService._internal();

  Future<List<Landmark>> searchPlaces(String query, {String? type}) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'places-search',
        body: {'query': q, if (type != null) 'type': type},
      );
      final data = res.data;
      if (data is! Map || data['results'] is! List) return const [];
      return (data['results'] as List)
          .whereType<Map>()
          .where(
              (r) => r['name'] is String && r['lat'] is num && r['lng'] is num)
          .map((r) => Landmark(
                id: 'google:${r['place_id'] ?? ''}',
                name: r['name'] as String,
                type: type ?? '',
                area: (r['label'] as String?)?.isEmpty ?? true
                    ? null
                    : r['label'] as String?,
                latitude: (r['lat'] as num).toDouble(),
                longitude: (r['lng'] as num).toDouble(),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
