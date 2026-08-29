import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/search_area_settings.dart';

/// The search radius used to be hardcoded (`[1000,3000,5000,10000]` and a
/// 15 km landmark ring). It is now typed by an admin into a text box, which
/// means the parser is the only thing standing between a typo and a search
/// that silently returns nothing. Every malformed input below must degrade to
/// something searchable rather than to an empty ring set.
void main() {
  group('radius tiers', () {
    test('parses the normal comma-separated form', () {
      final s = SearchAreaSettings.fromRaw(tiers: '1000,3000,5000,10000');
      expect(s.radiusTiersMeters, [1000, 3000, 5000, 10000]);
    });

    test('tolerates spaces and a trailing comma', () {
      final s = SearchAreaSettings.fromRaw(tiers: ' 1000 , 3000 ,5000, ');
      expect(s.radiusTiersMeters, [1000, 3000, 5000]);
    });

    test('sorts ascending — the RPC takes the smallest matching tier', () {
      // Order is load-bearing server-side; an admin typing them out of order
      // must not change which ring wins.
      final s = SearchAreaSettings.fromRaw(tiers: '10000,1000,5000');
      expect(s.radiusTiersMeters, [1000, 5000, 10000]);
    });

    test('drops duplicates', () {
      final s = SearchAreaSettings.fromRaw(tiers: '1000,1000,3000');
      expect(s.radiusTiersMeters, [1000, 3000]);
    });

    test('drops junk entries but keeps the usable ones', () {
      final s = SearchAreaSettings.fromRaw(tiers: '1000,abc,3000,,-5,0');
      expect(s.radiusTiersMeters, [1000, 3000]);
    });

    test('falls back to the defaults when nothing usable remains', () {
      for (final raw in ['', '   ', 'abc', '0', '-1', ',,,']) {
        expect(
          SearchAreaSettings.fromRaw(tiers: raw).radiusTiersMeters,
          SearchAreaSettings.defaults.radiusTiersMeters,
          reason: '"$raw" must not leave the search with zero rings',
        );
      }
    });

    test('a missing setting uses the defaults', () {
      expect(
        SearchAreaSettings.fromRaw().radiusTiersMeters,
        [1000, 3000, 5000, 10000],
      );
    });

    test('clamps absurd values instead of discarding them', () {
      // 1 m would match nothing; 5000 km would match the whole country. Clamp
      // to the searchable band rather than dropping the tier, so an admin who
      // fat-fingers a zero still gets a working search.
      final s = SearchAreaSettings.fromRaw(tiers: '1,50000000');
      expect(s.radiusTiersMeters.first, SearchAreaSettings.minRadiusMeters);
      expect(s.radiusTiersMeters.last, SearchAreaSettings.maxRadiusMeters);
    });

    test('caps how many tiers are accepted', () {
      final s = SearchAreaSettings.fromRaw(
        tiers: '1000,2000,3000,4000,5000,6000,7000,8000,9000',
      );
      expect(
        s.radiusTiersMeters.length,
        lessThanOrEqualTo(SearchAreaSettings.maxTiers),
      );
      // The widest ring must survive the cap — losing it would shrink the
      // search area, which is the opposite of what the admin asked for.
      expect(s.radiusTiersMeters.last, 9000);
    });
  });

  group('landmark ring', () {
    test('parses a plain integer', () {
      expect(
        SearchAreaSettings.fromRaw(landmarkRadius: '8000').landmarkRadiusMeters,
        8000,
      );
    });

    test('falls back to the default when unusable', () {
      for (final raw in ['', 'abc', '0', '-1']) {
        expect(
          SearchAreaSettings.fromRaw(landmarkRadius: raw).landmarkRadiusMeters,
          SearchAreaSettings.defaults.landmarkRadiusMeters,
          reason: '"$raw" must leave the landmark ring searchable',
        );
      }
    });

    test('clamps to the searchable band', () {
      expect(
        SearchAreaSettings.fromRaw(landmarkRadius: '1').landmarkRadiusMeters,
        SearchAreaSettings.minRadiusMeters,
      );
      expect(
        SearchAreaSettings.fromRaw(landmarkRadius: '99999999')
            .landmarkRadiusMeters,
        SearchAreaSettings.maxRadiusMeters,
      );
    });

    test('defaults to the 15 km ring the app shipped with', () {
      expect(SearchAreaSettings.defaults.landmarkRadiusMeters, 15000);
    });
  });
}
