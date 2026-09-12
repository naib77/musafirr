import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_settings_service.dart';
import 'update/app_update_decision.dart';

/// Android's half of "there is a newer version of this app".
///
/// [WebUpdateService] is the other half and the two are deliberately shaped
/// alike — same singleton, same `start(onUpdateAvailable:)`, same "offer, never
/// impose" default — but they solve different problems. On web a reload always
/// gets the newest build, so that service only has to notice a long-lived tab.
/// On Android the old build is *installed*, and only Play can replace it.
///
/// So everything here is a thin wrapper around Play's In-App Update API. It
/// owns no policy; [appUpdateActionFor] decides, and is tested on its own.
///
/// No-op off Android, including on web — the plugin declares no other platform,
/// so calling into it anywhere else is a `MissingPluginException`.
class AppUpdateService with WidgetsBindingObserver {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  VoidCallback? _onUpdateAvailable;
  VoidCallback? _onReadyToInstall;

  /// Offer the update at most once per session, exactly as the web banner does.
  /// Re-asking on every resume is nagging, and the answer does not change.
  bool _offered = false;

  /// True once Play has the new build on disk and is waiting for a restart.
  /// Kept because the app can be backgrounded between the download finishing
  /// and the user acting on it, and Play does not re-announce.
  bool _readyToInstall = false;

  int? _installedVersionCode;

  /// Whether this platform can do in-app updates at all. Checked rather than
  /// assumed because the plugin is Android-only and this service is started
  /// unconditionally from `MusafirApp`, the same way the web one is.
  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void start({
    required VoidCallback onUpdateAvailable,
    required VoidCallback onReadyToInstall,
  }) {
    if (!_supported) return;
    _onUpdateAvailable = onUpdateAvailable;
    _onReadyToInstall = onReadyToInstall;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_check());
  }

  void stop() {
    if (!_supported) return;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Two reasons to look again on resume. A user who left to do something
    // else may have come back to a release that landed meanwhile — same
    // reasoning as the web service's idle tab. And Play requires that an
    // update already downloaded be offered again on every foreground, or it
    // sits on disk forever waiting for a restart nobody asked for.
    unawaited(_check());
  }

  Future<void> _check() async {
    if (!_supported) return;
    if (_readyToInstall) {
      _onReadyToInstall?.call();
      return;
    }

    final AppUpdateInfo info;
    try {
      info = await InAppUpdate.checkForUpdate();
    } catch (e) {
      // Throws whenever Play cannot answer for this install: a debug build, a
      // sideloaded APK, an emulator with no Play services, or simply no
      // network. None of those is an error the user can act on, and the app
      // works fine without an update check — stay silent and try again on the
      // next resume.
      debugPrint('[AppUpdateService] check skipped: $e');
      return;
    }

    // Downloaded in an earlier session and never installed. Ask for the
    // restart before anything else — there is no newer update to look for.
    if (info.installStatus == InstallStatus.downloaded) {
      _readyToInstall = true;
      _onReadyToInstall?.call();
      return;
    }

    final action = appUpdateActionFor(
      updateAvailable:
          info.updateAvailability == UpdateAvailability.updateAvailable,
      flexibleAllowed: info.flexibleUpdateAllowed,
      immediateAllowed: info.immediateUpdateAllowed,
      installedVersionCode: await _versionCode(),
      minSupportedVersionCode:
          await AppSettingsService.instance.ensureAndroidMinVersionCode(),
    );

    switch (action) {
      case AppUpdateAction.none:
        return;
      case AppUpdateAction.immediate:
        // Play takes the screen from here and restarts the app itself, so
        // there is nothing to await and nothing to show. A user who backs out
        // is asked again on the next resume, which is the point of forcing.
        try {
          await InAppUpdate.performImmediateUpdate();
        } catch (e) {
          debugPrint('[AppUpdateService] immediate update failed: $e');
        }
        return;
      case AppUpdateAction.flexible:
        if (_offered) return;
        _offered = true;
        _onUpdateAvailable?.call();
        return;
    }
  }

  /// Start the background download. Returns false if Play refused or the user
  /// declined, so the caller can drop the banner instead of leaving a promise
  /// on screen that nothing is keeping.
  Future<bool> downloadUpdate() async {
    if (!_supported) return false;
    try {
      final result = await InAppUpdate.startFlexibleUpdate();
      if (result != AppUpdateResult.success) return false;
      _readyToInstall = true;
      _onReadyToInstall?.call();
      return true;
    } catch (e) {
      debugPrint('[AppUpdateService] flexible download failed: $e');
      return false;
    }
  }

  /// Install what was downloaded. Restarts the app, so nothing after this runs.
  Future<void> installUpdate() async {
    if (!_supported) return;
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (e) {
      debugPrint('[AppUpdateService] install failed: $e');
    }
  }

  /// This build's versionCode, read once. `buildNumber` is the `+N` half of
  /// pubspec's `version:` — the same number Play refuses to accept twice.
  Future<int> _versionCode() async {
    if (_installedVersionCode != null) return _installedVersionCode!;
    try {
      final info = await PackageInfo.fromPlatform();
      return _installedVersionCode = installedVersionCodeFromRaw(
        info.buildNumber,
      );
    } catch (e) {
      debugPrint('[AppUpdateService] version read failed: $e');
      // 0 is "unknown", which appUpdateActionFor reads as "never force".
      return _installedVersionCode = 0;
    }
  }
}
