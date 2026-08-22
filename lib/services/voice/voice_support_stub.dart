import 'package:flutter/foundation.dart';

/// Whether this build could plausibly run speech recognition, checked WITHOUT
/// touching the microphone.
///
/// The distinction matters: `SpeechToText.initialize()` asks Android for the
/// RECORD_AUDIO permission, so calling it just to decide whether to draw a
/// button would throw a permission dialog at every user on first launch. This
/// probe is free, so the mic can be hidden up front where it could never work.
///
/// Native: Android only, per the scope of this feature. iOS has no Bengali
/// locale on `SFSpeechRecognizer`, and shipping a mic that fails for exactly
/// the language it exists to serve is worse than shipping none.
bool speechRecognitionMaybeAvailable() =>
    defaultTargetPlatform == TargetPlatform.android;
