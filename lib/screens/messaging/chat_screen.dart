import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../services/messaging/message_router.dart';
import '../../state/messaging_state.dart';
import '../../widgets/messaging/channel_selector.dart';
import '../../widgets/messaging/message_bubble.dart';
import '../../widgets/messaging/message_input.dart';
import '../../widgets/messaging/typing_indicator.dart';
import '../../widgets/modern_banner.dart';

/// Chat screen for messaging with another user
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.messagingState,
    required this.otherParticipantName,
    this.otherParticipantAvatarUrl,
    this.bookingContextSubtitle,
    this.isArchived = false,
  });

  final String conversationId;
  final MessagingStateNotifier messagingState;
  final String otherParticipantName;
  final String? otherParticipantAvatarUrl;
  /// Booking context subtitle (e.g., "Room • Jan 1-5")
  final String? bookingContextSubtitle;
  /// Whether the conversation is archived (read-only)
  final bool isArchived;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  Message? _replyingTo;

  // Channel state
  MessagingChannel _selectedChannel = MessagingChannel.inApp;
  List<MessagingChannel> _availableChannels = [MessagingChannel.inApp];

  @override
  void initState() {
    super.initState();
    // Open the conversation and load messages
    widget.messagingState.openConversation(widget.conversationId);

    // Listen for new messages to scroll to bottom
    widget.messagingState.addListener(_onMessagesChanged);
  }

  @override
  void dispose() {
    widget.messagingState.removeListener(_onMessagesChanged);
    widget.messagingState.closeConversation();
    _scrollController.dispose();
    super.dispose();
  }

  void _onMessagesChanged() {
    // Scroll to bottom when new messages arrive
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    await widget.messagingState.sendTextMessage(text);
    _cancelReply();
  }

  void _replyToMessage(Message message) {
    setState(() => _replyingTo = message);
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  void _deleteMessage(Message message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text(
          'This message will be deleted. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              widget.messagingState.deleteMessage(message.id);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _copyMessage(Message message) {
    ModernBanner.showSuccess(context, 'Message copied to clipboard');
  }

  void _onChannelSelected(MessagingChannel channel) {
    setState(() => _selectedChannel = channel);
    ModernBanner.showInfo(context, 'Switched to ${channel.displayName}');
  }

  void _showChannelSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => ChannelPreferencesSheet(
        preferences: UserChannelPreferences(
          userId: widget.messagingState.currentUserId ?? '',
          preferredChannel: _selectedChannel,
        ),
        onPreferencesChanged: (prefs) {
          setState(() {
            _selectedChannel = prefs.preferredChannel;
            _availableChannels = prefs.availableChannels;
          });
        },
        onConnectWhatsApp: () {
          Navigator.pop(context);
          ModernBanner.showInfo(context, 'WhatsApp connection coming soon');
        },
        onConnectMessenger: () {
          Navigator.pop(context);
          ModernBanner.showInfo(context, 'Messenger connection coming soon');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 18,
              backgroundImage: widget.otherParticipantAvatarUrl != null
                  ? NetworkImage(widget.otherParticipantAvatarUrl!)
                  : null,
              child: widget.otherParticipantAvatarUrl == null
                  ? Text(
                      widget.otherParticipantName.substring(0, 1).toUpperCase(),
                      style: const TextStyle(fontSize: 14),
                    )
                  : null,
            ),
            const SizedBox(width: 12),

            // Name, booking context, and status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.otherParticipantName,
                    style: theme.textTheme.titleMedium,
                  ),
                  // Booking context or typing indicator
                  ListenableBuilder(
                    listenable: widget.messagingState,
                    builder: (context, _) {
                      final typingUsers = widget.messagingState.typingIndicators
                          .map((t) => t.userName ?? 'Someone')
                          .toList();

                      if (typingUsers.isNotEmpty) {
                        return Text(
                          'typing...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontStyle: FontStyle.italic,
                          ),
                        );
                      }

                      // Show booking context when not typing
                      if (widget.bookingContextSubtitle != null &&
                          widget.bookingContextSubtitle!.isNotEmpty) {
                        return Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.bookingContextSubtitle!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.isArchived) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Ended',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      }

                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),

            // Channel indicator (if multiple channels available)
            if (_availableChannels.length > 1)
              ChannelSelector(
                selectedChannel: _selectedChannel,
                availableChannels: _availableChannels,
                onChannelSelected: _onChannelSelected,
                compact: true,
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone),
            onPressed: () {
              ModernBanner.showInfo(context, 'Voice calls coming soon');
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () {
              ModernBanner.showInfo(context, 'Video calls coming soon');
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'search':
                  ModernBanner.showInfo(context, 'Search coming soon');
                  break;
                case 'media':
                  ModernBanner.showInfo(context, 'Media gallery coming soon');
                  break;
                case 'channels':
                  _showChannelSettings();
                  break;
                case 'mute':
                  ModernBanner.showSuccess(context, 'Notifications muted');
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'search',
                child: Row(
                  children: [
                    Icon(Icons.search),
                    SizedBox(width: 12),
                    Text('Search'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'media',
                child: Row(
                  children: [
                    Icon(Icons.photo_library),
                    SizedBox(width: 12),
                    Text('Media & Links'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'channels',
                child: Row(
                  children: [
                    Icon(Icons.multiple_stop),
                    SizedBox(width: 12),
                    Text('Message Channels'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'mute',
                child: Row(
                  children: [
                    Icon(Icons.notifications_off),
                    SizedBox(width: 12),
                    Text('Mute'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Read-only banner for archived conversations
          if (widget.isArchived)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This conversation is read-only. The booking has ended.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Messages list
          Expanded(
            child: ListenableBuilder(
              listenable: widget.messagingState,
              builder: (context, _) {
                if (widget.messagingState.isLoadingMessages) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = widget.messagingState.messages;

                if (messages.isEmpty) {
                  return _EmptyChatState(
                    otherParticipantName: widget.otherParticipantName,
                  );
                }

                return _MessagesList(
                  messages: messages,
                  currentUserId: widget.messagingState.currentUserId ?? '',
                  scrollController: _scrollController,
                  onReply: widget.isArchived ? null : _replyToMessage,
                  onDelete: widget.isArchived ? null : _deleteMessage,
                  onCopy: _copyMessage,
                  typingIndicator: _buildTypingIndicator(),
                );
              },
            ),
          ),

          // Input area (hidden when archived)
          if (!widget.isArchived)
            ListenableBuilder(
              listenable: widget.messagingState,
              builder: (context, _) {
                return MessageInput(
                  onSendMessage: _sendMessage,
                  onSendImage: () {
                    ModernBanner.showInfo(context, 'Image sharing coming soon');
                  },
                  onSendLocation: () {
                    ModernBanner.showInfo(context, 'Location sharing coming soon');
                  },
                  onSendFile: () {
                    ModernBanner.showInfo(context, 'File sharing coming soon');
                  },
                  onTextChanged: widget.messagingState.onTextChanged,
                  replyingTo: _replyingTo,
                  onCancelReply: _cancelReply,
                  isSending: widget.messagingState.isSendingMessage,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget? _buildTypingIndicator() {
    final typingIndicators = widget.messagingState.typingIndicators;
    if (typingIndicators.isEmpty) return null;

    return TypingIndicatorBubble(
      userName: typingIndicators.first.userName ?? widget.otherParticipantName,
      avatarUrl: widget.otherParticipantAvatarUrl,
    );
  }
}

/// Messages list widget
class _MessagesList extends StatelessWidget {
  const _MessagesList({
    required this.messages,
    required this.currentUserId,
    required this.scrollController,
    this.onReply,
    this.onDelete,
    required this.onCopy,
    this.typingIndicator,
  });

  final List<Message> messages;
  final String currentUserId;
  final ScrollController scrollController;
  final ValueChanged<Message>? onReply;
  final ValueChanged<Message>? onDelete;
  final ValueChanged<Message> onCopy;
  final Widget? typingIndicator;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length + (typingIndicator != null ? 1 : 0),
      itemBuilder: (context, index) {
        // Show typing indicator at the end
        if (typingIndicator != null && index == messages.length) {
          return typingIndicator!;
        }

        final message = messages[index];
        final previousMessage = index > 0 ? messages[index - 1] : null;
        final nextMessage =
            index < messages.length - 1 ? messages[index + 1] : null;

        final showDateHeader = _shouldShowDateHeader(message, previousMessage);
        final showAvatar = _shouldShowAvatar(message, nextMessage);
        final isMe = message.isMine(currentUserId);

        return Column(
          children: [
            if (showDateHeader) _DateHeader(date: message.createdAt),
            MessageBubble(
              message: message,
              isMe: isMe,
              showAvatar: showAvatar,
              avatarUrl: message.sender?.photoUrl,
              onReply: onReply != null ? () => onReply!(message) : null,
              onDelete: isMe && onDelete != null ? () => onDelete!(message) : null,
              onCopy: message.contentType == MessageContentType.text
                  ? () => onCopy(message)
                  : null,
            ),
          ],
        );
      },
    );
  }

  bool _shouldShowDateHeader(Message current, Message? previous) {
    if (previous == null) return true;

    final currentDate = DateTime(
      current.createdAt.year,
      current.createdAt.month,
      current.createdAt.day,
    );
    final previousDate = DateTime(
      previous.createdAt.year,
      previous.createdAt.month,
      previous.createdAt.day,
    );

    return currentDate != previousDate;
  }

  bool _shouldShowAvatar(Message current, Message? next) {
    if (current.isSystemMessage) return false;
    if (next == null) return true;
    if (next.isSystemMessage) return true;

    // Show avatar if next message is from a different sender
    // or if there's a significant time gap
    if (next.senderId != current.senderId) return true;

    final timeDiff = next.createdAt.difference(current.createdAt);
    return timeDiff.inMinutes > 5;
  }
}

/// Date header between message groups
class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();

    String dateText;
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      dateText = 'Today';
    } else if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day - 1) {
      dateText = 'Yesterday';
    } else if (date.year == now.year) {
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      dateText = '${months[date.month - 1]} ${date.day}';
    } else {
      dateText = '${date.day}/${date.month}/${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            dateText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty state when no messages
class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState({required this.otherParticipantName});

  final String otherParticipantName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline,
                size: 40,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Start a conversation',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Send a message to $otherParticipantName',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _SuggestedMessages(
              onSelect: (message) {
                // This would need to be implemented with a callback
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Suggested quick messages
class _SuggestedMessages extends StatelessWidget {
  const _SuggestedMessages({required this.onSelect});

  final ValueChanged<String> onSelect;

  static const _suggestions = [
    'Hi, is this property available?',
    'What time is check-in?',
    'Can I bring pets?',
    'Is parking included?',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: _suggestions.map((suggestion) {
        return ActionChip(
          label: Text(
            suggestion,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.primary,
            ),
          ),
          backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.3),
          side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.3)),
          onPressed: () => onSelect(suggestion),
        );
      }).toList(),
    );
  }
}
