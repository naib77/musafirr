import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/listing.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/widgets/search/search_services.dart';

/// The destination rows under the Where field used to count the whole
/// catalogue. With the search scoped to Turf that offered "Dhaka — 9 stays",
/// where the nine are rooms and seats: tapping the row and pressing Search
/// returned nothing, and the list had promised otherwise. The count has to
/// describe the search that is about to run.
void main() {
  Listing listingOf(String id, ListingType type, String city) => Listing(
        id: id,
        ownerName: 'Host',
        title: id,
        address: 'Road 1',
        type: type,
        latitude: 23.8,
        longitude: 90.4,
        dailyRate: 1500,
        facilities: const [],
        available: true,
        city: city,
      );

  final listings = [
    listingOf('r1', ListingType.room, 'Dhaka'),
    listingOf('r2', ListingType.room, 'Dhaka'),
    listingOf('s1', ListingType.seat, 'Dhaka'),
    listingOf('t1', ListingType.turf, 'Dhaka'),
    listingOf('t2', ListingType.turf, 'Chattogram'),
  ];

  group('listings offered in the dropdown', () {
    test('a turf search offers turfs, not places', () {
      final matches =
          listingSuggestionsFrom(listings, 'dha', [ListingType.turf]);

      expect(matches.map((l) => l.id), ['t1']);
    });

    test('matches the title as well as the area', () {
      // A guest typing "uttara" means the area and one typing the ground's
      // name means the ground; the field cannot tell which was intended.
      final byTitle = listingSuggestionsFrom(listings, 'r1');
      expect(byTitle.map((l) => l.id), ['r1']);
    });

    test('an empty query offers nothing', () {
      // The opening state of the panel is the city rows, not every listing.
      expect(listingSuggestionsFrom(listings, '   '), isEmpty);
    });

    test('a type with no listings yields no rows', () {
      expect(
        listingSuggestionsFrom(listings, 'dha', [ListingType.fullHouse]),
        isEmpty,
      );
    });

    test('capped at four so the place predictions stay reachable', () {
      final many = List.generate(
        9,
        (i) => listingOf('t$i', ListingType.turf, 'Dhaka'),
      );

      expect(listingSuggestionsFrom(many, 'dha').length, 4);
    });
  });

  test('an unscoped search counts everything', () {
    final dhaka = citySuggestionsFrom(listings, 'dha').single;

    expect(dhaka.count, 4);
    expect(dhaka.countLabel, '4 stays');
  });

  test('a turf search counts only turfs, and says so', () {
    final dhaka =
        citySuggestionsFrom(listings, 'dha', [ListingType.turf]).single;

    expect(dhaka.count, 1);
    expect(dhaka.countLabel, '1 turf');
  });

  test('a city with no turf drops out of a turf search', () {
    final cities = citySuggestionsFrom(listings, '', [ListingType.turf])
        .map((c) => c.city)
        .toList();

    expect(cities, containsAll(['Dhaka', 'Chattogram']));

    final roomCities = citySuggestionsFrom(listings, '', [ListingType.room])
        .map((c) => c.city)
        .toList();

    // Chattogram has only a turf, so a room search must not offer it.
    expect(roomCities, ['Dhaka']);
  });

  test('two types are not given a noun', () {
    // "3 rooms and turfs" is not a noun, so it falls back to the generic one
    // rather than naming whichever type happened to be first.
    final dhaka = citySuggestionsFrom(
      listings,
      'dha',
      [ListingType.room, ListingType.turf],
    ).single;

    expect(dhaka.count, 3);
    expect(dhaka.countLabel, '3 stays');
  });

  test('singular reads correctly', () {
    final chattogram =
        citySuggestionsFrom(listings, 'chat', [ListingType.turf]).single;

    expect(chattogram.countLabel, '1 turf');
  });
}
