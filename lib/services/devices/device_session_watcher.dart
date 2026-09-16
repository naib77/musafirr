import 'package:flutter/widgets.dart';

import 'device_registry.dart';

/// Notices, on resume, that this device has been signed out from somewhere
/// else — a user tapping it in "Your devices", or a `max_devices_per_user`
/// eviction — and signs the app out locally.
///
/// **This is promptness, not enforcement.** The real sign-out already
/// happened: `revoke_device` deleted the `auth.sessions` row, so this device's
/// refresh token is gone and its access token dies at the next refresh
/// whatever this class does. A client that ignored the answer would still be
/// locked out within the hour.
///
/// What it buys is that hour. Without it, a phone that was signed out because
/// it was lost keeps showing messages and bookings until its token expires,
/// which is exactly the window the feature exists to close. Same shape as
/// [WebUpdateService] and [AppUpdateService] — one singleton, a `start`, and a
/// resume hook — because those are the two other things that have to notice
/// the world changed while the app was in the background.
class DeviceSessionWatcher with WidgetsBindingObserver {
  DeviceSessionWatcher._();

  static final DeviceSessionWatcher instance = DeviceSessionWatcher._();

  VoidCallback? _onRevoked;
  bool _started = false;
  bool _checking = false;
  bool _fired = false;

  /// [onRevoked] should end the local session. It is called at most once.
  void start({required VoidCallback onRevoked}) {
    _onRevoked = onRevoked;
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    // Once at startup as well as on resume. A device evicted while the app was
    // closed is the LIKELIEST case, not an edge one — the user signed in
    // somewhere else in the meantime — and a cold start never fires `resumed`,
    // so waiting for it would mean that device keeps working until its access
    // token expires on its own.
    checkNow();
  }

  /// Called when the session ends, so a later sign-in in the same launch is
  /// watched again. Without it `_fired` stays true for the life of the
  /// process and the watcher is dead for whoever signs in next — which on a
  /// shared phone is a different person entirely.
  void reset() => _fired = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) checkNow();
  }

  /// Safe to call at any time; [start] calls it once itself.
  Future<void> checkNow() async {
    // Resume can fire more than once in quick succession on Android; a second
    // check in flight would double the RPC for no new answer.
    if (_checking || _fired) return;
    _checking = true;
    try {
      if (await DeviceRegistry.instance.isRevoked()) {
        _fired = true;
        _onRevoked?.call();
      }
    } finally {
      _checking = false;
    }
  }
}
