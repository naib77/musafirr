import '../../models/conversation.dart';
import '../../models/message.dart';

/// Result of a messaging operation
class MessagingResult<T> {
  const MessagingResult.success(this.data)
      : error = null,
        isSuccess = true;

  const MessagingResult.failure(this.error)
      : data = null,
        isSuccess = false;

  final T? data;
  final String? error;
  final bool isSuccess;
}

/// Filter for fetching conversations
class ConversationFilter {
  const ConversationFilter({
    this.status,
    this.hasUnread,
    this.bookingId,
    this.listingId,
  });

  final ConversationStatus? status;
  final bool? hasUnread;
  final String? bookingId;
  final String? listingId;
}

/// Filter for fetching messages
class MessageFilter {
  const MessageFilter({
    this.contentType,
    this.beforeId,
    this.afterId,
    this.senderId,
  });

  final MessageContentType? contentType;
  final String? beforeId;
  final String? afterId;
  final String? senderId;
}

/// Request to send a message
class SendMessageRequest {
  const SendMessageRequest({
    required this.conversationId,
    required this.contentType,
    required this.content,
    this.metadata,
    this.replyToId,
  });

  final String conversationId;
  final MessageContentType contentType;
  final String content;
  final MessageMetadata? metadata;
  final String? replyToId;

  /// Create a text message request
  factory SendMessageRequest.text({
    required String conversationId,
    required String text,
    String? replyToId,
  }) {
    return SendMessageRequest(
      conversationId: conversationId,
      contentType: MessageContentType.text,
      content: text,
      replyToId: replyToId,
    );
  }

  /// Create an image message request
  factory SendMessageRequest.image({
    required String conversationId,
    required String caption,
    required ImageMetadata metadata,
    String? replyToId,
  }) {
    return SendMessageRequest(
      conversationId: conversationId,
      contentType: MessageContentType.image,
      content: caption,
      metadata: metadata,
      replyToId: replyToId,
    );
  }

  /// Create a location message request
  factory SendMessageRequest.location({
    required String conversationId,
    required LocationMetadata metadata,
    String? replyToId,
  }) {
    return SendMessageRequest(
      conversationId: conversationId,
      contentType: MessageContentType.location,
      content: metadata.displayName,
      metadata: metadata,
      replyToId: replyToId,
    );
  }

  /// Create a file message request
  factory SendMessageRequest.file({
    required String conversationId,
    required FileMetadata metadata,
    String? replyToId,
  }) {
    return SendMessageRequest(
      conversationId: conversationId,
      contentType: MessageContentType.file,
      content: metadata.fileName,
      metadata: metadata,
      replyToId: replyToId,
    );
  }

  /// Create a booking card message request
  factory SendMessageRequest.bookingCard({
    required String conversationId,
    required BookingCardMetadata metadata,
  }) {
    return SendMessageRequest(
      conversationId: conversationId,
      contentType: MessageContentType.bookingCard,
      content: 'Booking: ${metadata.listingName}',
      metadata: metadata,
    );
  }
}

/// Abstract interface for messaging service
abstract class MessagingService {
  // ============================================
  // Conversations
  // ============================================

  /// Get all conversations for a user
  Future<MessagingResult<List<Conversation>>> getConversations(
    String userId, {
    ConversationFilter? filter,
    int limit = 20,
    int offset = 0,
  });

  /// Get a single conversation by ID
  Future<MessagingResult<Conversation>> getConversation(
    String conversationId,
    String currentUserId,
  );

  /// Get or create a conversation between two users
  Future<MessagingResult<Conversation>> getOrCreateConversation({
    required String currentUserId,
    required String otherUserId,
    String? bookingId,
    String? listingId,
  });

  /// Get or create a conversation and return only its ID.
  ///
  /// The id is all a caller needs to OPEN the chat — [ChatScreen] loads the
  /// messages itself and is handed the other participant's name and avatar by
  /// whoever pushes it. [getOrCreateConversation] additionally fetches the
  /// conversation row, the participant profile and the unread count, which on
  /// a remote backend is three more sequential round trips that the guest
  /// waits out staring at an unchanged screen.
  ///
  /// Use this when you are about to navigate; use
  /// [getOrCreateConversation] when you actually need the hydrated object.
  ///
  /// Does NOT populate booking context — that is two further round trips (read
  /// the booking, write the conversation). Call [populateBookingContext]
  /// afterwards, off the critical path, when a bookingId is involved.
  Future<MessagingResult<String>> getOrCreateConversationId({
    required String currentUserId,
    required String otherUserId,
    String? bookingId,
    String? listingId,
  });

  /// Copy a booking's dates, listing type and title onto its conversation, so
  /// the conversation list and chat header can show what the thread is about.
  ///
  /// Pure enrichment of an existing row: nothing about opening a chat depends
  /// on it, and it already swallows its own errors, so callers that are about
  /// to navigate should not wait for it.
  Future<void> populateBookingContext(String conversationId, String bookingId);

  /// Archive a conversation
  Future<MessagingResult<void>> archiveConversation(String conversationId);

  /// Unarchive a conversation
  Future<MessagingResult<void>> unarchiveConversation(String conversationId);

  /// Block a conversation
  Future<MessagingResult<void>> blockConversation(String conversationId);

  /// Unblock a conversation
  Future<MessagingResult<void>> unblockConversation(String conversationId);

  // ============================================
  // Messages
  // ============================================

  /// Get messages in a conversation
  Future<MessagingResult<List<Message>>> getMessages(
    String conversationId, {
    MessageFilter? filter,
    int limit = 50,
  });

  /// Send a message
  Future<MessagingResult<Message>> sendMessage(
    SendMessageRequest request,
    String senderId,
  );

  /// Edit a message (text only)
  Future<MessagingResult<Message>> editMessage(
    String messageId,
    String newContent,
  );

  /// Delete a message (soft delete)
  Future<MessagingResult<void>> deleteMessage(String messageId);

  /// Mark messages as read up to a specific message
  Future<MessagingResult<void>> markAsRead(
    String conversationId,
    String userId,
    String messageId,
  );

  /// Mark all messages in a conversation as read
  Future<MessagingResult<void>> markAllAsRead(
    String conversationId,
    String userId,
  );

  // ============================================
  // Typing Indicators
  // ============================================

  /// Set typing indicator for a user
  Future<MessagingResult<void>> setTyping(
    String conversationId,
    String userId,
    bool isTyping,
  );

  /// Get typing indicators for a conversation
  Future<MessagingResult<List<TypingIndicator>>> getTypingIndicators(
    String conversationId,
  );

  // ============================================
  // Real-time Subscriptions
  // ============================================

  /// Subscribe to new messages in a conversation
  Stream<Message> subscribeToMessages(String conversationId);

  /// Subscribe to conversation updates (last message, unread count)
  Stream<Conversation> subscribeToConversation(String conversationId);

  /// Subscribe to all conversation updates for a user
  Stream<Conversation> subscribeToConversations(String userId);

  /// Subscribe to typing indicators in a conversation
  Stream<List<TypingIndicator>> subscribeToTypingIndicators(
    String conversationId,
  );

  /// Subscribe to total unread count across all conversations
  Stream<int> subscribeToTotalUnreadCount(String userId);

  // ============================================
  // Counts
  // ============================================

  /// Get unread message count for a conversation
  Future<MessagingResult<int>> getUnreadCount(
    String conversationId,
    String userId,
  );

  /// Get total unread count across all conversations
  Future<MessagingResult<int>> getTotalUnreadCount(String userId);

  // ============================================
  // Lifecycle
  // ============================================

  /// Initialize the service
  Future<void> initialize();

  /// Dispose of resources
  /// Tears down the realtime channels opened for one conversation.
  ///
  /// Cancelling the Dart stream subscription is not enough — the websocket
  /// channel stays subscribed server-side, and every chat ever opened kept
  /// costing traffic for the rest of the session. Call this when a chat is
  /// closed, not just when the app shuts down.
  Future<void> unsubscribeFromConversation(String conversationId);

  Future<void> dispose();
}
