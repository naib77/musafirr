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
    DesktopSearchSummary? search,
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
          search: search,
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

  group('the search pill', () {
    testWidgets('is absent on a tab that passes no search', (tester) async {
      await pump(tester);
      expect(find.text('Where'), findsNothing);
      expect(find.text('Search destinations'), findsNothing);
    });

    // An untouched pill must read as an invitation, not as a filter already
    // narrowing the feed.
    testWidgets('shows placeholders when nothing is chosen', (tester) async {
      await pump(tester, search: DesktopSearchSummary(onTap: () {}));
      expect(find.text('Where'), findsOneWidget);
      expect(find.text('When'), findsOneWidget);
      expect(find.text('Who'), findsOneWidget);
      expect(find.text('Search destinations'), findsOneWidget);
      expect(find.text('Add dates'), findsOneWidget);
      expect(find.text('Add guests'), findsOneWidget);
    });

    testWidgets('shows the values it was given', (tester) async {
      await pump(
        tester,
        search: DesktopSearchSummary(
          where: 'Uttara, Dhaka',
          when: '12 – 15 Sep',
          who: '3 guests',
          onTap: () {},
        ),
      );
      expect(find.text('Uttara, Dhaka'), findsOneWidget);
      expect(find.text('12 – 15 Sep'), findsOneWidget);
      expect(find.text('3 guests'), findsOneWidget);
      expect(find.text('Search destinations'), findsNothing);
    });

    testWidgets('every segment opens the same search', (tester) async {
      var opened = 0;
      await pump(
        tester,
        search: DesktopSearchSummary(onTap: () => opened++),
      );
      await tester.tap(find.text('Search destinations'));
      await tester.tap(find.text('Add dates'));
      await tester.tap(find.text('Add guests'));
      await tester.tap(find.byTooltip('Search'));
      expect(opened, 4);
    });

    // No active search means nothing to clear, and a ✕ that clears nothing is
    // a button that looks broken.
    testWidgets('offers no clear button without onClear', (tester) async {
      await pump(tester, search: DesktopSearchSummary(onTap: () {}));
      expect(find.byTooltip('Clear search'), findsNothing);
    });

    testWidgets('clears when asked', (tester) async {
      var cleared = false;
      await pump(
        tester,
        search: DesktopSearchSummary(
          where: 'Uttara, Dhaka',
          onTap: () {},
          onClear: () => cleared = true,
        ),
      );
      await tester.tap(find.byTooltip('Clear search'));
      expect(cleared, isTrue);
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
              search: DesktopSearchSummary(
                where: 'Bashundhara R/A, Dhaka',
                when: '29 Sep – 2 Oct',
                who: '6 guests',
                onTap: () {},
                onClear: () {},
              ),
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
