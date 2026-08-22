import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:musafir/services/voice/speech_service.dart';

/// What the user is told when starting voice search fails, and whether they can
/// try again.
///
/// The reported symptom: "This browser cannot do voice search" on Chrome, where
/// the mic button had already rendered — so the browser demonstrably CAN. Two
/// faults produce that:
///   1. initialize() records no reason when the plugin fails, so the sheet
///      falls back to `unsupported` and blames the browser for everything.
///   2. `_initialised` latches on failure as well as success, so the very first
///      failure is permanent for the session — allowing the mic and tapping
///      again cannot recover, and "Try again" is dead.
class _FakePlugin extends stt.SpeechToText {
  _FakePlugin({this.succeedsOnCall, this.reportError, this.throwOnInit = false})
      : super.withMethodChannel();

  /// Succeeds from this call number onward (1-based). Null = never succeeds.
  final int? succeedsOnCall;

  /// An error message the plugin reports through onError, as the real one does
  /// before returning false.
  final String? reportError;

  final bool throwOnInit;

  int calls = 0;

  @override
  Future<bool> initialize({
    stt.SpeechErrorListener? onError,
    stt.SpeechStatusListener? onStatus,
    dynamic debugLogging = false,
    Duration finalTimeout = const Duration(milliseconds: 2000),
    List<stt.SpeechConfigOption>? options,
  }) async {
    calls++;
    // Order matters: the real web plugin reports the reason through onError
    // and THEN throws (it has a finally but no catch), so a report can be
    // followed by an exception in the same call.
    if (reportError != null) {
      onError?.call(SpeechRecognitionError(reportError!, true));
    }
    if (throwOnInit) throw Exception('platform blew up');
    return succeedsOnCall != null && calls >= succeedsOnCall!;
  }

  @override
  Future<List<stt.LocaleName>> locales() async => const [];
}

/// The real service, with the platform capability probe stubbed true — on a
/// test VM the stub reports Android-only, which would short-circuit before any
/// of the logic under test.
class _Service extends VoiceSpeechService {
  _Service(stt.SpeechToText plugin) : super(plugin: plugin);

  @override
  bool get maybeAvailable => true;
}

void main() {
  test('a refused microphone is reported as refused, not as a bad browser',
      () async {
    final plugin = _FakePlugin(reportError: 'not-allowed');
    final service = _Service(plugin);

    expect(await service.initialize(), isFalse);
    expect(
      service.initFailure,
      VoiceFailure.permissionDenied,
      reason: 'blaming the browser sends the user to install a different one '
          'when they only needed to allow the mic',
    );
  });

  test('an unknown plugin failure is not blamed on the browser', () async {
    // The plugin returned false and said nothing. That is NOT evidence the
    // browser lacks a recogniser — and claiming so is unfalsifiable advice.
    final plugin = _FakePlugin();
    final service = _Service(plugin);

    expect(await service.initialize(), isFalse);
    expect(service.initFailure, isNot(VoiceFailure.unsupported));
    expect(service.initFailure, VoiceFailure.error);
  });

  test('a thrown platform error is reported as an error', () async {
    final plugin = _FakePlugin(throwOnInit: true);
    final service = _Service(plugin);

    expect(await service.initialize(), isFalse);
    expect(service.initFailure, VoiceFailure.error);
  });

  test('a reason reported before a throw is not overwritten', () async {
    // Exactly the deployed failure: the plugin says 'speech_not_supported',
    // then throws "webkitSpeechRecognition is not a constructor". Letting the
    // throw flatten that into a generic error loses the only accurate account
    // of what happened.
    final plugin =
        _FakePlugin(reportError: 'speech_not_supported', throwOnInit: true);
    final service = _Service(plugin);

    expect(await service.initialize(), isFalse);
    expect(service.initFailure, VoiceFailure.unsupported);
  });

  test('a failed initialize can be retried', () async {
    // The whole point: the user allows the mic, taps again, and it must work.
    final plugin = _FakePlugin(succeedsOnCall: 2, reportError: 'not-allowed');
    final service = _Service(plugin);

    expect(await service.initialize(), isFalse);
    expect(plugin.calls, 1);

    expect(
      await service.initialize(),
      isTrue,
      reason: 'a first failure must not be permanent for the session',
    );
    expect(plugin.calls, 2);
    expect(service.initFailure, isNull,
        reason: 'success must clear the reason');
  });

  test('a successful initialize is not repeated', () async {
    final plugin = _FakePlugin(succeedsOnCall: 1);
    final service = _Service(plugin);

    expect(await service.initialize(), isTrue);
    expect(await service.initialize(), isTrue);
    expect(plugin.calls, 1,
        reason: 'the recogniser is set up once per session');
  });

  test('listen() reports the real reason when initialize failed', () async {
    final plugin = _FakePlugin(reportError: 'not-allowed');
    final service = _Service(plugin);

    final failure = await service.listen(
      language: VoiceLanguage.auto,
      onResult: (_, __) {},
    );
    expect(failure, VoiceFailure.permissionDenied);
  });
}
