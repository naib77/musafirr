import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/screens/wishlists/wishlists_screen.dart';

void main() {
  testWidgets('the unavailable card says so and offers Remove', (tester) async {
    var removed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 200,
          height: 280,
          child: UnavailableFavoriteCard(onRemove: () => removed++),
        ),
      ),
    ));

    expect(find.text('No longer available'), findsOneWidget);
    expect(find.text('The host has taken this listing down.'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    expect(removed, 1);
  });
}
