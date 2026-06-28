import 'package:flutter/material.dart';

import '../../models/message.dart';
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
  }

  @override
  void dispose() {
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
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            hasText ? Icons.send : Icons.mic,
                            key: ValueKey(hasText),
                          ),
                        ),
                        onPressed: widget.enabled
                            ? (hasText ? _sendMessage : _onVoiceMessage)
                            : null,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _onVoiceMessage() {
    // TODO: Implement voice message recording
    ModernBanner.showInfo(context, 'Voice messages coming soon');
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

/// Emoji picker button (for future use)
class EmojiPickerButton extends StatelessWidget {
  const EmojiPickerButton({
    super.key,
    required this.onEmojiSelected,
  });

  final ValueChanged<String> onEmojiSelected;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.emoji_emotions_outlined),
      onPressed: () {
        // TODO: Show emoji picker
        ModernBanner.showInfo(context, 'Emoji picker coming soon');
      },
    );
  }
}
