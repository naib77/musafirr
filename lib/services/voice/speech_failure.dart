import 'speech_service.dart';

/// Turns a recogniser error into something worth saying to the user.
///
/// Exists because these errors were being dropped. The Web Speech API reports
/// a refused microphone asynchronously — `error: not-allowed` arrives AFTER
/// `listen()` has already returned success — and the app only debugPrint'ed
/// it. The sheet then fell through to its silence path and told the user
/// "Nothing was heard. Try again, a little closer to the mic." for what was
/// actually a permission refusal, which is unactionable advice and looks
/// exactly like voice search being broken.
///
/// Returns null when the error is not the user's problem: an empty message, or
/// one [VoiceSpeechService] already answers itself (a rejected language, which
/// it retries in English).
///
/// Matching is substring-and-case-insensitive on purpose. Web Speech sends
/// terse codes (`not-allowed`), the Android plugin sends its own names
/// (`error_permission`), and both get wrapped in prose or JSON along the way,
/// so an equality check would miss nearly every real message.
VoiceFailure? mapSpeechError(String errorMsg) {
  final e = errorMsg.trim().toLowerCase();
  if (e.isEmpty) return null;

  // Checked before the permission group: 'service-not-allowed' would otherwise
  // be caught by it, and a browser that cannot serve the language is a retry,
  // not a refusal.
  if (e.contains('language-not-supported') || e.contains('language_not')) {
    return null;
  }

  // A refused mic. 'service-not-allowed' is Chrome's variant when the speech
  // service itself is blocked by policy or by the user blocking the site —
  // different cause, identical remedy, so it is not worth separating.
  if (e.contains('not-allowed') ||
      e.contains('not_allowed') ||
      e.contains('permission') ||
      e.contains('denied')) {
    return VoiceFailure.permissionDenied;
  }

  // Heard nothing. A real outcome rather than a fault, and the only one where
  // "try again, closer to the mic" is honest advice.
  if (e.contains('no-speech') ||
      e.contains('no_match') ||
      e.contains('no-match') ||
      e.contains('speech-timeout') ||
      e.contains('speech_timeout')) {
    return VoiceFailure.noSpeech;
  }

  // Everything else — no usable capture device, network, server, or a code no
  // browser has shipped yet. Unknown codes deliberately land here rather than
  // returning null: an error nobody anticipated is still a failed search, and
  // swallowing it is how this bug happened in the first place.
  return VoiceFailure.error;
}
