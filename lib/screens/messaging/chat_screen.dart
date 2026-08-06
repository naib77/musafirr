import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mime/mime.dart';

import '../../core/utils/responsive.dart';
import '../../models/message.dart';
import '../../services/image_compression_service.dart';
import '../../services/image_upload_service.dart';
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

  // In-conversation search
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Channel state
  MessagingChannel _selectedChannel = MessagingChannel.inApp;
  List<MessagingChannel> _availableChannels = [MessagingChannel.inApp];

  void _startSearch() => setState(() => _isSearching = true);

  void _stopSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _searchQuery = '';
    });
  }

  @override
  void initState() {
    super.initState();
    // Listen for new messages to scroll to bottom
    widget.messagingState.addListener(_onMessagesChanged);

    // Safe to call directly from initState: MessagingStateNotifier uses
    // SafeNotifier, which defers any build-phase notification to post-frame.
    widget.messagingState.openConversation(widget.conversationId);
  }

  @override
  void dispose() {
    widget.messagingState.removeListener(_onMessagesChanged);
    widget.messagingState.closeConversation();
    _scrollController.dispose();
    _searchController.dispose();
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

  /// Pick an image from the gallery, upload it, and send it as an image message.
  Future<void> _sendImage() async {
    final picked = await ImageUploadService.instance.pickImageFromGallery();
    if (picked == null || !mounted) return;

    ModernBanner.showInfo(context, 'Sending photo…');
    final path =
        '${widget.conversationId}/${DateTime.now().microsecondsSinceEpoch}_${picked.name}';
    final result = await ImageUploadService.instance.uploadXFile(
      file: picked,
      bucket: StorageBuckets.chatAttachments,
      path: path,
      compressionProfile: ImageCompressionProfile.listing,
    );
    if (!mounted) return;
    if (!result.success || result.publicUrl == null) {
      ModernBanner.showError(
          context, 'Could not send the photo. Please try again.');
      return;
    }
    final sent = await widget.messagingState
        .sendImageMessage(imageUrl: result.publicUrl!);
    if (!sent && mounted) {
      ModernBanner.showError(
          context, 'Could not send the photo. Please try again.');
    }
  }

  /// Pick a document/file, upload it, and send it as a file message.
  Future<void> _sendFile() async {
    final picked = await ImageUploadService.instance.pickFile();
    if (picked == null || !mounted) return;

    ModernBanner.showInfo(context, 'Sending file…');
    final path =
        '${widget.conversationId}/${DateTime.now().microsecondsSinceEpoch}_${picked.name}';
    final result = await ImageUploadService.instance.uploadPlatformFile(
      file: picked,
      bucket: StorageBuckets.chatAttachments,
      path: path,
    );
    if (!mounted) return;
    if (!result.success || result.publicUrl == null) {
      ModernBanner.showError(
          context, 'Could not send the file. Please try again.');
      return;
    }
    final sent = await widget.messagingState.sendFileMessage(
      url: result.publicUrl!,
      fileName: picked.name,
      mimeType: lookupMimeType(picked.name) ?? 'application/octet-stream',
      sizeBytes: picked.size,
    );
    if (!sent && mounted) {
      ModernBanner.showError(
          context, 'Could not send the file. Please try again.');
    }
  }

  /// Show a grid of all images shared in this conversation.
  void _openMediaGallery() {
    final images = widget.messagingState.messages
        .where((m) => m.contentType == MessageContentType.image)
        .map((m) => (m.metadata as ImageMetadata?)?.url)
        .whereType<String>()
        .toList();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _MediaGalleryScreen(imageUrls: images)),
    );
  }

  /// Shares the sender's current location as a map message.
  Future<void> _sendLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ModernBanner.showWarning(
            context,
            'Allow location access to share your location.',
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition();

      // Reverse-geocode for a readable label; not supported on web, and never
      // worth failing the send over.
      String? address;
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          address = [p.street, p.subLocality, p.locality]
              .whereType<String>()
              .where((part) => part.isNotEmpty)
              .join(', ');
          if (address.isEmpty) address = null;
        }
      } catch (_) {}

      final sent = await widget.messagingState.sendLocationMessage(
        latitude: position.latitude,
        longitude: position.longitude,
        address: address,
      );

      if (!sent && mounted) {
        ModernBanner.showError(
          context,
          'Could not share your location. Please try again.',
        );
      }
    } catch (e) {
      if (mounted) {
        ModernBanner.showError(
          context,
          'Could not get your location. Check that location is turned on.',
        );
      }
    }
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
        leading: _isSearching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _stopSearch,
              )
            : null,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search this conversation',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
              )
            : Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: widget.otherParticipantAvatarUrl != null
                        ? NetworkImage(widget.otherParticipantAvatarUrl!)
                        : null,
                    child: widget.otherParticipantAvatarUrl == null
                        ? Text(
                            widget.otherParticipantName
                                .substring(0, 1)
                                .toUpperCase(),
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
                            final typingUsers = widget
                                .messagingState.typingIndicators
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
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
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
                                        color: theme.colorScheme
                                            .surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Ended',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
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
        actions: _isSearching
            ? [
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
              ]
            : [
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
                        _startSearch();
                        break;
                      case 'media':
                        _openMediaGallery();
                        break;
                      case 'channels':
                        _showChannelSettings();
                        break;
                      case 'mute':
                        ModernBanner.showSuccess(
                            context, 'Notifications muted');
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
      body: ResponsiveCenter(
        maxWidth: 900,
        child: Column(
          children: [
            // Messages list
            Expanded(
              child: ListenableBuilder(
                listenable: widget.messagingState,
                builder: (context, _) {
                  if (widget.messagingState.isLoadingMessages) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allMessages = widget.messagingState.messages;

                  if (allMessages.isEmpty) {
                    return _EmptyChatState(
                      otherParticipantName: widget.otherParticipantName,
                      onSelectSuggestion: _sendMessage,
                    );
                  }

                  // In search mode, show only messages whose text matches.
                  if (_isSearching && _searchQuery.isNotEmpty) {
                    final q = _searchQuery.toLowerCase();
                    final matches = allMessages
                        .where((m) => m.content.toLowerCase().contains(q))
                        .toList();
                    if (matches.isEmpty) {
                      return _NoSearchResults(query: _searchQuery);
                    }
                    return _MessagesList(
                      messages: matches,
                      currentUserId: widget.messagingState.currentUserId ?? '',
                      scrollController: _scrollController,
                      onReply: _replyToMessage,
                      onDelete: _deleteMessage,
                      onCopy: _copyMessage,
                      typingIndicator: const SizedBox.shrink(),
                    );
                  }

                  return _MessagesList(
                    messages: allMessages,
                    currentUserId: widget.messagingState.currentUserId ?? '',
                    scrollController: _scrollController,
                    onReply: _replyToMessage,
                    onDelete: _deleteMessage,
                    onCopy: _copyMessage,
                    typingIndicator: _buildTypingIndicator(),
                  );
                },
              ),
            ),

            // Input area — always shown: guests and hosts can keep messaging
            // even after the booking ends.
            ListenableBuilder(
              listenable: widget.messagingState,
              builder: (context, _) {
                return MessageInput(
                  onSendMessage: _sendMessage,
                  onSendImage: _sendImage,
                  onSendLocation: _sendLocation,
                  onSendFile: _sendFile,
                  onTextChanged: widget.messagingState.onTextChanged,
                  replyingTo: _replyingTo,
                  onCancelReply: _cancelReply,
                  isSending: widget.messagingState.isSendingMessage,
                );
              },
            ),
          ],
        ),
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
            if (showDateHeader) _DateHeader(date: message.createdAt.toLocal()),
            MessageBubble(
              message: message,
              isMe: isMe,
              showAvatar: showAvatar,
              avatarUrl: message.sender?.photoUrl,
              onReply: onReply != null ? () => onReply!(message) : null,
              onDelete:
                  isMe && onDelete != null ? () => onDelete!(message) : null,
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

    // Compare LOCAL calendar days — timestamps arrive as UTC, and a UTC day
    // boundary splits an evening (BD time) conversation in the wrong place.
    final currentLocal = current.createdAt.toLocal();
    final previousLocal = previous.createdAt.toLocal();
    final currentDate = DateTime(
      currentLocal.year,
      currentLocal.month,
      currentLocal.day,
    );
    final previousDate = DateTime(
      previousLocal.year,
      previousLocal.month,
      previousLocal.day,
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
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
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
  const _EmptyChatState({
    required this.otherParticipantName,
    required this.onSelectSuggestion,
  });

  final String otherParticipantName;
  final ValueChanged<String> onSelectSuggestion;

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
              onSelect: onSelectSuggestion,
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid of every image shared in a conversation; tap to view full-screen.
class _MediaGalleryScreen extends StatelessWidget {
  const _MediaGalleryScreen({required this.imageUrls});

  final List<String> imageUrls;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Shared media')),
      body: imageUrls.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library_outlined,
                      size: 48, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text('No photos shared yet',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: imageUrls.length,
              itemBuilder: (context, i) {
                final url = imageUrls[i];
                return GestureDetector(
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      backgroundColor: Colors.black,
                      insetPadding: const EdgeInsets.all(12),
                      child: InteractiveViewer(
                        child: Image.network(url, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(Icons.broken_image_outlined,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Shown when an in-conversation search matches nothing.
class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'No messages match "$query"',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
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
          backgroundColor:
              theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
          side: BorderSide(
              color: theme.colorScheme.primary.withValues(alpha: 0.3)),
          onPressed: () => onSelect(suggestion),
        );
      }).toList(),
    );
  }
}
