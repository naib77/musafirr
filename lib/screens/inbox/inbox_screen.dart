import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../state/messaging_state.dart';
import '../../widgets/messaging/conversation_tile.dart';
import '../messaging/chat_screen.dart';

/// Unified message inbox, Airbnb-style: one list with every conversation —
/// inquiries, upcoming stays, and past bookings — sorted by latest activity.
class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    this.messagingState,
    this.embedded = false,
  });

  final MessagingStateNotifier? messagingState;

  /// When true the screen renders without its own AppBar, for use as a
  /// bottom-navigation tab where the shell provides the header.
  final bool embedded;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  void _openConversation(Conversation conversation) {
    if (widget.messagingState == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          conversationId: conversation.id,
          messagingState: widget.messagingState!,
          otherParticipantName: conversation.displayName,
          otherParticipantAvatarUrl: conversation.avatarUrl,
          bookingContextSubtitle: conversation.bookingContextSubtitle,
          isArchived: conversation.isArchived,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
      ),
      body: body,
    );
  }

  Widget _buildBody() {
    final messagingState = widget.messagingState;
    if (messagingState == null) {
      return const _InboxPlaceholder();
    }

    return ListenableBuilder(
      listenable: messagingState,
      builder: (context, _) {
        // One unified list: every conversation, newest activity first.
        final conversations = [...messagingState.conversations]..sort((a, b) {
            final aTime = a.lastMessageAt ?? a.updatedAt;
            final bTime = b.lastMessageAt ?? b.updatedAt;
            return bTime.compareTo(aTime);
          });

        if (messagingState.isLoadingConversations && conversations.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (conversations.isEmpty) {
          return const ConversationsEmptyState(
            title: 'No messages yet',
            subtitle: 'When you contact a host or receive a booking, your '
                'conversations will appear here.',
            icon: Icons.chat_bubble_outline,
          );
        }

        return RefreshIndicator(
          onRefresh: () => messagingState.refreshConversations(),
          child: ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              return ConversationTile(
                conversation: conversation,
                showDivider: index < conversations.length - 1,
                onTap: () => _openConversation(conversation),
              );
            },
          ),
        );
      },
    );
  }
}

/// Placeholder when no messaging state is available
class _InboxPlaceholder extends StatelessWidget {
  const _InboxPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              'No messages yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'When you book a trip or receive a reservation, messages from your host or guest will appear here.',
              style: theme.textTheme.bodyLarge?.copyWith(
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
