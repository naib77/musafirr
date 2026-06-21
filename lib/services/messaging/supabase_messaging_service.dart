import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../models/user.dart' as app;
import '../../models/user_role.dart';
import 'messaging_service.dart';

/// Supabase-backed implementation of [MessagingService].
///
/// Provides real-time messaging with persistence using Supabase
/// PostgreSQL database and Realtime subscriptions.
class SupabaseMessagingService implements MessagingService {
  SupabaseMessagingService._();

  static SupabaseMessagingService? _instance;
  static SupabaseMessagingService get instance {
    _instance ??= SupabaseMessagingService._();
    return _instance!;
  }

  SupabaseClient get _client => Supabase.instance.client;

  // User cache for participant info
  final Map<String, app.User> _userCache = {};

  // Stream controllers for real-time updates
  final Map<String, StreamController<Message>> _messageControllers = {};
  final Map<String, StreamController<Conversation>> _conversationControllers = {};
  final Map<String, StreamController<List<TypingIndicator>>> _typingControllers = {};
  StreamController<int>? _unreadCountController;

  // Supabase realtime subscriptions
  final Map<String, RealtimeChannel> _channels = {};

  // ============================================
  // Lifecycle
  // ============================================

  @override
  Future<void> initialize() async {
    debugPrint('[SupabaseMessagingService] Initialized');
  }

  @override
  Future<void> dispose() async {
    // Close all stream controllers
    for (final controller in _messageControllers.values) {
      await controller.close();
    }
    for (final controller in _conversationControllers.values) {
      await controller.close();
    }
    for (final controller in _typingControllers.values) {
      await controller.close();
    }
    await _unreadCountController?.close();

    // Unsubscribe from all channels
    for (final channel in _channels.values) {
      await _client.removeChannel(channel);
    }
    _channels.clear();

    debugPrint('[SupabaseMessagingService] Disposed');
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
    try {
      var query = _client
          .from('conversations')
          .select()
          .or('participant_one_id.eq.$userId,participant_two_id.eq.$userId');

      // Apply filters
      if (filter?.status != null) {
        query = query.eq('status', filter!.status!.name);
      }
      if (filter?.bookingId != null) {
        query = query.eq('booking_id', filter!.bookingId!);
      }
      if (filter?.listingId != null) {
        query = query.eq('listing_id', filter!.listingId!);
      }

      final response = await query
          .order('last_message_at', ascending: false, nullsFirst: false)
          .range(offset, offset + limit - 1);

      final conversations = <Conversation>[];
      for (final row in response as List) {
        final json = row as Map<String, dynamic>;
        var conversation = Conversation.fromJson(json);

        // Load other participant info
        final otherUserId = conversation.getOtherParticipantId(userId);
        final otherUser = await _loadUser(otherUserId);

        // Get unread count
        final unreadCount = await _getUnreadCountInternal(
          conversation.id,
          userId,
        );

        conversation = conversation.copyWith(
          otherParticipant: otherUser,
          unreadCount: unreadCount,
        );

        // Filter by hasUnread if specified
        if (filter?.hasUnread == true && unreadCount == 0) continue;
        if (filter?.hasUnread == false && unreadCount > 0) continue;

        conversations.add(conversation);
      }

      return MessagingResult.success(conversations);
    } catch (e) {
      debugPrint('[SupabaseMessagingService] Error getting conversations: $e');
      return MessagingResult.failure('Failed to load conversations: $e');
    }
  }

  @override
  Future<MessagingResult<Conversation>> getConversation(
    String conversationId,
    String currentUserId,
  ) async {
    try {
      final response = await _client
          .from('conversations')
          .select()
          .eq('id', conversationId)
          .single();

      var conversation = Conversation.fromJson(response);

      // Load other participant
      final otherUserId = conversation.getOtherParticipantId(currentUserId);
      final otherUser = await _loadUser(otherUserId);

      // Get unread count
      final unreadCount = await _getUnreadCountInternal(
        conversationId,
        currentUserId,
      );

      conversation = conversation.copyWith(
        otherParticipant: otherUser,
        unreadCount: unreadCount,
      );

      return MessagingResult.success(conversation);
    } catch (e) {
      debugPrint('[SupabaseMessagingService] Error getting conversation: $e');
      return MessagingResult.failure('Failed to load conversation: $e');
    }
  }

  @override
  Future<MessagingResult<Conversation>> getOrCreateConversation({
    required String currentUserId,
    required String otherUserId,
    String? bookingId,
    String? listingId,
  }) async {
    try {
      // Use the database function for thread-safe creation
      final response = await _client.rpc(
        'get_or_create_conversation',
        params: {
          'user_one': currentUserId,
          'user_two': otherUserId,
          'p_booking_id': bookingId,
          'p_listing_id': listingId,
        },
      );

      final conversationId = response as String;

      // If we have a bookingId, populate the booking context fields
      if (bookingId != null) {
        await _populateBookingContext(conversationId, bookingId);
      }

      // Fetch the full conversation
      return getConversation(conversationId, currentUserId);
    } catch (e) {
      debugPrint('[SupabaseMessagingService] Error creating conversation: $e');
      return MessagingResult.failure('Failed to create conversation: $e');
    }
  }

  /// Populate booking context fields on a conversation from the booking data
  Future<void> _populateBookingContext(String conversationId, String bookingId) async {
    try {
      // Fetch booking with listing info
      final bookingResponse = await _client
          .from('bookings')
          .select('starts_at, ends_at, listing_title, listings!inner(listing_type, title)')
          .eq('id', bookingId)
          .maybeSingle();

      if (bookingResponse != null) {
        final listingData = bookingResponse['listings'] as Map<String, dynamic>?;
        final listingType = listingData?['listing_type'] as String?;
        final listingTitle = bookingResponse['listing_title'] as String? ??
                            listingData?['title'] as String?;

        final updateData = <String, dynamic>{};
        if (listingType != null) updateData['listing_type'] = listingType;
        if (bookingResponse['starts_at'] != null) updateData['booking_start'] = bookingResponse['starts_at'];
        if (bookingResponse['ends_at'] != null) updateData['booking_end'] = bookingResponse['ends_at'];
        if (listingTitle != null) updateData['listing_title'] = listingTitle;

        if (updateData.isNotEmpty) {
          await _client
              .from('conversations')
              .update(updateData)
              .eq('id', conversationId);
          debugPrint('[SupabaseMessagingService] Populated booking context for conversation $conversationId');
        }
      }
    } catch (e) {
      debugPrint('[SupabaseMessagingService] Error populating booking context: $e');
      // Don't fail the whole operation if this fails
    }
  }

  @override
  Future<MessagingResult<void>> archiveConversation(String conversationId) async {
    return _updateConversationStatus(conversationId, ConversationStatus.archived);
  }

  @override
  Future<MessagingResult<void>> unarchiveConversation(String conversationId) async {
    return _updateConversationStatus(conversationId, ConversationStatus.active);
  }

  @override
  Future<MessagingResult<void>> blockConversation(String conversationId) async {
    return _updateConversationStatus(conversationId, ConversationStatus.blocked);
  }

  @override
  Future<MessagingResult<void>> unblockConversation(String conversationId) async {
    return _updateConversationStatus(conversationId, ConversationStatus.active);
  }

  Future<MessagingResult<void>> _updateConversationStatus(
    String conversationId,
    ConversationStatus status,
  ) async {
    try {
      await _client
          .from('conversations')
          .update({'status': status.name})
          .eq('id', conversationId);

      return const MessagingResult.success(null);
    } catch (e) {
      debugPrint('[SupabaseMessagingService] Error updating conversation: $e');
      return MessagingResult.failure('Failed to update conversation: $e');
    }
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
    try {
      var query = _client
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .isFilter('deleted_at', null);

      // Apply filters
      if (filter?.contentType != null) {
        query = query.eq('content_type', filter!.contentType!.toJsonValue());
      }
      if (filter?.senderId != null) {
        query = query.eq('sender_id', filter!.senderId!);
      }
      if (filter?.beforeId != null) {
        // Get the created_at of the before message for cursor pagination
        final beforeMsg = await _client
            .from('messages')
            .select('created_at')
            .eq('id', filter!.beforeId!)
            .single();
        query = query.lt('created_at', beforeMsg['created_at']);
      }
      if (filter?.afterId != null) {
        final afterMsg = await _client
            .from('messages')
            .select('created_at')
            .eq('id', filter!.afterId!)
            .single();
        query = query.gt('created_at', afterMsg['created_at']);
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(limit);

      final messages = <Message>[];
      for (final row in response as List) {
        final json = row as Map<String, dynamic>;
        var message = Message.fromJson(json);

        // Load sender info
        final sender = await _loadUser(message.senderId);
        message = message.copyWith(sender: sender);

        messages.add(message);
      }

      // Return in chronological order (oldest first)
      return MessagingResult.success(messages.reversed.toList());
    } catch (e) {
      debugPrint('[SupabaseMessagingService] Error getting messages: $e');
      return MessagingResult.failure('Failed to load messages: $e');
    }
  }

  @override
  Future<MessagingResult<Message>> sendMessage(
    SendMessageRequest request,
    String senderId,
  ) async {
    try {
      final now = DateTime.now();

      final messageData = {
        'conversation_id': request.conversationId,
        'sender_id': senderId,
        'content_type': request.contentType.toJsonValue(),
        'content': request.content,
        'metadata': request.metadata?.toJson() ?? {},
        'status': MessageStatus.sent.name,
        'reply_to_id': request.replyToId,
      };

      final response = await _client
          .from('messages')
          .insert(messageData)
          .select()
          .single();

      var message = Message.fromJson(response);

      // Load sender info
      final sender = await _loadUser(senderId);
      message = message.copyWith(sender: sender);

      return MessagingResult.success(message);
    } catch (e) {
      debugPrint('[SupabaseMessagingService] Error sending message: $e');
      return MessagingResult.failure('Failed to send message: $e');
    }
  }

  @override
  Future<MessagingResult<Message>> editMessage(
    String messageId,
    String newContent,
  ) async {
    try {
      final response = await _client
          .from('messages')
          .update({
            'content': newContent,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', messageId)
          .select()
          .single();

      final message = Message.fromJson(response);
      return MessagingResult.success(message);
    } catch (e) {
      debugPrint('[SupabaseMessagingService] Error editing message: $e');
      return MessagingResult.failure('Failed to edit message: $e');
    }
  }

  @override
  Future<MessagingResult<void>> deleteMessage(String messageId) async {
    try {
      // Soft delete
      await _client
          .from('messages')
          .update({'deleted_at': DateTime.now().toIso8601String()})
          .eq('id', messageId);

      return const MessagingResult.success(null);
    } catch (e) {
      debugPrint('[SupabaseMessagingService] Error deleting message: $e');
      return MessagingResult.failure('Failed to delete message: $e');
    }
  }

  @override
  Future<MessagingResult<void>> markAsRead(
    String conversationId,
    String userId,
    String messageId,
  ) async {
    try {
      await _client.from('read_cursors').upsert({
        'conversation_id': conversationId,
        'user_id': userId,
        'last_read_message_id': messageId,
        'last_read_at': DateTime.now().toIso8601String(),
      });

      return const MessagingResult.success(null);
    } catch (e) {
      debugPrint('[SupabaseMessagingService] Error marking as read: $e');
      return MessagingResult.failure('Failed to mark as read: $e');
    }
  }

  @override
  Future<MessagingResult<void>> markAllAsRead(
    String conversationId,
    String userId,
  ) async {
    try {
      // Get the latest message in the conversation
      final latestMessage = await _client
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (latestMessage != null) {
        return markAsRead(
          conversationId,
          userId,
          latestMessage['id'] as String,
        );
      }

      return const MessagingResult.success(null);
    } catch (e) {
      debugPrint('[SupabaseMessagingService] Error marking all as read: $e');
      return MessagingResult.failure('Failed to mark all as read: $e');
    }
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
    try {
      if (isTyping) {
        await _client.from('typing_indicators').upsert({
          'conversation_id': conversationId,
          'user_id': userId,
          'started_at': DateTime.now().toIso8601String(),
        });
      } else {
        await _client
            .from('typing_indicators')
            .delete()
            .eq('conversation_id', conversationId)
            .eq('user_id', userId);
      }

      return const MessagingResult.success(null);
    } catch (e) {
      debugPrint('[SupabaseMessagingService] Error setting typing: $e');
      return MessagingResult.failure('Failed to set typing indicator: $e');
    }
  }

  @override
  Future<MessagingResult<List<TypingIndicator>>> getTypingIndicators(
    String conversationId,
  ) async {
    try {
      // Clean up old indicators first
      final cutoff = DateTime.now().subtract(const Duration(seconds: 10));
      await _client
          .from('typing_indicators')
          .delete()
          .lt('started_at', cutoff.toIso8601String());

      final response = await _client
          .from('typing_indicators')
          .select()
          .eq('conversation_id', conversationId);

      final indicators = (response as List)
          .map((row) => TypingIndicator.fromJson(row as Map<String, dynamic>))
          .where((ti) => ti.isValid)
          .toList();

      return MessagingResult.success(indicators);
    } catch (e) {
      debugPrint('[SupabaseMessagingService] Error getting typing: $e');
      return MessagingResult.failure('Failed to get typing indicators: $e');
    }
  }

  // ============================================
  // Real-time Subscriptions
  // ============================================

  @override
  Stream<Message> subscribeToMessages(String conversationId) {
    final key = 'messages_$conversationId';

    if (!_messageControllers.containsKey(key)) {
      _messageControllers[key] = StreamController<Message>.broadcast();

      // Set up Supabase realtime subscription
      final channel = _client.channel(key);
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'conversation_id',
              value: conversationId,
            ),
            callback: (payload) async {
              final json = payload.newRecord;
              var message = Message.fromJson(json);

              // Load sender info
              final sender = await _loadUser(message.senderId);
              message = message.copyWith(sender: sender);

              _messageControllers[key]?.add(message);
            },
          )
          .subscribe();

      _channels[key] = channel;
    }

    return _messageControllers[key]!.stream;
  }

  @override
  Stream<Conversation> subscribeToConversation(String conversationId) {
    final key = 'conversation_$conversationId';

    if (!_conversationControllers.containsKey(key)) {
      _conversationControllers[key] = StreamController<Conversation>.broadcast();

      final channel = _client.channel(key);
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'conversations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: conversationId,
            ),
            callback: (payload) async {
              final json = payload.newRecord;
              final conversation = Conversation.fromJson(json);
              _conversationControllers[key]?.add(conversation);
            },
          )
          .subscribe();

      _channels[key] = channel;
    }

    return _conversationControllers[key]!.stream;
  }

  @override
  Stream<Conversation> subscribeToConversations(String userId) {
    final key = 'conversations_$userId';

    if (!_conversationControllers.containsKey(key)) {
      _conversationControllers[key] = StreamController<Conversation>.broadcast();

      // Subscribe to conversation updates for this user
      // Note: Supabase realtime doesn't support OR filters directly,
      // so we'll use a workaround with two subscriptions
      final channel = _client.channel(key);
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'conversations',
            callback: (payload) async {
              final json = payload.newRecord;
              if (json.isEmpty) return;

              final participantOne = json['participant_one_id'] as String?;
              final participantTwo = json['participant_two_id'] as String?;

              // Check if user is a participant
              if (participantOne == userId || participantTwo == userId) {
                var conversation = Conversation.fromJson(json);

                // Load other participant
                final otherUserId = conversation.getOtherParticipantId(userId);
                final otherUser = await _loadUser(otherUserId);

                // Get unread count
                final unreadCount = await _getUnreadCountInternal(
                  conversation.id,
                  userId,
                );

                conversation = conversation.copyWith(
                  otherParticipant: otherUser,
                  unreadCount: unreadCount,
                );

                _conversationControllers[key]?.add(conversation);
              }
            },
          )
          .subscribe();

      _channels[key] = channel;
    }

    return _conversationControllers[key]!.stream;
  }

  @override
  Stream<List<TypingIndicator>> subscribeToTypingIndicators(
    String conversationId,
  ) {
    final key = 'typing_$conversationId';

    if (!_typingControllers.containsKey(key)) {
      _typingControllers[key] = StreamController<List<TypingIndicator>>.broadcast();

      final channel = _client.channel(key);
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'typing_indicators',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'conversation_id',
              value: conversationId,
            ),
            callback: (payload) async {
              // Fetch current typing indicators
              final result = await getTypingIndicators(conversationId);
              if (result.isSuccess) {
                _typingControllers[key]?.add(result.data!);
              }
            },
          )
          .subscribe();

      _channels[key] = channel;
    }

    return _typingControllers[key]!.stream;
  }

  @override
  Stream<int> subscribeToTotalUnreadCount(String userId) {
    _unreadCountController ??= StreamController<int>.broadcast();

    final key = 'unread_$userId';
    if (!_channels.containsKey(key)) {
      // Subscribe to message inserts to update unread count
      final channel = _client.channel(key);
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            callback: (payload) async {
              // When a new message arrives, recalculate total unread
              final result = await getTotalUnreadCount(userId);
              if (result.isSuccess) {
                _unreadCountController?.add(result.data!);
              }
            },
          )
          .subscribe();

      _channels[key] = channel;
    }

    return _unreadCountController!.stream;
  }

  // ============================================
  // Counts
  // ============================================

  @override
  Future<MessagingResult<int>> getUnreadCount(
    String conversationId,
    String userId,
  ) async {
    try {
      final count = await _getUnreadCountInternal(conversationId, userId);
      return MessagingResult.success(count);
    } catch (e) {
      debugPrint('[SupabaseMessagingService] Error getting unread count: $e');
      return MessagingResult.failure('Failed to get unread count: $e');
    }
  }

  @override
  Future<MessagingResult<int>> getTotalUnreadCount(String userId) async {
    try {
      // Get all conversations for user
      final convResult = await getConversations(userId);
      if (!convResult.isSuccess) {
        return MessagingResult.failure(convResult.error!);
      }

      int total = 0;
      for (final conv in convResult.data!) {
        total += conv.unreadCount;
      }

      return MessagingResult.success(total);
    } catch (e) {
      debugPrint('[SupabaseMessagingService] Error getting total unread: $e');
      return MessagingResult.failure('Failed to get total unread count: $e');
    }
  }

  // ============================================
  // Helpers
  // ============================================

  Future<int> _getUnreadCountInternal(
    String conversationId,
    String userId,
  ) async {
    try {
      final response = await _client.rpc(
        'get_unread_count',
        params: {
          'p_conversation_id': conversationId,
          'p_user_id': userId,
        },
      );

      return response as int? ?? 0;
    } catch (e) {
      debugPrint('[SupabaseMessagingService] Error in _getUnreadCountInternal: $e');
      return 0;
    }
  }

  Future<app.User?> _loadUser(String userId) async {
    if (userId == 'system') return null;

    // Check cache first
    if (_userCache.containsKey(userId)) {
      return _userCache[userId];
    }

    try {
      final response = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response != null) {
        final roleStr = response['role'] as String?;
        final role = roleStr != null
            ? UserRole.values.firstWhere(
                (r) => r.name == roleStr,
                orElse: () => UserRole.tenant,
              )
            : UserRole.tenant;

        final user = app.User(
          id: response['id'] as String,
          name: response['full_name'] as String? ?? 'User',
          email: response['email'] as String?,
          phone: response['mobile'] as String?,
          avatarUrl: response['avatar_url'] as String?,
          role: role,
          isHost: response['is_host'] as bool? ?? false,
        );
        _userCache[userId] = user;
        return user;
      }
    } catch (e) {
      debugPrint('[SupabaseMessagingService] Error loading user $userId: $e');
    }

    return null;
  }
}
