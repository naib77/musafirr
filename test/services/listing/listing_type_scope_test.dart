import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/listing.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/models/turf_details.dart';
import 'package:musafir/services/listing/listing_type_scope.dart';

/// A host who has answered BOTH shapes' questions — which is exactly what form
/// state looks like after someone changes the type on page 1 and walks
/// forward again.
TypeScopedFields scopeFor(ListingType type) => scopeFieldsToType(
      type: type,
      turfDetails: const TurfDetails(
        sport: TurfSport.football,
        format: TurfFormat.seven,
        surface: TurfSurface.artificial,
      ),
      partyLimits: const PartyLimits(adults: 2, children: 1),
      bedrooms: 3,
      beds: 4,
      bathrooms: 2,
      petsAllowed: true,
      partiesAllowed: true,
    );

void main() {
  group('publishing a stay', () {
    // The load-bearing one. 121's listings_turf_fields_only_on_turf refuses
    // the whole INSERT with 23514 when a room carries a turf column, so this
    // is not tidiness — without it, a host who looked at "turf" and changed
    // their mind cannot save at all.
    test('clears every turf column', () {
      final scoped = scopeFor(ListingType.room);
      expect(scoped.turfDetails.sport, isNull);
      expect(scoped.turfDetails.format, isNull);
      expect(scoped.turfDetails.surface, isNull);
      expect(scoped.turfDetails.isEmpty, isTrue);
    });

    test('keeps the answers a stay actually owns', () {
      final scoped = scopeFor(ListingType.fullHouse);
      expect(scoped.bedrooms, 3);
      expect(scoped.beds, 4);
      expect(scoped.bathrooms, 2);
      expect(scoped.partyLimits.adults, 2);
      expect(scoped.petsAllowed, isTrue);
      expect(scoped.partiesAllowed, isTrue);
    });

    test('a seat is a stay too', () {
      expect(scopeFor(ListingType.seat).bedrooms, 3);
      expect(scopeFor(ListingType.seat).turfDetails.isEmpty, isTrue);
    });
  });

  group('publishing a turf', () {
    test('keeps what the host said about the ground', () {
      final scoped = scopeFor(ListingType.turf);
      expect(scoped.turfDetails.sport, TurfSport.football);
      expect(scoped.turfDetails.format, TurfFormat.seven);
      expect(scoped.turfDetails.surface, TurfSurface.artificial);
    });

    // Zero, not the model's default of 1: the listing card prints these, and
    // "1 bedroom · 1 bed" under a football pitch is a claim, not a blank.
    test('zeroes the room counts rather than leaving them at 1', () {
      final scoped = scopeFor(ListingType.turf);
      expect(scoped.bedrooms, 0);
      expect(scoped.beds, 0);
      expect(scoped.bathrooms, 0);
    });

    test('drops the party sub-caps', () {
      final scoped = scopeFor(ListingType.turf);
      expect(scoped.partyLimits.adults, isNull);
      expect(scoped.partyLimits.children, isNull);
      expect(scoped.partyLimits.infants, isNull);
      expect(scoped.partyLimits.pets, isNull);
    });

    // pets_allowed gates the whole pet branch of the search predicate (118),
    // so a stale `true` here does not merely look odd — it puts a football
    // pitch in the results for "somewhere that takes my dog".
    test('forces pets and parties off', () {
      final scoped = scopeFor(ListingType.turf);
      expect(scoped.petsAllowed, isFalse);
      expect(scoped.partiesAllowed, isFalse);
    });
  });

  // max_guests is the ONE capacity column, shared by both shapes — which is
  // why 121 added no players column. Scoping it would have been the bug.
  test('capacity survives either type unchanged', () {
    for (final type in ListingType.values) {
      final scoped = scopeFieldsToType(
        type: type,
        turfDetails: const TurfDetails(),
        partyLimits: const PartyLimits(),
        bedrooms: 1,
        beds: 1,
        bathrooms: 1,
        petsAllowed: false,
        partiesAllowed: false,
      );
      // Nothing in the scoped result can touch it; asserted by construction —
      // maxGuests is absent from TypeScopedFields entirely.
      expect(scoped.bedrooms, type.isStay ? 1 : 0);
    }
  });

  test('every listing type is covered, including ones added later', () {
    for (final type in ListingType.values) {
      final scoped = scopeFor(type);
      if (type.isStay) {
        expect(scoped.turfDetails.isEmpty, isTrue,
            reason: '$type is a stay and must carry no turf columns');
      } else {
        expect(scoped.bedrooms, 0,
            reason: '$type is not a stay and must claim no bedrooms');
      }
    }
  });
}
