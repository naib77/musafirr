import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/widgets/app_page_header.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  testWidgets('renders the title and optional subtitle', (tester) async {
    await _pump(
      tester,
      const AppPageHeader(title: 'Wishlists', subtitle: 'Your saved places'),
    );

    expect(find.text('Wishlists'), findsOneWidget);
    expect(find.text('Your saved places'), findsOneWidget);
  });

  testWidgets('omits the subtitle when none is given', (tester) async {
    await _pump(tester, const AppPageHeader(title: 'Profile'));

    expect(find.text('Profile'), findsOneWidget);
    // Only the title Text should be present in the header column.
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('renders action widgets and the bottom slot', (tester) async {
    await _pump(
      tester,
      AppPageHeader(
        title: 'Reservations',
        actions: const [Icon(Icons.star)],
        bottom: const Text('TABS'),
      ),
    );

    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.text('TABS'), findsOneWidget);
  });

  testWidgets('HeaderActionButton shows a badge only when count > 0',
      (tester) async {
    var taps = 0;
    await _pump(
      tester,
      HeaderActionButton(
        icon: Icons.chat_bubble_outline,
        badgeCount: 5,
        onTap: () => taps++,
        tooltip: 'Messages',
      ),
    );

    expect(find.text('5'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    expect(taps, 1);
  });

  testWidgets('HeaderActionButton hides the badge at zero', (tester) async {
    await _pump(
      tester,
      HeaderActionButton(
        icon: Icons.chat_bubble_outline,
        badgeCount: 0,
        onTap: () {},
      ),
    );

    expect(find.byType(Badge), findsNothing);
  });
}
