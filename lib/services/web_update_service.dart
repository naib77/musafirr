import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show VoidCallback, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'web_update/reload_stub.dart'
    if (dart.library.js_interop) 'web_update/reload_web.dart';

/// Detects that a newer web build has been deployed while this tab stays open.
///
/// Cache headers already guarantee any page RELOAD gets the newest deploy —
/// the gap is single-page-app tabs that never reload. `tool/build_web.sh`
/// stamps every build with `build_stamp.json` (git commit + build time,
/// served no-cache); this service remembers the stamp it booted with, re-reads
/// it every few minutes and on tab re-focus, and fires [start]'s callback once
/// when it changes so the app can offer a refresh.
///
/// No-op off web. Silent in dev runs (`flutter run` serves no stamp file).
class WebUpdateService with WidgetsBindingObserver {
  WebUpdateService._();
  static final WebUpdateService instance = WebUpdateService._();

  static const _pollEvery = Duration(minutes: 5);

  String? _baseline;
  Timer? _timer;
  VoidCallback? _onUpdateAvailable;
  bool _notified = false;

  void start({required VoidCallback onUpdateAvailable}) {
    if (!kIsWeb) return;
    _onUpdateAvailable = onUpdateAvailable;
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  void stop() {
    if (!kIsWeb) return;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Reload the page to pick up the new build (web only; no-op elsewhere).
  void reloadForUpdate() => reloadPage();

  Future<void> _init() async {
    _baseline = await _fetchStamp();
    if (_baseline == null) return; // no stamp (dev run) — stay silent
    _timer = Timer.periodic(_pollEvery, (_) => _check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to a long-idle tab is exactly when a stale build is likely.
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_notified || _baseline == null) return;
    final current = await _fetchStamp();
    if (current == null || current == _baseline) return;
    _notified = true;
    _timer?.cancel();
    _onUpdateAvailable?.call();
  }

  Future<String?> _fetchStamp() async {
    try {
      final uri = Uri.base.resolve(
          'build_stamp.json?ts=${DateTime.now().millisecondsSinceEpoch}');
      final res = await http.get(uri);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      return data is Map ? data['build'] as String? : null;
    } catch (_) {
      return null;
    }
  }
}
