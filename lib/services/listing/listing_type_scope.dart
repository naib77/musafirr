import '../../models/hotel_details.dart';
import '../../models/listing.dart';
import '../../models/listing_type.dart';
import '../../models/turf_details.dart';

/// The fields whose meaning depends on the listing's type, after the type has
/// had its say.
class TypeScopedFields {
  const TypeScopedFields({
    required this.turfDetails,
    required this.hotelDetails,
    required this.roomFacts,
    required this.partyLimits,
    required this.bedrooms,
    required this.beds,
    required this.bathrooms,
    required this.petsAllowed,
    required this.partiesAllowed,
  });

  final TurfDetails turfDetails;
  final HotelDetails hotelDetails;
  final RoomFacts roomFacts;
  final PartyLimits partyLimits;
  final int bedrooms;
  final int beds;
  final int bathrooms;
  final bool petsAllowed;
  final bool partiesAllowed;
}

/// Drops the answers that belong to the type the host is *not* publishing.
///
/// ## Why this exists rather than an `if` at each save
///
/// Both host screens hit the same trap: a host can pick "turf", answer the
/// sport, then go back and switch to "room" — or the reverse — and every
/// answer they gave under the old type is still sitting in form state. Sending
/// it is not untidy, it is **fatal to the save**: migration 121's
/// `listings_turf_fields_only_on_turf` refuses the whole INSERT/UPDATE with
/// `23514` if a non-turf row carries a `turf_sport`. The host sees a failure
/// they cannot act on, for a field the form no longer shows them.
///
/// Create and Edit are separate screens with separate save paths, so the rule
/// was written twice on the first pass. That is the duplication this
/// repository keeps paying for (see the availability and guest-counter notes
/// in CLAUDE.md), and it is worse than usual here because only one half of it
/// is reachable by the flow most hosts take — the create path — so a drift
/// would show up first as "editing this listing is broken".
///
/// ## What each direction clears, and why
///
/// * **Publishing a stay** clears the three turf columns. The database demands
///   it.
/// * **Publishing a turf** zeroes bedrooms/beds/bathrooms — they default to 1
///   in both the model and the column, and "1 bedroom" on a football pitch is
///   a lie the listing card would repeat — and clears the party sub-caps,
///   which are a question about who sleeps in a home.
/// * **Publishing a turf** also forces `petsAllowed` and `partiesAllowed`
///   off. These are not cosmetic: `pets_allowed` gates the entire pet filter
///   in `search_listings` (118), so a turf carrying a stale `true` would be
///   offered to someone searching for somewhere that takes their dog.
///
/// * **Publishing anything but a hotel** clears the hotel trio (150). Same
///   reason as turf: `listings_hotel_fields_only_on_hotel` refuses the row.
///   A hotel → room switch is the likely one — a guest house re-filed as
///   rooms — and the star rating it would otherwise carry is fatal.
/// * **Publishing a turf** clears the Room Matrix facts (150). The database
///   allows them on any type, but "attached bathroom, 180 sq ft" on a pitch
///   is the same lie as "1 bedroom". Every stay keeps them.
///
/// `maxGuests` is deliberately **not** scoped. It is the same column and the
/// same question for both — how many people fit — and a turf simply calls the
/// answer "players". That is why 121 added no capacity column of its own.
TypeScopedFields scopeFieldsToType({
  required ListingType type,
  required TurfDetails turfDetails,
  required HotelDetails hotelDetails,
  required RoomFacts roomFacts,
  required PartyLimits partyLimits,
  required int bedrooms,
  required int beds,
  required int bathrooms,
  required bool petsAllowed,
  required bool partiesAllowed,
}) {
  final isStay = type.isStay;
  return TypeScopedFields(
    turfDetails: isStay ? const TurfDetails() : turfDetails,
    hotelDetails:
        type == ListingType.hotel ? hotelDetails : const HotelDetails(),
    roomFacts: isStay ? roomFacts : const RoomFacts(),
    partyLimits: isStay ? partyLimits : const PartyLimits(),
    bedrooms: isStay ? bedrooms : 0,
    beds: isStay ? beds : 0,
    bathrooms: isStay ? bathrooms : 0,
    petsAllowed: isStay && petsAllowed,
    partiesAllowed: isStay && partiesAllowed,
  );
}
