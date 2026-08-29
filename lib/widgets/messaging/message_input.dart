import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../services/voice/dictation.dart';
import '../../services/voice/dictation_language.dart';
import '../../services/voice/speech_service.dart';
import '../modern_banner.dart';

/// Callback types for message input
typedef OnSendMessage = void Function(String text);
typedef OnSendImage = void Function();
typedef OnSendLocation = void Function();
typedef OnSendFile = void Function();
typedef OnTextChanged = void Function(String text);

/// A message input widget with text field and attachment options
class MessageInput extends StatefulWidget {
  const MessageInput({
    super.key,
    required this.onSendMessage,
    this.onSendImage,
    this.onSendLocation,
    this.onSendFile,
    this.onTextChanged,
    this.replyingTo,
    this.onCancelReply,
    this.isSending = false,
    this.enabled = true,
    this.placeholder = 'Type a message...',
  });

  final OnSendMessage onSendMessage;
  final OnSendImage? onSendImage;
  final OnSendLocation? onSendLocation;
  final OnSendFile? onSendFile;
  final OnTextChanged? onTextChanged;
  final Message? replyingTo;
  final VoidCallback? onCancelReply;
  final bool isSending;
  final bool enabled;
  final String placeholder;

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _showAttachmentMenu = false;

  /// Read once, like the listening sheet does, so a test's fake stands in for
  /// the real recogniser for the whole life of the composer.
  final VoiceSpeechService _speech = VoiceSpeechService.current;

  /// True while the mic is open. Drives both the button and the strip above
  /// the field — dictation with no visible sign it is running reads as a dead
  /// button, which is the bug this replaced.
  bool _dictating = false;

  /// Which language the mic listens for. Auto is Bangla-first by design (see
  /// `resolveSpeechLocaleId`), which is right for a Bangladeshi search box and
  /// wrong to impose on every message someone types — so this is the user's
  /// choice, remembered across sessions, not a constant.
  VoiceLanguage _language = VoiceLanguage.auto;

  /// Whatever was in the field when dictation started. The recogniser reports
  /// the whole turn each time, so every partial result is composed against
  /// this rather than appended to the field. See [composeDictationText].
  String _dictationBase = '';

  late AnimationController _attachmentAnimationController;
  late Animation<double> _attachmentAnimation;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);

    _attachmentAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _attachmentAnimation = CurvedAnimation(
      parent: _attachmentAnimationController,
      curve: Curves.easeOut,
    );

    // Fire-and-forget: the composer is usable immediately, and the stored
    // choice lands well before anyone can reach the mic. Auto until it does.
    unawaited(_loadLanguage());
  }

  Future<void> _loadLanguage() async {
    final stored = await DictationLanguageStore.current.load();
    if (!mounted) return;
    setState(() => _language = stored);
  }

  @override
  void dispose() {
    // Releases the microphone. Without this, leaving a chat mid-dictation
    // leaves the browser's recording indicator lit and the recogniser holding
    // the one native instance the plugin has.
    if (_dictating) unawaited(_speech.cancel());
    _controller.dispose();
    _focusNode.dispose();
    _attachmentAnimationController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    widget.onTextChanged?.call(_controller.text);
    setState(() {});
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    widget.onSendMessage(text);
    _controller.clear();
    _hideAttachmentMenu();
  }

  void _toggleAttachmentMenu() {
    setState(() {
      _showAttachmentMenu = !_showAttachmentMenu;
      if (_showAttachmentMenu) {
        _attachmentAnimationController.forward();
      } else {
        _attachmentAnimationController.reverse();
      }
    });
  }

  void _hideAttachmentMenu() {
    if (_showAttachmentMenu) {
      setState(() {
        _showAttachmentMenu = false;
        _attachmentAnimationController.reverse();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = _controller.text.trim().isNotEmpty;
    // Free property lookup — safe in build, never prompts for a microphone.
    final canDictate = _speech.maybeAvailable;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reply preview
        if (widget.replyingTo != null)
          _ReplyPreviewBanner(
            message: widget.replyingTo!,
            onCancel: widget.onCancelReply,
          ),

        // Attachment menu
        if (_showAttachmentMenu)
          SizeTransition(
            sizeFactor: _attachmentAnimation,
            child: _AttachmentMenu(
              onImage: () {
                _hideAttachmentMenu();
                widget.onSendImage?.call();
              },
              onLocation: () {
                _hideAttachmentMenu();
                widget.onSendLocation?.call();
              },
              onFile: () {
                _hideAttachmentMenu();
                widget.onSendFile?.call();
              },
            ),
          ),

        // Says the mic is open, and offers the way out. The button alone is
        // too small to carry that: someone who cannot see the transcript
        // arriving yet has no way to tell listening from broken.
        if (_dictating)
          _ListeningStrip(
            language: _language,
            onPickLanguage: _pickLanguage,
          ),

        // Input area
        Container(
          padding: EdgeInsets.only(
            left: 8,
            right: 8,
            top: 8,
            bottom: MediaQuery.of(context).padding.bottom + 8,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Attachment button
              AnimatedRotation(
                duration: const Duration(milliseconds: 200),
                turns: _showAttachmentMenu ? 0.125 : 0,
                child: IconButton(
                  icon: Icon(
                    _showAttachmentMenu ? Icons.close : Icons.add,
                    color: _showAttachmentMenu
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: widget.enabled ? _toggleAttachmentMenu : null,
                ),
              ),

              // Text input
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: widget.enabled,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: widget.placeholder,
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onTap: _hideAttachmentMenu,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Dictation gets its own button rather than sharing the send
              // button's empty state. Sharing it meant the mic vanished the
              // moment there was text — so a half-typed message could never
              // be finished by voice, and neither could a dictated one be
              // added to, which is most of what dictation is for.
              //
              // Drawn only where speech recognition could actually run: a mic
              // on Firefox, or on iOS, can never be anything but a dead
              // button, and hiding it costs only a property lookup.
              if (canDictate)
                // Long-press, not a second permanent button: the language is
                // set once and then rarely touched, and the composer has no
                // room to spend on it. While the mic is open the same choice
                // is one tap away in the strip above, which is where someone
                // watching the wrong language appear will look for it.
                //
                // Hand-built rather than an IconButton wrapped in a
                // GestureDetector: the button's own tap recogniser wins the
                // gesture arena, so an ancestor long-press never fires. One
                // InkWell owning both gestures is the only arrangement where
                // both actually happen.
                Tooltip(
                  message: _dictating
                      ? 'Stop dictating'
                      : 'Dictate in ${_language.label} '
                          '(long-press to change)',
                  child: Semantics(
                    button: true,
                    label: _dictating
                        ? 'Stop dictating'
                        : 'Dictate in ${_language.label}',
                    hint: 'Long press to change the dictation language',
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: widget.enabled
                            ? (_dictating ? _stopDictation : _startDictation)
                            : null,
                        onLongPress: widget.enabled ? _pickLanguage : null,
                        // Matches the 48x48 of the buttons either side of it,
                        // which is also the minimum touch target.
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(
                            child: Icon(
                              _dictating ? Icons.stop_rounded : Icons.mic,
                              color: _dictating
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Send button
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: widget.isSending
                    ? Container(
                        width: 48,
                        height: 48,
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : IconButton.filled(
                        tooltip: 'Send',
                        icon: const Icon(Icons.send),
                        // Disabled on an empty field rather than doing
                        // something else there: a button that changes job
                        // under the thumb is how the mic used to get lost.
                        onPressed:
                            widget.enabled && hasText ? _sendMessage : null,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Dictates into the composer: speech becomes text in the field, which the
  /// user then reads, edits and sends themselves.
  ///
  /// It deliberately does NOT send on its own. Voice search can afford to run
  /// the moment you stop speaking because a wrong search costs a scroll; a
  /// message goes to another person and cannot be recalled, so a mishearing
  /// has to be visible and fixable before it is sent.
  Future<void> _startDictation() async {
    // Ask for the microphone HERE, in the tap handler. Browsers only prompt
    // while the tap's user activation is live, and everything below this line
    // is past an await — the same trap that made voice search open on a mic
    // it was never granted.
    final granted = await _speech.ensureMicrophonePermission();
    if (!mounted) return;
    if (!granted) {
      ModernBanner.showError(
        context,
        dictationFailureMessage(VoiceFailure.permissionDenied),
      );
      return;
    }

    _hideAttachmentMenu();
    setState(() {
      _dictating = true;
      _dictationBase = _controller.text;
    });
    await _listen();
  }

  /// Opens the mic for the currently chosen language. Separate from
  /// [_startDictation] because switching language mid-turn has to run exactly
  /// this again, without asking for the microphone or resetting the base text.
  Future<void> _listen() async {
    final failure = await _speech.listen(
      language: _language,
      onResult: _onDictationResult,
      // A refused mic arrives through here, asynchronously, long after
      // listen() returned success — dropping it is what turns a denial into a
      // button that appears to do nothing.
      onFailure: _onDictationFailure,
      onDone: _onDictationDone,
      // Longer than voice search's 20s/3s: a search is a phrase, a message is
      // a sentence or three with thinking in between, and being cut off
      // mid-message is worse than holding the mic open a little longer.
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 5),
    );
    if (!mounted) return;
    if (failure != null) _onDictationFailure(failure);
  }

  /// Lets the user say which language they are speaking.
  Future<void> _pickLanguage() async {
    final chosen = await showModalBottomSheet<VoiceLanguage>(
      context: context,
      builder: (context) => _LanguageSheet(selected: _language),
    );
    if (chosen == null || !mounted) return;
    await _setLanguage(chosen);
  }

  Future<void> _setLanguage(VoiceLanguage language) async {
    if (language == _language) return;
    setState(() => _language = language);
    unawaited(DictationLanguageStore.current.save(language));
    if (!_dictating) return;

    // Mid-turn: start over in the new language. Whatever the wrong recogniser
    // heard is not a transcript of anything — someone switching language is
    // telling us the text in the field is wrong, so `cancel` (which discards)
    // rather than `stop` (which keeps), and the field goes back to what they
    // had typed before they ever pressed the mic.
    await _speech.cancel();
    if (!mounted) return;
    _setField(_dictationBase);
    await _listen();
  }

  void _onDictationResult(String text, bool isFinal) {
    if (!mounted) return;
    final composed = composeDictationText(
      base: _dictationBase,
      transcript: text,
    );
    _setField(composed);
    if (isFinal) {
      // The turn is over. Fold the transcript into the base so a second tap
      // of the mic adds to it instead of overwriting it.
      _dictationBase = composed;
      setState(() => _dictating = false);
    }
  }

  /// Written through `value` rather than `text` so the caret follows the
  /// dictated words. Assigning `text` alone leaves the selection where it was,
  /// which puts the next typed character in the middle of what was just heard.
  void _setField(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// The user ended the turn. Keeps whatever was heard — [VoiceSpeechService.stop]
  /// rather than cancel — and hands the text back for editing.
  Future<void> _stopDictation() async {
    setState(() => _dictating = false);
    await _speech.stop();
    if (!mounted) return;
    _dictationBase = _controller.text;
    // Focus follows the text: stopping means "now let me fix it and send it".
    _focusNode.requestFocus();
  }

  /// The recogniser closed the mic itself — a silence timeout, or the browser
  /// deciding the turn was over. Whatever partial text arrived is all there
  /// will be, and it is already in the field, so this only has to stop
  /// claiming to listen.
  void _onDictationDone() {
    if (!mounted || !_dictating) return;
    setState(() => _dictating = false);
    _dictationBase = _controller.text;
  }

  void _onDictationFailure(VoiceFailure failure) {
    if (!mounted) return;
    setState(() => _dictating = false);
    final heardSomething = _controller.text.trim() != _dictationBase.trim();
    _dictationBase = _controller.text;
    // Silence is not worth a banner once something was already transcribed:
    // an engine often ends a turn with 'no-speech' after it heard plenty, and
    // "nothing was heard" over a field full of words reads as a bug.
    if (failure == VoiceFailure.noSpeech && heardSomething) return;
    ModernBanner.showError(context, dictationFailureMessage(failure));
  }
}

/// The "listening" line shown above the composer while the mic is open.
///
/// Kept separate from [MessageInput] so its ticker exists only while dictation
/// is running — a pulse animating behind an idle composer is a frame callback
/// per frame for a dot nobody is looking at.
class _ListeningStrip extends StatefulWidget {
  const _ListeningStrip({
    required this.language,
    required this.onPickLanguage,
  });

  /// Named on the strip rather than hidden in a settings screen: the moment
  /// someone sees Bangla text appear for English speech is the moment they
  /// need to know what the mic is listening for, and how to change it.
  final VoiceLanguage language;
  final VoidCallback onPickLanguage;

  @override
  State<_ListeningStrip> createState() => _ListeningStripState();
}

class _ListeningStripState extends State<_ListeningStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// Not `initState`: reading MediaQuery there is an error, because a widget
  /// that depends on an inherited value before it is mounted will not be
  /// rebuilt when that value changes.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honours the platform's reduce-motion setting: the dot's colour already
    // says "recording", so the pulse is decoration and must not be forced on
    // someone who asked for less of it.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0.25).animate(_pulse),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.error,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Listening…',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          // Compact on purpose: the strip has to survive a 320dp phone
          // alongside the label above.
          TextButton.icon(
            onPressed: widget.onPickLanguage,
            icon: const Icon(Icons.arrow_drop_down, size: 18),
            label: Text(widget.language.label),
            iconAlignment: IconAlignment.end,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onErrorContainer,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
          ),
        ],
      ),
    );
  }
}

/// The dictation-language chooser.
///
/// A sheet rather than a popup menu so the hint under each option has room:
/// "Auto" is the whole reason this control exists, and it is meaningless
/// without the line explaining that it prefers Bangla.
class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet({required this.selected});

  final VoiceLanguage selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              'Dictation language',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          for (final language in VoiceLanguage.values)
            ListTile(
              title: Text(language.label),
              subtitle: Text(dictationLanguageHint(language)),
              trailing: language == selected
                  ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
                  : null,
              onTap: () => Navigator.of(context).pop(language),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Reply preview banner shown above input
class _ReplyPreviewBanner extends StatelessWidget {
  const _ReplyPreviewBanner({
    required this.message,
    this.onCancel,
  });

  final Message message;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
          left: BorderSide(color: theme.colorScheme.primary, width: 4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.reply,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to ${message.sender?.name ?? 'Unknown'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.displayText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onCancel,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
          ),
        ],
      ),
    );
  }
}

/// Attachment menu with options
class _AttachmentMenu extends StatelessWidget {
  const _AttachmentMenu({
    required this.onImage,
    required this.onLocation,
    required this.onFile,
  });

  final VoidCallback onImage;
  final VoidCallback onLocation;
  final VoidCallback onFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _AttachmentOption(
            icon: Icons.image,
            label: 'Photo',
            color: Colors.purple,
            onTap: onImage,
          ),
          _AttachmentOption(
            icon: Icons.location_on,
            label: 'Location',
            color: Colors.green,
            onTap: onLocation,
          ),
          _AttachmentOption(
            icon: Icons.insert_drive_file,
            label: 'File',
            color: Colors.blue,
            onTap: onFile,
          ),
        ],
      ),
    );
  }
}

/// Single attachment option button
class _AttachmentOption extends StatelessWidget {
  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
