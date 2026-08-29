import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/auth/phone_number.dart';

/// This function decides **which account you log into**.
///
/// `verify-otp` derives the Supabase auth identity from the canonical number
/// (`phone.<canonical>@musaafir.app`) and creates an account per distinct
/// value, so any two spellings of one number that canonicalise differently are
/// two separate users — separate listings, bookings, and separate identity
/// verifications to submit.
///
/// It shipped with no tests at all, and with two divergent implementations
/// (`OtpService.normalizePhoneNumber` and `SupabaseAuthService._normalizePhone`)
/// alongside a third in TypeScript. Four real accounts were duplicated before
/// anyone noticed.
void main() {
  group('canonicalBdPhone', () {
    // The login screen renders "+880" as a decorative prefixIcon and submits
    // the raw text, so the user is actively invited to omit the leading zero —
    // "+880" visually replaces it. Both spellings below are correct human
    // behaviour and MUST reach the same account.
    const spellings = <String>[
      '01711165212',
      '1711165212', // the one that used to fall through unchanged
      '+8801711165212',
      '+880 1711165212',
      '8801711165212',
      '+880 1711-165212',
      '01711 165212',
      '(017) 1116-5212',
    ];

    test('every spelling of one number yields exactly one identity', () {
      final identities = <String, List<String>>{};
      for (final s in spellings) {
        identities.putIfAbsent(canonicalBdPhone(s), () => []).add(s);
      }
      expect(
        identities.keys,
        hasLength(1),
        reason: 'one phone number must be one account, but got '
            '${identities.length}: $identities',
      );
      expect(identities.keys.single, '01711165212');
    });

    test('canonical form is the 11-digit national format', () {
      // Leading zero, no country code, no punctuation. profiles.mobile is
      // rendered from this, and CLAUDE.md documents the master-OTP allowlist as
      // matching on it.
      expect(canonicalBdPhone('+880 1673-293542'), '01673293542');
      expect(canonicalBdPhone('01673293542'), '01673293542');
      expect(canonicalBdPhone('1673293542'), '01673293542');
    });

    test('accepts every real BD operator prefix without a leading zero', () {
      // 013-019 are the assigned mobile prefixes. A 10-digit number starting
      // with any of them is a national-significant number missing its zero.
      for (final prefix in ['13', '14', '15', '16', '17', '18', '19']) {
        final bare = '${prefix}11165212';
        expect(bare.length, 10, reason: 'fixture is a 10-digit number');
        expect(
          canonicalBdPhone(bare),
          '0$bare',
          reason: 'prefix $prefix should gain a leading zero',
        );
      }
    });

    test('leaves a number that is not a bare BD mobile alone', () {
      // Only the exact "10 digits starting 1[3-9]" shape is assumed to be a
      // zero-less BD mobile. Guessing more widely would silently rewrite
      // numbers that are simply wrong, turning a failed login into a login to
      // somebody else's account.
      expect(canonicalBdPhone('1211165212'), '1211165212'); // 12x not assigned
      expect(canonicalBdPhone('171116521'), '171116521'); // 9 digits
      expect(canonicalBdPhone('17111652123'), '17111652123'); // 11 digits
      expect(canonicalBdPhone(''), '');
    });

    test('is idempotent — canonicalising twice changes nothing', () {
      // The value is stored and re-normalised on later reads; a second pass
      // that shifted it would resurrect the same class of bug.
      for (final s in spellings) {
        final once = canonicalBdPhone(s);
        expect(canonicalBdPhone(once), once, reason: 'not idempotent for "$s"');
      }
    });

    test('strips a non-BD country code rather than mangling it', () {
      // Matches the TypeScript implementation's final `+` branch, which the
      // Dart copy was missing entirely — a divergence the shared comment
      // claimed did not exist.
      expect(canonicalBdPhone('+11234567890'), '11234567890');
    });
  });

  group('phoneToAuthEmail', () {
    test('derives the identity the edge function derives', () {
      // Must match supabase/functions/_shared/otp.ts phoneToEmail exactly. If
      // these two ever disagree the client and server disagree about who is
      // logging in.
      expect(
        phoneToAuthEmail(canonicalBdPhone('1711165212')),
        'phone.01711165212@musaafir.app',
      );
      expect(
        phoneToAuthEmail(canonicalBdPhone('+880 1711165212')),
        'phone.01711165212@musaafir.app',
      );
    });
  });
}
