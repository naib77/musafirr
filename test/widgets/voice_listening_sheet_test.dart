import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/models/voice_query.dart';
import 'package:musafir/services/voice/remote_voice_parser.dart';
import 'package:musafir/services/voice/speech_service.dart';
import 'package:musafir/widgets/voice_listening_sheet.dart';

/// Stands in for the platform recogniser. Nothing here touches a microphone —
/// the test drives [emit] to play the part of the engine returning text.
class _FakeSpeech extends VoiceSpeechService {
  _FakeSpeech({this.ready = true});

  final bool ready;

  bool listenCalled = false;
  int cancelCount = 0;
  VoiceLanguage? lastLanguage;

  void Function(String text, bool isFinal)? _onResult;
  void Function(double level)? _onLevel;
  void Function()? _onDone;

  @override
  bool get maybeAvailable => true;

  @override
  Future<bool> initialize() async => ready;

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
    _onResult = onResult;
    _onLevel = onLevel;
    _onDone = onDone;
    return null;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async => cancelCount++;

  /// Plays the recogniser returning text.
  void emit(String text, {bool isFinal = false}) =>
      _onResult?.call(text, isFinal);

  void emitLevel(double level) => _onLevel?.call(level);

  /// Plays the recogniser closing the mic by itself.
  void emitDone() => _onDone?.call();
}

void main() {
  late _FakeSpeech speech;

  setUp(() {
    speech = _FakeSpeech();
    VoiceSpeechService.debugOverride = speech;
  });

  tearDown(() => VoiceSpeechService.debugOverride = null);

  /// Opens the sheet and lets its entrance finish.
  ///
  /// Deliberately `pump`s a fixed span rather than `pumpAndSettle`: while the
  /// mic is open the pulse animation repeats forever, so nothing ever settles.
  /// `pumpAndSettle` is only safe once the sheet has reached its parsed or
  /// failed state, where the pulse is stopped.
  Future<void> openSheet(
    WidgetTester tester, {
    Completer<VoiceQuery?>? out,
    RemoteVoiceParser? remoteParser,
  }) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        ctx = context;
        return const Scaffold(body: SizedBox());
      }),
    ));
    // No network in these: the lexicon is the whole subject here, and the
    // Gemini fallback has its own tests.
    unawaited(VoiceListeningSheet.show(ctx, remoteParser: remoteParser)
        .then((q) => out?.complete(q)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('starts listening as soon as it opens', (tester) async {
    await openSheet(tester);

    expect(speech.listenCalled, isTrue);
    expect(find.text('Listening…'), findsOneWidget);
    expect(find.text('Voice search'), findsOneWidget);
  });

  testWidgets('shows partial text while it is still being spoken',
      (tester) async {
    await openSheet(tester);

    speech.emit('ধানমন্ডির');
    await tester.pump();

    // The transcript is the trust anchor: it has to appear before the user
    // commits, not after.
    expect(find.text('ধানমন্ডির'), findsOneWidget);

    speech.emit('ধানমন্ডির দিকে বাসা');
    await tester.pump();
    expect(find.text('ধানমন্ডির দিকে বাসা'), findsOneWidget);
  });

  testWidgets('shows what it understood before it searches', (tester) async {
    await openSheet(tester);

    speech.emit('ধানমন্ডির দিকে বাসা খোঁজো', isFinal: true);
    await tester.pump();

    // The chips are the only account of what was heard, so they have to be on
    // screen even though nobody is being asked to approve them.
    expect(find.text('SEARCHING FOR'), findsOneWidget);
    expect(find.text('Dhanmondi'), findsOneWidget);
    expect(find.text('Full House'), findsOneWidget);
    expect(find.text('Searching…'), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('searches on its own, with nothing tapped', (tester) async {
    final out = Completer<VoiceQuery?>();
    await openSheet(tester, out: out);

    speech.emit('dhanmondir dike basa khojo', isFinal: true);
    await tester.pumpAndSettle();

    // No tap anywhere in this test — that is the whole point.
    final result = await out.future;
    expect(result, isNotNull);
    expect(result!.placeText, 'Dhanmondi');
    expect(result.types, [ListingType.fullHouse]);
  });

  testWidgets('a mic that closes without a final result still searches',
      (tester) async {
    final out = Completer<VoiceQuery?>();
    await openSheet(tester, out: out);

    // Partial text, then the engine gives up without ever marking it final.
    // Before, this left the sheet listening to a dead microphone; with no
    // button on the screen there would have been no way out of it.
    speech.emit('dhakay room');
    await tester.pump();
    speech.emitDone();
    await tester.pumpAndSettle();

    final result = await out.future;
    expect(result?.placeText, 'Dhaka');
  });

  testWidgets('a mic closing after the turn is already over changes nothing',
      (tester) async {
    final out = Completer<VoiceQuery?>();
    await openSheet(tester, out: out);

    speech.emit('dhanmondi room', isFinal: true);
    await tester.pump();
    // 'notListening' and 'done' both land after a final result; neither may
    // re-parse or fire a second search.
    speech.emitDone();
    speech.emitDone();
    await tester.pumpAndSettle();

    final result = await out.future;
    expect(result?.placeText, 'Dhanmondi');
  });

  testWidgets('explains an unparseable sentence instead of searching blind',
      (tester) async {
    await openSheet(tester);

    // All filler, no content words — unknown words are deliberately forwarded
    // to the geocoder, so a sentence only counts as unparseable when nothing
    // at all survives the stopword pass.
    speech.emit('ami kichu chai please', isFinal: true);
    await tester.pumpAndSettle();

    expect(find.textContaining('could not find a place'), findsOneWidget);
    expect(find.text('Searching…'), findsNothing,
        reason: 'an empty parse must not auto-search for everything');
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
  });

  testWidgets('says nothing was heard when the transcript is blank',
      (tester) async {
    await openSheet(tester);

    speech.emit('', isFinal: true);
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing was heard'), findsOneWidget);
  });

  testWidgets('offers a way out when the microphone is refused',
      (tester) async {
    speech = _FakeSpeech(ready: false);
    VoiceSpeechService.debugOverride = speech;

    await openSheet(tester);

    expect(speech.listenCalled, isFalse);
    expect(find.textContaining('microphone access'), findsOneWidget);
    expect(find.text('Type instead'), findsOneWidget);
  });

  testWidgets('restarts listening when the language is switched',
      (tester) async {
    await openSheet(tester);
    expect(speech.lastLanguage, VoiceLanguage.auto);

    await tester.tap(find.text('বাংলা'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(speech.lastLanguage, VoiceLanguage.bangla);
    expect(speech.cancelCount, greaterThan(0),
        reason: 'the previous session must be dropped, not left running');
  });

  testWidgets('asks the model only when the lexicon comes up empty',
      (tester) async {
    var calls = 0;
    final remote = RemoteVoiceParser(invoke: (t) async {
      calls++;
      return {'parsed': true, 'place': 'Dhanmondi 32', 'types': <String>[]};
    });
    final out = Completer<VoiceQuery?>();
    await openSheet(tester, out: out, remoteParser: remote);

    // Nothing but filler — the lexicon has no answer, so the fallback earns
    // its keep here.
    speech.emit('ami kichu chai please', isFinal: true);
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect((await out.future)?.placeText, 'Dhanmondi 32');
  });

  testWidgets('never asks the model when the lexicon already answered',
      (tester) async {
    // This is the cost and latency guard: the common query must stay local.
    var calls = 0;
    final remote = RemoteVoiceParser(invoke: (t) async {
      calls++;
      return null;
    });
    final out = Completer<VoiceQuery?>();
    await openSheet(tester, out: out, remoteParser: remote);

    speech.emit('dhanmondi room', isFinal: true);
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect((await out.future)?.placeText, 'Dhanmondi');
  });

  testWidgets('a model that fails still leaves an honest explanation',
      (tester) async {
    final remote =
        RemoteVoiceParser(invoke: (_) async => throw Exception('down'));
    await openSheet(tester, remoteParser: remote);

    speech.emit('ami kichu chai please', isFinal: true);
    await tester.pumpAndSettle();

    expect(find.textContaining('could not find a place'), findsOneWidget);
  });

  testWidgets('teaches the pattern with spoken examples', (tester) async {
    await openSheet(tester);

    expect(find.text('Try saying'), findsOneWidget);
    expect(find.text('ধানমন্ডিতে বাসা'), findsOneWidget);
  });

  testWidgets('survives amplitude updates without throwing', (tester) async {
    await openSheet(tester);

    // Android reports roughly -2..10 and web 0..1; both have to be safe.
    for (final level in [-2.0, 0.0, 0.4, 7.5, 12.0]) {
      speech.emitLevel(level);
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('cancels the session when dismissed', (tester) async {
    await openSheet(tester);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(speech.cancelCount, greaterThan(0));
  });
}
