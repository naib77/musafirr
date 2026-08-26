import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/config/legal_links.dart';
import 'package:musafir/models/support_links.dart';

void main() {
  group('sanitiseSupportUrl', () {
    test('keeps an ordinary https page', () {
      expect(
        sanitiseSupportUrl('https://musafir.example/terms'),
        'https://musafir.example/terms',
      );
    });

    test('keeps a mailto address', () {
      expect(
        sanitiseSupportUrl('mailto:help@musafir.example'),
        'mailto:help@musafir.example',
      );
    });

    test('preserves case, which a path depends on', () {
      // The settings loader lowercases every other key's value; these three
      // must not be, and this is the test that fails if that changes.
      expect(
        sanitiseSupportUrl('https://Musafir.example/Legal/Terms-EN'),
        'https://Musafir.example/Legal/Terms-EN',
      );
    });

    test('trims surrounding whitespace from a pasted URL', () {
      expect(
        sanitiseSupportUrl('  https://musafir.example/privacy \n'),
        'https://musafir.example/privacy',
      );
    });

    test('rejects a URL with no scheme, which nothing can open', () {
      expect(sanitiseSupportUrl('musafir.example/terms'), isNull);
      expect(sanitiseSupportUrl('www.musafir.example'), isNull);
    });

    test('rejects schemes that must never reach a URL launcher', () {
      // An allow-list, not a spell-check: this value comes from a database row
      // and is handed to the platform's launcher.
      expect(sanitiseSupportUrl('javascript:alert(1)'), isNull);
      expect(sanitiseSupportUrl('JavaScript:alert(1)'), isNull);
      expect(sanitiseSupportUrl('file:///etc/passwd'), isNull);
      expect(sanitiseSupportUrl('intent://scan/#Intent;end'), isNull);
      expect(sanitiseSupportUrl('data:text/html,<h1>hi'), isNull);
    });

    test('rejects a scheme with nothing behind it', () {
      expect(sanitiseSupportUrl('https://'), isNull);
      expect(sanitiseSupportUrl('mailto:'), isNull);
      expect(sanitiseSupportUrl('mailto:not-an-address'), isNull);
    });

    test('rejects empty and absent values', () {
      expect(sanitiseSupportUrl(null), isNull);
      expect(sanitiseSupportUrl(''), isNull);
      expect(sanitiseSupportUrl('   '), isNull);
    });
  });

  group('SupportLinks.fromRaw', () {
    test('an unmigrated settings table keeps the compiled-in links', () {
      final links = SupportLinks.fromRaw();

      expect(links.helpUrl, LegalLinks.helpUrl);
      expect(links.termsUrl, LegalLinks.termsUrl);
      expect(links.privacyUrl, LegalLinks.privacyUrl);
    });

    test('each configured link is used', () {
      final links = SupportLinks.fromRaw(
        help: 'https://help.musafir.example',
        terms: 'https://musafir.example/tos',
        privacy: 'https://musafir.example/privacy',
      );

      expect(links.helpUrl, 'https://help.musafir.example');
      expect(links.termsUrl, 'https://musafir.example/tos');
      expect(links.privacyUrl, 'https://musafir.example/privacy');
    });

    test('one bad value does not take the other two down with it', () {
      final links = SupportLinks.fromRaw(
        help: 'javascript:alert(1)',
        terms: 'https://musafir.example/tos',
        privacy: '  ',
      );

      expect(links.helpUrl, LegalLinks.helpUrl);
      expect(links.termsUrl, 'https://musafir.example/tos');
      expect(links.privacyUrl, LegalLinks.privacyUrl);
    });
  });
}
