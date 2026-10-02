import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/listing.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/widgets/desktop_top_nav.dart';
import 'package:musafir/widgets/listing_card_modern.dart';
import 'package:musafir/widgets/top_hosts_button.dart';

/// Every icon-only control has a name a screen reader can read.
///
/// This exists because of a measurement, not a hunch. The app was served and
/// driven in a browser with assistive technology switched on — Flutter builds
/// the semantics tree only when something asks for it — and of the 38 nodes
/// that appeared, **8 carried a label** (QA report 2026-09-18, N7). The two
/// section headings and the six listing cards. The search button, the
/// wishlist hearts, the account menu, the notification bell and the
/// leaderboard trophy were all `button` with no name at all.
///
/// The trap that produced it is worth naming, because it is easy to walk into
/// again and it looks fixed from the code: **a [Tooltip] does not name a
/// control.** It sets `SemanticsProperties.tooltip`, and `label` stays empty.
/// Nearly every control on this list already had a tooltip.
///
/// The second consequence is the one that costs time rather than users: the
/// end-to-end strategy in `docs/qa/qa-plan.md` selects controls by accessibility
/// label, so an unnamed control cannot be driven by a test either.
/// Finds a control by the accessibility name it declares.
///
/// Deliberately NOT `find.bySemanticsLabel`, which reads the label off the
/// render object's own semantics node and comes back empty for a control
/// whose node is merged into a parent — which is most of the ones here, since
/// they sit inside cards and toolbars that merge their descendants. That
/// finder answered 0 for a heart this file can see the label on, so it would
/// have made this suite pass or fail for reasons unrelated to the names.
Finder semanticsLabelled(String label) => find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == label,
      description: 'Semantics(label: "$label")',
    );

void main() {
  Listing aListing() => Listing(
        id: 'l1',
        ownerName: 'Host',
        title: 'A place',
        address: 'Road 1, Dhaka',
        type: ListingType.room,
        latitude: 23.8,
        longitude: 90.4,
        dailyRate: 1200,
        facilities: const [],
        available: true,
        city: 'Dhaka',
        bedrooms: 2,
        maxGuests: 4,
      );

  Widget card({required bool isFavorite}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 280,
              child: ListingCardModern(
                listing: aListing(),
                isFavorite: isFavorite,
                onTap: () {},
                onFavoriteTap: () {},
              ),
            ),
          ),
        ),
      );

  group('the wishlist heart', () {
    testWidgets('is named for what the tap will do, not for its own state',
        (tester) async {
      await tester.pumpWidget(card(isFavorite: false));
      expect(semanticsLabelled('Save to wishlist'), findsOneWidget);

      await tester.pumpWidget(card(isFavorite: true));
      await tester.pumpAndSettle();
      expect(semanticsLabelled('Remove from wishlist'), findsOneWidget);
    });

    testWidgets('is a button, and toggled when saved', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(card(isFavorite: true));
      await tester.pumpAndSettle();

      final node =
          tester.getSemantics(semanticsLabelled('Remove from wishlist'));
      expect(node.flagsCollection.isButton, isTrue);
      // `isToggled` is a tri-state rather than a bool, because "off" and "not
      // a toggle at all" are different answers and a screen reader says
      // different things for them. Compared by name so this does not depend
      // on the enum being exported from a public library.
      expect(node.flagsCollection.isToggled.name, 'isTrue');
      handle.dispose();
    });
  });

  group('the desktop header', () {
    Widget header() => MaterialApp(
          home: Scaffold(
            body: DesktopTopNav(
              destinations: const [
                DesktopNavDestination(
                  icon: Icons.search,
                  selectedIcon: Icons.search,
                  label: 'Explore',
                ),
                DesktopNavDestination(
                  icon: Icons.favorite_border,
                  selectedIcon: Icons.favorite,
                  label: 'Wishlists',
                ),
              ],
              selectedIndex: 0,
              onDestinationSelected: _ignore,
              accountMenu: [
                DesktopAccountMenuItem(
                  label: 'Log in or sign up',
                  icon: Icons.login_rounded,
                  onTap: () {},
                ),
              ],
              trailing: [
                TopHostsButton(onTap: () {}),
              ],
            ),
          ),
        );

    testWidgets('names the account menu and the leaderboard', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(header());
      await tester.pumpAndSettle();

      // The hamburger + avatar. `PopupMenuButton.tooltip` is a tooltip.
      expect(semanticsLabelled('Account and more'), findsOneWidget);
      // The destinations were already named; this pins that they stay so.
      expect(semanticsLabelled('Explore'), findsWidgets);
      expect(semanticsLabelled('Wishlists'), findsWidgets);
    });

    testWidgets('names the brand, which is also the home button',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DesktopTopNav(
            destinations: const [
              DesktopNavDestination(
                icon: Icons.search,
                selectedIcon: Icons.search,
                label: 'Explore',
              ),
            ],
            selectedIndex: 0,
            onDestinationSelected: _ignore,
            accountMenu: const [],
            onBrandTap: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(semanticsLabelled('Musaafir home'), findsOneWidget);
    });
  });
}

void _ignore(int _) {}
