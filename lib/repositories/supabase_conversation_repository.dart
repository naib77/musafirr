import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../models/conversation.dart';
import '../models/user.dart' as app;
import '../models/user_role.dart';
import 'conversation_repository.dart';

/// Supabase implementation of [ConversationRepository].
///
/// Uses Supabase PostgreSQL for storage with Row Level Security
/// for access control.
class SupabaseConversationRepository implements ConversationRepository {
  SupabaseConversationRepository._();

  static SupabaseConversationRepository? _instance;
  static SupabaseConversationRepository get instance {
    _instance ??= SupabaseConversationRepository._();
    return _instance!;
  }

  SupabaseClient get _client => Supabase.instance.client;

  // User cache to reduce database lookups
  final Map<String, app.User> _userCache = {};

  @override
  Future<ConversationResult<ConversationPage>> getAll({
    required String userId,
    int limit = 20,
    String? cursor,
  }) async {
    return _queryConversations(
      userId: userId,
      limit: limit,
      cursor: cursor,
    );
  }

  @override
  Future<ConversationResult<ConversationPage>> getActive({
    required String userId,
    int limit = 20,
    String? cursor,
  }) async {
    return _queryConversations(
      userId: userId,
      status: ConversationStatus.active,
      limit: limit,
      cursor: cursor,
    );
  }

  @override
  Future<ConversationResult<ConversationPage>> getArchived({
    required String userId,
    int limit = 20,
    String? cursor,
  }) async {
    return _queryConversations(
      userId: userId,
      status: ConversationStatus.archived,
      limit: limit,
      cursor: cursor,
    );
  }

  @override
  Future<ConversationResult<ConversationPage>> getUnread({
    required String userId,
    int limit = 20,
    String? cursor,
  }) async {
    return _queryConversations(
      userId: userId,
      hasUnread: true,
      limit: limit,
      cursor: cursor,
    );
  }

  @override
  Future<ConversationResult<Conversation>> findById({
    required String conversationId,
    required String userId,
  }) async {
    try {
      final response = await _client
          .from('conversations')
          .select()
          .eq('id', conversationId)
          .single();

      var conversation = Conversation.fromJson(response);

      // Verify user is a participant
      if (conversation.participantOneId != userId &&
          conversation.participantTwoId != userId) {
        return const ConversationResult.failure(ConversationUnauthorized());
      }

      // Load other participant
      conversation = await _enrichConversation(conversation, userId);

      return ConversationResult.success(conversation);
    } on PostgrestException catch (e) {
      debugPrint('[SupabaseConversationRepository] findById error: $e');
      if (e.code == 'PGRST116') {
        return ConversationResult.failure(ConversationNotFound(conversationId));
      }
      return ConversationResult.failure(ConversationNetworkError(e.message));
    } catch (e) {
      debugPrint('[SupabaseConversationRepository] findById error: $e');
      return ConversationResult.failure(ConversationNetworkError(e.toString()));
    }
  }

  @override
  Future<ConversationResult<Conversation?>> findByParticipants({
    required String userOneId,
    required String userTwoId,
  }) async {
    try {
      final response = await _client
          .from('conversations')
          .select()
          .or('and(participant_one_id.eq.$userOneId,participant_two_id.eq.$userTwoId),'
              'and(participant_one_id.eq.$userTwoId,participant_two_id.eq.$userOneId)')
          .maybeSingle();

      if (response == null) {
        return const ConversationResult.success(null);
      }

      var conversation = Conversation.fromJson(response);
      conversation = await _enrichConversation(conversation, userOneId);

      return ConversationResult.success(conversation);
    } catch (e) {
      debugPrint('[SupabaseConversationRepository] findByParticipants error: $e');
      return ConversationResult.failure(ConversationNetworkError(e.toString()));
    }
  }

  @override
  Future<ConversationResult<Conversation?>> findForBooking({
    required String bookingId,
    required String userId,
  }) async {
    try {
      final response = await _client
          .from('conversations')
          .select()
          .eq('booking_id', bookingId)
          .or('participant_one_id.eq.$userId,participant_two_id.eq.$userId')
          .maybeSingle();

      if (response == null) {
        return const ConversationResult.success(null);
      }

      var conversation = Conversation.fromJson(response);
      conversation = await _enrichConversation(conversation, userId);

      return ConversationResult.success(conversation);
    } catch (e) {
      debugPrint('[SupabaseConversationRepository] findForBooking error: $e');
      return ConversationResult.failure(ConversationNetworkError(e.toString()));
    }
  }

  @override
  Future<ConversationResult<ConversationPage>> findForListing({
    required String listingId,
    required String userId,
    int limit = 20,
    String? cursor,
  }) async {
    return _queryConversations(
      userId: userId,
      listingId: listingId,
      limit: limit,
      cursor: cursor,
    );
  }

  @override
  Future<ConversationResult<Conversation>> create({
    required String participantOneId,
    required String participantTwoId,
    String? bookingId,
    String? listingId,
  }) async {
    try {
      // Use database function for thread-safe upsert
      final response = await _client.rpc(
        'get_or_create_conversation',
        params: {
          'user_one': participantOneId,
          'user_two': participantTwoId,
          'p_booking_id': bookingId,
          'p_listing_id': listingId,
        },
      );

      final conversationId = response as String;

      // Fetch the full conversation
      return findById(
        conversationId: conversationId,
        userId: participantOneId,
      );
    } catch (e) {
      debugPrint('[SupabaseConversationRepository] create error: $e');
      return ConversationResult.failure(
        ConversationCreationFailed(e.toString()),
      );
    }
  }

  @override
  Future<ConversationResult<void>> archive(String conversationId) async {
    return _updateStatus(conversationId, ConversationStatus.archived);
  }

  @override
  Future<ConversationResult<void>> unarchive(String conversationId) async {
    return _updateStatus(conversationId, ConversationStatus.active);
  }

  @override
  Future<ConversationResult<void>> block(String conversationId) async {
    return _updateStatus(conversationId, ConversationStatus.blocked);
  }

  @override
  Future<ConversationResult<void>> unblock(String conversationId) async {
    return _updateStatus(conversationId, ConversationStatus.active);
  }

  @override
  Future<ConversationResult<int>> getTotalUnreadCount(String userId) async {
    try {
      // Get all conversations for user
      final response = await _client
          .from('conversations')
          .select('id')
          .or('participant_one_id.eq.$userId,participant_two_id.eq.$userId')
          .eq('status', 'active');

      int total = 0;
      for (final row in response as List) {
        final conversationId = row['id'] as String;
        final count = await _getUnreadCount(conversationId, userId);
        total += count;
      }

      return ConversationResult.success(total);
    } catch (e) {
      debugPrint('[SupabaseConversationRepository] getTotalUnreadCount error: $e');
      return ConversationResult.failure(ConversationNetworkError(e.toString()));
    }
  }

  @override
  Future<ConversationResult<app.User>> loadOtherParticipant({
    required Conversation conversation,
    required String currentUserId,
  }) async {
    final otherUserId = conversation.getOtherParticipantId(currentUserId);
    final user = await _loadUser(otherUserId);

    if (user != null) {
      return ConversationResult.success(user);
    }

    return ConversationResult.failure(
      ConversationNotFound('User not found: $otherUserId'),
    );
  }

  // ============================================
  // Private Helpers
  // ============================================

  Future<ConversationResult<ConversationPage>> _queryConversations({
    required String userId,
    ConversationStatus? status,
    bool? hasUnread,
    String? listingId,
    int limit = 20,
    String? cursor,
  }) async {
    try {
      var query = _client
          .from('conversations')
          .select()
          .or('participant_one_id.eq.$userId,participant_two_id.eq.$userId');

      if (status != null) {
        query = query.eq('status', status.name);
      }

      if (listingId != null) {
        query = query.eq('listing_id', listingId);
      }

      // Cursor-based pagination
      if (cursor != null) {
        query = query.lt('last_message_at', cursor);
      }

      final response = await query
          .order('last_message_at', ascending: false, nullsFirst: false)
          .limit(limit + 1); // Fetch one extra to check if there's more

      final rows = response as List;
      final hasMore = rows.length > limit;
      final items = hasMore ? rows.take(limit).toList() : rows;

      final conversations = <Conversation>[];
      for (final row in items) {
        final json = row as Map<String, dynamic>;
        var conversation = Conversation.fromJson(json);
        conversation = await _enrichConversation(conversation, userId);

        // Filter by unread if requested
        if (hasUnread == true && conversation.unreadCount == 0) continue;
        if (hasUnread == false && conversation.unreadCount > 0) continue;

        conversations.add(conversation);
      }

      String? nextCursor;
      if (hasMore && conversations.isNotEmpty) {
        nextCursor = conversations.last.lastMessageAt?.toIso8601String();
      }

      return ConversationResult.success(ConversationPage(
        conversations: conversations,
        hasMore: hasMore,
        nextCursor: nextCursor,
      ));
    } catch (e) {
      debugPrint('[SupabaseConversationRepository] _queryConversations error: $e');
      return ConversationResult.failure(ConversationNetworkError(e.toString()));
    }
  }

  Future<ConversationResult<void>> _updateStatus(
    String conversationId,
    ConversationStatus status,
  ) async {
    try {
      await _client
          .from('conversations')
          .update({'status': status.name})
          .eq('id', conversationId);

      return const ConversationResult.success(null);
    } catch (e) {
      debugPrint('[SupabaseConversationRepository] _updateStatus error: $e');
      return ConversationResult.failure(ConversationNetworkError(e.toString()));
    }
  }

  Future<Conversation> _enrichConversation(
    Conversation conversation,
    String currentUserId,
  ) async {
    // Load other participant
    final otherUserId = conversation.getOtherParticipantId(currentUserId);
    final otherUser = await _loadUser(otherUserId);

    // Get unread count
    final unreadCount = await _getUnreadCount(conversation.id, currentUserId);

    return conversation.copyWith(
      otherParticipant: otherUser,
      unreadCount: unreadCount,
    );
  }

  Future<int> _getUnreadCount(String conversationId, String userId) async {
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
      debugPrint('[SupabaseConversationRepository] _getUnreadCount error: $e');
      return 0;
    }
  }

  Future<app.User?> _loadUser(String userId) async {
    if (userId == 'system') return null;

    // Check cache
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
      debugPrint('[SupabaseConversationRepository] _loadUser error: $e');
    }

    return null;
  }

  /// Clear the user cache. Call when users might have updated their profiles.
  void clearUserCache() {
    _userCache.clear();
  }
}
