import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/screens/verification/identity_verification_screen.dart';

void main() {
  testWidgets('blocks submit and warns until required captures are provided',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: IdentityVerificationScreen(userId: 'user-1', reason: 'to test'),
      ),
    );

    // Let the initial status load resolve (falls back to 'none' in tests).
    await tester.pumpAndSettle();

    // Step 1: fill in a valid NID number and continue to the capture step.
    await tester.enterText(find.byType(TextFormField), '1234567890');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 2: submitting without any captures must be blocked with a warning.
    await tester.ensureVisible(find.text('Submit'));
    await tester.tap(find.text('Submit'));
    await tester.pump(); // build the toast
    await tester.pump(const Duration(milliseconds: 300)); // entrance anim

    // No upload was attempted; the user is told to take a selfie first.
    expect(
      find.text('Please take a selfie so we can match it to your document'),
      findsOneWidget,
    );
    expect(find.byType(IdentityVerificationScreen), findsOneWidget);

    // Let the toast's auto-dismiss timer fire so no timers leak into teardown.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
