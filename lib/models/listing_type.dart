enum ListingType { seat, room, fullHouse }

extension ListingTypeLabel on ListingType {
  String get title => switch (this) {
        ListingType.seat => 'Seat',
        ListingType.room => 'Room',
        ListingType.fullHouse => 'Full House',
      };

  /// What one unit of this listing is, for prices read as prose:
  /// "from ৳500/hr/seat". Lower-case because it sits mid-phrase.
  String get priceUnit => switch (this) {
        ListingType.seat => 'seat',
        ListingType.room => 'room',
        ListingType.fullHouse => 'full house',
      };
}
