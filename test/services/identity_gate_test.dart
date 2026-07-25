import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/screens/verification/identity_verification_screen.dart';
import 'package:musafir/services/verification/identity_gate.dart';

/// Pumps a button that runs [IdentityGate.ensure] and records its result.
Future<void> _pumpGate(
  WidgetTester tester, {
  required void Function(bool) onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                final ok = await IdentityGate.ensure(
                  context,
                  'user-1',
                  reason: 'to test',
                );
                onResult(ok);
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late Future<String> Function(String) original;
  setUp(() => original = IdentityGate.statusOf);
  tearDown(() => IdentityGate.statusOf = original);

  testWidgets('proceeds without prompting when the identity is verified',
      (tester) async {
    IdentityGate.statusOf = (_) async => 'verified';
    bool? result;
    await _pumpGate(tester, onResult: (r) => result = r);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.byType(IdentityVerificationScreen), findsNothing);
  });

  testWidgets('blocks without prompting while verification is pending',
      (tester) async {
    IdentityGate.statusOf = (_) async => 'pending';
    bool? result;
    await _pumpGate(tester, onResult: (r) => result = r);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // No upload screen — they've already submitted and are awaiting an admin.
    expect(find.byType(IdentityVerificationScreen), findsNothing);
    expect(result, isFalse);
  });

  testWidgets('prompts for upload and blocks when the user backs out',
      (tester) async {
    IdentityGate.statusOf = (_) async => 'none';
    bool? result;
    await _pumpGate(tester, onResult: (r) => result = r);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // The upload screen is shown and the action is still pending.
    expect(find.byType(IdentityVerificationScreen), findsOneWidget);
    expect(result, isNull);

    // User backs out of the upload screen.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(IdentityVerificationScreen), findsNothing);
    expect(result, isFalse);
  });
}
