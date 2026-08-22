import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Whether this browser exposes a Web Speech API that `speech_to_text` can
/// actually use.
///
/// Deliberately checks ONLY the prefixed `webkitSpeechRecognition`, even though
/// the unprefixed `SpeechRecognition` is the standard name. The reason is a
/// mismatch inside the plugin: its own support check accepts either name, but
/// the constructor it calls is hardcoded to the prefixed one —
///
///     @JS('webkitSpeechRecognition')
///     extension type _SpeechRecognition._(web.SpeechRecognition _) ...
///
/// — and that `try` has a `finally` but no `catch`. So on a browser carrying
/// only the unprefixed name, the plugin reports itself supported, then throws
/// `webkitSpeechRecognition is not a constructor` out of `initialize()`.
/// Accepting either name here drew a mic button that could only ever fail, and
/// reported it as "this browser cannot do voice search" — on browsers that
/// plainly can.
///
/// Testing the name the plugin will really construct keeps the button honest:
/// hidden where it cannot work, shown where it can. Widen this only once the
/// plugin constructs the unprefixed name too.
bool speechRecognitionMaybeAvailable() =>
    globalContext.has('webkitSpeechRecognition');

/// Asks the browser for the microphone, returning whether it was granted.
///
/// This is the request the app was missing entirely. `speech_to_text`'s web
/// implementation never touches the microphone — its `initialize()` only
/// constructs a `SpeechRecognition` and wires callbacks, and its
/// `hasPermission()` is `return supported;`, i.e. it reports whether the API
/// exists, not whether the mic is allowed. The only implicit prompt came from
/// `start()`, deep inside listen(), by which point a refusal surfaced as
/// "Nothing was heard".
///
/// Call this from the tap handler itself. Browsers only show a permission
/// prompt while a user gesture is still active, and the listening sheet asks
/// after a frame callback and an await, by which point the activation is gone.
///
/// The track is stopped immediately: the grant is the whole point, and leaving
/// it open would light the browser's recording indicator with nothing
/// recording.
Future<bool> requestMicrophonePermission() async {
  final mediaDevices = web.window.navigator.mediaDevices;
  // Older/odd browsers, and any insecure context, expose no mediaDevices at
  // all. Report true and let the recogniser be the one to fail — this probe
  // must never be the reason a working browser is turned away.
  if (mediaDevices.isUndefinedOrNull) return true;
  try {
    final stream = await mediaDevices
        .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
        .toDart;
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }
    return true;
  } catch (_) {
    // Only a definite refusal may block voice search. Everything else —
    // no input device enumerated, an aborted request, a hardware hiccup — must
    // let the attempt proceed: the recogniser may still work off the system
    // default input, and where it truly cannot it fails with 'audio-capture',
    // which reaches the user as a real message. Treating every rejection as a
    // refusal turned a machine with no enumerable microphone into "voice
    // search unavailable".
    return !await _microphoneExplicitlyDenied();
  }
}

/// Whether the browser records the microphone as denied for this origin.
///
/// Asked of the Permissions API rather than inferred from the getUserMedia
/// exception: the exception's shape is not consistent across browsers, and a
/// wrong reading here either blocks a working microphone or reports a blocked
/// one as available.
Future<bool> _microphoneExplicitlyDenied() async {
  try {
    final permissions = web.window.navigator.permissions;
    if (permissions.isUndefinedOrNull) return false;
    final status = await permissions
        .query({'name': 'microphone'}.jsify() as JSObject)
        .toDart;
    return status.state == 'denied';
  } catch (_) {
    // Safari does not accept 'microphone' as a permission name at all. Unknown
    // is not the same as denied, so do not block on it.
    return false;
  }
}
