import 'package:flutter/foundation.dart';

import '../../models/geo_bounds.dart';
import '../../models/listing_purpose.dart';
import '../../models/search_filters.dart';
import '../../models/voice_query.dart';
import '../../state/search_state.dart';
import '../geocoding_service.dart';
import 'remote_voice_parser.dart';

/// Runs a parsed voice query against the ordinary search stack.
///
/// The point of this class is what it does NOT do: it never invents
/// coordinates, never calls a new backend, and never bypasses
/// [SearchStateNotifier]. Voice is a different way to fill in the same
/// [SearchFilters] the search sheet fills in by hand, so it resolves the
/// spoken place through the same geocoder and hands the result to the same
/// notifier. Everything downstream — the RPC, the map framing, the empty
/// state — is code that already works.
class VoiceSearchRunner {
  const VoiceSearchRunner({
    required this.searchState,
    required this.isKnownCity,
    GeocodingService? geocoder,
    this.remoteParser = const RemoteVoiceParser(),
  }) : _geocoder = geocoder;

  final SearchStateNotifier searchState;

  /// Whether a name is a city we already stock listings in. Passed as a
  /// predicate rather than a repository because that is the entire dependency
  /// — handing the runner a whole repository would make it untestable without
  /// standing one up, for one boolean.
  final bool Function(String name) isKnownCity;

  final GeocodingService? _geocoder;

  /// Last resort when a spoken place will not geocode. Null disables it.
  final RemoteVoiceParser? remoteParser;

  GeocodingService get _geo => _geocoder ?? GeocodingService();

  /// Resolves [query]'s place and applies the whole thing as a search.
  ///
  /// Returns false when the query carried nothing actionable — the caller
  /// should say so rather than run an empty search, which returns the entire
  /// catalogue and reads as "voice search is broken".
  Future<bool> run(VoiceQuery query) async {
    if (query.isEmpty) return false;

    double? lat;
    double? lng;
    GeoBounds? bounds;

    var place = query.placeText;
    if (place != null && place.isNotEmpty) {
      var result = await _geo.geocode(place);

      // The canonical form is a heuristic — case-suffix stripping can guess
      // wrong on a place the alias table has never seen. Retrying the spoken
      // form costs one request and rescues exactly those cases.
      if (result == null && query.rawPlaceText != null) {
        result = await _geo.geocode(query.rawPlaceText!);
      }

      // Both spellings failed, so the lexicon's reading of the sentence was
      // wrong rather than merely unpolished. The model gets one attempt at a
      // place name Google will accept — this is the second and last place the
      // fallback is paid for, and only after two geocodes have already missed.
      if (result == null && remoteParser != null && !query.fromModel) {
        final better = await remoteParser!.parse(query.transcript);
        final rewritten = better?.placeText;
        if (rewritten != null && rewritten != place) {
          result = await _geo.geocode(rewritten);
          if (result != null) place = rewritten;
        }
      }

      if (result != null) {
        bounds = result.bounds;
        // Same priority the typed search uses: a box frames the real extent
        // of an area, a bare point only makes sense for somewhere that is not
        // already a city we stock listings in.
        if (bounds == null && !isKnownCity(place)) {
          lat = result.latitude;
          lng = result.longitude;
        }
      }
    }

    await searchState.updateFilters(
      searchState.filters.copyWith(
        location: place,
        clearLocation: place == null || place.isEmpty,
        latitude: lat,
        longitude: lng,
        clearCoordinates: lat == null || lng == null,
        bounds: bounds,
        clearBounds: bounds == null,
        propertyTypes: query.types,
        guestCount: query.guestCount ?? 1,
        maxPrice: query.maxPrice,
        // No ceiling spoken → drop whatever the last search left behind,
        // rather than silently applying it to a fresh spoken query.
        clearPriceRange: query.maxPrice == null,
        purposeTags:
            query.purpose == null ? const <ListingPurpose>[] : [query.purpose!],
        // A spoken query never carries a landmark, and leaving a stale one in
        // place would silently keep ranking by distance to the last hospital
        // the user picked by hand.
        clearLandmark: true,
      ),
    );

    // One line per spoken search, naming the stage that produced nothing.
    // "Voice search is not working" is four different failures wearing the
    // same face — heard nothing, parsed nothing, geocoded nothing, matched
    // nothing — and only the last two are invisible from the console
    // otherwise.
    if (kDebugMode) {
      final geo = place == null || place.isEmpty
          ? 'no place'
          : bounds != null
              ? 'box'
              : lat != null
                  ? 'point'
                  : 'name only (geocode miss)';
      debugPrint('[VoiceSearch] "${query.transcript}" -> place=$place '
          '($geo) types=${query.types.map((t) => t.name).toList()} '
          'guests=${query.guestCount} maxPrice=${query.maxPrice} '
          'purpose=${query.purpose?.name} '
          '=> ${searchState.results.length} result(s)');
    }
    return true;
  }
}

/// Records what was said and whether it parsed, so the lexicon can grow from
/// real Bangladeshi speech instead of guesswork.
///
/// This is the free stand-in for an LLM parser: misses accumulate in a table,
/// and adding the phrasings people actually used costs nothing but a weekly
/// read. Every failure path is swallowed — a logging outage must never break
/// a search the user is watching.
class VoiceSearchLogger {
  const VoiceSearchLogger(this._insert);

  /// Injected rather than reaching for Supabase directly, so tests can assert
  /// on what would be written without a network or a client.
  final Future<void> Function(Map<String, dynamic> row) _insert;

  /// Process-wide, so the "table is missing" note appears once per run rather
  /// than under every query.
  static bool _warnedMissingTable = false;

  @visibleForTesting
  static void resetWarnings() => _warnedMissingTable = false;

  Future<void> log({
    required VoiceQuery query,
    required String localeId,
    required bool parsed,
    required int resultCount,
  }) async {
    try {
      await _insert({
        'transcript': query.transcript,
        'locale_id': localeId,
        'parsed_place': query.placeText,
        'parsed_types': [for (final t in query.types) t.name],
        'parsed_purpose': query.purpose?.wireName,
        'parsed_guests': query.guestCount,
        'parsed_max_price': query.maxPrice,
        'parsed': parsed,
        'result_count': resultCount,
      });
    } catch (e) {
      // Said once, not once per search. A missing table is a setup step, not a
      // fault, and repeating it under every query made a working feature look
      // broken in the console.
      final missingTable = e.toString().contains('PGRST205');
      if (!missingTable) {
        debugPrint('[VoiceSearchLogger] insert failed (search unaffected): $e');
      } else if (!_warnedMissingTable) {
        _warnedMissingTable = true;
        debugPrint('[VoiceSearchLogger] voice_search_log table not found — '
            'telemetry off, voice search itself is unaffected. Apply '
            'supabase/migrations/096_voice_search_log.sql to start collecting '
            'the misses the lexicon grows from.');
      }
    }
  }
}
