import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/widgets/photo_carousel.dart';

Future<void> _pump(WidgetTester tester, List<String> urls) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 225,
          child: PhotoCarousel(urls: urls),
        ),
      ),
    ));

void main() {
  testWidgets('arrows step through every photo (a mouse cannot swipe)',
      (tester) async {
    await _pump(tester, ['a', 'b', 'c']);
    expect(find.text('1 / 3'), findsOneWidget);
    // On the first photo there is nowhere to go back to.
    expect(find.bySemanticsLabel('Previous photo'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Next photo'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Next photo'));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Next photo'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Previous photo'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('a single photo has no controls', (tester) async {
    await _pump(tester, ['a']);
    expect(find.bySemanticsLabel('Next photo'), findsNothing);
    expect(find.textContaining('/'), findsNothing);
  });
}
