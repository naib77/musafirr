import 'speech_service.dart';

/// Merges a dictation transcript into whatever the composer already held.
///
/// Dictation is additive on purpose: someone who typed half a sentence and
/// then reached for the mic means "carry on from here", so the transcript is
/// appended rather than made to replace the field. The whole turn's transcript
/// is passed every time — the recogniser reports cumulative text for a turn —
/// so the caller keeps the pre-dictation text as [base] and recomposes on each
/// partial result. Appending the partials as they arrive would stutter the
/// field ("Dhaka Dhaka te Dhaka te jabo").
///
/// [base]'s own trailing whitespace is respected rather than normalised: a
/// user who left a newline there was starting a new line, and a chat message
/// is one place where that formatting is the point.
String composeDictationText(
    {required String base, required String transcript}) {
  final heard = transcript.trim();
  // Nothing heard yet — the field must be left exactly as the user left it,
  // including a trailing space they typed.
  if (heard.isEmpty) return base;
  if (base.isEmpty) return heard;
  final needsSpace =
      !base.endsWith(' ') && !base.endsWith('\n') && !base.endsWith('\t');
  return needsSpace ? '$base $heard' : '$base$heard';
}

/// What to tell someone whose dictation could not run.
///
/// Deliberately separate from the voice-search wording: those messages end in
/// "You can still type your search", which is nonsense over a chat composer,
/// and the remedy for a blocked mic is worth spelling out in both places
/// rather than collapsing every cause into one apology. See [mapSpeechError]
/// for why the causes are kept apart at all.
String dictationFailureMessage(VoiceFailure failure) => switch (failure) {
      VoiceFailure.permissionDenied =>
        'Musafir needs permission to use your microphone. Allow it for this '
            'site — in Chrome, tap the icon at the left of the address bar — '
            'then tap the mic again.',
      VoiceFailure.unsupported =>
        'This browser cannot take dictation. Chrome on Android or desktop '
            'can; Firefox cannot. You can still type your message.',
      VoiceFailure.noSpeech =>
        'Nothing was heard. Tap the mic and try again, a little closer to it.',
      VoiceFailure.error =>
        'Dictation could not start. Check that no other app is using the '
            'microphone, then try again.',
    };
