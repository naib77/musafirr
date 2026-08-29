/// Central place for the app's external legal / support destinations.
///
/// These are served from the same origin as the web app: they are static files
/// under `web/legal/`, which `flutter build web` copies into `build/web`, which
/// the Cloudflare Worker in `wrangler.jsonc` serves. Same-origin on purpose —
/// the URL in the Play listing and the URL behind Profile → Support are then
/// literally the same page, and neither can rot while the other works.
///
/// They previously pointed at `musaafir.app`, which does not resolve. Google
/// Play requires a *reachable* privacy policy and account-deletion URL, so a
/// dead link here is a blocked submission, not a cosmetic bug.
///
/// If `musaafir.app` is later pointed at the same Worker, change [_origin] to it
/// and every link moves with it — the paths are unchanged.
class LegalLinks {
  const LegalLinks._();

  /// The deployed web app's origin. `tool/verify_deploy.sh` defaults to this
  /// same host; keep the two in step.
  static const String _origin = 'https://musafirr.knaib77.workers.dev';

  /// Terms of Service page.
  static const String termsUrl = '$_origin/legal/terms.html';

  /// Privacy Policy page.
  static const String privacyUrl = '$_origin/legal/privacy.html';

  /// Account-deletion request page.
  ///
  /// Play requires this to be reachable **without installing the app**, and it
  /// is a separate Play Console field from [privacyUrl] — a policy page that
  /// merely mentions deletion does not satisfy it. There is no in-app deletion
  /// flow yet, so the page documents the email request route; build the in-app
  /// flow and this URL can keep pointing at the page that explains both.
  static const String deleteAccountUrl = '$_origin/legal/delete-account.html';

  /// Support/help destination. A `mailto:` opens the user's mail client; an
  /// `https://` opens a help center.
  ///
  /// ⚠️ This mailbox must actually receive mail before the app is public: it is
  /// the contact address in the Play listing, the only route for the deletion
  /// requests promised by [deleteAccountUrl], and Google emails it. The
  /// `musaafir.app` domain did not resolve as of 2026-08-26.
  static const String helpUrl = 'mailto:support@musaafir.app';
}
