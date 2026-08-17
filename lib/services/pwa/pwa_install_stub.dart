/// Non-web stub — "add to home screen" only means something in a browser.
/// Mirrors `pwa_install_web.dart`; the conditional import in
/// `pwa_install_service.dart` picks whichever applies.
bool pwaCanInstall() => false;

bool pwaIsInstalled() => false;

bool pwaIsIosSafari() => false;

Future<String> pwaPromptInstall() async => 'unavailable';

void pwaOnChanged(void Function() listener) {}
