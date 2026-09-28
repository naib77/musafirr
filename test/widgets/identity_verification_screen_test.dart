import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/screens/verification/identity_verification_screen.dart';
import 'package:musafir/services/verification/face_verification_service.dart';

class FakeFaceRepository implements FaceVerificationRepository {
  String currentStatus = 'none';
  bool enabled = true;
  bool failSubmit = false, failStatus = false;
  int starts = 0, submissions = 0;
  bool? manual;
  @override
  Future<Map<String, dynamic>> status() async {
    if (failStatus) throw StateError('offline');
    return {'status': currentStatus, 'enabled': enabled};
  }

  @override
  Future<FaceAttempt> start({required bool manual}) async {
    starts++;
    this.manual = manual;
    return FaceAttempt(
        id: 'attempt',
        userId: 'user-1',
        nonce: 'nonce',
        method: manual ? 'manual' : 'guided',
        actions: const ['blink', 'left', 'right']);
  }

  @override
  Future<void> submit(FaceAttempt attempt, FaceCapture capture) async {
    submissions++;
    if (failSubmit) throw StateError('offline');
    currentStatus = 'pending';
  }
}

Future<void> pumpScreen(WidgetTester tester, FakeFaceRepository repository,
    {double width = 400, double scale = 1}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale), disableAnimations: true),
          child: child!),
      home: IdentityVerificationScreen(
          userId: 'user-1',
          repository: repository,
          capture: (context, attempt) async =>
              FaceCapture(selfie: Uint8List(100), clip: Uint8List(100)))));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no ID inputs; consent required before camera starts',
      (tester) async {
    final repository = FakeFaceRepository();
    await pumpScreen(tester, repository);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('ID is a separate step'), findsOneWidget);
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start face check'));
    expect(button.onPressed, isNull);
    expect(repository.starts, 0);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Start face check');
    expect(repository.starts, 1);
    expect(repository.manual, false);
    expect(find.text('Ready for review'), findsOneWidget);
    expect(repository.submissions, 0);
  });
  testWidgets('submission waits for admin and failure remains retryable',
      (tester) async {
    final repository = FakeFaceRepository()..failSubmit = true;
    await pumpScreen(tester, repository);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Start face check');
    await tapVisible(tester, 'Submit for admin review');
    expect(find.textContaining('Submission was not confirmed'), findsOneWidget);
    expect(find.text('Pending admin review'), findsNothing);
    repository.failSubmit = false;
    await tapVisible(tester, 'Submit for admin review');
    expect(find.text('Pending admin review'), findsOneWidget);
    expect(find.text('You’re approved'), findsNothing);
    repository.currentStatus = 'verified';
    await tapVisible(tester, 'Refresh status');
    expect(find.text('You’re approved'), findsOneWidget);
  });
  testWidgets('manual route is explicit and needs fresh consent',
      (tester) async {
    final repository = FakeFaceRepository();
    await pumpScreen(tester, repository);
    await tapVisible(tester, 'Unable to do the movements?');
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Take review photo'))
            .onPressed,
        isNull);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Take review photo');
    expect(repository.manual, true);
    expect(
        find.textContaining('No gesture check was completed'), findsOneWidget);
  });
  testWidgets('status outage blocks starting a duplicate attempt',
      (tester) async {
    final repository = FakeFaceRepository()..failStatus = true;
    await pumpScreen(tester, repository);
    expect(find.text('Start face check'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    repository.failStatus = false;
    await tapVisible(tester, 'Try again');
    expect(find.text('Start face check'), findsOneWidget);
  });
  testWidgets('server rollout switch blocks new capture', (tester) async {
    final repository = FakeFaceRepository()..enabled = false;
    await pumpScreen(tester, repository);
    expect(find.text('Start face check'), findsNothing);
    expect(find.textContaining('not available yet'), findsOneWidget);
    expect(repository.starts, 0);
  });
  for (final width in [320.0, 1000.0]) {
    testWidgets(
        'no overflow at width $width with large text and reduced motion',
        (tester) async {
      await pumpScreen(tester, FakeFaceRepository(), width: width, scale: 2);
      await tester.scrollUntilVisible(
          find.text('Unable to do the movements?'), 300);
      expect(tester.takeException(), isNull);
    });
  }
}
