import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/geo_bounds.dart';
import 'package:musafir/models/listing_purpose.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/models/search_filters.dart';
import 'package:musafir/models/voice_query.dart';
import 'package:musafir/models/landmark.dart';
import 'package:musafir/repositories/musafir_repository.dart';
import 'package:musafir/services/geocoding_service.dart';
import 'package:musafir/services/voice/remote_voice_parser.dart';
import 'package:musafir/services/voice/voice_search_runner.dart';
import 'package:musafir/state/search_state.dart';

/// Records what the geocoder was asked for and hands back a scripted answer,
/// so the runner's place-resolution priority can be asserted without network.
class _FakeGeocoder implements GeocodingService {
  _FakeGeocoder(this.answers);

  final Map<String, GeocodeResult?> answers;
  final List<String> asked = [];

  @override
  Future<GeocodeResult?> geocode(String query) async {
    asked.add(query);
    return answers[query];
  }

  @override
  Future<String?> reverse(double latitude, double longitude) async => null;
}

GeocodeResult _result({GeoBounds? bounds}) => GeocodeResult(
      latitude: 23.74,
      longitude: 90.37,
      label: 'Dhanmondi',
      bounds: bounds,
    );

void main() {
  // SafeNotifier defers notifications through the scheduler, so the binding
  // has to exist before any notifier fires.
  TestWidgetsFlutterBinding.ensureInitialized();

  late SearchStateNotifier searchState;
  late List<SearchFilters> applied;

  setUp(() {
    searchState = SearchStateNotifier();
    applied = [];
    // Capture what the runner asks the search stack for, without running the
    // real RPC. The searcher is the notifier's only outbound dependency.
    searchState.attachSearcher((filters) async {
      applied.add(filters);
      return const ListingSearchResult(listings: []);
    });
  });

  /// No city is "known" by default, so the point-vs-box branch is exercised;
  /// the one test that cares passes its own predicate.
  VoiceSearchRunner runnerWith(
    _FakeGeocoder geocoder, {
    bool Function(String)? isKnownCity,
  }) =>
      VoiceSearchRunner(
        searchState: searchState,
        isKnownCity: isKnownCity ?? (_) => false,
        geocoder: geocoder,
        // Offline: the Gemini fallback has its own tests.
        remoteParser: null,
      );

  test('refuses a query with nothing in it', () async {
    final geocoder = _FakeGeocoder({});
    final ran = await runnerWith(geocoder)
        .run(const VoiceQuery(transcript: 'kichu ekta'));

    expect(ran, isFalse);
    expect(geocoder.asked, isEmpty);
    expect(applied, isEmpty, reason: 'an empty query must not search at all');
  });

  test('prefers a place box over a bare point', () async {
    const bounds = GeoBounds(
      swLat: 23.73,
      swLng: 90.36,
      neLat: 23.76,
      neLng: 90.39,
    );
    final geocoder = _FakeGeocoder({'Dhanmondi': _result(bounds: bounds)});

    final ran = await runnerWith(geocoder).run(const VoiceQuery(
      transcript: 'dhanmondir dike basa',
      placeText: 'Dhanmondi',
      types: [ListingType.fullHouse],
    ));

    expect(ran, isTrue);
    expect(applied, hasLength(1));
    expect(applied.single.bounds, bounds);
    expect(applied.single.latitude, isNull,
        reason: 'a box already frames the area; a point would fight it');
    expect(applied.single.propertyTypes, [ListingType.fullHouse]);
    expect(applied.single.location, 'Dhanmondi');
  });

  test('falls back to a point when the place has no box', () async {
    final geocoder = _FakeGeocoder({'Kushtia': _result()});

    await runnerWith(geocoder).run(const VoiceQuery(
      transcript: 'kushtia te basa',
      placeText: 'Kushtia',
      types: [ListingType.fullHouse],
    ));

    expect(applied.single.latitude, 23.74);
    expect(applied.single.longitude, 90.37);
    expect(applied.single.bounds, isNull);
  });

  test('keeps a known city as a text search rather than a point', () async {
    final geocoder = _FakeGeocoder({'Dhaka': _result()});

    await runnerWith(geocoder, isKnownCity: (n) => n == 'Dhaka').run(
      const VoiceQuery(
        transcript: 'dhaka basa',
        placeText: 'Dhaka',
        types: [ListingType.fullHouse],
      ),
    );

    expect(applied.single.location, 'Dhaka');
    expect(applied.single.latitude, isNull,
        reason: 'a point in the middle of Dhaka would exclude most of Dhaka');
  });

  test('retries the spoken form when the canonical form misses', () async {
    // Suffix stripping is a heuristic; this is the path that rescues it.
    final geocoder = _FakeGeocoder({
      'Banan': null,
      'banani': _result(),
    });

    await runnerWith(geocoder).run(const VoiceQuery(
      transcript: 'banani te room',
      placeText: 'Banan',
      rawPlaceText: 'banani',
      types: [ListingType.room],
    ));

    expect(geocoder.asked, ['Banan', 'banani']);
    expect(applied.single.latitude, 23.74);
  });

  test('does not retry when there is no distinct spoken form', () async {
    final geocoder = _FakeGeocoder({'Nowhere': null});

    await runnerWith(geocoder).run(const VoiceQuery(
      transcript: 'nowhere basa',
      placeText: 'Nowhere',
      types: [ListingType.fullHouse],
    ));

    expect(geocoder.asked, ['Nowhere']);
  });

  test('still searches when the place cannot be resolved at all', () async {
    final geocoder = _FakeGeocoder({'Nowhere': null});

    final ran = await runnerWith(geocoder).run(const VoiceQuery(
      transcript: 'nowhere basa',
      placeText: 'Nowhere',
      types: [ListingType.fullHouse],
    ));

    // Text-only search is a real fallback — the RPC matches on city name too.
    expect(ran, isTrue);
    expect(applied.single.location, 'Nowhere');
    expect(applied.single.latitude, isNull);
    expect(applied.single.bounds, isNull);
  });

  test('carries guests, price and purpose through', () async {
    final geocoder = _FakeGeocoder({'Uttara': _result()});

    await runnerWith(geocoder).run(const VoiceQuery(
      transcript: 'uttara 2 jon 5 hajar taka room hospital er kache',
      placeText: 'Uttara',
      types: [ListingType.room],
      guestCount: 2,
      maxPrice: 5000,
      purpose: ListingPurpose.medical,
    ));

    final f = applied.single;
    expect(f.guestCount, 2);
    expect(f.maxPrice, 5000);
    expect(f.purposeTags, [ListingPurpose.medical]);
  });

  test('clears a stale landmark from the previous search', () async {
    final geocoder = _FakeGeocoder({'Mirpur': _result()});
    searchState.updateFilters(
      const SearchFilters(
        landmark: Landmark(
          id: 'l1',
          name: 'Square Hospital',
          type: 'hospital',
          latitude: 23.75,
          longitude: 90.38,
        ),
        radiusMeters: 15000,
      ),
    );
    applied.clear();

    await runnerWith(geocoder).run(const VoiceQuery(
      transcript: 'mirpur e room',
      placeText: 'Mirpur',
      types: [ListingType.room],
    ));

    expect(applied.single.landmark, isNull,
        reason: 'a spoken query names no landmark, so ranking by distance to '
            'the last one silently distorts the results');
    expect(applied.single.radiusMeters, isNull);
  });

  test('drops a price ceiling left over from a previous search', () async {
    final geocoder = _FakeGeocoder({'Mirpur': _result()});
    searchState.updateFilters(const SearchFilters(maxPrice: 2000));
    applied.clear();

    await runnerWith(geocoder).run(const VoiceQuery(
      transcript: 'mirpur e room',
      placeText: 'Mirpur',
      types: [ListingType.room],
    ));

    expect(applied.single.maxPrice, isNull);
  });

  test('resets the guest count when none was spoken', () async {
    final geocoder = _FakeGeocoder({'Mirpur': _result()});
    searchState.updateFilters(const SearchFilters(guestCount: 6));
    applied.clear();

    await runnerWith(geocoder).run(const VoiceQuery(
      transcript: 'mirpur e room',
      placeText: 'Mirpur',
      types: [ListingType.room],
    ));

    expect(applied.single.guestCount, 1);
  });

  group('the Gemini fallback is rationed', () {
    test('is asked once when the lexicon place will not geocode', () async {
      var calls = 0;
      final searchState = SearchStateNotifier();
      final runner = VoiceSearchRunner(
        searchState: searchState,
        isKnownCity: (_) => false,
        geocoder: _FakeGeocoder(const {}),
        remoteParser: RemoteVoiceParser(invoke: (_) async {
          calls++;
          return {'parsed': true, 'place': 'Dhanmondi 32', 'types': <String>[]};
        }),
      );

      await runner.run(const VoiceQuery(
        transcript: 'dhanmondi bottris',
        placeText: 'Dhanmondi bottris',
      ));
      expect(calls, 1);
    });

    test('is not asked again about a sentence it already answered', () async {
      // The sheet's fallback already ran and produced this query. Asking the
      // same model the same sentence returns the same place, so a second call
      // is a guaranteed-useless charge against the rate limit.
      var calls = 0;
      final searchState = SearchStateNotifier();
      final runner = VoiceSearchRunner(
        searchState: searchState,
        isKnownCity: (_) => false,
        geocoder: _FakeGeocoder(const {}),
        remoteParser: RemoteVoiceParser(invoke: (_) async {
          calls++;
          return {'parsed': true, 'place': 'Dhanmondi 32', 'types': <String>[]};
        }),
      );

      await runner.run(const VoiceQuery(
        transcript: 'dhanmondi bottris',
        placeText: 'Dhanmondi 32',
        fromModel: true,
      ));
      expect(calls, 0);
    });
  });

  group('VoiceSearchLogger', () {
    test('records the transcript and what came out of it', () async {
      Map<String, dynamic>? row;
      final logger = VoiceSearchLogger((r) async => row = r);

      await logger.log(
        query: const VoiceQuery(
          transcript: 'dhanmondir dike basa khojo',
          placeText: 'Dhanmondi',
          types: [ListingType.fullHouse],
        ),
        localeId: 'bn-BD',
        parsed: true,
        resultCount: 7,
      );

      expect(row!['transcript'], 'dhanmondir dike basa khojo');
      expect(row!['parsed_place'], 'Dhanmondi');
      expect(row!['parsed_types'], ['fullHouse']);
      expect(row!['locale_id'], 'bn-BD');
      expect(row!['parsed'], isTrue);
      expect(row!['result_count'], 7);
    });

    test('swallows a logging failure', () async {
      final logger = VoiceSearchLogger((_) async => throw Exception('offline'));

      // The point: a logging outage must never surface to someone who is just
      // trying to search.
      await expectLater(
        logger.log(
          query: const VoiceQuery(transcript: 'x'),
          localeId: 'en-US',
          parsed: false,
          resultCount: 0,
        ),
        completes,
      );
    });

    test('a missing table is survivable and announced only once', () async {
      VoiceSearchLogger.resetWarnings();
      var attempts = 0;
      // What PostgREST returns when the migration has not been applied.
      final logger = VoiceSearchLogger((_) async {
        attempts++;
        throw Exception("PostgrestException(message: Could not find the table "
            "'public.voice_search_log' in the schema cache, code: PGRST205)");
      });

      final lines = <String>[];
      final previous = debugPrint;
      debugPrint =
          (String? message, {int? wrapWidth}) => lines.add(message ?? '');
      try {
        for (var i = 0; i < 3; i++) {
          await logger.log(
            query: const VoiceQuery(transcript: 'dhanmondi'),
            localeId: 'bn-BD',
            parsed: true,
            resultCount: 4,
          );
        }
      } finally {
        debugPrint = previous;
      }

      // Every search still tried to log, and none of them threw...
      expect(attempts, 3);
      // ...but the console said so once. Repeating it under every query is
      // what made a working feature look broken.
      expect(lines.where((l) => l.contains('voice_search_log')), hasLength(1));
      expect(lines.single, contains('voice search itself is unaffected'));
    });
  });
}
