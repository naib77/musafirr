import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// How this device names itself to `register_device`.
///
/// Deliberately **not** a hardware identifier. Android 10+ refuses IMEI and
/// serial to normal apps, iOS's IDFV resets when the last app from a vendor is
/// uninstalled, and the web has nothing of the kind at all — every app that
/// tried fingerprinting gave it up. It is an opaque UUID this device generates
/// once and keeps, which is what the apps in `docs/DEVICE_SESSIONS.md` settled
/// on too.
///
/// The consequence to remember before a cap is ever turned on: **clearing site
/// data on the web produces a new device**, and a private window never keeps
/// one at all. That is why web cannot share a tight limit with phones.
typedef ReadStoredId = Future<String?> Function();
typedef WriteStoredId = Future<void> Function(String id);

/// The wire values `user_devices.platform` accepts — the check constraint in
/// migration 123 refuses anything else, so this cannot drift quietly.
enum DevicePlatform { web, android, ios }

extension DevicePlatformWire on DevicePlatform {
  String get wireName => name;
}

/// Reads the stored device id, or creates and stores one.
///
/// Pure over its two callbacks so it can be tested without `SharedPreferences`
/// and without a platform channel, following `speech_locale.dart` and
/// `selfie_camera.dart` — the decision is worth a test, the storage is not.
///
/// [newId] exists for the same reason: a test needs to know what it is
/// asserting on.
Future<String> loadOrCreateDeviceId({
  required ReadStoredId read,
  required WriteStoredId write,
  String Function()? newId,
}) async {
  final stored = (await read())?.trim();
  if (stored != null && isUsableDeviceId(stored)) return stored;

  // A stored value that is somehow unusable — truncated by a failed write, or
  // left by an older build — is replaced rather than sent. `register_device`
  // raises 22023 for it, which would otherwise fail every launch silently.
  final fresh = (newId ?? const Uuid().v4)();
  await write(fresh);
  return fresh;
}

/// The bounds `register_device` enforces (22023 outside them).
///
/// Duplicated from the migration on purpose: the client should not send a
/// value it knows the server will refuse, and the server cannot trust the
/// client to have checked. Both halves have tests.
bool isUsableDeviceId(String id) => id.length >= 8 && id.length <= 128;

/// Which platform to record. `kIsWeb` is checked first because `Platform` is
/// not available on the web at all — reading it there throws rather than
/// returning false.
DevicePlatform currentDevicePlatform({
  bool isWeb = kIsWeb,
  required bool Function() isAndroid,
  required bool Function() isIos,
}) {
  if (isWeb) return DevicePlatform.web;
  if (isAndroid()) return DevicePlatform.android;
  if (isIos()) return DevicePlatform.ios;
  // The constraint takes three values and nothing else, so an unrecognised
  // platform is recorded as the one that is always true of a Flutter build we
  // did not ship: treat it as web rather than failing the insert.
  return DevicePlatform.web;
}
