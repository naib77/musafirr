import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/screens/verification/verification_overview_screen.dart';
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
    expect(find.byType(VerificationOverviewScreen), findsNothing);
  });

  testWidgets('blocks without prompting while verification is pending',
      (tester) async {
    IdentityGate.statusOf = (_) async => 'pending';
    bool? result;
    await _pumpGate(tester, onResult: (r) => result = r);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // No upload screen — they've already submitted and are awaiting an admin.
    expect(find.byType(VerificationOverviewScreen), findsNothing);
    expect(result, isFalse);
  });

  testWidgets('a rejected identity is sent back to upload, not waved through',
      (tester) async {
    // 'rejected' is the status an admin sets after refusing a document, and it
    // was the one case with no test. It must behave like 'none' — offer the
    // upload again — rather than like 'pending', which shows no screen at all
    // and would leave a rejected host with nothing to do and no explanation.
    IdentityGate.statusOf = (_) async => 'rejected';
    bool? result;
    await _pumpGate(tester, onResult: (r) => result = r);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byType(VerificationOverviewScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
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
    expect(find.byType(VerificationOverviewScreen), findsOneWidget);
    expect(result, isNull);

    // User backs out of the upload screen.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(VerificationOverviewScreen), findsNothing);
    expect(result, isFalse);
  });
  testWidgets('status outage never opens the action', (tester) async {
    IdentityGate.statusOf = (_) async => 'unavailable';
    bool? result;
    await _pumpGate(tester, onResult: (value) => result = value);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.byType(VerificationOverviewScreen), findsNothing);
  });

  testWidgets('returning from capture rechecks admin approval', (tester) async {
    var status = 'none';
    IdentityGate.statusOf = (_) async => status;
    bool? result;
    await _pumpGate(tester, onResult: (value) => result = value);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    status = 'verified';
    final context = tester.element(find.byType(VerificationOverviewScreen));
    Navigator.of(context).pop(true);
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
