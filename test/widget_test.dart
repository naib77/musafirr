import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/app.dart';

void main() {
  testWidgets('musafir app renders role selector', (tester) async {
    await tester.pumpWidget(const MusafirApp());
    await tester.pumpAndSettle();

    expect(find.text('Musafir'), findsOneWidget);
    expect(find.byType(DropdownButton<UserRole>), findsOneWidget);
    expect(find.text('Find by Area'), findsOneWidget);
  });
}
