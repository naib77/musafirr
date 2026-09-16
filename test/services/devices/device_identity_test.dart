import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/devices/device_identity.dart';

/// The device id is the whole of how a device is recognised, so the decision
/// worth pinning is that it is created exactly once and then never changes —
/// under a future cap, an id that regenerates is a device that consumes a new
/// slot on every launch.
void main() {
  group('loading or creating the id', () {
    test('creates and stores one when nothing is stored', () async {
      String? stored;

      final id = await loadOrCreateDeviceId(
        read: () async => stored,
        write: (value) async => stored = value,
        newId: () => 'generated-0000-0001',
      );

      expect(id, 'generated-0000-0001');
      expect(stored, 'generated-0000-0001');
    });

    test('reuses what is stored, and writes nothing', () async {
      var writes = 0;

      final id = await loadOrCreateDeviceId(
        read: () async => 'already-stored-0001',
        write: (_) async => writes++,
        newId: () => 'must-not-be-used',
      );

      expect(id, 'already-stored-0001');
      // A second write is a second id waiting to happen.
      expect(writes, 0);
    });

    test('is stable across calls', () async {
      String? stored;
      var generated = 0;
      Future<String> load() => loadOrCreateDeviceId(
            read: () async => stored,
            write: (value) async => stored = value,
            newId: () => 'generated-${generated++}-padding',
          );

      final first = await load();
      final second = await load();
      final third = await load();

      expect(second, first);
      expect(third, first);
      expect(generated, 1);
    });

    test('replaces a stored value the server would refuse', () async {
      // Truncated by a failed write, or left by an older build.
      // `register_device` raises 22023 for it, which would otherwise fail
      // every launch silently.
      String? stored = 'short';

      final id = await loadOrCreateDeviceId(
        read: () async => stored,
        write: (value) async => stored = value,
        newId: () => 'replacement-0001',
      );

      expect(id, 'replacement-0001');
      expect(stored, 'replacement-0001');
    });

    test('a real generated id is one the server accepts', () async {
      String? stored;

      final id = await loadOrCreateDeviceId(
        read: () async => stored,
        write: (value) async => stored = value,
      );

      // No newId override: this is the uuid the app actually ships with, held
      // to the same 8..128 bounds migration 123 enforces.
      expect(isUsableDeviceId(id), isTrue);
    });
  });

  group('the bounds the server enforces', () {
    test('rejects what 22023 would reject', () {
      expect(isUsableDeviceId('short'), isFalse);
      expect(isUsableDeviceId(''), isFalse);
      expect(isUsableDeviceId('a' * 129), isFalse);
    });

    test('accepts the edges', () {
      expect(isUsableDeviceId('a' * 8), isTrue);
      expect(isUsableDeviceId('a' * 128), isTrue);
    });
  });

  group('which platform is recorded', () {
    test('web wins before Platform is ever read', () {
      // `Platform` is not available on the web — reading it throws rather than
      // answering false — so these callbacks must never run there.
      expect(
        currentDevicePlatform(
          isWeb: true,
          isAndroid: () => throw StateError('Platform read on web'),
          isIos: () => throw StateError('Platform read on web'),
        ),
        DevicePlatform.web,
      );
    });

    test('android and ios are named', () {
      expect(
        currentDevicePlatform(
          isWeb: false,
          isAndroid: () => true,
          isIos: () => false,
        ),
        DevicePlatform.android,
      );
      expect(
        currentDevicePlatform(
          isWeb: false,
          isAndroid: () => false,
          isIos: () => true,
        ),
        DevicePlatform.ios,
      );
    });

    test('an unrecognised platform still records something valid', () {
      // The check constraint takes three values and nothing else, so falling
      // through has to land on one of them or the insert fails.
      final platform = currentDevicePlatform(
        isWeb: false,
        isAndroid: () => false,
        isIos: () => false,
      );

      expect(
        DevicePlatform.values.map((p) => p.wireName),
        contains(platform.wireName),
      );
    });

    test('the wire names are exactly what the constraint allows', () {
      // migration 123: check (platform in ('web','android','ios'))
      expect(
        DevicePlatform.values.map((p) => p.wireName).toList(),
        ['web', 'android', 'ios'],
      );
    });
  });
}
