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

    expect(find.text('from '), findsOneWidget);
    // Cheapest plan drives the teaser.
    expect(find.textContaining('/hr/room'), findsOneWidget);
  });

  testWidgets('longest unit still renders without overflow', (tester) async {
    await tester.pumpWidget(
      wrap(listingOf(ListingType.fullHouse, monthly: 45000)),
    );

    expect(find.textContaining('/mo/full house'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no coloured listing-type badge on the card', (tester) async {
    await tester.pumpWidget(wrap(listingOf(ListingType.seat, hourly: 500)));

    // The badge used to render the capitalised title ("Seat") on the photo.
    expect(find.text('Seat'), findsNothing);
    expect(find.text('Room'), findsNothing);
    expect(find.text('Full House'), findsNothing);
  });
}
