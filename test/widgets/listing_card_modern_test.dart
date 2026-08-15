import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/listing.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/widgets/listing_card_modern.dart';

/// The Explore card carries the listing type (plus "Guest favorite" when
/// earned) on the photo, and up to two rates with the rating underneath.
/// A rate is never shown in both places.
///
/// Positions are only ever asserted *relative to each other*: the test font
/// draws every glyph as a fixed-width square, so text boxes measure far wider
/// here than on a device and edge-relative assertions would be meaningless.
void main() {
  Listing listingOf(
    ListingType type, {
    double? hourly,
    double? daily,
    double? monthly,
    double? rating,
    int reviewCount = 0,
    double? distanceMeters,
  }) {
    return Listing(
      id: 'l1',
      ownerName: 'Host',
      title: 'A place',
      address: 'Road 1, Dhaka',
      type: type,
      latitude: 23.8,
      longitude: 90.4,
      hourlyRate: hourly,
      dailyRate: daily,
      monthlyRate: monthly,
      facilities: const [],
      available: true,
      city: 'Dhaka',
      rating: rating,
      reviewCount: reviewCount,
      bedrooms: 2,
      maxGuests: 4,
      distanceMeters: distanceMeters,
    );
  }

  Widget wrap(Listing listing) {
    return MaterialApp(
      home: Scaffold(
        // A realistic two-column grid cell, so long labels have to fit the
        // same width they do on a phone.
        body: Center(
          child: SizedBox(
            width: 160,
            height: 230,
            child: ListingCardModern(
              listing: listing,
              isFavorite: false,
              onTap: () {},
              onFavoriteTap: () {},
            ),
          ),
        ),
      ),
    );
  }

  group('photo badge', () {
    testWidgets('names the listing type', (tester) async {
      await tester.pumpWidget(wrap(listingOf(ListingType.room, hourly: 300)));

      expect(find.textContaining('Room'), findsOneWidget);
      // Exactly once on the whole card: the rate used to appear both on the
      // photo and under it, which is what this badge replaced.
      expect(find.textContaining('৳300'), findsOneWidget);
    });

    testWidgets('adds "Guest favorite" only when earned', (tester) async {
      await tester.pumpWidget(wrap(
        listingOf(ListingType.room, hourly: 300, rating: 4.9, reviewCount: 20),
      ));

      expect(find.textContaining('Guest favorite'), findsOneWidget);
      expect(find.textContaining('Room'), findsOneWidget);
    });

    testWidgets('a great rating from too few reviews does not earn it',
        (tester) async {
      await tester.pumpWidget(wrap(
        listingOf(ListingType.room, hourly: 300, rating: 5.0, reviewCount: 2),
      ));

      expect(find.textContaining('Guest favorite'), findsNothing);
      expect(find.textContaining('Room'), findsOneWidget);
    });

    testWidgets('many reviews at a mediocre rating do not earn it',
        (tester) async {
      await tester.pumpWidget(wrap(
        listingOf(ListingType.seat, hourly: 300, rating: 4.4, reviewCount: 90),
      ));

      expect(find.textContaining('Guest favorite'), findsNothing);
    });

    testWidgets('longest label still clears the favourite button',
        (tester) async {
      await tester.pumpWidget(wrap(listingOf(
        ListingType.fullHouse,
        monthly: 45000,
        rating: 4.9,
        reviewCount: 30,
      )));

      expect(tester.takeException(), isNull);
      final badge = tester.getRect(
        find
            .ancestor(
              of: find.textContaining('Guest favorite'),
              matching: find.byType(Container),
            )
            .first,
      );
      final heart = tester.getRect(find.byIcon(Icons.favorite_border));
      expect(badge.right, lessThan(heart.left));
    });
  });

  group('two lines under the photo', () {
    testWidgets('all three rates offered → hourly and daily', (tester) async {
      await tester.pumpWidget(wrap(
        listingOf(ListingType.room, hourly: 300, daily: 1500, monthly: 35000),
      ));

      expect(find.text('৳300/hr · ৳1.5K/day'), findsOneWidget);
      expect(find.textContaining('35K'), findsNothing);
    });

    testWidgets('no daily → hourly and monthly', (tester) async {
      await tester.pumpWidget(wrap(
        listingOf(ListingType.room, hourly: 300, monthly: 35000),
      ));

      expect(find.text('৳300/hr · ৳35K/mo'), findsOneWidget);
    });

    testWidgets('no hourly → daily and monthly', (tester) async {
      await tester.pumpWidget(wrap(
        listingOf(ListingType.room, daily: 1500, monthly: 35000),
      ));

      expect(find.text('৳1.5K/day · ৳35K/mo'), findsOneWidget);
    });

    testWidgets('a single offered rate shows alone', (tester) async {
      await tester.pumpWidget(
        wrap(listingOf(ListingType.fullHouse, daily: 1500)),
      );

      expect(find.text('৳1.5K/day'), findsOneWidget);
    });

    testWidgets('rates sit right beside the rating', (tester) async {
      await tester.pumpWidget(wrap(listingOf(
        ListingType.seat,
        hourly: 500,
        daily: 3000,
        rating: 4.8,
        reviewCount: 30,
      )));

      final rates = tester.getRect(find.text('৳500/hr · ৳3K/day'));
      final star = tester.getRect(find.byIcon(Icons.star_rounded));
      final rating = tester.getRect(find.text('4.8'));

      expect((rates.center.dy - rating.center.dy).abs(), lessThan(4));
      expect(star.left - rates.right, lessThan(10));
      expect(rating.left - star.right, lessThan(6));
    });

    testWidgets('a proximity search trades the second rate for the distance',
        (tester) async {
      await tester.pumpWidget(wrap(listingOf(
        ListingType.room,
        hourly: 300,
        daily: 1500,
        distanceMeters: 2300,
      )));

      // One rate only, so rate + distance + rating still fit one line.
      expect(find.text('৳300/hr'), findsOneWidget);
      expect(find.textContaining('1.5K'), findsNothing);
      expect(find.byIcon(Icons.near_me_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('city and bed/guest counts are gone', (tester) async {
      await tester.pumpWidget(
        wrap(listingOf(ListingType.room, hourly: 300, monthly: 35000)),
      );

      expect(find.text('Dhaka'), findsNothing);
      expect(find.byIcon(Icons.bed_outlined), findsNothing);
      expect(find.byIcon(Icons.person_outline), findsNothing);
      expect(find.text('A place'), findsOneWidget);
    });
  });
}
