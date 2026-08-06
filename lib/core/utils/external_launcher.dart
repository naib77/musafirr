/// Cross-platform "open this URL outside the app" helper.
///
/// Why this exists instead of calling `launchUrl` directly:
/// on Flutter **web**, `url_launcher`'s `launchUrl` ignores the launch mode and
/// wraps a `window.open(..., 'noopener,noreferrer')`. That call is easy for
/// browsers to treat as a programmatic popup and silently block, so external
/// links (e.g. "View location on map") appear to do nothing. The web
/// implementation here instead synthesizes a real `<a target="_blank">` click,
/// which browsers treat as first-party user navigation and rarely block.
///
/// On mobile/desktop this delegates to `url_launcher` with
/// `LaunchMode.externalApplication` so the OS hands off to the maps/dialer app.
///
/// Call it **synchronously inside the tap handler** (no `await` before it) so
/// the browser still sees an active user gesture.
library;

export 'external_launcher_io.dart'
    if (dart.library.js_interop) 'external_launcher_web.dart';
