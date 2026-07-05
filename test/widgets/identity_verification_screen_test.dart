import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/screens/verification/identity_verification_screen.dart';

void main() {
  testWidgets('blocks submit and warns until a front image is captured',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: IdentityVerificationScreen(userId: 'user-1', reason: 'to test'),
      ),
    );

    await tester.ensureVisible(find.text('Submit'));
    await tester.tap(find.text('Submit'));
    await tester.pump(); // build the toast
    await tester.pump(const Duration(milliseconds: 300)); // entrance anim

    // No upload was attempted; the user is told to scan the front first.
    expect(find.textContaining('scan the front'), findsOneWidget);
    expect(find.byType(IdentityVerificationScreen), findsOneWidget);

    // Let the toast's auto-dismiss timer fire so no timers leak into teardown.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
