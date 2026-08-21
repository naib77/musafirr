import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../models/user.dart';
import '../../models/user_role.dart';
import 'messaging_service.dart';

/// In-memory implementation of MessagingService for development
class InMemoryMessagingService implements MessagingService {
  InMemoryMessagingService();

  // Storage
  final Map<String, Conversation> _conversations = {};
  final Map<String, List<Message>> _messages = {};
  final Map<String, ReadCursor> _readCursors = {};
  final Map<String, TypingIndicator> _typingIndicators = {};
  final Map<String, User> _users = {};

  // Stream controllers
  final Map<String, StreamController<Message>> _messageStreams = {};
  final Map<String, StreamController<Conversation>> _conversationStreams = {};
  final Map<String, StreamController<List<TypingIndicator>>> _typingStreams =
      {};
  final Map<String, StreamController<int>> _unreadCountStreams = {};

  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    // Create sample users
    _createSampleUsers();

    // Create sample conversations and messages
    _createSampleData();

    _initialized = true;
    debugPrint('[InMemoryMessagingService] Initialized with sample data');
  }

  void _createSampleUsers() {
    _users['user_host_1'] = User(
      id: 'user_host_1',
      name: 'Karim Ahmed',
      email: 'karim@example.com',
      avatarUrl: 'https://i.pravatar.cc/150?img=11',
      role: UserRole.owner,
      isHost: true,
      responseRate: 98,
      responseTime: 'within an hour',
    );

    _users['user_host_2'] = User(
      id: 'user_host_2',
      name: 'Fatima Rahman',
      email: 'fatima@example.com',
      avatarUrl: 'https://i.pravatar.cc/150?img=5',
      role: UserRole.owner,
      isHost: true,
      responseRate: 95,
      responseTime: 'within a few hours',
    );

    _users['user_guest_1'] = User(
      id: 'user_guest_1',
      name: 'Rahim Khan',
      email: 'rahim@example.com',
      avatarUrl: 'https://i.pravatar.cc/150?img=12',
      role: UserRole.guest,
    );

    _users['current_user'] = User(
      id: 'current_user',
      name: 'You',
      email: 'you@example.com',
      avatarUrl: 'https://i.pravatar.cc/150?img=3',
      role: UserRole.guest,
    );
  }

  void _createSampleData() {
    final now = DateTime.now();

    // Conversation 1: With host about a booking
    final conv1 = Conversation(
      id: 'conv_1',
      participantOneId: 'current_user',
      participantTwoId: 'user_host_1',
      bookingId: 'booking_123',
      listingId: 'listing_456',
      status: ConversationStatus.active,
      lastMessageText: 'Sure, the check-in time is 2 PM',
      lastMessageAt: now.subtract(const Duration(minutes: 5)),
      lastMessageSenderId: 'user_host_1',
      createdAt: now.subtract(const Duration(days: 2)),
      updatedAt: now.subtract(const Duration(minutes: 5)),
      otherParticipant: _users['user_host_1'],
      unreadCount: 2,
    );
    _conversations[conv1.id] = conv1;

    // Messages for conversation 1
    _messages[conv1.id] = [
      Message(
        id: 'msg_1_1',
        conversationId: conv1.id,
        senderId: 'current_user',
        contentType: MessageContentType.text,
        content: 'Hi, I have a question about the property',
        status: MessageStatus.read,
        createdAt: now.subtract(const Duration(days: 1, hours: 2)),
        updatedAt: now.subtract(const Duration(days: 1, hours: 2)),
        sender: _users['current_user'],
      ),
      Message(
        id: 'msg_1_2',
        conversationId: conv1.id,
        senderId: 'user_host_1',
        contentType: MessageContentType.text,
        content: 'Hello! Of course, how can I help you?',
        status: MessageStatus.read,
        createdAt: now.subtract(const Duration(days: 1, hours: 1)),
        updatedAt: now.subtract(const Duration(days: 1, hours: 1)),
        sender: _users['user_host_1'],
      ),
      Message(
        id: 'msg_1_3',
        conversationId: conv1.id,
        senderId: 'current_user',
        contentType: MessageContentType.text,
        content: 'What time is check-in?',
        status: MessageStatus.read,
        createdAt: now.subtract(const Duration(hours: 1)),
        updatedAt: now.subtract(const Duration(hours: 1)),
        sender: _users['current_user'],
      ),
      Message(
        id: 'msg_1_4',
        conversationId: conv1.id,
        senderId: 'user_host_1',
        contentType: MessageContentType.text,
        content: 'Sure, the check-in time is 2 PM',
        status: MessageStatus.sent,
        createdAt: now.subtract(const Duration(minutes: 5)),
        updatedAt: now.subtract(const Duration(minutes: 5)),
        sender: _users['user_host_1'],
      ),
    ];

    // Conversation 2: With another host
    final conv2 = Conversation(
      id: 'conv_2',
      participantOneId: 'current_user',
      participantTwoId: 'user_host_2',
      status: ConversationStatus.active,
      lastMessageText: 'Thank you for your interest!',
      lastMessageAt: now.subtract(const Duration(hours: 3)),
      lastMessageSenderId: 'user_host_2',
      createdAt: now.subtract(const Duration(days: 5)),
      updatedAt: now.subtract(const Duration(hours: 3)),
      otherParticipant: _users['user_host_2'],
      unreadCount: 0,
    );
    _conversations[conv2.id] = conv2;

    _messages[conv2.id] = [
      Message(
        id: 'msg_2_1',
        conversationId: conv2.id,
        senderId: 'current_user',
        contentType: MessageContentType.text,
        content: 'Is the apartment still available for next weekend?',
        status: MessageStatus.read,
        createdAt: now.subtract(const Duration(hours: 5)),
        updatedAt: now.subtract(const Duration(hours: 5)),
        sender: _users['current_user'],
      ),
      Message(
        id: 'msg_2_2',
        conversationId: conv2.id,
        senderId: 'user_host_2',
        contentType: MessageContentType.text,
        content: 'Thank you for your interest!',
        status: MessageStatus.read,
        createdAt: now.subtract(const Duration(hours: 3)),
        updatedAt: now.subtract(const Duration(hours: 3)),
        sender: _users['user_host_2'],
      ),
    ];

    // Conversation 3: Archived conversation
    final conv3 = Conversation(
      id: 'conv_3',
      participantOneId: 'current_user',
      participantTwoId: 'user_guest_1',
      status: ConversationStatus.archived,
      lastMessageText: 'Thanks for staying!',
      lastMessageAt: now.subtract(const Duration(days: 30)),
      lastMessageSenderId: 'current_user',
      createdAt: now.subtract(const Duration(days: 45)),
      updatedAt: now.subtract(const Duration(days: 30)),
      otherParticipant: _users['user_guest_1'],
      unreadCount: 0,
    );
    _conversations[conv3.id] = conv3;

    _messages[conv3.id] = [
      Message(
        id: 'msg_3_1',
        conversationId: conv3.id,
        senderId: 'current_user',
        contentType: MessageContentType.text,
        content: 'Thanks for staying!',
        status: MessageStatus.read,
        createdAt: now.subtract(const Duration(days: 30)),
        updatedAt: now.subtract(const Duration(days: 30)),
        sender: _users['current_user'],
      ),
    ];

    // Create read cursors
    _readCursors['conv_1_current_user'] = ReadCursor(
      id: 'rc_1',
      conversationId: 'conv_1',
      userId: 'current_user',
      lastReadMessageId: 'msg_1_2',
      lastReadAt: now.subtract(const Duration(hours: 1)),
    );
  }

  @override
  Future<void> dispose() async {
    for (final controller in _messageStreams.values) {
      await controller.close();
    }
    for (final controller in _conversationStreams.values) {
      await controller.close();
    }
    for (final controller in _typingStreams.values) {
      await controller.close();
    }
    for (final controller in _unreadCountStreams.values) {
      await controller.close();
    }
    _messageStreams.clear();
    _conversationStreams.clear();
    _typingStreams.clear();
    _unreadCountStreams.clear();
  }

  // ============================================
  // Conversations
  // ============================================

  @override
  Future<MessagingResult<List<Conversation>>> getConversations(
    String userId, {
    ConversationFilter? filter,
    int limit = 20,
    int offset = 0,
  }) async {
    await _ensureInitialized();

    var conversations = _conversations.values.where((c) {
      return c.participantOneId == userId || c.participantTwoId == userId;
    }).toList();

    // Apply filters
    if (filter != null) {
      if (filter.status != null) {
        conversations =
            conversations.where((c) => c.status == filter.status).toList();
      }
      if (filter.hasUnread == true) {
        conversations = conversations.where((c) => c.unreadCount > 0).toList();
      }
      if (filter.bookingId != null) {
        conversations = conversations
            .where((c) => c.bookingId == filter.bookingId)
            .toList();
      }
      if (filter.listingId != null) {
        conversations = conversations
            .where((c) => c.listingId == filter.listingId)
            .toList();
      }
    }

    // Sort by last message time
    conversations.sort((a, b) {
      final aTime = a.lastMessageAt ?? a.createdAt;
      final bTime = b.lastMessageAt ?? b.createdAt;
      return bTime.compareTo(aTime);
    });

    // Apply pagination
    final start = offset;
    final end = (offset + limit).clamp(0, conversations.length);
    final paginated = conversations.sublist(start, end);

    return MessagingResult.success(paginated);
  }

  @override
  Future<MessagingResult<Conversation>> getConversation(
    String conversationId,
    String currentUserId,
  ) async {
    await _ensureInitialized();

    final conversation = _conversations[conversationId];
    if (conversation == null) {
      return const MessagingResult.failure('Conversation not found');
    }

    return MessagingResult.success(conversation);
  }

  @override
  Future<void> populateBookingContext(
    String conversationId,
    String bookingId,
  ) async {
    // Nothing to enrich in memory: conversations here are built with their
    // booking fields already set.
  }

  @override
  Future<MessagingResult<String>> getOrCreateConversationId({
    required String currentUserId,
    required String otherUserId,
    String? bookingId,
    String? listingId,
  }) async {
    // In memory there are no round trips to save, so the fast path is just the
    // full one with the id picked out.
    final result = await getOrCreateConversation(
      currentUserId: currentUserId,
      otherUserId: otherUserId,
      bookingId: bookingId,
      listingId: listingId,
    );
    if (!result.isSuccess || result.data == null) {
      return MessagingResult.failure(
          result.error ?? 'Failed to create conversation');
    }
    return MessagingResult.success(result.data!.id);
  }

  @override
  Future<MessagingResult<Conversation>> getOrCreateConversation({
    required String currentUserId,
    required String otherUserId,
    String? bookingId,
    String? listingId,
  }) async {
    await _ensureInitialized();

    // Look for existing conversation
    for (final conv in _conversations.values) {
      final hasUsers = (conv.participantOneId == currentUserId &&
              conv.participantTwoId == otherUserId) ||
          (conv.participantOneId == otherUserId &&
              conv.participantTwoId == currentUserId);

      if (hasUsers) {
        return MessagingResult.success(conv);
      }
    }

    // Create new conversation
    final now = DateTime.now();
    final id = 'conv_${now.millisecondsSinceEpoch}';

    final otherUser = _users[otherUserId];
    final conversation = Conversation(
      id: id,
      participantOneId: currentUserId.compareTo(otherUserId) < 0
          ? currentUserId
          : otherUserId,
      participantTwoId: currentUserId.compareTo(otherUserId) < 0
          ? otherUserId
          : currentUserId,
      bookingId: bookingId,
      listingId: listingId,
      status: ConversationStatus.active,
      createdAt: now,
      updatedAt: now,
      otherParticipant: otherUser,
      unreadCount: 0,
    );

    _conversations[id] = conversation;
    _messages[id] = [];

    debugPrint('[InMemoryMessagingService] Created conversation: $id');
    return MessagingResult.success(conversation);
  }

  @override
  Future<MessagingResult<void>> archiveConversation(
      String conversationId) async {
    final conv = _conversations[conversationId];
    if (conv == null) {
      return const MessagingResult.failure('Conversation not found');
    }

    _conversations[conversationId] = conv.copyWith(
      status: ConversationStatus.archived,
      updatedAt: DateTime.now(),
    );

    _notifyConversationUpdate(conversationId);
    return const MessagingResult.success(null);
  }

  @override
  Future<MessagingResult<void>> unarchiveConversation(
      String conversationId) async {
    final conv = _conversations[conversationId];
    if (conv == null) {
      return const MessagingResult.failure('Conversation not found');
    }

    _conversations[conversationId] = conv.copyWith(
      status: ConversationStatus.active,
      updatedAt: DateTime.now(),
    );

    _notifyConversationUpdate(conversationId);
    return const MessagingResult.success(null);
  }

  @override
  Future<MessagingResult<void>> blockConversation(String conversationId) async {
    final conv = _conversations[conversationId];
    if (conv == null) {
      return const MessagingResult.failure('Conversation not found');
    }

    _conversations[conversationId] = conv.copyWith(
      status: ConversationStatus.blocked,
      updatedAt: DateTime.now(),
    );

    _notifyConversationUpdate(conversationId);
    return const MessagingResult.success(null);
  }

  @override
  Future<MessagingResult<void>> unblockConversation(
      String conversationId) async {
    final conv = _conversations[conversationId];
    if (conv == null) {
      return const MessagingResult.failure('Conversation not found');
    }

    _conversations[conversationId] = conv.copyWith(
      status: ConversationStatus.active,
      updatedAt: DateTime.now(),
    );

    _notifyConversationUpdate(conversationId);
    return const MessagingResult.success(null);
  }

  // ============================================
  // Messages
  // ============================================

  @override
  Future<MessagingResult<List<Message>>> getMessages(
    String conversationId, {
    MessageFilter? filter,
    int limit = 50,
  }) async {
    await _ensureInitialized();

    var messages = _messages[conversationId] ?? [];

    // Apply filters
    if (filter != null) {
      if (filter.contentType != null) {
        messages =
            messages.where((m) => m.contentType == filter.contentType).toList();
      }
      if (filter.senderId != null) {
        messages =
            messages.where((m) => m.senderId == filter.senderId).toList();
      }
      if (filter.beforeId != null) {
        final beforeIndex = messages.indexWhere((m) => m.id == filter.beforeId);
        if (beforeIndex >= 0) {
          messages = messages.sublist(0, beforeIndex);
        }
      }
      if (filter.afterId != null) {
        final afterIndex = messages.indexWhere((m) => m.id == filter.afterId);
        if (afterIndex >= 0) {
          messages = messages.sublist(afterIndex + 1);
        }
      }
    }

    // Filter out deleted messages
    messages = messages.where((m) => m.deletedAt == null).toList();

    // Sort by time (oldest first for display)
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Limit
    if (messages.length > limit) {
      messages = messages.sublist(messages.length - limit);
    }

    return MessagingResult.success(messages);
  }

  @override
  Future<MessagingResult<Message>> sendMessage(
    SendMessageRequest request,
    String senderId,
  ) async {
    await _ensureInitialized();

    final conv = _conversations[request.conversationId];
    if (conv == null) {
      return const MessagingResult.failure('Conversation not found');
    }

    if (conv.status != ConversationStatus.active) {
      return const MessagingResult.failure(
          'Cannot send message to inactive conversation');
    }

    final now = DateTime.now();
    final id = 'msg_${now.millisecondsSinceEpoch}';

    final message = Message(
      id: id,
      conversationId: request.conversationId,
      senderId: senderId,
      contentType: request.contentType,
      content: request.content,
      metadata: request.metadata,
      status: MessageStatus.sent,
      replyToId: request.replyToId,
      createdAt: now,
      updatedAt: now,
      sender: _users[senderId],
    );

    // Add to messages
    _messages[request.conversationId] ??= [];
    _messages[request.conversationId]!.add(message);

    // Update conversation
    _conversations[request.conversationId] = conv.copyWith(
      lastMessageId: id,
      lastMessageText: message.displayText,
      lastMessageAt: now,
      lastMessageSenderId: senderId,
      updatedAt: now,
    );

    // Notify streams
    _notifyNewMessage(message);
    _notifyConversationUpdate(request.conversationId);

    debugPrint('[InMemoryMessagingService] Sent message: ${message.content}');
    return MessagingResult.success(message);
  }

  @override
  Future<MessagingResult<Message>> editMessage(
    String messageId,
    String newContent,
  ) async {
    for (final messages in _messages.values) {
      final index = messages.indexWhere((m) => m.id == messageId);
      if (index >= 0) {
        final oldMessage = messages[index];
        final updatedMessage = oldMessage.copyWith(
          content: newContent,
          updatedAt: DateTime.now(),
        );
        messages[index] = updatedMessage;
        _notifyNewMessage(updatedMessage);
        return MessagingResult.success(updatedMessage);
      }
    }
    return const MessagingResult.failure('Message not found');
  }

  @override
  Future<MessagingResult<void>> deleteMessage(String messageId) async {
    for (final messages in _messages.values) {
      final index = messages.indexWhere((m) => m.id == messageId);
      if (index >= 0) {
        final updatedMessage = messages[index].copyWith(
          deletedAt: DateTime.now(),
        );
        messages[index] = updatedMessage;
        _notifyNewMessage(updatedMessage);
        return const MessagingResult.success(null);
      }
    }
    return const MessagingResult.failure('Message not found');
  }

  @override
  Future<MessagingResult<void>> markAsRead(
    String conversationId,
    String userId,
    String messageId,
  ) async {
    final cursorKey = '${conversationId}_$userId';
    _readCursors[cursorKey] = ReadCursor(
      id: cursorKey,
      conversationId: conversationId,
      userId: userId,
      lastReadMessageId: messageId,
      lastReadAt: DateTime.now(),
    );

    // Update conversation unread count
    final conv = _conversations[conversationId];
    if (conv != null) {
      _conversations[conversationId] = conv.copyWith(unreadCount: 0);
      _notifyConversationUpdate(conversationId);
    }

    return const MessagingResult.success(null);
  }

  @override
  Future<MessagingResult<void>> markAllAsRead(
    String conversationId,
    String userId,
  ) async {
    final messages = _messages[conversationId];
    if (messages == null || messages.isEmpty) {
      return const MessagingResult.success(null);
    }

    final lastMessage = messages.last;
    return markAsRead(conversationId, userId, lastMessage.id);
  }

  // ============================================
  // Typing Indicators
  // ============================================

  @override
  Future<MessagingResult<void>> setTyping(
    String conversationId,
    String userId,
    bool isTyping,
  ) async {
    final key = '${conversationId}_$userId';

    if (isTyping) {
      _typingIndicators[key] = TypingIndicator(
        conversationId: conversationId,
        userId: userId,
        startedAt: DateTime.now(),
        userName: _users[userId]?.name,
      );
    } else {
      _typingIndicators.remove(key);
    }

    _notifyTypingUpdate(conversationId);
    return const MessagingResult.success(null);
  }

  @override
  Future<MessagingResult<List<TypingIndicator>>> getTypingIndicators(
    String conversationId,
  ) async {
    final indicators = _typingIndicators.values
        .where((t) => t.conversationId == conversationId && t.isValid)
        .toList();
    return MessagingResult.success(indicators);
  }

  // ============================================
  // Real-time Subscriptions
  // ============================================

  @override
  Stream<Message> subscribeToMessages(String conversationId) {
    _messageStreams[conversationId] ??= StreamController<Message>.broadcast();
    return _messageStreams[conversationId]!.stream;
  }

  @override
  Stream<Conversation> subscribeToConversation(String conversationId) {
    _conversationStreams[conversationId] ??=
        StreamController<Conversation>.broadcast();
    return _conversationStreams[conversationId]!.stream;
  }

  @override
  Stream<Conversation> subscribeToConversations(String userId) {
    final key = 'user_$userId';
    _conversationStreams[key] ??= StreamController<Conversation>.broadcast();
    return _conversationStreams[key]!.stream;
  }

  @override
  Stream<List<TypingIndicator>> subscribeToTypingIndicators(
    String conversationId,
  ) {
    _typingStreams[conversationId] ??=
        StreamController<List<TypingIndicator>>.broadcast();
    return _typingStreams[conversationId]!.stream;
  }

  @override
  Stream<int> subscribeToTotalUnreadCount(String userId) {
    _unreadCountStreams[userId] ??= StreamController<int>.broadcast();
    return _unreadCountStreams[userId]!.stream;
  }

  // ============================================
  // Counts
  // ============================================

  @override
  Future<MessagingResult<int>> getUnreadCount(
    String conversationId,
    String userId,
  ) async {
    final conv = _conversations[conversationId];
    if (conv == null) {
      return const MessagingResult.success(0);
    }
    return MessagingResult.success(conv.unreadCount);
  }

  @override
  Future<MessagingResult<int>> getTotalUnreadCount(String userId) async {
    var total = 0;
    for (final conv in _conversations.values) {
      if (conv.participantOneId == userId || conv.participantTwoId == userId) {
        total += conv.unreadCount;
      }
    }
    return MessagingResult.success(total);
  }

  // ============================================
  // Private Helpers
  // ============================================

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  void _notifyNewMessage(Message message) {
    final controller = _messageStreams[message.conversationId];
    if (controller != null && !controller.isClosed) {
      controller.add(message);
    }
  }

  void _notifyConversationUpdate(String conversationId) {
    final conv = _conversations[conversationId];
    if (conv == null) return;

    // Notify specific conversation stream
    final convController = _conversationStreams[conversationId];
    if (convController != null && !convController.isClosed) {
      convController.add(conv);
    }

    // Notify user-level streams
    for (final userId in [conv.participantOneId, conv.participantTwoId]) {
      final userKey = 'user_$userId';
      final userController = _conversationStreams[userKey];
      if (userController != null && !userController.isClosed) {
        userController.add(conv);
      }

      // Update unread count stream
      _notifyUnreadCountUpdate(userId);
    }
  }

  void _notifyTypingUpdate(String conversationId) {
    final controller = _typingStreams[conversationId];
    if (controller != null && !controller.isClosed) {
      final indicators = _typingIndicators.values
          .where((t) => t.conversationId == conversationId && t.isValid)
          .toList();
      controller.add(indicators);
    }
  }

  void _notifyUnreadCountUpdate(String userId) {
    final controller = _unreadCountStreams[userId];
    if (controller != null && !controller.isClosed) {
      var total = 0;
      for (final conv in _conversations.values) {
        if (conv.participantOneId == userId ||
            conv.participantTwoId == userId) {
          total += conv.unreadCount;
        }
      }
      controller.add(total);
    }
  }

  // ============================================
  // Testing Helpers
  // ============================================

  /// Add a sample user (for testing)
  void addUser(User user) {
    _users[user.id] = user;
  }

  /// Get a user by ID
  User? getUser(String userId) => _users[userId];

  /// Simulate receiving a message from another user
  Future<void> simulateIncomingMessage({
    required String conversationId,
    required String senderId,
    required String content,
    MessageContentType contentType = MessageContentType.text,
  }) async {
    await _ensureInitialized();

    final conv = _conversations[conversationId];
    if (conv == null) return;

    final now = DateTime.now();
    final id = 'msg_${now.millisecondsSinceEpoch}';

    final message = Message(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      contentType: contentType,
      content: content,
      status: MessageStatus.sent,
      createdAt: now,
      updatedAt: now,
      sender: _users[senderId],
    );

    _messages[conversationId] ??= [];
    _messages[conversationId]!.add(message);

    // Update conversation with incremented unread count
    _conversations[conversationId] = conv.copyWith(
      lastMessageId: id,
      lastMessageText: message.displayText,
      lastMessageAt: now,
      lastMessageSenderId: senderId,
      updatedAt: now,
      unreadCount: conv.unreadCount + 1,
    );

    _notifyNewMessage(message);
    _notifyConversationUpdate(conversationId);

    debugPrint(
        '[InMemoryMessagingService] Simulated incoming message: $content');
  }
}
