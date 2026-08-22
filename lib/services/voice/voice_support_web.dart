import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Whether this browser exposes the Web Speech API.
///
/// Chrome and Samsung Internet do (prefixed), Safari does under the prefix,
/// and Firefox and Edge do not ship it at all — so this returns false for a
/// meaningful slice of desktop traffic, which is exactly the point. A mic
/// button that cannot listen is worse than no mic button.
bool speechRecognitionMaybeAvailable() =>
    globalContext.has('SpeechRecognition') ||
    globalContext.has('webkitSpeechRecognition');
