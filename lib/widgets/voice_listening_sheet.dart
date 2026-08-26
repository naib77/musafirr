import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../models/voice_query.dart';
import '../services/voice/speech_service.dart';
import '../services/voice/remote_voice_parser.dart';
import '../services/voice/voice_query_parser.dart';

/// What the sheet is doing right now. Each state shows a different thing, and
/// the user is never left looking at a spinner with no explanation.
enum _Phase { starting, listening, thinking, parsed, failed }

/// The listening surface for voice search.
///
/// Two decisions drive the whole design:
///
/// * **The partial transcript is shown as it arrives.** Seeing "ধানমন্ডি"
///   appear is what convinces someone the feature heard them correctly; a bare
///   animation asks them to take it on faith and then surprises them.
/// * **It searches on its own.** Stopping speaking is the whole interaction —
///   there is no button to press. The parsed slots still flash up as chips for
///   a beat first, so the search is never silent about what it heard and the
///   chips still teach which phrasings work; the Explore search field is left
///   holding the place name, so a mishearing is visible and clearable.
///
/// Returns the confirmed [VoiceQuery] via `Navigator.pop`, or null if the user
/// backed out.
class VoiceListeningSheet extends StatefulWidget {
  const VoiceListeningSheet({
    super.key,
    this.parser = const VoiceQueryParser(),
    this.remoteParser = const RemoteVoiceParser(),
  });

  final VoiceQueryParser parser;

  /// Consulted only when [parser] finds nothing. Null disables the fallback
  /// entirely, which is what the widget tests do.
  final RemoteVoiceParser? remoteParser;

  /// Opens the sheet and resolves to the query the user confirmed, or null.
  ///
  /// [remoteParser] is threaded through rather than reached for inside, so a
  /// test can pass null and keep the sheet entirely offline.
  static Future<VoiceQuery?> show(
    BuildContext context, {
    RemoteVoiceParser? remoteParser = const RemoteVoiceParser(),
  }) {
    return showModalBottomSheet<VoiceQuery>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // The feed stays visible behind it: the sheet is a step in a search, not
      // a destination, and the context helps people phrase the next attempt.
      builder: (_) => VoiceListeningSheet(remoteParser: remoteParser),
    );
  }

  @override
  State<VoiceListeningSheet> createState() => _VoiceListeningSheetState();
}

class _VoiceListeningSheetState extends State<VoiceListeningSheet>
    with SingleTickerProviderStateMixin {
  final VoiceSpeechService _speech = VoiceSpeechService.current;

  _Phase _phase = _Phase.starting;
  VoiceLanguage _language = VoiceLanguage.auto;
  String _transcript = '';
  String _failureMessage = '';
  VoiceQuery? _query;

  /// Smoothed mic amplitude, 0..1. Raw levels are jumpy enough to make the
  /// ring jitter, so each sample is eased toward rather than assigned.
  double _level = 0;

  /// How long the chips stay up before the search fires. Long enough to read
  /// "Dhanmondi · Room" and know it heard you, short enough that it reads as
  /// feedback rather than a wait.
  static const Duration _confirmBeat = Duration(milliseconds: 900);

  Timer? _autoSearch;

  /// Only spins while the mic is actually open — see [_setPhase]. Left
  /// repeating it would keep a frame callback alive behind the results and
  /// error screens, where nothing moves.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    // Deferred to the first frame so the sheet is painted before the platform
    // permission dialog covers it — otherwise the user is asked for a
    // microphone by what looks like nothing at all.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _autoSearch?.cancel();
    _pulse.dispose();
    unawaited(_speech.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    _autoSearch?.cancel();
    setState(() {
      _transcript = '';
      _query = null;
    });
    _setPhase(_Phase.starting);

    final ready = await _speech.initialize();
    if (!mounted) return;
    if (!ready) {
      // Default to a plain error, never to "bad browser": an unattributed
      // failure is not evidence the browser lacks a recogniser.
      _fail(_messageFor(_speech.initFailure ?? VoiceFailure.error));
      return;
    }

    _setPhase(_Phase.listening);

    final failure = await _speech.listen(
      language: _language,
      onResult: _onResult,
      onLevel: _onLevel,
      // Web Speech reports a refused microphone asynchronously, after listen()
      // has already succeeded. Without this the refusal never arrived and the
      // sheet blamed a quiet mic for it.
      onFailure: _onFailure,
      onDone: _onEngineStopped,
    );
    if (!mounted) return;
    if (failure != null) _fail(_messageFor(failure));
  }

  void _onFailure(VoiceFailure failure) {
    if (!mounted) return;
    // A refusal can land while the sheet is mid-turn; whatever partial text
    // exists is worthless if the mic was never open, so the failure wins.
    _autoSearch?.cancel();
    _fail(_messageFor(failure));
  }

  /// One message per cause. These were collapsed into "needs microphone
  /// access" and "nothing was heard", which sent users to retry a mic they had
  /// blocked and to speak closer to a browser that has no recogniser at all.
  String _messageFor(VoiceFailure failure) => switch (failure) {
        VoiceFailure.permissionDenied =>
          'Musafir needs permission to use your microphone. Allow it for this '
              'site — in Chrome, tap the icon at the left of the address bar — '
              'then try again. You can still type your search.',
        VoiceFailure.unsupported =>
          'This browser cannot do voice search. Chrome on Android or desktop '
              'can; Firefox cannot. You can still type your search.',
        VoiceFailure.noSpeech =>
          'Nothing was heard. Try again, a little closer to the mic.',
        VoiceFailure.error =>
          'Voice search could not start. Check your connection and that no '
              'other app is using the microphone, then try again.',
      };

  void _onLevel(double raw) {
    if (!mounted) return;
    // The plugin reports roughly -2..10 on Android and 0..1 on web; normalise
    // both into 0..1 and ease so the ring breathes instead of flickering.
    final normalised = (raw > 1 ? raw / 10 : raw).clamp(0.0, 1.0);
    setState(() => _level = _level + (normalised - _level) * 0.35);
  }

  void _onResult(String text, bool isFinal) {
    if (!mounted) return;
    setState(() => _transcript = text);
    if (!isFinal) return;
    unawaited(_finish(text));
  }

  Future<void> _finish(String text) async {
    var query = widget.parser.parse(text);

    // The lexicon knows only the words someone put in it. When it comes up
    // empty on speech that clearly had content, the model gets a look before
    // the user is told it failed — that is the whole point of the fallback,
    // and it is the only path that pays for it.
    final remote = widget.remoteParser;
    if (query.isEmpty && text.trim().isNotEmpty && remote != null) {
      _setPhase(_Phase.thinking);
      final better = await remote.parse(text);
      if (!mounted || _phase != _Phase.thinking) return;
      if (better != null) query = better;
    }
    if (!mounted) return;
    setState(() => _query = query);

    // An empty parse is a real outcome, not an error — say what was heard and
    // let them retry, rather than running a search for everything.
    if (query.isEmpty) {
      _fail(text.trim().isEmpty
          ? 'Nothing was heard. Try again, a little closer to the mic.'
          : 'Heard "$text", but could not find a place or a stay type in it. '
              'Try something like "ধানমন্ডিতে বাসা".');
      return;
    }
    _setPhase(_Phase.parsed);

    // The search the user asked for, without the tap they did not.
    _autoSearch?.cancel();
    _autoSearch = Timer(_confirmBeat, _confirm);
  }

  /// The recogniser closed the mic by itself — a silence timeout, or the
  /// browser deciding the turn was over.
  ///
  /// Usually a final result has already arrived and this is a no-op. When one
  /// has not, whatever partial text exists is all there will ever be, so it is
  /// treated as final rather than leaving the sheet listening to a dead mic
  /// with no button to rescue it.
  void _onEngineStopped() {
    if (!mounted || _phase != _Phase.listening) return;
    _onResult(_transcript, true);
  }

  void _fail(String message) {
    _failureMessage = message;
    _setPhase(_Phase.failed);
  }

  /// Single place the phase changes, so the pulse can never be left running
  /// after the mic closes.
  void _setPhase(_Phase phase) {
    if (mounted) setState(() => _phase = phase);
    if (phase == _Phase.listening) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else if (_pulse.isAnimating) {
      _pulse.stop();
    }
  }

  Future<void> _stopAndParse() async {
    _setPhase(_Phase.thinking);
    await _speech.stop();
    // The final result arrives through onResult; if the engine returns
    // nothing at all, fall back to whatever partial text we already have so
    // the tap is never a dead end.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted || _phase != _Phase.thinking) return;
    _onResult(_transcript, true);
  }

  Future<void> _switchLanguage(VoiceLanguage language) async {
    if (language == _language) return;
    setState(() => _language = language);
    await _speech.cancel();
    if (!mounted) return;
    await _start();
  }

  void _confirm() {
    if (!mounted) return;
    final query = _query;
    if (query == null) return;
    _autoSearch?.cancel();
    Navigator.of(context).pop(query);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          // Capped so the sheet stays a dialog on desktop instead of a
          // full-width banner with a lonely mic in the middle.
          constraints: const BoxConstraints(maxWidth: 520),
          child: Material(
            color: AppColors.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Grabber(),
                    const SizedBox(height: 12),
                    _header(),
                    const SizedBox(height: 18),
                    _body(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Voice search',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              letterSpacing: -0.2,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
          color: AppColors.inkMuted,
          iconSize: 20,
        ),
      ],
    );
  }

  Widget _body() {
    return switch (_phase) {
      _Phase.starting => _listeningBody(caption: 'Getting the microphone…'),
      _Phase.listening => _listeningBody(
          caption: _transcript.isEmpty ? 'Listening…' : null,
        ),
      _Phase.thinking => _listeningBody(caption: 'Working it out…'),
      _Phase.parsed => _parsedBody(),
      _Phase.failed => _failedBody(),
    };
  }

  // ── Listening ─────────────────────────────────────────────────────────────

  Widget _listeningBody({String? caption}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MicOrb(
          pulse: _pulse,
          level: _level,
          animate: _phase == _Phase.listening && !_reduceMotion,
        ),
        const SizedBox(height: 20),
        _TranscriptBox(text: _transcript, caption: caption),
        const SizedBox(height: 16),
        const _ExampleHints(),
        const SizedBox(height: 18),
        _languageToggle(),
        const SizedBox(height: 14),
        Text(
          'Searches on its own when you stop speaking',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
        ),
        const SizedBox(height: 8),
        // Kept only as a way to skip the silence timeout for someone who has
        // finished and does not want to wait. Nothing requires it.
        TextButton.icon(
          onPressed: _phase == _Phase.listening ? _stopAndParse : null,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text("I'm done"),
          style: TextButton.styleFrom(foregroundColor: AppColors.brand),
        ),
      ],
    );
  }

  Widget _languageToggle() {
    return SegmentedButton<VoiceLanguage>(
      segments: [
        for (final l in VoiceLanguage.values)
          ButtonSegment(value: l, label: Text(l.label)),
      ],
      selected: {_language},
      showSelectedIcon: false,
      onSelectionChanged: (s) => _switchLanguage(s.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 13)),
      ),
    );
  }

  // ── Parsed ────────────────────────────────────────────────────────────────

  Widget _parsedBody() {
    final query = _query!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TranscriptBox(text: query.transcript, caption: null),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'SEARCHING FOR',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: AppColors.inkMuted,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final chip in query.chips) _SlotChip(chip)],
        ),
        const SizedBox(height: 22),
        // No button: the search is already on its way. This says so rather
        // than leaving a still frame that looks like it is waiting for a tap.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(AppColors.brand),
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Searching…',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.brand,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  // ── Failed ────────────────────────────────────────────────────────────────

  Widget _failedBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.mic_off_rounded,
                color: AppColors.inkMuted, size: 26),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _failureMessage,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: AppColors.inkMuted,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.refresh_rounded, size: 20),
          label: const Text('Try again'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Type instead'),
        ),
      ],
    );
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────────

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.outline,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// The mic with a ring that breathes on the smoothed amplitude, so it is
/// visibly reacting to the room rather than looping regardless of input.
class _MicOrb extends StatelessWidget {
  const _MicOrb({
    required this.pulse,
    required this.level,
    required this.animate,
  });

  final Animation<double> pulse;
  final double level;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: Center(
        child: AnimatedBuilder(
          animation: pulse,
          builder: (context, child) {
            // Halo = a slow idle breath plus whatever the mic is picking up,
            // so it never sits perfectly still while listening.
            final breath = animate ? math.sin(pulse.value * 2 * math.pi) : 0.0;
            final double scale =
                animate ? 1 + level * 0.5 + breath * 0.06 : 1.0;
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 108 * scale,
                  height: 108 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.brand.withValues(alpha: 0.10),
                  ),
                ),
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.brand.withValues(alpha: 0.16),
                  ),
                ),
                child!,
              ],
            );
          },
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.brandGradient,
            ),
            child: const Icon(Icons.mic_rounded, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}

/// Live transcript. Shown even while partial — this is the trust anchor of the
/// whole flow, so it gets the biggest type on the sheet.
class _TranscriptBox extends StatelessWidget {
  const _TranscriptBox({required this.text, required this.caption});

  final String text;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final showCaption = text.trim().isEmpty && caption != null;
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      child: Text(
        showCaption ? caption! : text,
        key: ValueKey(showCaption ? caption : text),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: showCaption ? 14 : 19,
          height: 1.4,
          fontWeight: showCaption ? FontWeight.w500 : FontWeight.w600,
          color: showCaption ? AppColors.inkMuted : AppColors.ink,
        ),
      ),
    );
  }
}

/// Teaching the pattern is what keeps the free parser viable — people converge
/// on phrasings that work, which shrinks the lexicon problem instead of
/// growing it.
class _ExampleHints extends StatelessWidget {
  const _ExampleHints();

  static const List<String> _examples = [
    'ধানমন্ডিতে বাসা',
    'উত্তরায় ২ জন রুম',
    'hospital er kache room',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Try saying',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.inkMuted,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in _examples)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  e,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.brandDark,
        ),
      ),
    );
  }
}
