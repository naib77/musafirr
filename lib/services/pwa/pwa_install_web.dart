import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Dart half of the `window.__musafirPwa` bridge installed by `web/index.html`.
///
/// The bridge is what actually holds the deferred `beforeinstallprompt` event —
/// it has to, because that event fires long before this bundle boots.
///
/// A `flutter run` served from an older index.html (or any host that serves its
/// own shell) has no bridge, so every accessor degrades to "nothing to install"
/// rather than throwing.
JSObject? get _bridge {
  if (!globalContext.has('__musafirPwa')) return null;
  return globalContext.getProperty<JSObject?>('__musafirPwa'.toJS);
}

/// Whether a one-tap install prompt is currently available (Chromium browsers).
bool pwaCanInstall() => _probe('canInstall');

/// Whether we are already running as an installed app (standalone display mode,
/// or `navigator.standalone` on iOS).
bool pwaIsInstalled() => _probe('isInstalled');

/// iOS Safari, where installing is a manual Share ▸ Add to Home Screen flow.
bool pwaIsIosSafari() => _probe('isIos');

/// Shows the browser's install dialog.
/// Resolves to `'accepted'`, `'dismissed'` or `'unavailable'`.
Future<String> pwaPromptInstall() async {
  final bridge = _bridge;
  if (bridge == null) return 'unavailable';
  final outcome =
      await bridge.callMethod<JSPromise<JSString>>('prompt'.toJS).toDart;
  return outcome.toDart;
}

/// Fires whenever installability changes: the prompt becomes available, gets
/// consumed, or the app is installed.
void pwaOnChanged(void Function() listener) {
  web.window.addEventListener(
    'musafir-pwa-changed',
    ((web.Event _) => listener()).toJS,
  );
}

bool _probe(String method) {
  final bridge = _bridge;
  if (bridge == null || !bridge.has(method)) return false;
  return bridge.callMethod<JSBoolean>(method.toJS).toDart;
}
