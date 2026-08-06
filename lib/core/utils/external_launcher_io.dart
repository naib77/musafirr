import 'package:url_launcher/url_launcher.dart';

/// Mobile/desktop implementation: hand the URL to the OS (maps app, dialer,
/// mail client, browser) via url_launcher. Returns whether the launch
/// succeeded.
Future<bool> openExternalUrl(String url) {
  return launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
}
