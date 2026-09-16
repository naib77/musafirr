import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/devices/device_hardware.dart';

/// The model is what makes the device list usable — three rows reading
/// "Android phone" tell nobody which one to sign out. It is never an
/// identifier: that is the opaque UUID in `device_identity.dart`.
class _ThrowingPlugin implements DeviceInfoPlugin {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('no platform channel in a test');
}

void main() {
  test('a platform that answers nothing still records the device', () async {
    // The whole read is best-effort: `register_device` coalesces, so a null
    // never erases what an earlier launch knew, and a missing plugin must not
    // stop a device being recorded at all.
    final hardware = await describeThisDevice(plugin: _ThrowingPlugin());

    expect(hardware.model, isNull);
    expect(hardware.osVersion, isNull);
  });

  test('unknown is a real value, not an error', () {
    expect(DeviceHardware.unknown.model, isNull);
    expect(DeviceHardware.unknown.osVersion, isNull);
  });
}
