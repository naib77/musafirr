import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_device.dart';
import 'device_hardware.dart';
import 'device_identity.dart';

/// Records this device against the signed-in account, lists the account's
/// devices, and ends one.
///
/// See `docs/DEVICE_SESSIONS.md`. The eviction under
/// `max_devices_per_user` happens inside `register_device` (125), so it is
/// **not** something this class decides — a client that chose its own victim
/// would be a second enforcer of a rule the database owns.
///
/// **Registering is still a client call, and that is the remaining gap.** A
/// client that never calls `register_device` is never recorded and so never
/// evicted. Closing it means registering inside `verify-otp`, the only place a
/// session is minted and the only one running as service role — the client
/// would send its device id with the OTP. Same shape as "the booking form is
/// not enforcement".
///
/// Registration failures are swallowed: a device that cannot be written down
/// must still be able to use the app. Failures in [revoke] and [revokeOthers]
/// are NOT — a sign-out that quietly did nothing is worse than an error.
/// What the devices screen needs, and nothing else.
///
/// A seam rather than the singleton, so the screen can be driven in a test
/// without Supabase — the same reason `WherePanel` takes its lookups as
/// functions. [DeviceRegistry] is the production implementation.
abstract class DeviceDirectory {
  Future<String> deviceId();
  Future<List<UserDevice>> listDevices();
  Future<bool> revoke(String deviceId);
  Future<int> revokeOthers();
  Future<int> deviceLimit();
  Future<void> rename(String deviceId, String label);
}

class DeviceRegistry implements DeviceDirectory {
  DeviceRegistry._();

  static final DeviceRegistry instance = DeviceRegistry._();

  static const _storageKey = 'musafir_device_id';

  String? _deviceId;

  /// Cached so a token refresh storm cannot turn into a write per refresh.
  String? _registeredForUser;

  SupabaseClient get _client => Supabase.instance.client;

  /// The id this device is known by, created on first call.
  @override
  Future<String> deviceId() async {
    final cached = _deviceId;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final id = await loadOrCreateDeviceId(
      read: () async => prefs.getString(_storageKey),
      write: (value) => prefs.setString(_storageKey, value),
    );
    _deviceId = id;
    return id;
  }

  /// The device keys to send alongside an OTP, so `verify-otp` can apply the
  /// cap before it hands back a session.
  ///
  /// Empty when the id cannot be read: the login then proceeds uncounted,
  /// because refusing to sign someone in over device bookkeeping is exactly
  /// the lockout this design exists to avoid.
  Future<Map<String, String>> loginFields() async {
    try {
      return {
        'deviceId': await deviceId(),
        'devicePlatform': _platform().wireName,
      };
    } catch (e) {
      debugPrint('[DeviceRegistry] loginFields failed: $e');
      return const {};
    }
  }

  DevicePlatform _platform() => currentDevicePlatform(
        isAndroid: () => !kIsWeb && Platform.isAndroid,
        isIos: () => !kIsWeb && Platform.isIOS,
      );

  /// Called when a session appears — a fresh sign-in, or a restored one at
  /// startup. **Not** on `tokenRefreshed`, which fires on a timer.
  Future<void> registerForUser(String userId) async {
    if (_registeredForUser == userId) return;

    try {
      final id = await deviceId();
      final hardware = await describeThisDevice();

      // This call is what fills in `session_id` — verify-otp cannot, because
      // the session does not exist until the client redeems the token hash.
      // Everything else here coalesces server-side, so a field this build
      // cannot read never erases what an earlier one knew.
      await _client.rpc('register_device', params: {
        'p_device_id': id,
        'p_platform': _platform().wireName,
        'p_model': hardware.model,
        'p_os_version': hardware.osVersion,
        'p_app_version': await _appVersion(),
      });

      _registeredForUser = userId;
    } catch (e) {
      // Includes the window where build/web is newer than the database and
      // `register_device` does not exist yet. Recording a device is not worth
      // a visible failure.
      debugPrint('[DeviceRegistry] register failed: $e');
    }
  }

  /// Heartbeat. Answers true when this device has been signed out elsewhere.
  ///
  /// **Acting on this is a courtesy, not the enforcement.** The real sign-out
  /// is the deleted `auth.sessions` row — a client that ignores this answer
  /// has already lost its refresh token and dies at the next one. What this
  /// buys is *promptness*: without it the evicted device keeps working until
  /// its access token expires, which is the hour in which a stolen phone is
  /// still reading messages.
  Future<bool> isRevoked() async {
    try {
      final id = await deviceId();
      final revoked = await _client.rpc('touch_device', params: {
        'p_device_id': id,
      });
      return revoked == true;
    } catch (e) {
      debugPrint('[DeviceRegistry] touch failed: $e');
      // Fail open: a network blip must not sign anyone out.
      return false;
    }
  }

  /// Every device on this account, most recently seen first.
  ///
  /// A plain select, not an RPC: `user_devices` has a SELECT policy scoped to
  /// `auth.uid()`, so RLS is the whole of the access control and a function
  /// would only be a second place to get it wrong.
  @override
  Future<List<UserDevice>> listDevices() async {
    final rows = await _client
        .from('user_devices')
        .select('device_id, platform, label, model, app_version, '
            'created_at, last_seen_at, revoked_at')
        .order('last_seen_at', ascending: false);

    return (rows as List)
        .map((r) => UserDevice.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Signs a device out. True when a live session was actually ended — false
  /// means the row was marked but the session had already expired, which the
  /// UI should not describe as "signed out just now".
  @override
  Future<bool> revoke(String deviceId) async {
    final ended = await _client.rpc('revoke_device', params: {
      'p_device_id': deviceId,
    });
    return ended == true;
  }

  /// "Sign out everywhere else". Returns how many devices were ended.
  ///
  /// The device to keep is the caller's own, identified server-side by the
  /// session in the JWT — deliberately not sent from here, since a caller who
  /// could name the device to keep could name one that is not theirs.
  @override
  Future<int> revokeOthers() async {
    final count = await _client.rpc('revoke_other_devices');
    return (count as num?)?.toInt() ?? 0;
  }

  /// Names a device. `label` is the ONLY column the client may write — 123
  /// revokes UPDATE and re-grants it column-wise — so this is a plain update
  /// rather than an RPC, and RLS plus that grant are the whole of the control.
  ///
  /// An empty name clears it, and [UserDevice.displayName] falls back to the
  /// model. A device called "" would otherwise be a row with no name at all.
  @override
  Future<void> rename(String deviceId, String label) async {
    final trimmed = label.trim();
    await _client.from('user_devices').update(
        {'label': trimmed.isEmpty ? null : trimmed}).eq('device_id', deviceId);
  }

  /// The admin's cap, or 0 for no limit. Read so the list can say "2 of 3".
  @override
  Future<int> deviceLimit() async {
    try {
      final value = await _client.rpc('max_devices_per_user');
      return (value as num?)?.toInt() ?? 0;
    } catch (_) {
      // Fail open, the same way the database's own read-side guard does: this
      // is a setting that can take the app away from someone.
      return 0;
    }
  }

  /// Forgets who this device is registered for, so the next sign-in records
  /// again. The device id itself survives — it identifies the hardware, not
  /// the account, and a shared phone is still one device.
  void forgetUser() => _registeredForUser = null;

  Future<String?> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      // Empty on web, where there is no package to read.
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      if (version.isEmpty) return null;
      return build.isEmpty ? version : '$version+$build';
    } catch (_) {
      return null;
    }
  }
}
