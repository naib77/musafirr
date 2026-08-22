import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/voice/speech_failure.dart';
import 'package:musafir/services/voice/speech_service.dart';

/// Why a voice turn ended.
///
/// This is the gap being closed: the Web Speech API reports a denied
/// microphone asynchronously as `error: not-allowed`, AFTER listen() has
/// already returned success. The app only debugPrint'ed it, so the sheet fell
/// through to "Nothing was heard. Try again, a little closer to the mic." — a
/// permission refusal reported as a quiet microphone. VoiceFailure.
/// permissionDenied and .noSpeech existed but were never once produced.
void main() {
  group('permission refusals', () {
    test('not-allowed is a denied microphone', () {
      expect(mapSpeechError('not-allowed'), VoiceFailure.permissionDenied);
    });

    test('service-not-allowed is also a denied microphone', () {
      // Chrome uses this when the speech SERVICE is blocked (policy, or the
      // user blocked the site). Same thing to the user: they must allow it.
      expect(
        mapSpeechError('service-not-allowed'),
        VoiceFailure.permissionDenied,
      );
    });

    test('Android phrasing is recognised too', () {
      // The native plugin sends prose, not Web Speech error codes.
      expect(
        mapSpeechError('error_permission'),
        VoiceFailure.permissionDenied,
      );
    });
  });

  group('silence', () {
    test('no-speech is silence, not a fault', () {
      expect(mapSpeechError('no-speech'), VoiceFailure.noSpeech);
    });

    test('Android no-match phrasing is silence', () {
      expect(mapSpeechError('error_no_match'), VoiceFailure.noSpeech);
    });
  });

  group('real faults', () {
    test('audio-capture means no usable microphone', () {
      expect(mapSpeechError('audio-capture'), VoiceFailure.error);
    });

    test('network failures are faults', () {
      expect(mapSpeechError('network'), VoiceFailure.error);
    });

    test('an unrecognised code is still a fault, not silently ignored', () {
      expect(
          mapSpeechError('something-new-from-a-browser'), VoiceFailure.error);
    });
  });

  group('handled elsewhere', () {
    test('language-not-supported is not a user-facing failure', () {
      // VoiceSpeechService answers this one by retrying in English, so
      // surfacing it would show an error for something already being fixed.
      expect(mapSpeechError('language-not-supported'), isNull);
    });

    test('an empty message is not a failure', () {
      expect(mapSpeechError(''), isNull);
      expect(mapSpeechError('   '), isNull);
    });
  });

  test('matching ignores case and surrounding prose', () {
    // The plugin wraps codes in json/prose depending on platform, so an exact
    // equality check would quietly miss every real-world message.
    expect(
      mapSpeechError('SpeechRecognitionError: NOT-ALLOWED (fatal)'),
      VoiceFailure.permissionDenied,
    );
  });
}
