/// Canonical form of a Bangladeshi phone number, and the auth identity derived
/// from it.
///
/// ## Why this is its own file
///
/// This is not formatting — it decides **which account a user logs into**.
/// `supabase/functions/verify-otp` derives the Supabase auth email from the
/// canonical number (`phone.<canonical>@musaafir.app`) and creates one account
/// per distinct value. Two spellings of the same number that canonicalise
/// differently are therefore two different people as far as the app is
/// concerned: separate listings, separate bookings, and a separate identity
/// verification to submit and have approved.
///
/// It used to live as a method on `OtpService` (which pulls in Supabase and so
/// could not be unit-tested), duplicated as a private `_normalizePhone` on
/// `SupabaseAuthService` that had diverged, and a third time in TypeScript.
/// None of the three had a test. Extracted here so the rule has exactly one
/// implementation per language and a seam to test it through.
///
/// ## The bug this fixes
///
/// The login screen renders `+880` as a decorative `prefixIcon` and submits the
/// raw field text, so the user is actively invited to leave out the leading
/// zero — visually the `+880` replaces it. The old rule handled `+880…`, `880…`
/// and an already-canonical `01…`, but a bare `1711165212` matched no branch
/// and was returned unchanged, producing `phone.1711165212@musaafir.app`
/// alongside `phone.01711165212@musaafir.app` for one human being.
///
/// Four production accounts were duplicated this way, with users submitting
/// identity documents twice and their listings and bookings split across two
/// logins. See `supabase/migrations/109_merge_duplicate_phone_accounts.sql`.
///
/// **Keep [canonicalBdPhone] and [phoneToAuthEmail] byte-for-byte equivalent to
/// `normalizePhone` / `phoneToEmail` in `supabase/functions/_shared/otp.ts`.**
/// The server is authoritative for account creation; a client that disagrees
/// merely rate-limits the wrong key, but a *server* that disagrees with the
/// stored rows locks users out. `test/services/phone_number_test.dart` pins the
/// contract on this side.
library;

/// The assigned Bangladeshi mobile operator prefixes, as they appear once the
/// national leading zero is stripped: 013-019 → `1[3-9]`, then eight more
/// digits.
final RegExp _bareBdMobile = RegExp(r'^1[3-9][0-9]{8}$');

/// Reduces any spelling of a BD number to the 11-digit national format
/// (`01711165212`).
///
/// Handles `+880…`, `880…`, an already-canonical `01…`, punctuation and spaces,
/// and — the case that caused duplicate accounts — a bare 10-digit
/// national-significant number with the leading zero omitted.
String canonicalBdPhone(String input) {
  var n = input.replaceAll(RegExp(r'[\s\-()]'), '');

  if (n.startsWith('+880')) {
    n = '0${n.substring(4)}';
  } else if (n.startsWith('880')) {
    n = '0${n.substring(3)}';
  } else if (n.startsWith('+')) {
    // Some other country code. Strip the plus and leave it alone rather than
    // guessing — this branch exists in the TypeScript original and was missing
    // from the Dart copy, despite a comment claiming the two matched.
    n = n.substring(1);
  }

  // The fix. Only the exact "10 digits starting 1[3-9]" shape is treated as a
  // BD mobile missing its zero. Guessing more widely would rewrite numbers that
  // are simply mistyped, which turns a failed login into a login to somebody
  // else's account — a worse failure than the one being fixed.
  if (_bareBdMobile.hasMatch(n)) {
    n = '0$n';
  }

  return n;
}

/// The internal Supabase-auth email for a canonical number.
///
/// Phone accounts have no real email address; this synthetic one is the key
/// phone logins are matched on. Pass the output of [canonicalBdPhone] — passing
/// raw input here is how duplicate accounts get created.
String phoneToAuthEmail(String canonicalPhone) =>
    'phone.$canonicalPhone@musaafir.app';
