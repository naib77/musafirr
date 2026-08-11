import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/listing.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/widgets/listing_card_modern.dart';

/// The Explore card shows the listing type as part of the price
/// ("from ৳500/hr/seat") and deliberately carries NO coloured type badge —
/// a badge on every card made the grid noisy.
void main() {
  Listing listingOf(
    ListingType type, {
    double? hourly,
    double? daily,
    double? monthly,
    double? rating,
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
      reviewCount: rating == null ? 0 : 12,
      bedrooms: 2,
      maxGuests: 4,
    );
  }

  Widget wrap(Listing listing) {
    return MaterialApp(
      home: Scaffold(
        // A realistic two-column grid cell, so a long unit would have to fit
        // the same width it does on a phone.
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

  testWidgets('price teaser names the unit sold: hourly seat', (tester) async {
    await tester.pumpWidget(wrap(listingOf(ListingType.seat, hourly: 500)));

    expect(find.textContaining('/hr/seat'), findsOneWidget);
    // Single plan offered → no "from" prefix.
    expect(find.textContaining('from'), findsNothing);
  });

  testWidgets('shows "from" only when several plans are offered',
      (tester) async {
    await tester.pumpWidget(
      wrap(listingOf(ListingType.room, hourly: 300, daily: 1500)),
    );

    // Cheapest plan drives the teaser, prefixed with "from".
    expect(find.textContaining('from ৳300/hr/room'), findsOneWidget);
  });

  testWidgets('longest unit still renders without overflow', (tester) async {
    await tester.pumpWidget(
      wrap(listingOf(ListingType.fullHouse, monthly: 45000)),
    );

    expect(find.textContaining('/mo/full house'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Worst case for width: the pill must still stop short of the heart.
    final price = tester.getRect(
      find
          .ancestor(
            of: find.textContaining('/mo/full house'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
        price.right,
        lessThan(tester
            .getRect(
              find.byIcon(Icons.favorite_border),
            )
            .left));
  });

  testWidgets('price sits top-left, above the status pill', (tester) async {
    // A listing with no reviews renders the "New" pill, so both are on screen.
    await tester.pumpWidget(wrap(listingOf(ListingType.seat, hourly: 500)));

    final card = tester.getRect(find.byType(ListingCardModern));
    // The pill Container is the closest ancestor of the teaser text.
    final price = tester.getRect(
      find
          .ancestor(
            of: find.textContaining('/hr/seat'),
            matching: find.byType(Container),
          )
          .first,
    );
    final heart = tester.getRect(find.byIcon(Icons.favorite_border));
    final status = tester.getRect(find.text('New'));

    // Upper portion of the photo, not the bottom edge it used to sit on.
    expect(price.top, lessThan(card.center.dy));
    expect(price.top - card.top, lessThan(30));
    // Hugging the left edge, and never running under the favourite button.
    expect(price.left - card.left, lessThan(20));
    expect(price.right, lessThan(heart.left));
    // The status pill moved out of the way, below the price.
    expect(status.top, greaterThan(price.bottom));
  });

  testWidgets('no coloured listing-type badge on the card', (tester) async {
    await tester.pumpWidget(wrap(listingOf(ListingType.seat, hourly: 500)));

    // The badge used to render the capitalised title ("Seat") on the photo.
    expect(find.text('Seat'), findsNothing);
    expect(find.text('Room'), findsNothing);
    expect(find.text('Full House'), findsNothing);
  });

  group('two lines under the photo', () {
    // The line-2 rate is an exact string ("৳300/hr"); the pill on the photo
    // carries the unit type too ("৳300/hr/room"), so exact-vs-containing
    // matching keeps the two apart.
    testWidgets('headline rate is the hourly one when let by the hour',
        (tester) async {
      await tester.pumpWidget(wrap(
        listingOf(ListingType.room, hourly: 300, daily: 1500, monthly: 35000),
      ));

      expect(find.text('৳300/hr'), findsOneWidget);
      // The other offered rates are no longer listed anywhere on the card.
      expect(find.textContaining('1.5K'), findsNothing);
      expect(find.textContaining('35K'), findsNothing);
    });

    testWidgets('falls back to monthly when there is no hourly rate',
        (tester) async {
      await tester.pumpWidget(wrap(
        listingOf(ListingType.room, daily: 1500, monthly: 35000),
      ));

      expect(find.text('৳35K/mo'), findsOneWidget);
      // The pill keeps showing the cheapest plan, which here is the daily one.
      expect(find.textContaining('৳1.5K/day/room'), findsOneWidget);
    });

    testWidgets('a daily-only listing still shows a rate', (tester) async {
      await tester.pumpWidget(
        wrap(listingOf(ListingType.fullHouse, daily: 1500)),
      );

      expect(find.text('৳1.5K/day'), findsOneWidget);
    });

    testWidgets('rate shares the line with the rating', (tester) async {
      await tester.pumpWidget(
        wrap(listingOf(ListingType.seat, hourly: 500, rating: 4.8)),
      );

      final rate = tester.getRect(find.text('৳500/hr'));
      final rating = tester.getRect(find.text('4.8'));
      // Same row, rating to the right.
      expect((rate.center.dy - rating.center.dy).abs(), lessThan(4));
      expect(rating.left, greaterThan(rate.right));
    });

    testWidgets('city and bed/guest counts are gone', (tester) async {
      await tester.pumpWidget(
        wrap(listingOf(ListingType.room, hourly: 300, monthly: 35000)),
      );

      expect(find.text('Dhaka'), findsNothing);
      expect(find.byIcon(Icons.bed_outlined), findsNothing);
      expect(find.byIcon(Icons.person_outline), findsNothing);
      // Title plus the rate line, and no third line of text.
      expect(find.text('A place'), findsOneWidget);
    });
  });
}
