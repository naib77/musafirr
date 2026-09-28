import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// What a device calls itself, for the "Your devices" list.
///
/// Both fields are nullable and every read is best-effort. `register_device`
/// coalesces, so a null never erases what an earlier launch knew — which is
/// what lets this be added long after the columns existed, and what makes a
/// failure here cost nothing.
class DeviceHardware {
  const DeviceHardware({this.model, this.osVersion});

  final String? model;
  final String? osVersion;

  static const unknown = DeviceHardware();
}

/// Reads the model and OS of the device this is running on.
///
/// The point is a list a human recognises: three rows reading "Android phone"
/// tell nobody which one to sign out. A user-given label still beats this —
/// see [UserDevice.displayName] — but most people will never set one.
///
/// **Not an identifier.** Nothing here is stable enough or unique enough to
/// identify a device, and it is never used for that: the device id is the
/// opaque UUID in `device_identity.dart`. Android's `id`/`serial` are refused
/// to normal apps since Android 10 anyway.
Future<DeviceHardware> describeThisDevice({DeviceInfoPlugin? plugin}) async {
  final info = plugin ?? DeviceInfoPlugin();
  try {
    if (kIsWeb) {
      final web = await info.webBrowserInfo;
      // The browser name, not the user agent: that string is long, changes
      // every release, and the row has one line to render it in.
      final browser = web.browserName.name;
      return DeviceHardware(
        model: browser.isEmpty ? null : _capitalise(browser),
        osVersion: web.platform,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = await info.androidInfo;
      // Marketing name where the manufacturer supplies one ("Galaxy A54"),
      // because `model` alone is often a part number like "SM-A546E".
      final name = _firstNonEmpty([android.device, android.model]);
      final brand = android.manufacturer.trim();
      return DeviceHardware(
        model: _joinBrand(brand, name),
        osVersion: 'Android ${android.version.release}',
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = await info.iosInfo;
      return DeviceHardware(
        model: _firstNonEmpty([ios.utsname.machine, ios.model]),
        osVersion: 'iOS ${ios.systemVersion}',
      );
    }
  } catch (e) {
    // A plugin that is missing, or a platform that answers nothing, must not
    // stop the device being recorded.
    debugPrint('[DeviceHardware] read failed: $e');
  }
  return DeviceHardware.unknown;
}

String? _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

/// "Samsung Galaxy A54", but not "Google Google Pixel 8" — a brand already in
/// the name is not repeated.
String? _joinBrand(String brand, String? name) {
  if (name == null) return brand.isEmpty ? null : _capitalise(brand);
  if (brand.isEmpty) return name;
  if (name.toLowerCase().startsWith(brand.toLowerCase())) return name;
  return '${_capitalise(brand)} $name';
}

String _capitalise(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
