import 'package:web/web.dart' as web;

/// Full page reload: re-fetches index.html + flutter_bootstrap.js (both
/// served no-cache), which pulls in the freshly deployed build.
void reloadPage() => web.window.location.reload();
