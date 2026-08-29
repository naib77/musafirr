import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'speech_failure.dart';
import 'speech_locale.dart';
import 'voice_support_stub.dart'
    if (dart.library.js_interop) 'voice_support_web.dart';

/// Which language the recogniser was asked for. Auto is not a third engine —
/// it just picks Bangla where the device has it, because that is what most
/// Bangladeshi users speak into a search box.
enum VoiceLanguage { bangla, english, auto }

extension VoiceLanguageLabel on VoiceLanguage {
  String get label => switch (this) {
        VoiceLanguage.bangla => 'বাংলা',
        VoiceLanguage.english => 'English',
        VoiceLanguage.auto => 'Auto',
      };
}

/// Why listening could not start. Each maps to a different thing worth saying
/// to the user — "your browser can't" and "you said no to the mic" need
/// different responses, and a single generic failure message earns support
/// tickets.
enum VoiceFailure { unsupported, permissionDenied, noSpeech, error }

/// Thin wrapper over `speech_to_text`, which is itself a wrapper over the
/// Android recogniser and the browser Web Speech API. Both are free, keyless,
/// and unlimited — there is no cloud STT behind this and no billing account
/// attached to it.
///
/// Kept as a singleton because the underlying plugin holds one native
/// recogniser per process; two instances listening at once fight over it.
class VoiceSpeechService {
  /// [plugin] is a test seam. The initialize/retry logic here is exactly what
  /// decides which message a user sees when voice search fails, and it was
  /// untestable: tests could only replace the whole service via
  /// [debugOverride], which skips this logic entirely.
  VoiceSpeechService({stt.SpeechToText? plugin}) : _plugin = plugin;

  static final VoiceSpeechService instance = VoiceSpeechService();

  /// Test seam — a fake subclass stands in so widget tests never touch a real
  /// microphone (there isn't one in the test harness). Always read the service
  /// through [current], never through [instance].
  @visibleForTesting
  static VoiceSpeechService? debugOverride;

  static VoiceSpeechService get current => debugOverride ?? instance;

  /// Created on first use, not in the field initialiser: a fake overrides
  /// every method that would touch it, and constructing the real plugin in a
  /// test that will never listen is pure waste.
  stt.SpeechToText? _plugin;

  stt.SpeechToText get _speech => _plugin ??= stt.SpeechToText();

  bool _available = false;

  /// The most recent message from the recogniser. Read straight after a failed
  /// initialize to say WHY it failed: the platform reports the reason through
  /// onError and then simply returns false, so this is the only record of it.
  String? _lastErrorMsg;

  /// Fired once when the recogniser stops on its own. Search runs without a
  /// button press, so the caller has to know the turn ended even in the case
  /// where the engine closes the mic without ever sending a final result —
  /// otherwise the sheet would sit listening to a microphone that is shut.
  void Function()? _onDone;
  List<stt.LocaleName> _locales = const [];

  /// Why the last [initialize] failed, so the caller can say something true.
  /// `unsupported` means this browser/device has no recogniser at all;
  /// `permissionDenied` means the microphone was refused.
  VoiceFailure? _initFailure;

  /// Set when a turn is reported failed asynchronously (the Web Speech API
  /// delivers a refused mic through onError, long after listen() returned).
  void Function(VoiceFailure failure)? _onFailure;

  /// The turn in flight, kept so a `language-not-supported` error — which
  /// arrives asynchronously, after listen() has already returned success — can
  /// be answered by retrying in English instead of showing the user a dead mic.
  _LocaleRetry? _retry;

  /// Free capability probe — safe to call during `build`, never prompts.
  bool get maybeAvailable => speechRecognitionMaybeAvailable();

  /// True once [initialize] has run and the platform said yes.
  bool get isAvailable => _available;

  bool get isListening => _speech.isListening;

  /// Why [initialize] last returned false. Null when it succeeded.
  VoiceFailure? get initFailure => _initFailure;

  /// Asks for the microphone up front, returning whether it is available.
  ///
  /// MUST be called straight from the tap handler. Browsers only show a
  /// permission prompt while a user gesture is still live, and the listening
  /// sheet asks after a post-frame callback and an await — by which point the
  /// activation is spent and Chrome can decline to prompt at all.
  ///
  /// A grant is remembered for the session so [initialize] does not ask again
  /// moments later: the second request is silent, but it re-opens and closes an
  /// audio track, which blinks the browser's recording indicator for no reason.
  /// A revoked permission still surfaces — the turn then fails with
  /// `not-allowed`, which [mapSpeechError] turns into a real message.
  Future<bool> ensureMicrophonePermission() async {
    if (_micGranted == true) return true;
    final granted = await requestMicrophonePermission();
    _micGranted = granted;
    return granted;
  }

  bool? _micGranted;

  /// Asks the platform for a recogniser, prompting for microphone permission
  /// on the way. MUST be called from a user gesture: browsers reject a
  /// permission request that no click preceded, and asking an Android user
  /// for the mic before they tapped anything reads as spyware.
  Future<bool> initialize() async {
    // Only success is cached. A failed attempt MUST be retryable: the usual
    // reason for failing is a permission the user is about to grant, and
    // remembering the refusal meant they could never get past it without
    // reloading the page.
    if (_available) return true;
    if (!maybeAvailable) {
      _initFailure = VoiceFailure.unsupported;
      return false;
    }
    // On web this is the only thing that ever asks for the microphone: the
    // plugin's initialize() just builds a SpeechRecognition and its
    // hasPermission() reports whether the API exists, not whether the mic is
    // allowed. No-op on native, where the plugin asks for RECORD_AUDIO itself.
    if (!await ensureMicrophonePermission()) {
      _initFailure = VoiceFailure.permissionDenied;
      return false;
    }
    _lastErrorMsg = null;
    try {
      _available = await _speech.initialize(
        onError: (e) {
          debugPrint('[VoiceSpeechService] error: ${e.errorMsg}');
          _lastErrorMsg = e.errorMsg;
          _maybeRetryInEnglish(e.errorMsg);
          // Errors arrive here asynchronously, after listen() has already
          // returned success, so this is the ONLY route by which a refused
          // microphone can reach the UI. Dropping it is what made a denial
          // read as "Nothing was heard".
          final failure = mapSpeechError(e.errorMsg);
          if (failure != null) _onFailure?.call(failure);
        },
        onStatus: (s) {
          debugPrint('[VoiceSpeechService] status: $s');
          // Both 'notListening' and 'done' arrive for one turn; the callback
          // is cleared as it fires so the caller hears about it once.
          if (s == 'notListening' || s == 'done') {
            final ended = _onDone;
            _onDone = null;
            ended?.call();
          }
        },
        debugLogging: false,
      );
      if (_available) {
        _locales = await _speech.locales();
        _initFailure = null;
      } else {
        // The platform said no. Prefer what it actually reported; fall back to
        // a plain error rather than claiming the browser has no recogniser —
        // that reading is unfalsifiable to the user and, on a browser that
        // clearly does have one, simply wrong. It is also what produced
        // "This browser cannot do voice search" on Chrome.
        _initFailure = _failureFromLastError() ?? VoiceFailure.error;
      }
    } catch (e) {
      debugPrint('[VoiceSpeechService] initialize failed: $e');
      _available = false;
      // The platform commonly reports the reason through onError and THEN
      // throws — the web plugin does exactly that, sending
      // 'speech_not_supported' before throwing "webkitSpeechRecognition is not
      // a constructor". That report is the only accurate account of what
      // happened, so it must survive the exception.
      _initFailure = _failureFromLastError() ?? VoiceFailure.error;
    }
    return _available;
  }

  /// The `bn` locale this device actually has, or null when it has none.
  /// Never assume Bangla is present — Android phones without Google speech
  /// services, and every Safari build, will not have it.
  stt.LocaleName? get banglaLocale {
    for (final l in _locales) {
      final id = l.localeId.toLowerCase().replaceAll('-', '_');
      if (id == 'bn_bd') return l;
    }
    for (final l in _locales) {
      if (l.localeId.toLowerCase().startsWith('bn')) return l;
    }
    return null;
  }

  /// Whether a Bangla search is worth offering.
  ///
  /// On web this can only ever be a "probably": the browser exposes no locale
  /// list (see [resolveSpeechLocaleId]), so absence of evidence is not
  /// evidence of absence. Chrome does serve bn-BD, so web reports true and
  /// [listen] retries in English if a particular browser disagrees.
  bool get supportsBangla => banglaLocale != null || !_canEnumerateLocales;

  /// False where the platform cannot list its speech locales — web, where
  /// `locales()` reads `SpeechRecognition.lang` and gets an empty string until
  /// a listen has already set it, so the list is always empty.
  bool get _canEnumerateLocales => !kIsWeb;

  String _resolveLocaleId(VoiceLanguage language) => resolveSpeechLocaleId(
        language: language,
        availableLocaleIds: [for (final l in _locales) l.localeId],
        canEnumerateLocales: _canEnumerateLocales,
      );

  /// Starts listening. [onResult] fires repeatedly with partial text and once
  /// more with `isFinal` set; [onLevel] carries mic amplitude for the meter.
  Future<VoiceFailure?> listen({
    required VoiceLanguage language,
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onLevel,
    void Function(VoiceFailure failure)? onFailure,
    void Function()? onDone,
    Duration listenFor = const Duration(seconds: 20),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    final ready = await initialize();
    if (!ready) return _initFailure ?? VoiceFailure.error;

    _onDone = onDone;
    _onFailure = onFailure;
    final localeId = _resolveLocaleId(language);
    // A browser may accept the tag and only then report that it cannot serve
    // that language. Remember enough to retry once in English rather than
    // leaving the sheet on "Nothing was heard".
    _retry = _LocaleRetry(
      localeId: localeId,
      onResult: onResult,
      onLevel: onLevel,
      onFailure: onFailure,
      onDone: onDone,
      listenFor: listenFor,
      pauseFor: pauseFor,
    );
    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult r) =>
            onResult(r.recognizedWords, r.finalResult),
        onSoundLevelChange: onLevel == null ? null : (l) => onLevel(l),
        listenOptions: stt.SpeechListenOptions(
          localeId: localeId,
          // Partial results are what let the sheet show text as it is spoken,
          // which is the single biggest trust factor in a voice UI.
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.search,
          listenFor: listenFor,
          pauseFor: pauseFor,
        ),
      );
      return null;
    } catch (e) {
      debugPrint('[VoiceSpeechService] listen failed: $e');
      onFailure?.call(VoiceFailure.error);
      return VoiceFailure.error;
    }
  }

  /// What the platform last reported, as a failure — null when it said nothing
  /// useful.
  VoiceFailure? _failureFromLastError() {
    final msg = _lastErrorMsg;
    return msg == null ? null : mapSpeechError(msg);
  }

  /// Web Speech accepts any language tag and only then reports that it cannot
  /// serve it. Bangla is requested optimistically on web (the browser exposes
  /// no locale list to check against), so this is the other half of that bet:
  /// one retry in English, then give up.
  void _maybeRetryInEnglish(String errorMsg) {
    final pending = _retry;
    if (pending == null) return;
    // Web reports 'language-not-supported'; Android's message differs but also
    // names the language. Anything else is a real failure, not a wrong guess.
    if (!errorMsg.toLowerCase().contains('language')) return;
    if (fallbackLocaleId(pending.localeId) == null) return;

    _retry = null;
    debugPrint('[VoiceSpeechService] ${pending.localeId} not supported — '
        'retrying in English');
    unawaited(listen(
      language: VoiceLanguage.english,
      onResult: pending.onResult,
      onLevel: pending.onLevel,
      onFailure: pending.onFailure,
      onDone: pending.onDone,
      listenFor: pending.listenFor,
      pauseFor: pending.pauseFor,
    ));
  }

  /// Ends the turn and keeps whatever was heard.
  Future<void> stop() async {
    // The turn ended on purpose; a late language error must not restart it.
    _retry = null;
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('[VoiceSpeechService] stop failed: $e');
    }
  }

  /// Ends the turn and throws the transcript away.
  Future<void> cancel() async {
    // A cancelled turn must not trigger a search on the way out, nor come back
    // to life as an English retry.
    _onDone = null;
    _onFailure = null;
    _retry = null;
    try {
      await _speech.cancel();
    } catch (e) {
      debugPrint('[VoiceSpeechService] cancel failed: $e');
    }
  }
}

/// Everything needed to start the same turn again in a different language.
class _LocaleRetry {
  const _LocaleRetry({
    required this.localeId,
    required this.onResult,
    required this.onLevel,
    required this.onFailure,
    required this.onDone,
    required this.listenFor,
    required this.pauseFor,
  });

  final String localeId;
  final void Function(String text, bool isFinal) onResult;
  final void Function(double level)? onLevel;
  final void Function(VoiceFailure failure)? onFailure;
  final void Function()? onDone;
  final Duration listenFor;
  final Duration pauseFor;
}
