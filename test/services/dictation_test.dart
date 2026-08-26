import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/voice/dictation.dart';
import 'package:musafir/services/voice/speech_service.dart';

void main() {
  group('composeDictationText', () {
    test('uses the transcript alone when the field was empty', () {
      expect(
        composeDictationText(base: '', transcript: '  আমি আসছি  '),
        'আমি আসছি',
      );
    });

    test('appends to text the user had already typed', () {
      expect(
        composeDictationText(base: 'Hi,', transcript: 'I will arrive at nine'),
        'Hi, I will arrive at nine',
      );
    });

    test('does not double the separator the user already typed', () {
      expect(
        composeDictationText(base: 'Hi, ', transcript: 'see you soon'),
        'Hi, see you soon',
      );
    });

    test('keeps a trailing newline, which was a deliberate line break', () {
      expect(
        composeDictationText(base: 'Address:\n', transcript: 'Dhanmondi 27'),
        'Address:\nDhanmondi 27',
      );
    });

    test('leaves the field untouched before anything is heard', () {
      // The recogniser reports an empty partial the moment it opens. Trimming
      // the field there would silently eat a space the user typed.
      expect(composeDictationText(base: 'Hi, ', transcript: ''), 'Hi, ');
      expect(composeDictationText(base: 'Hi, ', transcript: '   '), 'Hi, ');
    });

    test('recomposing a growing turn replaces rather than stutters', () {
      // Each partial carries the whole turn, so composing against the same
      // base is what keeps the field from reading "Dhaka Dhaka te".
      const base = 'Hi,';
      expect(composeDictationText(base: base, transcript: 'I am'), 'Hi, I am');
      expect(
        composeDictationText(base: base, transcript: 'I am on my way'),
        'Hi, I am on my way',
      );
    });
  });

  group('dictationFailureMessage', () {
    test('says something different for every cause', () {
      final messages = {
        for (final f in VoiceFailure.values) dictationFailureMessage(f)
      };
      expect(messages.length, VoiceFailure.values.length);
    });

    test('never tells a chat user to type their search', () {
      // The voice-search wording leaked into messaging once; these messages
      // are separate precisely so that cannot happen silently.
      for (final f in VoiceFailure.values) {
        expect(dictationFailureMessage(f).toLowerCase(),
            isNot(contains('search')));
      }
    });

    test('a refused mic explains how to grant it', () {
      expect(
        dictationFailureMessage(VoiceFailure.permissionDenied),
        contains('address bar'),
      );
    });
  });
}
