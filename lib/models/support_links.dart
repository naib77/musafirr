import '../config/legal_links.dart';

/// Where Profile → Support sends people: the help destination, the terms, and
/// the privacy policy.
///
/// These were compile-time constants in [LegalLinks], which made replacing a
/// placeholder URL — or moving the terms to a new host — a Dart edit, a
/// rebuild, and a redeploy of the committed web bundle, for a decision that is
/// legal and operational rather than technical. They are now rows in
/// `app_settings`, edited from the admin portal.
///
/// [LegalLinks] stays as the compiled-in fallback, so an unreadable or
/// unmigrated settings table still opens a working link rather than a dead
/// menu item.
class SupportLinks {
  const SupportLinks({
    required this.helpUrl,
    required this.termsUrl,
    required this.privacyUrl,
  });

  /// Where "Get help" goes. A `mailto:` opens the mail client; an `https://`
  /// opens a help centre.
  final String helpUrl;
  final String termsUrl;
  final String privacyUrl;

  /// What the app ships with, and what any unusable setting falls back to.
  static const SupportLinks defaults = SupportLinks(
    helpUrl: LegalLinks.helpUrl,
    termsUrl: LegalLinks.termsUrl,
    privacyUrl: LegalLinks.privacyUrl,
  );

  /// Builds links from the raw `app_settings` text. Any argument may be null
  /// (key absent) or unusable; each falls back to its own default, so one bad
  /// URL never takes the other two down with it.
  static SupportLinks fromRaw({
    String? help,
    String? terms,
    String? privacy,
  }) {
    return SupportLinks(
      helpUrl: sanitiseSupportUrl(help) ?? defaults.helpUrl,
      termsUrl: sanitiseSupportUrl(terms) ?? defaults.termsUrl,
      privacyUrl: sanitiseSupportUrl(privacy) ?? defaults.privacyUrl,
    );
  }
}

/// The value if it is something the app may hand to `launchUrl`, else null.
///
/// Two separate jobs, and both matter:
///
/// * **Correctness.** A typed URL with no scheme (`musaafir.app/terms`) is not
///   openable — `launchUrl` fails and the user gets "Could not open the link"
///   on a legal page they are entitled to read. Falling back to the compiled
///   default shows something that works.
/// * **Safety.** This string comes from a database row and is passed to the
///   platform's URL handler, so the scheme is an allow-list, not a sanity
///   check: `javascript:`, `file:` and `intent:` must never reach it, however
///   they got into the table. Migration 108 refuses them on write too — this
///   is the second half of that, because the app must also survive a row that
///   predates the validator.
///
/// Case is preserved. Paths and mailto addresses are case-sensitive in
/// practice, so this must never be handed an already-lowercased value.
String? sanitiseSupportUrl(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;

  final uri = Uri.tryParse(value);
  if (uri == null) return null;

  switch (uri.scheme.toLowerCase()) {
    case 'http':
    case 'https':
      // A scheme with no host is `https:///terms` and similar — parseable, and
      // openable by nothing.
      return uri.host.isEmpty ? null : value;
    case 'mailto':
      // `mailto:` with no address opens an empty compose window, which reads
      // as the button being broken.
      return uri.path.contains('@') ? value : null;
    default:
      return null;
  }
}
