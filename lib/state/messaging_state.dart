import 'dart:async';

import 'package:flutter/foundation.dart';
import '../core/state/safe_notifier.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../repositories/conversation_repository.dart';
import '../services/messaging/messaging_service.dart';
import 'active_chat_state.dart';
import 'conversation_list_state.dart';

/// Facade for messaging state management.
///
/// This class coordinates [ConversationListState] and [ActiveChatState],
/// providing a unified interface for UI components.
///
/// ## Architecture
///
/// The messaging state is split into focused modules:
/// - [ConversationListState]: Owns the conversation list, filtering, pagination
/// - [ActiveChatState]: Owns the current conversation's messages, typing, sending
///
/// This facade:
/// - Initializes both modules together
/// - Forwards calls to the appropriate module
/// - Notifies listeners when either module changes
///
/// ## Usage
///
/// ```dart
/// final state = MessagingStateNotifier(
///   conversationRepository: repository,
///   messagingService: service,
/// );
///
/// await state.initialize(userId);
///
/// // List operations
/// final conversations = state.activeConversations;
///
/// // Chat operations
/// await state.openConversation(conversationId);
/// await state.sendTextMessage('Hello!');
/// state.closeConversation();
/// ```
class MessagingStateNotifier extends ChangeNotifier with SafeNotifier {
  MessagingStateNotifier({
    required ConversationRepository conversationRepository,
    required MessagingService messagingService,
  })  : _conversationList = ConversationListState(
          repository: conversationRepository,
        ),
        _activeChat = ActiveChatState(
          messagingService: messagingService,
        ),
        _messagingService = messagingService {
    // Forward notifications from child states
    _conversationList.addListener(_onChildChanged);
    _activeChat.addListener(_onChildChanged);
  }

  final ConversationListState _conversationList;
  final ActiveChatState _activeChat;
  final MessagingService _messagingService;

  String? _currentUserId;

  // Real-time subscriptions
  StreamSubscription<Conversation>? _conversationsSubscription;
  StreamSubscription<int>? _unreadCountSubscription;

  // ============================================
  // Initialization
  // ============================================

  /// Initialize messaging for a user.
  Future<void> initialize(String userId) async {
    if (_currentUserId == userId) return;

    _currentUserId = userId;
    await _messagingService.initialize();

    // Initialize child states
    await _conversationList.initialize(userId);

    // Subscribe to real-time updates
    _subscribeToConversations();
    _subscribeToUnreadCount();
  }

  /// Clear all state (e.g., on logout).
  void clear() {
    _conversationsSubscription?.cancel();
    _unreadCountSubscription?.cancel();
    _conversationList.clear();
    _activeChat.closeConversation();
    _currentUserId = null;
  }

  // ============================================
  // Conversation List (delegated)
  // ============================================

  /// Current user ID.
  String? get currentUserId => _currentUserId;

  /// All conversations.
  List<Conversation> get conversations => _conversationList.conversations;

  /// Active conversations (non-archived).
  List<Conversation> get activeConversations =>
      _conversationList.activeConversations;

  /// Archived conversations.
  List<Conversation> get archivedConversations =>
      _conversationList.archivedConversations;

  /// Conversations with unread messages.
  List<Conversation> get unreadConversations =>
      _conversationList.unreadConversations;

  /// Whether conversations are loading.
  bool get isLoadingConversations => _conversationList.isLoading;

  /// Total unread message count.
  int get totalUnreadCount => _conversationList.totalUnreadCount;

  /// Load conversations.
  Future<void> loadConversations({ConversationFilter? filter}) async {
    await _conversationList.loadConversations();
  }

  /// Refresh conversations.
  Future<void> refreshConversations() async {
    await _conversationList.refresh();
  }

  /// Get conversations by status.
  List<Conversation> getConversationsByStatus(ConversationStatus status) {
    return conversations.where((c) => c.status == status).toList();
  }

  /// Archive a conversation.
  Future<bool> archiveConversation(String conversationId) {
    return _conversationList.archiveConversation(conversationId);
  }

  /// Start a new conversation.
  Future<Conversation?> startConversation({
    required String otherUserId,
    String? bookingId,
    String? listingId,
  }) async {
    if (_currentUserId == null) return null;

    final result = await _messagingService.getOrCreateConversation(
      currentUserId: _currentUserId!,
      otherUserId: otherUserId,
      bookingId: bookingId,
      listingId: listingId,
    );

    if (result.isSuccess && result.data != null) {
      _conversationList.addConversation(result.data!);
      return result.data;
    }

    return null;
  }

  // ============================================
  // Active Chat (delegated)
  // ============================================

  /// The active conversation.
  Conversation? get activeConversation => _activeChat.conversation;

  /// Messages in the active conversation.
  List<Message> get messages => _activeChat.messages;

  /// Typing indicators in the active conversation.
  List<TypingIndicator> get typingIndicators => _activeChat.typingIndicators;

  /// Whether messages are loading.
  bool get isLoadingMessages => _activeChat.isLoadingMessages;

  /// Whether a message is being sent.
  bool get isSendingMessage => _activeChat.isSendingMessage;

  /// Open a conversation.
  Future<void> openConversation(String conversationId) async {
    if (_currentUserId == null) return;
    await _activeChat.openConversation(conversationId, _currentUserId!);
    // The active chat advanced the server-side read cursor while opening;
    // mirror that locally or the Messages badge stays lit until a realtime
    // echo (or a sent message) happens to refresh the list.
    _conversationList.markAsRead(conversationId);
  }

  /// Close the active conversation.
  void closeConversation() {
    _activeChat.closeConversation();
  }

  /// Send a text message.
  Future<bool> sendTextMessage(String text) async {
    final success = await _activeChat.sendTextMessage(text);
    if (success && _activeChat.conversation != null) {
      // Update the conversation in the list with new last message
      final updatedConv = _activeChat.conversation!.copyWith(
        lastMessageText: text,
        lastMessageAt: DateTime.now(),
        lastMessageSenderId: _currentUserId,
        // The active chat still holds the pre-open unread count; the user is
        // reading this thread right now, so it must be zero — otherwise the
        // list's delta math re-lights the Messages badge for a read thread.
        unreadCount: 0,
      );
      _conversationList.updateConversation(updatedConv);
    }
    return success;
  }

  /// Send an image message.
  Future<bool> sendImageMessage({
    required String imageUrl,
    String caption = '',
    int? width,
    int? height,
  }) {
    return _activeChat.sendImageMessage(
      imageUrl: imageUrl,
      caption: caption,
      width: width,
      height: height,
    );
  }

  /// Send a file (document) message.
  Future<bool> sendFileMessage({
    required String url,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
  }) {
    return _activeChat.sendFileMessage(
      url: url,
      fileName: fileName,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
    );
  }

  /// Send a location message.
  Future<bool> sendLocationMessage({
    required double latitude,
    required double longitude,
    String? address,
    String? placeName,
  }) {
    return _activeChat.sendLocationMessage(
      latitude: latitude,
      longitude: longitude,
      address: address,
      placeName: placeName,
    );
  }

  /// Delete a message.
  Future<bool> deleteMessage(String messageId) {
    return _activeChat.deleteMessage(messageId);
  }

  /// Mark all messages in the active conversation as read.
  Future<void> markAllAsRead() async {
    await _activeChat.markAllAsRead();
    if (_activeChat.conversation != null) {
      _conversationList.markAsRead(_activeChat.conversation!.id);
    }
  }

  /// Set typing indicator.
  Future<void> setTyping(bool isTyping) {
    return _activeChat.setTyping(isTyping);
  }

  /// Handle text input changes.
  void onTextChanged(String text) {
    _activeChat.onTextChanged(text);
  }

  // ============================================
  // Error Handling
  // ============================================

  /// Current error (from either child state).
  String? get error => _conversationList.error ?? _activeChat.error;

  /// Clear any errors.
  void clearError() {
    _conversationList.clearError();
    _activeChat.clearError();
  }

  // ============================================
  // Private Methods
  // ============================================

  void _onChildChanged() {
    notifyListeners();
  }

  void _subscribeToConversations() {
    if (_currentUserId == null) return;

    _conversationsSubscription?.cancel();
    _conversationsSubscription = _messagingService
        .subscribeToConversations(_currentUserId!)
        .listen((conversation) {
      _conversationList.updateConversation(conversation);
    });
  }

  void _subscribeToUnreadCount() {
    if (_currentUserId == null) return;

    _unreadCountSubscription?.cancel();
    _unreadCountSubscription = _messagingService
        .subscribeToTotalUnreadCount(_currentUserId!)
        .listen((count) {
      // The list state tracks its own count, but we can use this
      // to trigger a refresh if counts diverge
      if (count != _conversationList.totalUnreadCount) {
        _conversationList.refresh();
      }
    });
  }

  @override
  void dispose() {
    _conversationsSubscription?.cancel();
    _unreadCountSubscription?.cancel();
    _conversationList.removeListener(_onChildChanged);
    _activeChat.removeListener(_onChildChanged);
    _conversationList.dispose();
    _activeChat.dispose();
    super.dispose();
  }
}
