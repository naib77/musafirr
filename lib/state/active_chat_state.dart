import 'dart:async';

import 'package:flutter/foundation.dart';
import '../core/state/safe_notifier.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../services/messaging/messaging_service.dart';

/// State management for the active chat conversation.
///
/// This module owns:
/// - Current conversation details
/// - Message list for the active conversation
/// - Sending messages
/// - Typing indicators
/// - Read receipts
///
/// ## Usage
///
/// ```dart
/// final state = ActiveChatState(messagingService: service);
///
/// // Open a conversation
/// await state.openConversation(conversationId, userId);
///
/// // Send a message
/// await state.sendTextMessage('Hello!');
///
/// // Close when done
/// state.closeConversation();
/// ```
class ActiveChatState extends ChangeNotifier with SafeNotifier {
  ActiveChatState({
    required MessagingService messagingService,
  }) : _messagingService = messagingService;

  final MessagingService _messagingService;

  String? _currentUserId;
  String? get currentUserId => _currentUserId;

  Conversation? _conversation;
  Conversation? get conversation => _conversation;

  List<Message> _messages = [];
  List<Message> get messages => List.unmodifiable(_messages);

  List<TypingIndicator> _typingIndicators = [];
  List<TypingIndicator> get typingIndicators =>
      List.unmodifiable(_typingIndicators);

  bool _isLoadingMessages = false;
  bool get isLoadingMessages => _isLoadingMessages;

  bool _isSendingMessage = false;
  bool get isSendingMessage => _isSendingMessage;

  String? _error;
  String? get error => _error;

  // Subscriptions
  StreamSubscription<Message>? _messagesSubscription;
  StreamSubscription<List<TypingIndicator>>? _typingSubscription;

  // Typing state
  Timer? _typingTimer;
  bool _isTyping = false;

  /// Whether a conversation is currently open.
  bool get isOpen => _conversation != null;

  /// Open a conversation and load its messages.
  Future<void> openConversation(
    String conversationId,
    String currentUserId,
  ) async {
    // Close any existing conversation
    if (_conversation != null) {
      closeConversation();
    }

    _currentUserId = currentUserId;
    _isLoadingMessages = true;
    _messages = [];
    _typingIndicators = [];
    notifyListeners();

    // Get conversation details
    final convResult = await _messagingService.getConversation(
      conversationId,
      currentUserId,
    );

    if (convResult.isSuccess && convResult.data != null) {
      _conversation = convResult.data;
    }

    // Load messages
    final msgResult = await _messagingService.getMessages(conversationId);

    if (msgResult.isSuccess && msgResult.data != null) {
      _messages = msgResult.data!;
    } else {
      _error = msgResult.error;
    }

    _isLoadingMessages = false;
    notifyListeners();

    // Subscribe to real-time updates
    _subscribeToMessages(conversationId);
    _subscribeToTypingIndicators(conversationId);

    // Mark as read
    if (_messages.isNotEmpty) {
      await markAllAsRead();
    }
  }

  /// Close the active conversation.
  void closeConversation() {
    _messagesSubscription?.cancel();
    _messagesSubscription = null;
    _typingSubscription?.cancel();
    _typingSubscription = null;
    _typingTimer?.cancel();
    _typingTimer = null;

    _conversation = null;
    _messages = [];
    _typingIndicators = [];
    _isTyping = false;

    notifyListeners();
  }

  /// Send a text message.
  Future<bool> sendTextMessage(String text) async {
    if (_currentUserId == null || _conversation == null) return false;
    if (text.trim().isEmpty) return false;

    _isSendingMessage = true;
    notifyListeners();

    final request = SendMessageRequest.text(
      conversationId: _conversation!.id,
      text: text.trim(),
    );

    final result = await _messagingService.sendMessage(
      request,
      _currentUserId!,
    );

    _isSendingMessage = false;

    if (result.isSuccess && result.data != null) {
      // Add message immediately for responsiveness
      _addMessageIfNotExists(result.data!);
      notifyListeners();

      // Stop typing indicator
      await setTyping(false);
      return true;
    }

    _error = result.error;
    notifyListeners();
    return false;
  }

  /// Send an image message.
  Future<bool> sendImageMessage({
    required String imageUrl,
    String caption = '',
    int? width,
    int? height,
  }) async {
    if (_currentUserId == null || _conversation == null) return false;

    _isSendingMessage = true;
    notifyListeners();

    final request = SendMessageRequest.image(
      conversationId: _conversation!.id,
      caption: caption,
      metadata: ImageMetadata(
        url: imageUrl,
        width: width,
        height: height,
      ),
    );

    final result = await _messagingService.sendMessage(
      request,
      _currentUserId!,
    );

    _isSendingMessage = false;

    if (result.isSuccess && result.data != null) {
      _addMessageIfNotExists(result.data!);
      notifyListeners();
      return true;
    }

    _error = result.error;
    notifyListeners();
    return false;
  }

  /// Send a file (document) message.
  Future<bool> sendFileMessage({
    required String url,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
  }) async {
    if (_currentUserId == null || _conversation == null) return false;

    _isSendingMessage = true;
    notifyListeners();

    final request = SendMessageRequest.file(
      conversationId: _conversation!.id,
      metadata: FileMetadata(
        url: url,
        fileName: fileName,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
      ),
    );

    final result =
        await _messagingService.sendMessage(request, _currentUserId!);

    _isSendingMessage = false;

    if (result.isSuccess && result.data != null) {
      _addMessageIfNotExists(result.data!);
      notifyListeners();
      return true;
    }

    _error = result.error;
    notifyListeners();
    return false;
  }

  /// Send a location message.
  Future<bool> sendLocationMessage({
    required double latitude,
    required double longitude,
    String? address,
    String? placeName,
  }) async {
    if (_currentUserId == null || _conversation == null) return false;

    _isSendingMessage = true;
    notifyListeners();

    final request = SendMessageRequest.location(
      conversationId: _conversation!.id,
      metadata: LocationMetadata(
        latitude: latitude,
        longitude: longitude,
        address: address,
        placeName: placeName,
      ),
    );

    final result = await _messagingService.sendMessage(
      request,
      _currentUserId!,
    );

    _isSendingMessage = false;

    if (result.isSuccess && result.data != null) {
      _addMessageIfNotExists(result.data!);
      notifyListeners();
      return true;
    }

    _error = result.error;
    notifyListeners();
    return false;
  }

  /// Delete a message.
  Future<bool> deleteMessage(String messageId) async {
    final result = await _messagingService.deleteMessage(messageId);

    if (result.isSuccess) {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index >= 0) {
        _messages[index] = _messages[index].copyWith(
          deletedAt: DateTime.now(),
        );
        notifyListeners();
      }
      return true;
    }

    _error = result.error;
    notifyListeners();
    return false;
  }

  /// Mark all messages in the conversation as read.
  Future<void> markAllAsRead() async {
    if (_currentUserId == null || _conversation == null) return;

    await _messagingService.markAllAsRead(
      _conversation!.id,
      _currentUserId!,
    );
  }

  /// Set typing indicator.
  Future<void> setTyping(bool isTyping) async {
    if (_currentUserId == null || _conversation == null) return;
    if (_isTyping == isTyping) return;

    _isTyping = isTyping;

    await _messagingService.setTyping(
      _conversation!.id,
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

  /// Handle text input changes (for typing indicator).
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

  /// Clear any errors.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ============================================
  // Private Methods
  // ============================================

  void _subscribeToMessages(String conversationId) {
    _messagesSubscription?.cancel();
    _messagesSubscription =
        _messagingService.subscribeToMessages(conversationId).listen((message) {
      _addMessageIfNotExists(message);
      _sortMessages();
      notifyListeners();

      // Mark as read if from someone else
      if (_currentUserId != null && message.senderId != _currentUserId) {
        markAllAsRead();
      }
    });
  }

  void _subscribeToTypingIndicators(String conversationId) {
    _typingSubscription?.cancel();
    _typingSubscription = _messagingService
        .subscribeToTypingIndicators(conversationId)
        .listen((indicators) {
      // Filter out own typing indicator
      _typingIndicators = indicators
          .where((t) => t.userId != _currentUserId && t.isValid)
          .toList();
      notifyListeners();
    });
  }

  void _addMessageIfNotExists(Message message) {
    final exists = _messages.any((m) => m.id == message.id);
    if (!exists) {
      _messages.add(message);
    }
  }

  void _sortMessages() {
    _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _typingSubscription?.cancel();
    _typingTimer?.cancel();
    super.dispose();
  }
}
