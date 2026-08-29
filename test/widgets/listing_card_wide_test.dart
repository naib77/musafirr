import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/listing.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/widgets/listing_card_wide.dart';

/// The single-column results row: one listing per row with the detail a guest
/// needs to judge it — what it is and where, the host's own name for it,
/// capacity, the searched dates, every rate, and the rating.
void main() {
  Listing listingOf({
    ListingType type = ListingType.room,
    String title = 'Sunny corner room',
    String? area = 'Khilgaon',
    String? city = 'Dhaka',
    double? hourly,
    double? daily,
    double? monthly,
    double? rating,
    int reviewCount = 0,
    bool isSuperhost = false,
    int bedrooms = 1,
    int beds = 1,
    int maxGuests = 2,
    List<String> imageUrls = const [],
    double? distanceMeters,
  }) {
    return Listing(
      id: 'l1',
      ownerName: 'Host',
      title: title,
      address: 'Road 1, Dhaka',
      type: type,
      latitude: 23.8,
      longitude: 90.4,
      hourlyRate: hourly,
      dailyRate: daily,
      monthlyRate: monthly,
      facilities: const [],
      available: true,
      area: area,
      city: city,
      rating: rating,
      reviewCount: reviewCount,
      isSuperhost: isSuperhost,
      bedrooms: bedrooms,
      beds: beds,
      maxGuests: maxGuests,
      imageUrls: imageUrls,
      distanceMeters: distanceMeters,
    );
  }

  Future<void> pumpCard(
    WidgetTester tester,
    Listing listing, {
    String? stayLabel,
    bool isFavorite = false,
    double width = 390,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: ListingCardWide(
                listing: listing,
                isFavorite: isFavorite,
                onTap: () {},
                onFavoriteTap: () {},
                stayLabel: stayLabel,
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('what the row says', () {
    testWidgets('leads with the type and the neighbourhood', (tester) async {
      await pumpCard(tester, listingOf(daily: 1500));

      expect(find.text('Room in Khilgaon'), findsOneWidget);
      // The host's own name for the place is the second line, not the first.
      expect(find.text('Sunny corner room'), findsOneWidget);
    });

    testWidgets('falls back to the city when there is no area', (tester) async {
      await pumpCard(tester, listingOf(area: null, daily: 1500));

      expect(find.text('Room in Dhaka'), findsOneWidget);
    });

    testWidgets('uses the title alone when there is no place name at all',
        (tester) async {
      await pumpCard(
        tester,
        listingOf(area: null, city: null, daily: 1500),
      );

      expect(find.text('Sunny corner room'), findsOneWidget);
      // Not repeated as both headline and subtitle.
      expect(find.text('Room in null'), findsNothing);
    });

    testWidgets('counts bedrooms, beds and guests', (tester) async {
      await pumpCard(
        tester,
        listingOf(bedrooms: 2, beds: 3, maxGuests: 5, daily: 1500),
      );

      expect(find.text('2 bedrooms · 3 beds · 5 guests'), findsOneWidget);
    });

    testWidgets('a single one of each reads in the singular', (tester) async {
      await pumpCard(tester, listingOf(bedrooms: 1, beds: 1, maxGuests: 1));

      expect(find.text('1 bedroom · 1 bed · 1 guest'), findsOneWidget);
    });

    testWidgets('a seat counts seats, not the bedroom it does not have',
        (tester) async {
      await pumpCard(
        tester,
        listingOf(type: ListingType.seat, maxGuests: 4, hourly: 200),
      );

      expect(find.text('4 seats'), findsOneWidget);
      expect(find.textContaining('bedroom'), findsNothing);
    });

    testWidgets('shows the searched dates when there are any', (tester) async {
      await pumpCard(tester, listingOf(daily: 1500), stayLabel: '21 – 23 Aug');

      expect(find.text('21 – 23 Aug'), findsOneWidget);
    });

    testWidgets('claims no dates when the search had none', (tester) async {
      await pumpCard(tester, listingOf(daily: 1500));

      expect(find.textContaining('Aug'), findsNothing);
    });

    testWidgets('shows every rate in full, not compacted', (tester) async {
      await pumpCard(
        tester,
        listingOf(hourly: 500, daily: 3000, monthly: 35000),
      );

      // A full-width row has space for exact figures — "৳35K" hides the
      // difference between two nearby prices.
      expect(
          find.text('৳500/hr  ·  ৳3,000/day  ·  ৳35,000/mo'), findsOneWidget);
    });

    testWidgets('rating carries its review count', (tester) async {
      await pumpCard(
        tester,
        listingOf(daily: 1500, rating: 4.9, reviewCount: 1002),
      );

      expect(find.text('4.9 (1002)'), findsOneWidget);
    });

    testWidgets('a proximity search adds the distance', (tester) async {
      await pumpCard(
        tester,
        listingOf(daily: 1500, distanceMeters: 2300),
      );

      expect(find.byIcon(Icons.near_me_rounded), findsOneWidget);
    });
  });

  group('the pill on the photo', () {
    testWidgets('guest favorite wins when earned', (tester) async {
      await pumpCard(
        tester,
        listingOf(daily: 1500, rating: 4.9, reviewCount: 40, isSuperhost: true),
      );

      expect(find.text('Guest favorite'), findsOneWidget);
      expect(find.text('Superhost'), findsNothing);
    });

    testWidgets('superhost otherwise', (tester) async {
      await pumpCard(
        tester,
        listingOf(daily: 1500, rating: 4.2, reviewCount: 40, isSuperhost: true),
      );

      expect(find.text('Superhost'), findsOneWidget);
    });

    testWidgets('a place with no reviews is marked new', (tester) async {
      await pumpCard(tester, listingOf(daily: 1500));

      expect(find.text('New'), findsOneWidget);
    });

    testWidgets('a reviewed, ordinary place gets no pill', (tester) async {
      await pumpCard(
        tester,
        listingOf(daily: 1500, rating: 4.2, reviewCount: 40),
      );

      expect(find.text('New'), findsNothing);
      expect(find.text('Superhost'), findsNothing);
      expect(find.text('Guest favorite'), findsNothing);
    });
  });

  testWidgets('several photos are swipeable, one is not', (tester) async {
    await pumpCard(
      tester,
      listingOf(daily: 1500, imageUrls: const ['a.jpg', 'b.jpg', 'c.jpg']),
    );
    expect(find.byType(PageView), findsOneWidget);

    await pumpCard(tester, listingOf(daily: 1500, imageUrls: const ['a.jpg']));
    expect(find.byType(PageView), findsNothing);
  });

  group('the photo slider buttons', () {
    // A swipe is the only other way through the photos, and a desktop browser
    // has no swipe — so without these the extra photos are unreachable there.
    final next = find.byIcon(Icons.chevron_right_rounded);
    final previous = find.byIcon(Icons.chevron_left_rounded);

    testWidgets('a single photo gets no buttons to step through',
        (tester) async {
      await pumpCard(
          tester, listingOf(daily: 1500, imageUrls: const ['a.jpg']));

      expect(next, findsNothing);
      expect(previous, findsNothing);
    });

    testWidgets('steps forward, and back again', (tester) async {
      await pumpCard(
        tester,
        listingOf(daily: 1500, imageUrls: const ['a.jpg', 'b.jpg', 'c.jpg']),
      );
      final page = tester.widget<PageView>(find.byType(PageView)).controller!;

      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(page.page, 1);

      await tester.tap(previous);
      await tester.pumpAndSettle();
      expect(page.page, 0);
    });

    testWidgets('stepping a photo does not open the listing', (tester) async {
      // The whole card is tappable, so the arrow has to win its own taps or
      // reaching photo two would push the detail screen instead.
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390,
              child: ListingCardWide(
                listing: listingOf(
                  daily: 1500,
                  imageUrls: const ['a.jpg', 'b.jpg'],
                ),
                isFavorite: false,
                onTap: () => opened = true,
                onFavoriteTap: () {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();

      expect(opened, isFalse);
    });

    testWidgets('no arrow points past either end of the carousel',
        (tester) async {
      await pumpCard(
        tester,
        listingOf(daily: 1500, imageUrls: const ['a.jpg', 'b.jpg']),
      );

      // Laid out but faded out, so the photo does not twitch as it appears.
      double opacityOf(Finder button) => tester
          .widget<AnimatedOpacity>(
            find
                .ancestor(of: button, matching: find.byType(AnimatedOpacity))
                .first,
          )
          .opacity;

      expect(opacityOf(previous), 0, reason: 'nothing before the first photo');
      expect(opacityOf(next), 1);

      await tester.tap(next);
      await tester.pumpAndSettle();

      expect(opacityOf(previous), 1);
      expect(opacityOf(next), 0, reason: 'nothing after the last photo');
    });

    testWidgets('a screen reader is told which way each arrow goes',
        (tester) async {
      // The chevrons say nothing on their own.
      final semantics = tester.ensureSemantics();
      await pumpCard(
        tester,
        listingOf(daily: 1500, imageUrls: const ['a.jpg', 'b.jpg']),
      );

      expect(find.bySemanticsLabel('Next photo'), findsOneWidget);
      // The arrow that points nowhere is inert, so it is not announced either —
      // a screen reader is offered only the step that exists.
      expect(find.bySemanticsLabel('Previous photo'), findsNothing);

      // And the tap target is a comfortable one, not the 30px circle drawn.
      final box = tester.getSize(find.bySemanticsLabel('Next photo'));
      expect(box.width, greaterThanOrEqualTo(44));
      expect(box.height, greaterThanOrEqualTo(44));

      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Previous photo'), findsOneWidget);

      semantics.dispose();
    });
  });

  testWidgets('nothing overflows on a narrow phone', (tester) async {
    // Everything at once, on the narrowest screen we support.
    await pumpCard(
      tester,
      listingOf(
        title: 'A very long name a host typed out for their lovely place',
        area: 'Dakshinkhan',
        hourly: 500,
        daily: 3000,
        monthly: 35000,
        rating: 4.94,
        reviewCount: 1002,
        bedrooms: 3,
        beds: 4,
        maxGuests: 8,
        distanceMeters: 2300,
      ),
      stayLabel: '21 Aug – 23 Sep',
      width: 320,
    );

    expect(tester.takeException(), isNull);
  });
}
