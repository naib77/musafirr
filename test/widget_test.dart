import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/app.dart';

void main() {
  testWidgets('musafir app renders login screen when not authenticated', (tester) async {
    await tester.pumpWidget(const MusafirApp());
    await tester.pumpAndSettle();

    // App should show login screen initially
    expect(find.text('Welcome to Musafir'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
  });
}
