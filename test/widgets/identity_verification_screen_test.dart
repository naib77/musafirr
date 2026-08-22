import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/screens/verification/identity_verification_screen.dart';
import 'package:musafir/screens/verification/selfie_capture_screen.dart';

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

  testWidgets('the selfie tile opens the in-app front camera, not the picker',
      (tester) async {
    // The bug: handing off to the system camera app meant the phone chose the
    // lens, and most chose the REAR one. The selfie must go through our own
    // capture screen, which selects the front lens itself.
    await tester.pumpWidget(
      const MaterialApp(
        home: IdentityVerificationScreen(userId: 'user-1', reason: 'to test'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '1234567890');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // The selfie capture CARD, not the section heading above it.
    final selfieCard = find.byIcon(Icons.face_retouching_natural_rounded);
    await tester.ensureVisible(selfieCard);
    await tester.tap(selfieCard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byType(SelfieCaptureScreen),
      findsOneWidget,
      reason: 'the selfie must be captured in-app, where we pick the lens',
    );

    // availableCameras() has no platform implementation under `flutter test`,
    // so the screen can never reach a live preview here. Pump past the 10s
    // init timeout (NOT pumpAndSettle, which never returns while the spinner
    // turns) and assert it degrades to an actionable error instead of either
    // throwing or spinning forever.
    await tester.pump(const Duration(seconds: 11));
    expect(tester.takeException(), isNull);
    expect(find.text('Could not open the camera. Please try again.'),
        findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
