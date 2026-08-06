/// Central place for the app's external legal / support destinations.
///
/// ⚠️ ACTION REQUIRED: verify/replace these with your real URLs and support
/// address. They are wired to open in the browser / mail client from
/// Profile → Support and Profile → Settings. If a value is left blank the
/// corresponding menu item shows a graceful "not available" message instead of
/// opening a broken link.
class LegalLinks {
  const LegalLinks._();

  /// Terms of Service page.
  static const String termsUrl = 'https://musafir.app/terms';

  /// Privacy Policy page.
  static const String privacyUrl = 'https://musafir.app/privacy';

  /// Support/help destination. A `mailto:` opens the user's mail client; an
  /// `https://` opens a help center.
  static const String helpUrl = 'mailto:support@musafir.app';
}
