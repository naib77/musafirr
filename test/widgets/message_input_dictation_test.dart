import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/voice/dictation_language.dart';
import 'package:musafir/services/voice/speech_service.dart';
import 'package:musafir/widgets/messaging/message_input.dart';

/// Stands in for the platform recogniser — nothing here opens a microphone,
/// which the test harness does not have. The test plays the engine by calling
/// [emit].
class _FakeSpeech extends VoiceSpeechService {
  _FakeSpeech({this.available = true, this.granted = true, this.startFailure});

  final bool available;
  final bool granted;

  /// What `listen()` reports back synchronously, standing in for an
  /// initialize() that the platform refused.
  final VoiceFailure? startFailure;

  bool listenCalled = false;
  VoiceLanguage? lastLanguage;
  int stopCount = 0;
  int cancelCount = 0;
  Duration? lastListenFor;

  void Function(String text, bool isFinal)? _onResult;
  void Function(VoiceFailure failure)? _onFailure;
  void Function()? _onDone;

  @override
  bool get maybeAvailable => available;

  @override
  Future<bool> ensureMicrophonePermission() async => granted;

  @override
  Future<bool> initialize() async => granted;

  @override
  Future<VoiceFailure?> listen({
    required VoiceLanguage language,
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onLevel,
    void Function(VoiceFailure failure)? onFailure,
    void Function()? onDone,
    Duration listenFor = const Duration(seconds: 20),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    listenCalled = true;
    lastLanguage = language;
    lastListenFor = listenFor;
    _onResult = onResult;
    _onFailure = onFailure;
    _onDone = onDone;
    return startFailure;
  }

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<void> cancel() async => cancelCount++;

  void emit(String text, {bool isFinal = false}) =>
      _onResult?.call(text, isFinal);

  /// Plays the browser reporting a failure after listen() already returned.
  void emitFailure(VoiceFailure failure) => _onFailure?.call(failure);

  /// Plays the recogniser closing the mic by itself.
  void emitDone() => _onDone?.call();
}

/// In-memory stand-in for the stored language preference, so no test touches
/// platform storage and every test states the choice it is exercising.
class _FakeLanguageStore extends DictationLanguageStore {
  /// Tests that care set [stored] directly before pumping — the default
  /// stands for "the user has never chosen".
  VoiceLanguage stored = VoiceLanguage.auto;
  final List<VoiceLanguage> saved = [];

  @override
  Future<VoiceLanguage> load() async => stored;

  @override
  Future<void> save(VoiceLanguage language) async {
    saved.add(language);
    stored = language;
  }
}

void main() {
  late _FakeSpeech speech;
  late _FakeLanguageStore languages;
  late List<String> sent;

  setUp(() {
    speech = _FakeSpeech();
    VoiceSpeechService.debugOverride = speech;
    languages = _FakeLanguageStore();
    DictationLanguageStore.debugOverride = languages;
    sent = [];
  });

  tearDown(() {
    VoiceSpeechService.debugOverride = null;
    DictationLanguageStore.debugOverride = null;
  });

  Future<void> pumpInput(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: MessageInput(onSendMessage: sent.add),
        ),
      ),
    ));
    // Two frames: the stored language is loaded asynchronously, and every
    // assertion about the mic depends on that having landed.
    await tester.pump();
    await tester.pump();
  }

  /// Starts dictation. Deliberately not `pumpAndSettle`: the listening strip's
  /// dot pulses forever, so nothing settles while the mic is open.
  Future<void> tapMic(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.mic));
    await tester.pump();
    await tester.pump();
  }

  Future<void> tapStop(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();
    await tester.pump();
  }

  /// Taps while dictation is running. `pumpAndSettle` is unusable here — the
  /// strip's dot pulses forever — so this pumps a fixed span long enough for a
  /// modal sheet to finish opening or closing.
  Future<void> tapWhileListening(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapSend(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
  }

  /// The send button — `IconButton.filled`, the only one wrapped in an
  /// AnimatedContainer, so it is the last in the row.
  IconButton sendButton(WidgetTester tester) =>
      tester.widget<IconButton>(find.byType(IconButton).last);

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('the mic is offered alongside a dead send button',
      (tester) async {
    await pumpInput(tester);

    // Both are always drawn where speech can run: the mic must stay reachable
    // whether or not there is text, and send must never become something else.
    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
    expect(sendButton(tester).onPressed, isNull);
  });

  testWidgets('tapping the mic starts listening and says so', (tester) async {
    await pumpInput(tester);
    await tapMic(tester);

    expect(speech.listenCalled, isTrue);
    // A message is a sentence with thinking in it, not a search phrase.
    expect(speech.lastListenFor, const Duration(seconds: 60));
    expect(find.textContaining('Listening…'), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
  });

  testWidgets('speech lands in the field as it is heard', (tester) async {
    await pumpInput(tester);
    await tapMic(tester);

    speech.emit('আমি');
    await tester.pump();
    expect(fieldText(tester), 'আমি');

    // The whole turn arrives each time; the field must not stutter.
    speech.emit('আমি আসছি');
    await tester.pump();
    expect(fieldText(tester), 'আমি আসছি');
  });

  testWidgets('dictation never sends on its own — the user still does',
      (tester) async {
    await pumpInput(tester);
    await tapMic(tester);

    speech.emit('I will arrive at nine', isFinal: true);
    await tester.pumpAndSettle();

    // A mishearing has to be visible and fixable: it goes to another person.
    expect(sent, isEmpty);
    expect(fieldText(tester), 'I will arrive at nine');
    expect(find.textContaining('Listening…'), findsNothing);

    await tapSend(tester);
    expect(sent, ['I will arrive at nine']);
  });

  testWidgets('dictation finishes a half-typed message', (tester) async {
    await pumpInput(tester);
    await tester.enterText(find.byType(TextField), 'Hi,');
    await tester.pump();

    // The whole reason the mic has its own button: text in the field must not
    // take dictation away.
    await tapMic(tester);
    speech.emit('I am on my way', isFinal: true);
    await tester.pumpAndSettle();

    expect(fieldText(tester), 'Hi, I am on my way');
  });

  testWidgets('a second turn adds to the first instead of replacing it',
      (tester) async {
    await pumpInput(tester);
    await tapMic(tester);
    speech.emit('I am on my way', isFinal: true);
    await tester.pumpAndSettle();

    await tapMic(tester);
    speech.emit('about ten minutes', isFinal: true);
    await tester.pumpAndSettle();

    expect(fieldText(tester), 'I am on my way about ten minutes');
  });

  testWidgets('listens in the language the user chose last time',
      (tester) async {
    languages.stored = VoiceLanguage.english;
    await pumpInput(tester);
    await tapMic(tester);

    // Auto is Bangla-first, which is why this must not be a constant: someone
    // who dictates in English should not have to say so again every session.
    expect(speech.lastLanguage, VoiceLanguage.english);
  });

  testWidgets('the language can be changed mid-turn, from the strip',
      (tester) async {
    await pumpInput(tester);
    await tapMic(tester);
    expect(speech.lastLanguage, VoiceLanguage.auto);

    // What the wrong recogniser made of English speech.
    speech.emit('আমার নাম');
    await tester.pump();

    await tapWhileListening(tester, find.text(VoiceLanguage.auto.label));
    await tapWhileListening(tester, find.text(VoiceLanguage.english.label));

    // Restarted in English, with the nonsense discarded rather than left for
    // the user to delete by hand.
    expect(speech.cancelCount, 1);
    expect(speech.lastLanguage, VoiceLanguage.english);
    expect(fieldText(tester), '');
    expect(find.textContaining('Listening…'), findsOneWidget);
    // And remembered, so the next message does not repeat the same surprise.
    expect(languages.saved, [VoiceLanguage.english]);
  });

  testWidgets('the language can be set before speaking, by long-press',
      (tester) async {
    await pumpInput(tester);

    await tester.longPress(find.byIcon(Icons.mic));
    await tester.pumpAndSettle();
    // The hint is the point of the sheet: "Auto" alone does not explain why
    // English speech came back as Bangla.
    expect(
        find.textContaining('Bangla where your device has it'), findsOneWidget);

    await tester.tap(find.text(VoiceLanguage.bangla.label));
    await tester.pumpAndSettle();
    expect(languages.saved, [VoiceLanguage.bangla]);

    // No mic was opened by choosing — it only set what the next turn uses.
    expect(speech.listenCalled, isFalse);
    await tapMic(tester);
    expect(speech.lastLanguage, VoiceLanguage.bangla);
  });

  testWidgets('choosing the language already in use changes nothing',
      (tester) async {
    await pumpInput(tester);
    await tapMic(tester);
    speech.emit('already heard this');
    await tester.pump();

    await tapWhileListening(tester, find.text(VoiceLanguage.auto.label));
    // The strip's own label and the sheet's row read the same; the sheet is
    // on top, so its row is the last one.
    await tapWhileListening(tester, find.text(VoiceLanguage.auto.label).last);

    // No pointless restart, and no transcript thrown away.
    expect(speech.cancelCount, 0);
    expect(languages.saved, isEmpty);
    expect(fieldText(tester), 'already heard this');
  });

  testWidgets('stopping keeps what was heard', (tester) async {
    await pumpInput(tester);
    await tapMic(tester);

    speech.emit('on my way');
    await tester.pump();
    await tapStop(tester);
    await tester.pumpAndSettle();

    // stop(), not cancel(): cancel throws the transcript away.
    expect(speech.stopCount, 1);
    expect(speech.cancelCount, 0);
    expect(fieldText(tester), 'on my way');
    expect(find.textContaining('Listening…'), findsNothing);
  });

  testWidgets('a mic closed by the engine stops claiming to listen',
      (tester) async {
    await pumpInput(tester);
    await tapMic(tester);

    speech.emit('see you soon');
    await tester.pump();
    speech.emitDone();
    await tester.pumpAndSettle();

    expect(find.textContaining('Listening…'), findsNothing);
    expect(fieldText(tester), 'see you soon');
  });

  testWidgets('a recogniser that will not start is reported', (tester) async {
    speech = _FakeSpeech(startFailure: VoiceFailure.unsupported);
    VoiceSpeechService.debugOverride = speech;
    await pumpInput(tester);
    await tapMic(tester);

    // listen() reports an initialize() the platform refused synchronously —
    // the other half of the asynchronous path below.
    expect(find.textContaining('cannot take dictation'), findsOneWidget);
    expect(find.textContaining('Listening…'), findsNothing);
  });

  testWidgets('a refused microphone is reported, not swallowed',
      (tester) async {
    await pumpInput(tester);
    await tapMic(tester);

    // The browser reports this long after listen() returned success. Dropping
    // it is what makes a denial look like a dead button.
    speech.emitFailure(VoiceFailure.permissionDenied);
    await tester.pump();

    expect(find.textContaining('permission to use your microphone'),
        findsOneWidget);
    expect(find.textContaining('Listening…'), findsNothing);
  });

  testWidgets('silence after a transcript is not reported as failure',
      (tester) async {
    await pumpInput(tester);
    await tapMic(tester);

    speech.emit('already heard this');
    await tester.pump();
    speech.emitFailure(VoiceFailure.noSpeech);
    await tester.pump();

    expect(find.textContaining('Nothing was heard'), findsNothing);
    expect(fieldText(tester), 'already heard this');
  });

  testWidgets('leaving mid-dictation releases the microphone', (tester) async {
    await pumpInput(tester);
    await tapMic(tester);

    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();

    expect(speech.cancelCount, 1);
  });

  group('where speech recognition cannot run', () {
    setUp(() {
      speech = _FakeSpeech(available: false);
      VoiceSpeechService.debugOverride = speech;
    });

    testWidgets('no mic is drawn at all', (tester) async {
      await pumpInput(tester);

      // A mic on Firefox or iOS can only ever fail; drawing one is worse than
      // drawing none.
      expect(find.byIcon(Icons.mic), findsNothing);
      expect(find.byIcon(Icons.send), findsOneWidget);
      expect(sendButton(tester).onPressed, isNull);
    });
  });

  testWidgets('a refused permission never opens the mic', (tester) async {
    speech = _FakeSpeech(granted: false);
    VoiceSpeechService.debugOverride = speech;
    await pumpInput(tester);
    await tapMic(tester);

    expect(speech.listenCalled, isFalse);
    expect(find.textContaining('permission to use your microphone'),
        findsOneWidget);
  });
}
