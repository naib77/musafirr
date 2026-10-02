import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/hotel_details.dart';
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
      hotelDetails: const HotelDetails(
        starRating: 3,
        frontDesk24h: true,
        idRequired: true,
      ),
      roomFacts: const RoomFacts(
        sizeSqft: 180,
        bathroom: BathroomKind.attached,
        toilet: ToiletKind.commode,
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
        hotelDetails: const HotelDetails(),
        roomFacts: const RoomFacts(),
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
      // 150's listings_hotel_fields_only_on_hotel: the other way round from
      // turf, only ONE type may carry these, so it is checked for every type.
      expect(scoped.hotelDetails.isEmpty, type != ListingType.hotel,
          reason: '$type: hotel fields kept only on a hotel');
    }
  });

  group('the hotel fields (150)', () {
    test('a hotel keeps its stars, desk and ID answers', () {
      final h = scopeFor(ListingType.hotel).hotelDetails;
      expect(h.starRating, 3);
      expect(h.frontDesk24h, isTrue);
      expect(h.idRequired, isTrue);
    });

    // The realistic switch: a guest house re-filed as rooms. A star rating
    // left behind is a 23514 the host cannot see or fix.
    test('a hotel re-filed as a room drops them', () {
      expect(scopeFor(ListingType.room).hotelDetails.isEmpty, isTrue);
    });

    test('a hotel is a stay: no turf columns, rooms kept', () {
      final s = scopeFor(ListingType.hotel);
      expect(s.turfDetails.isEmpty, isTrue);
      expect(s.bedrooms, 3);
    });

    // Room Matrix facts describe any stay; only a pitch sheds them.
    test('room facts survive every stay type and clear on a turf', () {
      for (final type in ListingType.values) {
        expect(scopeFor(type).roomFacts.isEmpty, !type.isStay, reason: '$type');
      }
    });
  });

  group('RoomFacts / HotelDetails wire', () {
    test('round-trips through the column names', () {
      const facts = RoomFacts(
          sizeSqft: 250,
          bathroom: BathroomKind.common,
          toilet: ToiletKind.indian);
      final back = RoomFacts.fromJson(facts.toJson());
      expect(back.sizeSqft, 250);
      expect(back.bathroom, BathroomKind.common);
      expect(back.toilet, ToiletKind.indian);
      const hotel = HotelDetails(starRating: 4, frontDesk24h: false);
      final h = HotelDetails.fromJson(hotel.toJson());
      expect(h.starRating, 4);
      expect(h.frontDesk24h, isFalse);
      expect(h.idRequired, isNull);
    });

    // Always all keys, nulls included: that is how a switch away from hotel
    // clears the columns in the same write.
    test('an empty value still writes every key, as null', () {
      expect(const HotelDetails().toJson(), {
        'hotel_star_rating': null,
        'hotel_front_desk_24h': null,
        'hotel_id_required': null,
      });
      expect(const RoomFacts().toJson().keys,
          ['size_sqft', 'bathroom_kind', 'toilet_kind']);
    });

    test('values the constraints forbid read as unstated', () {
      expect(
          HotelDetails.fromJson({'hotel_star_rating': 7}).starRating, isNull);
      expect(RoomFacts.fromJson({'size_sqft': 0}).sizeSqft, isNull);
      expect(RoomFacts.fromJson({'toilet_kind': 'bucket'}).toilet, isNull);
      // A database without 150: no keys at all.
      expect(HotelDetails.fromJson(const {}).isEmpty, isTrue);
      expect(RoomFacts.fromJson(const {}).isEmpty, isTrue);
    });

    test('the host size field: blank is fine, junk is an error', () {
      expect(RoomFacts.parseSize(''), isNull);
      expect(RoomFacts.sizeError(''), isNull);
      expect(RoomFacts.parseSize(' 180 '), 180);
      expect(RoomFacts.sizeError('180'), isNull);
      expect(RoomFacts.sizeError('0'), isNotNull);
      expect(RoomFacts.sizeError('20001'), isNotNull);
      expect(RoomFacts.sizeError('12.5'), isNotNull);
      expect(RoomFacts.sizeError('big'), isNotNull);
    });
  });
}
