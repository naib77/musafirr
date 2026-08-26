import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/voice/dictation_language.dart';
import 'package:musafir/services/voice/speech_service.dart';

void main() {
  group('the stored form of a language', () {
    test('round-trips every language', () {
      for (final language in VoiceLanguage.values) {
        expect(decodeVoiceLanguage(encodeVoiceLanguage(language)), language);
      }
    });

    test('is the short code, not the enum name', () {
      // Pinned deliberately: these strings are already on users' devices, so a
      // rename of VoiceLanguage must break this test rather than silently
      // resetting everyone's choice to Auto.
      expect(encodeVoiceLanguage(VoiceLanguage.bangla), 'bn');
      expect(encodeVoiceLanguage(VoiceLanguage.english), 'en');
      expect(encodeVoiceLanguage(VoiceLanguage.auto), 'auto');
    });

    test('anything unreadable means "never chosen"', () {
      expect(decodeVoiceLanguage(null), VoiceLanguage.auto);
      expect(decodeVoiceLanguage(''), VoiceLanguage.auto);
      expect(decodeVoiceLanguage('bengali'), VoiceLanguage.auto);
    });
  });

  group('dictationLanguageHint', () {
    test('explains what Auto actually prefers', () {
      // The whole complaint this control answers is "why is it Bangla?" —
      // saying only "Auto" would leave that unanswered.
      expect(
        dictationLanguageHint(VoiceLanguage.auto).toLowerCase(),
        contains('bangla'),
      );
    });

    test('says something different for each language', () {
      final hints = {
        for (final l in VoiceLanguage.values) dictationLanguageHint(l)
      };
      expect(hints.length, VoiceLanguage.values.length);
    });
  });
}
