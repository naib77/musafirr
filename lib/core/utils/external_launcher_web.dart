import 'package:web/web.dart' as web;

/// Web implementation: synthesize a real anchor click.
///
/// A `<a href target="_blank" rel="noopener noreferrer">` that is clicked during
/// the user's tap is treated as first-party navigation, so it opens a new tab
/// reliably where `window.open` (what url_launcher uses under the hood) is often
/// popup-blocked. The anchor is briefly attached to the DOM because some
/// browsers ignore `.click()` on a detached element.
Future<bool> openExternalUrl(String url) async {
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..target = '_blank'
    ..rel = 'noopener noreferrer'
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  return true;
}
