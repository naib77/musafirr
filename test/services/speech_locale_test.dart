import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/voice/speech_locale.dart';
import 'package:musafir/services/voice/speech_service.dart';

/// Which language the recogniser is asked for.
///
/// This is the bug: on web, `speech_to_text`'s `locales()` reads
/// `SpeechRecognition.lang`, which is an empty string until a listen has
/// already set it — so it returns an EMPTY list, every time. The app called it
/// once during initialize() to decide whether Bangla existed, concluded it did
/// not, and pinned every "Auto" search to en-US. A Bangladeshi user speaking
/// Bangla got an English recogniser and heard "Nothing was heard".
void main() {
  group('with a real locale list (native platforms)', () {
    const native = ['en_US', 'bn_BD', 'hi_IN'];

    test('auto prefers Bangla when the device really has it', () {
      expect(
        resolveSpeechLocaleId(
          language: VoiceLanguage.auto,
          availableLocaleIds: native,
          canEnumerateLocales: true,
        ),
        'bn_BD',
      );
    });

    test('auto falls back to English when the device has no Bangla', () {
      expect(
        resolveSpeechLocaleId(
          language: VoiceLanguage.auto,
          availableLocaleIds: const ['en_US', 'hi_IN'],
          canEnumerateLocales: true,
        ),
        'en-US',
      );
    });

    test('an explicit Bangla request uses the device id', () {
      expect(
        resolveSpeechLocaleId(
          language: VoiceLanguage.bangla,
          availableLocaleIds: native,
          canEnumerateLocales: true,
        ),
        'bn_BD',
      );
    });

    test('English is always plain en-US', () {
      expect(
        resolveSpeechLocaleId(
          language: VoiceLanguage.english,
          availableLocaleIds: native,
          canEnumerateLocales: true,
        ),
        'en-US',
      );
    });

    test('matches a regional Bangla variant', () {
      expect(
        resolveSpeechLocaleId(
          language: VoiceLanguage.auto,
          availableLocaleIds: const ['en_US', 'bn_IN'],
          canEnumerateLocales: true,
        ),
        'bn_IN',
      );
    });
  });

  group('when locales cannot be enumerated (web)', () {
    // The whole point. An empty list on web means "we do not know", NOT
    // "Bangla is absent" — the browser will accept any BCP-47 tag and tell us
    // only once we try. Treating unknown as absent is what broke voice search
    // for exactly the language the feature exists to serve.
    test('auto still asks for Bangla', () {
      expect(
        resolveSpeechLocaleId(
          language: VoiceLanguage.auto,
          availableLocaleIds: const [],
          canEnumerateLocales: false,
        ),
        'bn-BD',
        reason: 'an unenumerable list must not be read as "no Bangla"',
      );
    });

    test('an explicit Bangla request asks for Bangla', () {
      expect(
        resolveSpeechLocaleId(
          language: VoiceLanguage.bangla,
          availableLocaleIds: const [],
          canEnumerateLocales: false,
        ),
        'bn-BD',
      );
    });

    test('an explicit English request is still honoured', () {
      expect(
        resolveSpeechLocaleId(
          language: VoiceLanguage.english,
          availableLocaleIds: const [],
          canEnumerateLocales: false,
        ),
        'en-US',
      );
    });
  });

  group('the fallback after the browser rejects a language', () {
    test('Bangla falls back to English', () {
      expect(fallbackLocaleId('bn-BD'), 'en-US');
    });

    test('English has nowhere left to fall back to', () {
      // Retrying en-US with en-US would loop forever on a browser that
      // supports no speech language at all.
      expect(fallbackLocaleId('en-US'), isNull);
    });

    test('any Bangla variant falls back to English', () {
      expect(fallbackLocaleId('bn_IN'), 'en-US');
    });
  });
}
