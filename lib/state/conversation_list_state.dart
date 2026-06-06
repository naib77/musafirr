import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/conversation.dart';
import '../repositories/conversation_repository.dart';

/// State management for the conversation list.
///
/// This module owns:
/// - List of conversations
/// - Filtering (active/archived/unread)
/// - Pagination
/// - Real-time conversation updates
///
/// ## Usage
///
/// ```dart
/// final state = ConversationListState(
///   repository: conversationRepository,
/// );
///
/// await state.initialize(userId);
///
/// // Access conversations
/// final active = state.activeConversations;
/// final archived = state.archivedConversations;
///
/// // Refresh
/// await state.refresh();
/// ```
class ConversationListState extends ChangeNotifier {
  ConversationListState({
    required ConversationRepository repository,
  }) : _repository = repository;

  final ConversationRepository _repository;

  String? _userId;
  String? get userId => _userId;

  List<Conversation> _conversations = [];
  List<Conversation> get conversations => List.unmodifiable(_conversations);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _hasMore = true;
  bool get hasMore => _hasMore;

  String? _nextCursor;

  String? _error;
  String? get error => _error;

  int _totalUnreadCount = 0;
  int get totalUnreadCount => _totalUnreadCount;

  // Real-time subscription
  StreamSubscription<Conversation>? _subscription;

  /// Initialize the state for a user.
  Future<void> initialize(String userId) async {
    if (_userId == userId) return;

    _userId = userId;
    await loadConversations();
    await _loadUnreadCount();
  }

  /// Load conversations (first page).
  Future<void> loadConversations() async {
    if (_userId == null) return;

    _isLoading = true;
    _error = null;
    _nextCursor = null;
    notifyListeners();

    final result = await _repository.getAll(
      userId: _userId!,
      limit: 20,
    );

    if (result.isSuccess && result.data != null) {
      _conversations = result.data!.conversations;
      _hasMore = result.data!.hasMore;
      _nextCursor = result.data!.nextCursor;
    } else {
      _error = result.error?.message;
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load more conversations (pagination).
  Future<void> loadMore() async {
    if (_userId == null || _isLoading || !_hasMore) return;

    _isLoading = true;
    notifyListeners();

    final result = await _repository.getAll(
      userId: _userId!,
      limit: 20,
      cursor: _nextCursor,
    );

    if (result.isSuccess && result.data != null) {
      _conversations.addAll(result.data!.conversations);
      _hasMore = result.data!.hasMore;
      _nextCursor = result.data!.nextCursor;
    } else {
      _error = result.error?.message;
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Refresh the conversation list.
  Future<void> refresh() async {
    await loadConversations();
    await _loadUnreadCount();
  }

  /// Get active (non-archived) conversations.
  List<Conversation> get activeConversations {
    return _conversations
        .where((c) => c.status == ConversationStatus.active)
        .toList();
  }

  /// Get archived conversations.
  List<Conversation> get archivedConversations {
    return _conversations
        .where((c) => c.status == ConversationStatus.archived)
        .toList();
  }

  /// Get conversations with unread messages.
  List<Conversation> get unreadConversations {
    return _conversations.where((c) => c.hasUnread).toList();
  }

  /// Find a conversation by ID.
  Conversation? findById(String conversationId) {
    try {
      return _conversations.firstWhere((c) => c.id == conversationId);
    } catch (_) {
      return null;
    }
  }

  /// Update a conversation in the list.
  void updateConversation(Conversation conversation) {
    final index = _conversations.indexWhere((c) => c.id == conversation.id);
    if (index >= 0) {
      _conversations[index] = conversation;
    } else {
      _conversations.insert(0, conversation);
    }
    _sortConversations();
    notifyListeners();
  }

  /// Add a new conversation to the list.
  void addConversation(Conversation conversation) {
    final exists = _conversations.any((c) => c.id == conversation.id);
    if (!exists) {
      _conversations.insert(0, conversation);
      _sortConversations();
      notifyListeners();
    }
  }

  /// Archive a conversation.
  Future<bool> archiveConversation(String conversationId) async {
    final result = await _repository.archive(conversationId);

    if (result.isSuccess) {
      final index = _conversations.indexWhere((c) => c.id == conversationId);
      if (index >= 0) {
        _conversations[index] = _conversations[index].copyWith(
          status: ConversationStatus.archived,
        );
        notifyListeners();
      }
      return true;
    }

    _error = result.error?.message;
    notifyListeners();
    return false;
  }

  /// Unarchive a conversation.
  Future<bool> unarchiveConversation(String conversationId) async {
    final result = await _repository.unarchive(conversationId);

    if (result.isSuccess) {
      final index = _conversations.indexWhere((c) => c.id == conversationId);
      if (index >= 0) {
        _conversations[index] = _conversations[index].copyWith(
          status: ConversationStatus.active,
        );
        notifyListeners();
      }
      return true;
    }

    _error = result.error?.message;
    notifyListeners();
    return false;
  }

  /// Mark a conversation as read (update local unread count).
  void markAsRead(String conversationId) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index >= 0 && _conversations[index].unreadCount > 0) {
      final oldUnread = _conversations[index].unreadCount;
      _conversations[index] = _conversations[index].copyWith(unreadCount: 0);
      _totalUnreadCount = (_totalUnreadCount - oldUnread).clamp(0, 999999);
      notifyListeners();
    }
  }

  /// Increment unread count for a conversation.
  void incrementUnread(String conversationId) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index >= 0) {
      _conversations[index] = _conversations[index].copyWith(
        unreadCount: _conversations[index].unreadCount + 1,
      );
      _totalUnreadCount++;
      notifyListeners();
    }
  }

  /// Clear any errors.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Clear all state.
  void clear() {
    _userId = null;
    _conversations = [];
    _isLoading = false;
    _hasMore = true;
    _nextCursor = null;
    _error = null;
    _totalUnreadCount = 0;
    _subscription?.cancel();
    _subscription = null;
    notifyListeners();
  }

  Future<void> _loadUnreadCount() async {
    if (_userId == null) return;

    final result = await _repository.getTotalUnreadCount(_userId!);
    if (result.isSuccess && result.data != null) {
      _totalUnreadCount = result.data!;
      notifyListeners();
    }
  }

  void _sortConversations() {
    _conversations.sort((a, b) {
      final aTime = a.lastMessageAt ?? a.createdAt;
      final bTime = b.lastMessageAt ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
