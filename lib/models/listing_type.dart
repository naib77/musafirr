enum ListingType { seat, room, fullHouse }

extension ListingTypeLabel on ListingType {
  String get title => switch (this) {
        ListingType.seat => 'Seat',
        ListingType.room => 'Room',
        ListingType.fullHouse => 'Full House',
      };
}
