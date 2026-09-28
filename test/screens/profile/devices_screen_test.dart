import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/user_device.dart';
import 'package:musafir/screens/profile/devices_screen.dart';
import 'package:musafir/services/devices/device_registry.dart';

/// The device list has to ship before any cap does — a limit with no way to
/// see or manage what is using it is a support queue. These pin the parts of
/// it that are not cosmetic.
class _FakeDirectory implements DeviceDirectory {
  _FakeDirectory({
    required this.devices,
    this.limit = 0,
    this.revokeAnswer = true,
  });

  List<UserDevice> devices;

  /// Every fixture below calls the caller's own device `dev-this-0001`, so the
  /// "This device" chip has something to match.
  static const thisDevice = 'dev-this-0001';
  final int limit;
  final bool revokeAnswer;

  final List<String> revoked = [];
  final List<(String, String)> renamed = [];
  int revokeOthersCalls = 0;

  @override
  Future<String> deviceId() async => thisDevice;

  @override
  Future<List<UserDevice>> listDevices() async => devices;

  @override
  Future<int> deviceLimit() async => limit;

  @override
  Future<bool> revoke(String deviceId) async {
    revoked.add(deviceId);
    return revokeAnswer;
  }

  @override
  Future<void> rename(String deviceId, String label) async {
    renamed.add((deviceId, label));
  }

  @override
  Future<int> revokeOthers() async {
    revokeOthersCalls++;
    return 2;
  }
}

UserDevice deviceOf(
  String id, {
  String platform = 'android',
  String? label,
  String? model,
  DateTime? revokedAt,
}) {
  final now = DateTime(2026, 9, 16, 12);
  return UserDevice(
    deviceId: id,
    platform: platform,
    label: label,
    model: model,
    createdAt: now.subtract(const Duration(days: 30)),
    lastSeenAt: now.subtract(const Duration(hours: 2)),
    revokedAt: revokedAt,
  );
}

void main() {
  Future<void> pump(WidgetTester tester, _FakeDirectory fake) async {
    await tester.pumpWidget(MaterialApp(
      // A fresh key per pump: without it Flutter updates the existing element
      // in place, `initState` never runs again, and a second pump in one test
      // quietly keeps the first fake's data.
      home: DevicesScreen(key: UniqueKey(), registry: fake),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('marks the device you are holding', (tester) async {
    await pump(
      tester,
      _FakeDirectory(devices: [
        deviceOf('dev-this-0001', model: 'Pixel 8'),
        deviceOf('dev-other-002', model: 'Galaxy A54'),
      ]),
    );

    expect(find.text('Pixel 8'), findsOneWidget);
    expect(find.text('Galaxy A54'), findsOneWidget);
    // Without it, the row that logs you out looks like every other row.
    expect(find.text('This device'), findsOneWidget);
  });

  testWidgets('names a device without falling back to a UUID', (tester) async {
    await pump(tester, _FakeDirectory(devices: [deviceOf('dev-nameless-01')]));

    // A UUID names nothing to a human.
    expect(find.textContaining('dev-nameless'), findsNothing);
    expect(find.text('Android phone'), findsOneWidget);
  });

  testWidgets('a signed-out device is kept, not hidden', (tester) async {
    await pump(
      tester,
      _FakeDirectory(devices: [
        deviceOf('dev-this-0001', model: 'Pixel 8'),
        // Long enough ago to be rendered as a date: "13 days ago" is harder
        // to place than a date, and placing it is the point when someone is
        // looking for a login they did not make.
        deviceOf('dev-lost-0002',
            model: 'Old phone', revokedAt: DateTime(2026, 3, 12)),
      ]),
    );

    // A device that simply vanishes reads as data loss, and hides the very
    // event the user may have come to look for.
    expect(find.text('Signed out'), findsOneWidget);
    expect(find.text('Old phone'), findsOneWidget);
    expect(find.textContaining('Signed out on 12 Mar 2026'), findsOneWidget);
  });

  testWidgets('says signed out only when a session was really ended',
      (tester) async {
    final fake = _FakeDirectory(
      devices: [deviceOf('dev-other-002', model: 'Galaxy A54')],
      revokeAnswer: false,
    );
    await pump(tester, fake);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(fake.revoked, ['dev-other-002']);
    // The row was marked but no live session existed. Claiming otherwise is
    // how a security control stops being believed.
    expect(find.text('Galaxy A54 was already signed out'), findsOneWidget);
  });

  testWidgets('a sign-out is confirmed first', (tester) async {
    final fake = _FakeDirectory(
      devices: [deviceOf('dev-other-002', model: 'Galaxy A54')],
    );
    await pump(tester, fake);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(fake.revoked, isEmpty);
  });

  testWidgets('warns that signing out this device logs you out here',
      (tester) async {
    await pump(
      tester,
      _FakeDirectory(devices: [deviceOf('dev-this-0001', model: 'Pixel 8')]),
    );

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('This is the device you are using now'),
      findsOneWidget,
    );
  });

  testWidgets('offers sign-out-everywhere-else only when there is an else',
      (tester) async {
    await pump(
      tester,
      _FakeDirectory(devices: [deviceOf('dev-this-0001', model: 'Pixel 8')]),
    );
    expect(find.text('Sign out everywhere else'), findsNothing);

    await pump(
      tester,
      _FakeDirectory(devices: [
        deviceOf('dev-this-0001', model: 'Pixel 8'),
        deviceOf('dev-other-002', model: 'Galaxy A54'),
      ]),
    );
    expect(find.text('Sign out everywhere else'), findsOneWidget);
  });

  testWidgets('shows the cap, and says browsers are not counted',
      (tester) async {
    await pump(
      tester,
      _FakeDirectory(
        limit: 3,
        devices: [
          deviceOf('dev-this-0001', model: 'Pixel 8'),
          deviceOf('dev-web-0003', platform: 'web'),
        ],
      ),
    );

    // One phone of three — the browser must not be counted, or the number
    // looks wrong to anyone who also uses the site.
    expect(find.textContaining('1 of 3 phones'), findsOneWidget);
    expect(find.textContaining('Browsers are not counted'), findsOneWidget);
  });

  testWidgets('a device can be named', (tester) async {
    // Three rows all reading "Android phone" tell nobody which to sign out,
    // so naming them is what makes the list usable at all.
    final fake = _FakeDirectory(devices: [deviceOf('dev-other-002')]);
    await pump(tester, fake);

    await tester.tap(find.text('Android phone'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Work phone');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fake.renamed, [('dev-other-002', 'Work phone')]);
  });

  testWidgets('a signed-out device cannot be renamed', (tester) async {
    // The row is there to be read; naming a device you no longer hold is
    // editing history.
    final fake = _FakeDirectory(devices: [
      deviceOf('dev-lost-0002',
          model: 'Old phone', revokedAt: DateTime(2026, 3, 12)),
    ]);
    await pump(tester, fake);

    await tester.tap(find.text('Old phone'));
    await tester.pumpAndSettle();

    expect(find.text('Name this device'), findsNothing);
    expect(fake.renamed, isEmpty);
  });

  testWidgets('a name replaces the fallback', (tester) async {
    await pump(
      tester,
      _FakeDirectory(devices: [
        deviceOf('dev-other-002', model: 'Galaxy A54', label: 'Work phone'),
      ]),
    );

    expect(find.text('Work phone'), findsOneWidget);
    expect(find.text('Galaxy A54'), findsNothing);
  });

  testWidgets('says nothing about a cap when there is none', (tester) async {
    await pump(
      tester,
      _FakeDirectory(devices: [deviceOf('dev-this-0001', model: 'Pixel 8')]),
    );

    expect(find.textContaining('of 0'), findsNothing);
    expect(find.textContaining('phones.'), findsNothing);
  });
}
