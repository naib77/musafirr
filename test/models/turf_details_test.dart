import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/data/facility_catalog.dart';
import 'package:musafir/models/turf_details.dart';

void main() {
  group('wire values match the check constraints in migration 121', () {
    // These strings are not formatting — they are the exact vocabulary
    // `listings_turf_sport_valid` and friends accept. A rename here is refused
    // by the database with 23514 at save time, which is the worst place to
    // find out.
    test('sports serialise as their enum name', () {
      expect(TurfSport.values.map((s) => s.name).toList(), [
        'football',
        'cricket',
        'badminton',
        'basketball',
        'volleyball',
        'multi',
      ]);
    });

    // The one that does NOT use `name`: the constraint spells these with
    // hyphens, so TurfFormat.five must serialise as '5-a-side', not 'five'.
    test('formats serialise with the hyphenated spelling, not the enum name',
        () {
      expect(TurfFormat.values.map((f) => f.wireName).toList(), [
        '5-a-side',
        '6-a-side',
        '7-a-side',
        '9-a-side',
        '11-a-side',
        'other',
      ]);
      expect(TurfFormat.five.name, isNot(TurfFormat.five.wireName),
          reason: 'if these ever coincide the round-trip below stops proving '
              'anything');
    });

    test('surfaces serialise as their enum name', () {
      expect(TurfSurface.values.map((s) => s.name).toList(),
          ['artificial', 'natural', 'concrete', 'wooden', 'clay']);
    });
  });

  group('parsing back from the wire', () {
    test('every value round-trips', () {
      for (final v in TurfSport.values) {
        expect(turfSportFromWire(v.name), v);
      }
      for (final v in TurfFormat.values) {
        expect(turfFormatFromWire(v.wireName), v);
      }
      for (final v in TurfSurface.values) {
        expect(turfSurfaceFromWire(v.name), v);
      }
    });

    // A database that grows a sixth sport must not crash a build that predates
    // it — the same fail-soft rule _listingTypeFromString follows.
    test('an unknown value parses to null rather than throwing', () {
      expect(turfSportFromWire('kabaddi'), isNull);
      expect(turfFormatFromWire('3-a-side'), isNull);
      expect(turfSurfaceFromWire('astroturf'), isNull);
    });

    test('null stays null', () {
      expect(turfSportFromWire(null), isNull);
      expect(turfFormatFromWire(null), isNull);
      expect(turfSurfaceFromWire(null), isNull);
    });
  });

  group('copyWith treats null as a value, not as "unchanged"', () {
    // A host must be able to take a statement back OFF, not merely swap it for
    // a different wrong answer — the same reason PartyLimits carries explicit
    // clear flags and its stepper floors at "Any".
    test('clearSport removes a sport that was set', () {
      const d = TurfDetails(sport: TurfSport.cricket);
      expect(d.copyWith(clearSport: true).sport, isNull);
    });

    test('a plain copyWith leaves the others alone', () {
      const d = TurfDetails(
        sport: TurfSport.cricket,
        format: TurfFormat.eleven,
        surface: TurfSurface.natural,
      );
      final next = d.copyWith(sport: TurfSport.football);
      expect(next.sport, TurfSport.football);
      expect(next.format, TurfFormat.eleven);
      expect(next.surface, TurfSurface.natural);
    });

    test('clearing one does not clear the rest', () {
      const d = TurfDetails(
        sport: TurfSport.cricket,
        format: TurfFormat.eleven,
      );
      final next = d.copyWith(clearSport: true);
      expect(next.sport, isNull);
      expect(next.format, TurfFormat.eleven);
    });

    test('isEmpty only when nothing is stated', () {
      expect(const TurfDetails().isEmpty, isTrue);
      expect(const TurfDetails(surface: TurfSurface.clay).isEmpty, isFalse);
    });
  });

  group('the amenity catalog', () {
    // The bug this pins was nearly shipped: turfGroups reuses Parking,
    // Drinking Water, First Aid Kit, CCTV Security and Security Guard from the
    // stay groups, and the submit path filters ownerSelectable by the selected
    // NAMES. A plain concatenation therefore yields Parking twice, which
    // reaches listing_facilities as two identical rows and is refused by its
    // (listing_id, facility_id) unique index with 23505 — failing the entire
    // save because the host ticked a shared amenity.
    test('ownerSelectable holds no duplicate names', () {
      final names = FacilityCatalog.ownerSelectable.map((f) => f.name).toList();
      expect(names.toSet().length, names.length,
          reason: 'duplicates: '
              '${names.where((n) => names.where((m) => m == n).length > 1).toSet()}');
    });

    test('it still spans both shapes', () {
      final names = FacilityCatalog.ownerSelectable.map((f) => f.name).toSet();
      // A stay-only amenity and a turf-only one must both resolve, or changing
      // a listing's type would silently drop amenities it already carried.
      expect(names, contains('Wi-Fi'));
      expect(names, contains('Floodlights'));
    });

    test('the two shapes genuinely overlap, or the dedupe proves nothing', () {
      final stay = {
        for (final g in FacilityCatalog.groups)
          for (final f in g.facilities) f.name
      };
      final turf = {
        for (final g in FacilityCatalog.turfGroups)
          for (final f in g.facilities) f.name
      };
      expect(stay.intersection(turf), isNotEmpty);
    });

    test('groupsFor picks the right list', () {
      expect(FacilityCatalog.groupsFor(true), FacilityCatalog.groups);
      expect(FacilityCatalog.groupsFor(false), FacilityCatalog.turfGroups);
    });

    // Every name here must exist as a row in public.facilities or the amenity
    // silently fails to persist (_saveListingFacilities skips unknown names).
    // Migration 121 inserts exactly these seven.
    test('the turf-only amenities are the seven 121 inserts', () {
      final stay = {
        for (final g in FacilityCatalog.groups)
          for (final f in g.facilities) f.name
      };
      final turfOnly = [
        for (final g in FacilityCatalog.turfGroups)
          for (final f in g.facilities)
            if (!stay.contains(f.name)) f.name
      ];
      expect(turfOnly.toSet(), {
        'Floodlights',
        'Changing Room',
        'Showers',
        'Washroom',
        'Equipment Rental',
        'Covered Turf',
        'Spectator Seating',
      });
    });
  });
}
