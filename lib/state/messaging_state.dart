import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../services/messaging/messaging_service.dart';

/// State management for messaging functionality
class MessagingStateNotifier extends ChangeNotifier {
  MessagingStateNotifier({
    required MessagingService messagingService,
  }) : _messagingService = messagingService;

  final MessagingService _messagingService;

  // Current user
  String? _currentUserId;
  String? get currentUserId => _currentUserId;

  // Conversations
  List<Conversation> _conversations = [];
  List<Conversation> get conversations => List.unmodifiable(_conversations);

  // Active conversation (when in chat view)
  Conversation? _activeConversation;
  Conversation? get activeConversation => _activeConversation;

  // Messages for active conversation
  List<Message> _messages = [];
  List<Message> get messages => List.unmodifiable(_messages);

  // Typing indicators
  List<TypingIndicator> _typingIndicators = [];
  List<TypingIndicator> get typingIndicators => List.unmodifiable(_typingIndicators);

  // Total unread count
  int _totalUnreadCount = 0;
  int get totalUnreadCount => _totalUnreadCount;

  // Loading states
  bool _isLoadingConversations = false;
  bool get isLoadingConversations => _isLoadingConversations;

  bool _isLoadingMessages = false;
  bool get isLoadingMessages => _isLoadingMessages;

  bool _isSendingMessage = false;
  bool get isSendingMessage => _isSendingMessage;

  // Error handling
  String? _error;
  String? get error => _error;

  // Subscriptions
  StreamSubscription<Conversation>? _conversationsSubscription;
  StreamSubscription<Message>? _messagesSubscription;
  StreamSubscription<List<TypingIndicator>>? _typingSubscription;
  StreamSubscription<int>? _unreadCountSubscription;

  // Typing debounce
  Timer? _typingTimer;
  bool _isTyping = false;

  /// Initialize the messaging state for a user
  Future<void> initialize(String userId) async {
    if (_currentUserId == userId) return;

    _currentUserId = userId;
    await _messagingService.initialize();

    // Load conversations
    await loadConversations();

    // Subscribe to real-time updates
    _subscribeToConversations();
    _subscribeToUnreadCount();
  }

  /// Load conversations for the current user
  Future<void> loadConversations({ConversationFilter? filter}) async {
    if (_currentUserId == null) return;

    _isLoadingConversations = true;
    _error = null;
    notifyListeners();

    final result = await _messagingService.getConversations(
      _currentUserId!,
      filter: filter,
    );

    if (result.isSuccess) {
      _conversations = result.data ?? [];
    } else {
      _error = result.error;
    }

    _isLoadingConversations = false;
    notifyListeners();
  }

  /// Refresh conversations
  Future<void> refreshConversations() async {
    await loadConversations();
  }

  /// Open a conversation and load its messages
  Future<void> openConversation(String conversationId) async {
    if (_currentUserId == null) return;

    // Cancel existing subscriptions
    await _messagesSubscription?.cancel();
    await _typingSubscription?.cancel();

    _isLoadingMessages = true;
    _messages = [];
    _typingIndicators = [];
    notifyListeners();

    // Get conversation details
    final convResult = await _messagingService.getConversation(
      conversationId,
      _currentUserId!,
    );

    if (convResult.isSuccess) {
      _activeConversation = convResult.data;
    }

    // Load messages
    final msgResult = await _messagingService.getMessages(conversationId);

    if (msgResult.isSuccess) {
      _messages = msgResult.data ?? [];
    } else {
      _error = msgResult.error;
    }

    _isLoadingMessages = false;
    notifyListeners();

    // Subscribe to new messages
    _subscribeToMessages(conversationId);
    _subscribeToTypingIndicators(conversationId);

    // Mark as read
    if (_messages.isNotEmpty) {
      await markAllAsRead();
    }
  }

  /// Close the active conversation
  void closeConversation() {
    _messagesSubscription?.cancel();
    _typingSubscription?.cancel();
    _typingTimer?.cancel();

    _activeConversation = null;
    _messages = [];
    _typingIndicators = [];
    _isTyping = false;

    notifyListeners();
  }

  /// Get or create a conversation with another user
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
      // Add to conversations if not already present
      final existingIndex = _conversations.indexWhere((c) => c.id == result.data!.id);
      if (existingIndex < 0) {
        _conversations.insert(0, result.data!);
        notifyListeners();
      }
      return result.data;
    }

    _error = result.error;
    notifyListeners();
    return null;
  }

  /// Send a text message
  Future<bool> sendTextMessage(String text) async {
    if (_currentUserId == null || _activeConversation == null) return false;
    if (text.trim().isEmpty) return false;

    _isSendingMessage = true;
    notifyListeners();

    final request = SendMessageRequest.text(
      conversationId: _activeConversation!.id,
      text: text.trim(),
    );

    final result = await _messagingService.sendMessage(request, _currentUserId!);

    _isSendingMessage = false;

    if (result.isSuccess && result.data != null) {
      // Add message to list (will also come via stream, but add immediately for responsiveness)
      _messages.add(result.data!);
      notifyListeners();

      // Stop typing indicator
      await setTyping(false);
      return true;
    }

    _error = result.error;
    notifyListeners();
    return false;
  }

  /// Send an image message
  Future<bool> sendImageMessage({
    required String imageUrl,
    String caption = '',
    int? width,
    int? height,
  }) async {
    if (_currentUserId == null || _activeConversation == null) return false;

    _isSendingMessage = true;
    notifyListeners();

    final request = SendMessageRequest.image(
      conversationId: _activeConversation!.id,
      caption: caption,
      metadata: ImageMetadata(
        url: imageUrl,
        width: width,
        height: height,
      ),
    );

    final result = await _messagingService.sendMessage(request, _currentUserId!);

    _isSendingMessage = false;

    if (result.isSuccess && result.data != null) {
      _messages.add(result.data!);
      notifyListeners();
      return true;
    }

    _error = result.error;
    notifyListeners();
    return false;
  }

  /// Send a location message
  Future<bool> sendLocationMessage({
    required double latitude,
    required double longitude,
    String? address,
    String? placeName,
  }) async {
    if (_currentUserId == null || _activeConversation == null) return false;

    _isSendingMessage = true;
    notifyListeners();

    final request = SendMessageRequest.location(
      conversationId: _activeConversation!.id,
      metadata: LocationMetadata(
        latitude: latitude,
        longitude: longitude,
        address: address,
        placeName: placeName,
      ),
    );

    final result = await _messagingService.sendMessage(request, _currentUserId!);

    _isSendingMessage = false;

    if (result.isSuccess && result.data != null) {
      _messages.add(result.data!);
      notifyListeners();
      return true;
    }

    _error = result.error;
    notifyListeners();
    return false;
  }

  /// Delete a message
  Future<bool> deleteMessage(String messageId) async {
    final result = await _messagingService.deleteMessage(messageId);

    if (result.isSuccess) {
      // Update local message
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index >= 0) {
        _messages[index] = _messages[index].copyWith(deletedAt: DateTime.now());
        notifyListeners();
      }
      return true;
    }

    _error = result.error;
    notifyListeners();
    return false;
  }

  /// Mark all messages in the active conversation as read
  Future<void> markAllAsRead() async {
    if (_currentUserId == null || _activeConversation == null) return;

    await _messagingService.markAllAsRead(
      _activeConversation!.id,
      _currentUserId!,
    );

    // Update local conversation
    final index = _conversations.indexWhere((c) => c.id == _activeConversation!.id);
    if (index >= 0) {
      _conversations[index] = _conversations[index].copyWith(unreadCount: 0);
      notifyListeners();
    }
  }

  /// Set typing indicator
  Future<void> setTyping(bool isTyping) async {
    if (_currentUserId == null || _activeConversation == null) return;
    if (_isTyping == isTyping) return;

    _isTyping = isTyping;

    await _messagingService.setTyping(
      _activeConversation!.id,
      _currentUserId!,
      isTyping,
    );

    // Auto-stop typing after 5 seconds
    _typingTimer?.cancel();
    if (isTyping) {
      _typingTimer = Timer(const Duration(seconds: 5), () {
        setTyping(false);
      });
    }
  }

  /// Handle text input changes (for typing indicator)
  void onTextChanged(String text) {
    if (text.isNotEmpty && !_isTyping) {
      setTyping(true);
    }

    // Reset typing timer
    _typingTimer?.cancel();
    if (text.isNotEmpty) {
      _typingTimer = Timer(const Duration(seconds: 3), () {
        setTyping(false);
      });
    } else {
      setTyping(false);
    }
  }

  /// Archive a conversation
  Future<bool> archiveConversation(String conversationId) async {
    final result = await _messagingService.archiveConversation(conversationId);

    if (result.isSuccess) {
      // Update local conversation
      final index = _conversations.indexWhere((c) => c.id == conversationId);
      if (index >= 0) {
        _conversations[index] = _conversations[index].copyWith(
          status: ConversationStatus.archived,
        );
        notifyListeners();
      }
      return true;
    }

    _error = result.error;
    notifyListeners();
    return false;
  }

  /// Get conversations filtered by status
  List<Conversation> getConversationsByStatus(ConversationStatus status) {
    return _conversations.where((c) => c.status == status).toList();
  }

  /// Get active (non-archived) conversations
  List<Conversation> get activeConversations {
    return _conversations.where((c) => c.status == ConversationStatus.active).toList();
  }

  /// Get archived conversations
  List<Conversation> get archivedConversations {
    return _conversations.where((c) => c.status == ConversationStatus.archived).toList();
  }

  /// Clear any errors
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ============================================
  // Private Subscription Methods
  // ============================================

  void _subscribeToConversations() {
    if (_currentUserId == null) return;

    _conversationsSubscription?.cancel();
    _conversationsSubscription = _messagingService
        .subscribeToConversations(_currentUserId!)
        .listen((conversation) {
      // Update or add conversation
      final index = _conversations.indexWhere((c) => c.id == conversation.id);
      if (index >= 0) {
        _conversations[index] = conversation;
      } else {
        _conversations.insert(0, conversation);
      }

      // Re-sort by last message time
      _conversations.sort((a, b) {
        final aTime = a.lastMessageAt ?? a.createdAt;
        final bTime = b.lastMessageAt ?? b.createdAt;
        return bTime.compareTo(aTime);
      });

      notifyListeners();
    });
  }

  void _subscribeToMessages(String conversationId) {
    _messagesSubscription?.cancel();
    _messagesSubscription = _messagingService
        .subscribeToMessages(conversationId)
        .listen((message) {
      // Check if message already exists (might have been added optimistically)
      final exists = _messages.any((m) => m.id == message.id);
      if (!exists) {
        _messages.add(message);
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        notifyListeners();

        // Mark as read if this is from someone else
        if (_currentUserId != null && message.senderId != _currentUserId) {
          markAllAsRead();
        }
      }
    });
  }

  void _subscribeToTypingIndicators(String conversationId) {
    _typingSubscription?.cancel();
    _typingSubscription = _messagingService
        .subscribeToTypingIndicators(conversationId)
        .listen((indicators) {
      // Filter out our own typing indicator
      _typingIndicators = indicators
          .where((t) => t.userId != _currentUserId && t.isValid)
          .toList();
      notifyListeners();
    });
  }

  void _subscribeToUnreadCount() {
    if (_currentUserId == null) return;

    _unreadCountSubscription?.cancel();
    _unreadCountSubscription = _messagingService
        .subscribeToTotalUnreadCount(_currentUserId!)
        .listen((count) {
      _totalUnreadCount = count;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _conversationsSubscription?.cancel();
    _messagesSubscription?.cancel();
    _typingSubscription?.cancel();
    _unreadCountSubscription?.cancel();
    _typingTimer?.cancel();
    super.dispose();
  }
}
