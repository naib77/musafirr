import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../state/messaging_state.dart';
import '../../widgets/messaging/conversation_tile.dart';
import '../messaging/chat_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    this.messagingState,
  });

  final MessagingStateNotifier? messagingState;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
        ),
      ),
    );
  }

  void _showConversationOptions(Conversation conversation) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _ConversationOptionsSheet(
        conversation: conversation,
        onArchive: () {
          Navigator.pop(context);
          widget.messagingState?.archiveConversation(conversation.id);
        },
        onDelete: () {
          Navigator.pop(context);
          // Show confirmation dialog
          _confirmDelete(conversation);
        },
      ),
    );
  }

  void _confirmDelete(Conversation conversation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
          'This will permanently delete this conversation and all messages. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // For now, just archive since we don't have a delete method
              widget.messagingState?.archiveConversation(conversation.id);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If no messaging state provided, show placeholder
    if (widget.messagingState == null) {
      return const _InboxPlaceholder();
    }

    return ListenableBuilder(
      listenable: widget.messagingState!,
      builder: (context, _) {
        final activeConversations = widget.messagingState!.activeConversations;
        final archivedConversations = widget.messagingState!.archivedConversations;

        return Column(
          children: [
            // Tab bar
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Messages'),
                      if (widget.messagingState!.totalUnreadCount > 0) ...[
                        const SizedBox(width: 8),
                        _UnreadBadge(
                          count: widget.messagingState!.totalUnreadCount,
                        ),
                      ],
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Archived'),
                      if (archivedConversations.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          '(${archivedConversations.length})',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Active messages
                  _buildConversationList(
                    conversations: activeConversations,
                    isLoading: widget.messagingState!.isLoadingConversations,
                    emptyTitle: 'No messages yet',
                    emptySubtitle:
                        'When you book a trip or receive a reservation, messages from your host or guest will appear here.',
                  ),

                  // Archived
                  _buildConversationList(
                    conversations: archivedConversations,
                    isLoading: false,
                    emptyTitle: 'No archived messages',
                    emptySubtitle:
                        'Conversations you archive will appear here.',
                    emptyIcon: Icons.archive_outlined,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildConversationList({
    required List<Conversation> conversations,
    required bool isLoading,
    required String emptyTitle,
    required String emptySubtitle,
    IconData emptyIcon = Icons.chat_bubble_outline,
  }) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (conversations.isEmpty) {
      return ConversationsEmptyState(
        title: emptyTitle,
        subtitle: emptySubtitle,
        icon: emptyIcon,
      );
    }

    return RefreshIndicator(
      onRefresh: () => widget.messagingState!.refreshConversations(),
      child: ListView.builder(
        itemCount: conversations.length,
        itemBuilder: (context, index) {
          final conversation = conversations[index];
          return ConversationTile(
            conversation: conversation,
            showDivider: index < conversations.length - 1,
            onTap: () => _openConversation(conversation),
            onLongPress: () => _showConversationOptions(conversation),
          );
        },
      ),
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

/// Unread count badge
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Bottom sheet for conversation options
class _ConversationOptionsSheet extends StatelessWidget {
  const _ConversationOptionsSheet({
    required this.conversation,
    required this.onArchive,
    required this.onDelete,
  });

  final Conversation conversation;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isArchived = conversation.status == ConversationStatus.archived;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Conversation preview
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundImage: conversation.avatarUrl != null
                      ? NetworkImage(conversation.avatarUrl!)
                      : null,
                  child: conversation.avatarUrl == null
                      ? Text(conversation.displayName[0].toUpperCase())
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    conversation.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),

          // Actions
          ListTile(
            leading: Icon(
              isArchived ? Icons.unarchive : Icons.archive,
            ),
            title: Text(isArchived ? 'Unarchive' : 'Archive'),
            onTap: onArchive,
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Delete', style: TextStyle(color: Colors.red)),
            onTap: onDelete,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
