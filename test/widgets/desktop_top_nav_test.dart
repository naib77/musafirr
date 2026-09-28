import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/widgets/desktop_top_nav.dart';

/// A desktop-sized window, since this header only ever renders on one.
const Size _desktop = Size(1440, 900);

void main() {
  const explore = DesktopNavDestination(
    icon: Icons.search_outlined,
    selectedIcon: Icons.search,
    label: 'Explore',
  );
  const wishlists = DesktopNavDestination(
    icon: Icons.favorite_outline,
    selectedIcon: Icons.favorite,
    label: 'Wishlists',
  );
  const messages = DesktopNavDestination(
    icon: Icons.chat_bubble_outline,
    selectedIcon: Icons.chat_bubble,
    label: 'Messages',
    badgeCount: 3,
  );

  Future<void> pump(
    WidgetTester tester, {
    List<DesktopNavDestination> destinations = const [explore, wishlists],
    int selectedIndex = 0,
    ValueChanged<int>? onDestinationSelected,
    List<DesktopAccountMenuItem> accountMenu = const [],
    DesktopTopNavAction? primaryAction,
    Widget? searchBar,
    bool accountHighlighted = false,
  }) async {
    tester.view.physicalSize = _desktop;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DesktopTopNav(
          destinations: destinations,
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected ?? (_) {},
          accountMenu: accountMenu,
          primaryAction: primaryAction,
          searchBar: searchBar,
          accountHighlighted: accountHighlighted,
        ),
      ),
    ));
  }

  group('destinations', () {
    testWidgets('renders every label', (tester) async {
      await pump(tester, destinations: const [explore, wishlists, messages]);
      expect(find.text('Explore'), findsOneWidget);
      expect(find.text('Wishlists'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
    });

    testWidgets('reports the index that was tapped', (tester) async {
      final taps = <int>[];
      await pump(
        tester,
        destinations: const [explore, wishlists, messages],
        onDestinationSelected: taps.add,
      );
      await tester.tap(find.text('Messages'));
      expect(taps, [2]);
    });

    // Re-selecting the current tab is meaningful — Explore drops an active
    // search, Trips refreshes — so the callback must still fire.
    testWidgets('reports a tap on the destination already selected',
        (tester) async {
      final taps = <int>[];
      await pump(tester, selectedIndex: 0, onDestinationSelected: taps.add);
      await tester.tap(find.text('Explore'));
      expect(taps, [0]);
    });

    testWidgets('draws the selected icon for the current tab only',
        (tester) async {
      await pump(tester, destinations: const [explore, wishlists]);
      expect(find.byIcon(Icons.search), findsOneWidget); // selected Explore
      expect(find.byIcon(Icons.favorite_outline), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsNothing);
    });

    // -1 is how the header says "a screen from the account menu is showing".
    // Nothing may look current, and nothing may throw.
    testWidgets('selectedIndex -1 marks nothing current', (tester) async {
      await pump(tester,
          destinations: const [explore, wishlists], selectedIndex: -1);
      expect(find.byIcon(Icons.search_outlined), findsOneWidget);
      expect(find.byIcon(Icons.search), findsNothing);
      expect(find.byIcon(Icons.favorite), findsNothing);
    });

    testWidgets('an unread count rides on the destination', (tester) async {
      await pump(tester, destinations: const [explore, messages]);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('a zero count shows no badge', (tester) async {
      await pump(tester, destinations: const [explore, wishlists]);
      expect(find.byType(Badge), findsNothing);
    });
  });

  group('account menu', () {
    testWidgets('opens on tap and runs the item chosen', (tester) async {
      var loggedOut = false;
      await pump(tester, accountMenu: [
        DesktopAccountMenuItem(label: 'Profile', onTap: () {}),
        DesktopAccountMenuItem(
          label: 'Log out',
          dividerAbove: true,
          onTap: () => loggedOut = true,
        ),
      ]);

      // Nothing is on screen until the button is tapped.
      expect(find.text('Log out'), findsNothing);

      await tester.tap(find.byTooltip('Account and more'));
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);

      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(loggedOut, isTrue);
    });
  });

  group('primary action', () {
    testWidgets('shows its label and fires', (tester) async {
      var tapped = false;
      await pump(
        tester,
        primaryAction: DesktopTopNavAction(
          label: 'Log in or sign up',
          onTap: () => tapped = true,
        ),
      );
      await tester.tap(find.text('Log in or sign up'));
      expect(tapped, isTrue);
    });

    testWidgets('is absent when there is none', (tester) async {
      await pump(tester);
      expect(find.text('Log in or sign up'), findsNothing);
      expect(find.text('Become a host'), findsNothing);
    });
  });

  // The bar itself is tested in search_pill_test.dart. All the header owes it
  // is a slot on a second row, on the right tab and no other.
  group('the search row', () {
    testWidgets('is absent on a tab that passes no bar', (tester) async {
      await pump(tester);
      expect(find.text('SEARCH BAR'), findsNothing);
    });

    testWidgets('renders whatever bar it was handed', (tester) async {
      await pump(tester, searchBar: const Text('SEARCH BAR'));
      expect(find.text('SEARCH BAR'), findsOneWidget);
    });
  });

  // The header is fixed chrome: a user cannot scroll away from an overflow in
  // it. These are the two widths where it is tightest — the breakpoint it
  // first appears at, and that width with the text scaled up.
  group('does not overflow', () {
    Future<void> pumpFull(WidgetTester tester, Size size,
        {double textScale = 1.0}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: DesktopTopNav(
              destinations: const [explore, wishlists, messages],
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              primaryAction: DesktopTopNavAction(
                label: 'Switch to hosting',
                onTap: () {},
              ),
              trailing: const [Icon(Icons.notifications_none)],
              accountMenu: [
                DesktopAccountMenuItem(label: 'Profile', onTap: () {}),
              ],
              // A stand-in as wide as the real bar's cap, so the header is
              // measured against the widest row it will ever hold.
              searchBar: const SizedBox(width: 780, height: 68),
            ),
          ),
        ),
      ));
    }

    testWidgets('at the 1000px breakpoint', (tester) async {
      await pumpFull(tester, const Size(1000, 800));
      expect(tester.takeException(), isNull);
    });

    testWidgets('with text scaled to the header clamp', (tester) async {
      // The header clamps scaling at 1.1; 2.0 here proves the clamp is what
      // holds, not the happy path.
      await pumpFull(tester, const Size(1000, 800), textScale: 2.0);
      expect(tester.takeException(), isNull);
    });
  });
}
