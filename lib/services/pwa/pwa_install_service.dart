import 'package:flutter/foundation.dart';

import 'pwa_install_stub.dart'
    if (dart.library.js_interop) 'pwa_install_web.dart';

/// How (or whether) this browser can add Musaafir to the home screen.
enum PwaInstallMode {
  /// Already running as an installed app — nothing left to offer.
  installed,

  /// A `beforeinstallprompt` event is parked and ready: one tap installs.
  prompt,

  /// iOS Safari, which never fires that event. The user has to go through
  /// Share ▸ Add to Home Screen, so we show instructions rather than a button
  /// that cannot do what it says.
  manualIos,

  /// Not installable here — a desktop browser without support, an in-app
  /// webview, a dev run without the bridge, or plain native.
  unsupported,
}

enum PwaInstallOutcome { accepted, dismissed, unavailable }

/// App-wide view of PWA installability, kept in sync with the browser.
///
/// Installability is not a one-shot check: Chrome fires
/// `beforeinstallprompt` some time after load (once its engagement heuristics
/// are satisfied), and revokes it once used. Hence a [ChangeNotifier] the UI
/// listens to, rather than a value read once at startup.
class PwaInstallService extends ChangeNotifier {
  PwaInstallService._();

  static final PwaInstallService instance = PwaInstallService._();

  bool _started = false;
  PwaInstallMode _mode = PwaInstallMode.unsupported;

  PwaInstallMode get mode => _mode;

  /// Whether there is anything worth showing the user — either a real prompt
  /// or the iOS instructions.
  bool get canOffer =>
      _mode == PwaInstallMode.prompt || _mode == PwaInstallMode.manualIos;

  /// Safe to call more than once; a no-op off web.
  void start() {
    if (_started || !kIsWeb) return;
    _started = true;
    pwaOnChanged(_refresh);
    _refresh();
  }

  Future<PwaInstallOutcome> install() async {
    if (!kIsWeb) return PwaInstallOutcome.unavailable;
    final outcome = await pwaPromptInstall();
    _refresh();
    switch (outcome) {
      case 'accepted':
        return PwaInstallOutcome.accepted;
      case 'dismissed':
        return PwaInstallOutcome.dismissed;
      default:
        return PwaInstallOutcome.unavailable;
    }
  }

  void _refresh() {
    final PwaInstallMode next;
    if (pwaIsInstalled()) {
      next = PwaInstallMode.installed;
    } else if (pwaCanInstall()) {
      next = PwaInstallMode.prompt;
    } else if (pwaIsIosSafari()) {
      next = PwaInstallMode.manualIos;
    } else {
      next = PwaInstallMode.unsupported;
    }
    if (next == _mode) return;
    _mode = next;
    notifyListeners();
  }
}
