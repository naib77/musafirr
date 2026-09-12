/// What kind of space a listing is.
///
/// The `name` of each value is the wire value: it is written straight into
/// `listings.listing_type` (a Postgres enum, migrations 001 and 120) and sent
/// as-is in `search_listings`'s `p_property_types`. Renaming one silently
/// orphans every row already stored under the old spelling.
enum ListingType { seat, room, fullHouse, turf }

extension ListingTypeLabel on ListingType {
  String get title => switch (this) {
        ListingType.seat => 'Seat',
        ListingType.room => 'Room',
        ListingType.fullHouse => 'Full House',
        ListingType.turf => 'Turf',
      };

  /// True when the listing is a place someone *stays* in, as opposed to a
  /// space booked for a slot and left.
  ///
  /// This is the one distinction worth naming, because it is what decides
  /// whether bedrooms, beds, bathrooms, check-in times, wifi codes and the
  /// adults/children/infants/pets breakdown mean anything at all. Asking
  /// `type.isStay` at each of those sites keeps the question in one place; a
  /// scattering of `type == ListingType.turf` would have to be revisited in
  /// full the first time a second non-stay type (a court, a hall) is added.
  bool get isStay => this != ListingType.turf;

  /// What this listing type calls the people a booking brings.
  ///
  /// A turf holds players, not guests, and `max_guests` is the column behind
  /// both — the same "how many fit" question, which is why turf needed no
  /// capacity column of its own in 121.
  String get occupantNoun => switch (this) {
        ListingType.turf => 'player',
        _ => 'guest',
      };
}
