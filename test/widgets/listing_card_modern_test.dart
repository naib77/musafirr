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

  Widget wrapSized(Listing listing, Size size, {double textScale = 1.0}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: ListingCardModern(
                listing: listing,
                isFavorite: false,
                onTap: () {},
                onFavoriteTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The card's height used to be split `flex: 5` photo / `flex: 2` text, so
  /// the text slot was 2/7 of the cell whatever the text actually needed — 108
  /// pixels for ~43 at 1440px — and shrinking the card shrank the text's
  /// headroom with it. The text block is its own intrinsic height now and the
  /// photo takes the remainder, which is what lets the Explore grid and the
  /// curated rows use a card this size at all.
  group('the text block sizes itself, the photo takes the rest', () {
    Rect textBlockOf(WidgetTester tester) => tester.getRect(
          find
              .ancestor(
                of: find.text('A place'),
                matching: find.byType(Padding),
              )
              .first,
        );

    testWidgets('does not grow with the cell', (tester) async {
      final listing = listingOf(ListingType.room, hourly: 300);

      await tester.pumpWidget(wrapSized(listing, const Size(225, 274)));
      final short = textBlockOf(tester).height;

      await tester.pumpWidget(wrapSized(listing, const Size(225, 420)));
      final tall = textBlockOf(tester).height;

      // Under the old flex it was 2/7 of the cell: 78 against 120.
      expect(tall, short);
    });

    testWidgets('grows with the text scale instead, without overflowing',
        (tester) async {
      final listing = listingOf(ListingType.room, hourly: 300);

      await tester.pumpWidget(wrapSized(listing, const Size(225, 274)));
      final plain = textBlockOf(tester).height;

      await tester.pumpWidget(
        wrapSized(listing, const Size(225, 274), textScale: 2.0),
      );
      expect(textBlockOf(tester).height, greaterThan(plain));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the smallest card any surface asks for still fits',
        (tester) async {
      // The curated row on a phone, which is the narrowest cell in the app.
      const width = 162.0;
      await tester.pumpWidget(
        wrapSized(
          listingOf(ListingType.room,
              hourly: 300, rating: 4.9, reviewCount: 20),
          const Size(width, width / kListingCardAspectRatio),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

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

      expect(
          find.text('৳300/hr · ৳1.5K/day', findRichText: true), findsOneWidget);
      expect(find.textContaining('35K'), findsNothing);
    });

    testWidgets('no daily → hourly and monthly', (tester) async {
      await tester.pumpWidget(wrap(
        listingOf(ListingType.room, hourly: 300, monthly: 35000),
      ));

      expect(
          find.text('৳300/hr · ৳35K/mo', findRichText: true), findsOneWidget);
    });

    testWidgets('no hourly → daily and monthly', (tester) async {
      await tester.pumpWidget(wrap(
        listingOf(ListingType.room, daily: 1500, monthly: 35000),
      ));

      expect(
          find.text('৳1.5K/day · ৳35K/mo', findRichText: true), findsOneWidget);
    });

    testWidgets('a single offered rate shows alone', (tester) async {
      await tester.pumpWidget(
        wrap(listingOf(ListingType.fullHouse, daily: 1500)),
      );

      expect(find.text('৳1.5K/day', findRichText: true), findsOneWidget);
    });

    testWidgets('rates sit right beside the rating', (tester) async {
      await tester.pumpWidget(wrap(listingOf(
        ListingType.seat,
        hourly: 500,
        daily: 3000,
        rating: 4.8,
        reviewCount: 30,
      )));

      final rates =
          tester.getRect(find.text('৳500/hr · ৳3K/day', findRichText: true));
      final star = tester.getRect(find.byIcon(Icons.star_rounded));
      final rating = tester.getRect(find.text('4.8'));

      expect((rates.center.dy - rating.center.dy).abs(), lessThan(4));
      expect(star.left - rates.right, lessThan(10));
      expect(rating.left - star.right, lessThan(6));
    });

    /// The phrase used to be one flat `fontSize: 12, w700` string, so two
    /// rates and a rating were six numerals and two slashes with nothing
    /// leading. A settled screenshot cannot catch that coming back — the
    /// string is identical either way — so the span styles are asserted.
    testWidgets('the lead rate carries the weight, the rest is demoted',
        (tester) async {
      await tester.pumpWidget(wrap(
        listingOf(ListingType.room, hourly: 300, daily: 1500),
      ));

      final spans = <TextSpan>[];
      (tester
              .widget<RichText>(find.descendant(
                of: find.byType(ListingCardModern),
                matching: find.byWidgetPredicate((w) =>
                    w is RichText && w.text.toPlainText().contains('1.5K')),
              ))
              .text as TextSpan)
          .visitChildren((span) {
        if (span is TextSpan) spans.add(span);
        return true;
      });

      final lead = spans.firstWhere((s) => s.text == '৳300');
      final leadUnit = spans.firstWhere((s) => s.text == '/hr');
      final second = spans.firstWhere((s) => s.text == '৳1.5K');

      // The lead outweighs everything beside it, on all three axes.
      expect(lead.style!.fontWeight!.value,
          greaterThan(second.style!.fontWeight!.value));
      expect(lead.style!.fontSize!, greaterThan(second.style!.fontSize!));
      expect(lead.style!.fontSize!, greaterThan(leadUnit.style!.fontSize!));
      expect(lead.style!.color, isNot(second.style!.color));
      expect(lead.style!.color, isNot(leadUnit.style!.color));
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
      expect(find.text('৳300/hr', findRichText: true), findsOneWidget);
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
