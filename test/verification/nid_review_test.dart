import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/screens/verification/nid_verification_screen.dart';
import 'package:musafir/screens/verification/verification_overview_screen.dart';
import 'package:musafir/services/verification/nid_verification_service.dart';

class FakeNidRepository implements NidVerificationRepository {
  String state = 'rejected';
  bool fail = false, failStatus = false;
  int submissions = 0;
  String? lastType;
  Uint8List? lastBack;
  @override
  Future<Map<String, dynamic>> status() async {
    if (failStatus) throw StateError('offline');
    return {'status': state, 'note': 'Please submit clear images.'};
  }

  @override
  Future<void> submit(Uint8List front, Uint8List? back,
      {required String documentType, required String documentNumber}) async {
    lastType = documentType;
    lastBack = back;
    submissions++;
    if (fail) throw StateError('upload row write failed');
    state = 'pending';
  }
}

Future<void> tap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.tap(finder);
  await t.pumpAndSettle();
}

Uint8List photo() => Uint8List.fromList([
      ...base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='),
      ...List.filled(100, 0),
    ]);
void main() {
  test('NID accepts bounded image bytes, rejects disguised and oversized files',
      () {
    expect(NidVerificationService.imageType(photo()), 'png');
    expect(() => NidVerificationService.imageType(Uint8List(100)),
        throwsFormatException);
    expect(() => NidVerificationService.imageType(Uint8List(6 * 1024 * 1024)),
        throwsFormatException);
  });
  testWidgets(
      'revoked NID requires both sides and consent; failed submit stays unapproved',
      (t) async {
    final repo = FakeNidRepository()..fail = true;
    await t.pumpWidget(MaterialApp(
        home: NidVerificationScreen(
            repository: repo, pickImage: () async => photo())));
    await t.pumpAndSettle();
    expect(find.textContaining('rejected or revoked'), findsOneWidget);
    FilledButton button() => t.widget(
        find.widgetWithText(FilledButton, 'Submit document for review'));
    expect(button().onPressed, isNull);
    await t.enterText(find.byType(TextField), '1234567890');
    await tap(t, find.text('Choose front image'));
    await tap(t, find.byType(CheckboxListTile));
    expect(button().onPressed, isNull);
    await tap(t, find.text('Choose back image'));
    expect(button().onPressed, isNotNull);
    await tap(t, find.text('Submit document for review'));
    expect(find.textContaining('Submission was not confirmed'), findsOneWidget);
    expect(find.text('Document pending admin review'), findsNothing);
    repo.fail = false;
    await tap(t, find.text('Submit document for review'));
    expect(find.text('Document pending admin review'), findsOneWidget);
    expect(find.text('Document approved by admin'), findsNothing);
    expect(repo.submissions, 2);
  });
  for (final type
      in identityDocumentTypes.entries.where((e) => e.key != 'nid')) {
    testWidgets('${type.value} supports front-only admin submission',
        (t) async {
      final repo = FakeNidRepository();
      await t.pumpWidget(MaterialApp(
          home: NidVerificationScreen(
              repository: repo, pickImage: () async => photo())));
      await t.pumpAndSettle();
      await tap(t, find.byType(DropdownButtonFormField<String>));
      await t.tap(find.text(type.value).last);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'DOC-123');
      await tap(t, find.text('Choose front image'));
      await tap(t, find.byType(CheckboxListTile));
      await tap(t, find.text('Submit document for review'));
      expect(repo.lastType, type.key);
      expect(repo.lastBack, isNull);
      expect(find.text('Document pending admin review'), findsOneWidget);
    });
  }
  testWidgets('status failure cannot open upload form', (t) async {
    await t.pumpWidget(MaterialApp(
        home: NidVerificationScreen(
            repository: FakeNidRepository()..failStatus = true)));
    await t.pumpAndSettle();
    expect(
        find.textContaining('Could not load document status'), findsOneWidget);
    expect(find.text('Choose front image'), findsNothing);
  });

  /// Opened steps are appended to [opened], so a test can assert on taps.
  Future<void> pumpOverview(WidgetTester t, Map<String, dynamic> status,
      {double width = 1000, List<String>? opened, bool? nidResult}) async {
    t.view.physicalSize = Size(width, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true),
            child: child!),
        home: VerificationOverviewScreen(
            userId: 'u',
            loadStatus: () async => status,
            openNid: () async {
              opened?.add('nid');
              return nidResult;
            },
            openFace: () async => opened?.add('face'))));
    await t.pumpAndSettle();
  }

  for (final width in [320.0, 1000.0]) {
    testWidgets(
        'face required: both steps reachable once NID is pending, width $width',
        (t) async {
      final opened = <String>[];
      await pumpOverview(
          t,
          {
            'status': 'none',
            'nid_status': 'pending',
            'face_status': 'none',
            'face_required': true,
          },
          width: width,
          opened: opened);
      await tap(t, find.text('Open document review'));
      await tap(t, find.text('Open face review'));
      expect(opened, ['nid', 'face']);
      expect(find.text('Both approved — continue'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('face required: face step is hidden until a document is sent',
      (t) async {
    await pumpOverview(t, {
      'status': 'none',
      'nid_status': 'none',
      'face_status': 'none',
      'face_required': true,
    });
    expect(find.text('Open face review'), findsNothing);
    expect(find.textContaining('opens after you submit your document'),
        findsOneWidget);
    final nid = t.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Open document review'));
    expect(nid.onPressed, isNotNull);
  });

  testWidgets('face required: "Next" from the document goes to the face step',
      (t) async {
    final opened = <String>[];
    await pumpOverview(
        t,
        {
          'status': 'none',
          'nid_status': 'none',
          'face_status': 'none',
          'face_required': true,
        },
        opened: opened,
        nidResult: true);
    await tap(t, find.text('Open document review'));
    expect(opened, ['nid', 'face']);
  });

  testWidgets('submitted document offers "Next" only when a face step follows',
      (t) async {
    for (final faceNext in [true, false]) {
      await t.pumpWidget(MaterialApp(
          key: ValueKey(faceNext),
          home: NidVerificationScreen(
              repository: FakeNidRepository()..state = 'pending',
              faceNext: faceNext)));
      await t.pumpAndSettle();
      expect(find.text('Next: live face check'),
          faceNext ? findsOneWidget : findsNothing);
    }
  });

  testWidgets('face not required: only the document step is shown', (t) async {
    await pumpOverview(t, {
      'status': 'verified',
      'nid_status': 'verified',
      'face_status': 'none',
      'face_required': false,
    });
    expect(find.text('Open face review'), findsNothing);
    expect(find.text('Identity document'), findsOneWidget);
    expect(find.text('Approved — continue'), findsOneWidget);
  });

  testWidgets('pre-144 database: face_enabled false also means not required',
      (t) async {
    await pumpOverview(t, {
      'status': 'pending',
      'nid_status': 'pending',
      'face_status': 'none',
      'face_enabled': false,
    });
    expect(find.text('Open face review'), findsNothing);
  });
}
