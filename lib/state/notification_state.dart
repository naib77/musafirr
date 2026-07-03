import 'dart:async';

import 'package:flutter/foundation.dart';
import '../core/state/safe_notifier.dart';

import '../models/notification.dart';
import '../models/notification_preferences.dart';
import '../services/notifications/notification_service.dart';

/// State notifier for managing notifications
class NotificationStateNotifier extends ChangeNotifier with SafeNotifier {
  NotificationStateNotifier({
    required NotificationService service,
  }) : _service = service;

  final NotificationService _service;

  String? _currentUserId;
  List<AppNotification> _notifications = [];
  int _unreadCount = 0;
  NotificationPreferences? _preferences;
  bool _isLoading = false;
  String? _error;

  StreamSubscription<AppNotification>? _notificationSubscription;
  StreamSubscription<int>? _unreadCountSubscription;

  /// Called for every realtime notification, letting other state (e.g. the
  /// messaging unread badge) piggyback on this channel's delivery.
  void Function(AppNotification notification)? onNewNotification;

  // ============================================================
  // GETTERS
  // ============================================================

  /// Current user ID
  String? get currentUserId => _currentUserId;

  /// All notifications
  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  /// Unread notifications
  List<AppNotification> get unreadNotifications =>
      _notifications.where((n) => n.isUnread).toList();

  /// Number of unread notifications
  int get unreadCount => _unreadCount;

  /// Has unread notifications
  bool get hasUnread => _unreadCount > 0;

  /// User's notification preferences
  NotificationPreferences? get preferences => _preferences;

  /// Whether notifications are loading
  bool get isLoading => _isLoading;

  /// Current error message
  String? get error => _error;

  /// Notifications grouped by category
  Map<String, List<AppNotification>> get groupedNotifications {
    final grouped = <String, List<AppNotification>>{};
    for (final notification in _notifications) {
      final category = notification.type.category;
      grouped.putIfAbsent(category, () => []).add(notification);
    }
    return grouped;
  }

  /// Today's notifications
  List<AppNotification> get todayNotifications {
    final today = DateTime.now();
    return _notifications.where((n) {
      return n.createdAt.year == today.year &&
          n.createdAt.month == today.month &&
          n.createdAt.day == today.day;
    }).toList();
  }

  /// Earlier notifications
  List<AppNotification> get earlierNotifications {
    final today = DateTime.now();
    return _notifications.where((n) {
      return !(n.createdAt.year == today.year &&
          n.createdAt.month == today.month &&
          n.createdAt.day == today.day);
    }).toList();
  }

  // ============================================================
  // INITIALIZATION
  // ============================================================

  /// Initialize notification state for a user
  Future<void> initialize(String userId) async {
    if (_currentUserId == userId) return;

    // Claim the user id BEFORE the first await so a second auth event firing
    // during login short-circuits on the guard above — otherwise both calls
    // pass and create duplicate (leaked) realtime subscriptions.
    _currentUserId = userId;

    // Cleanup previous user's subscriptions
    await _cleanup();

    _setLoading(true);
    _error = null;

    try {
      // Load initial data in parallel
      final results = await Future.wait([
        _service.getNotifications(userId,
            filter: const NotificationFilter(limit: 50)),
        _service.getUnreadCount(userId),
        _service.getPreferences(userId),
      ]);

      _notifications = results[0] as List<AppNotification>;
      _unreadCount = results[1] as int;
      _preferences = results[2] as NotificationPreferences? ??
          NotificationPreferences.defaultFor(userId);

      // Subscribe to real-time updates
      _subscribeToUpdates(userId);

      notifyListeners();
    } catch (e) {
      _error = 'Failed to load notifications: $e';
      debugPrint(_error);
    } finally {
      _setLoading(false);
    }
  }

  void _subscribeToUpdates(String userId) {
    // Subscribe to new notifications
    _notificationSubscription =
        _service.subscribeToNotifications(userId).listen(
      (notification) {
        _onNewNotification(notification);
      },
      onError: (e) {
        debugPrint('Notification stream error: $e');
      },
    );

    // Subscribe to unread count
    _unreadCountSubscription = _service.subscribeToUnreadCount(userId).listen(
      (count) {
        if (_unreadCount != count) {
          _unreadCount = count;
          notifyListeners();
        }
      },
      onError: (e) {
        debugPrint('Unread count stream error: $e');
      },
    );
  }

  void _onNewNotification(AppNotification notification) {
    // Check if notification already exists
    final existingIndex =
        _notifications.indexWhere((n) => n.id == notification.id);

    if (existingIndex >= 0) {
      // Update existing notification
      _notifications[existingIndex] = notification;
    } else {
      // Add new notification at the top
      _notifications.insert(0, notification);
    }

    notifyListeners();

    onNewNotification?.call(notification);

    // Show in-app toast/banner for new notifications
    _showInAppNotification(notification);
  }

  void _showInAppNotification(AppNotification notification) {
    // This would trigger showing a toast/snackbar
    // Implementation depends on the UI layer
    debugPrint('📬 New notification: ${notification.title}');
  }

  // ============================================================
  // ACTIONS
  // ============================================================

  /// Refresh notifications
  Future<void> refresh() async {
    if (_currentUserId == null) return;

    _setLoading(true);
    try {
      _notifications = await _service.getNotifications(
        _currentUserId!,
        filter: const NotificationFilter(limit: 50),
      );
      _unreadCount = await _service.getUnreadCount(_currentUserId!);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to refresh notifications: $e';
      debugPrint(_error);
    } finally {
      _setLoading(false);
    }
  }

  /// Load more notifications (pagination)
  Future<void> loadMore() async {
    if (_currentUserId == null || _isLoading) return;

    _setLoading(true);
    try {
      final moreNotifications = await _service.getNotifications(
        _currentUserId!,
        filter: NotificationFilter(
          offset: _notifications.length,
          limit: 20,
        ),
      );

      if (moreNotifications.isNotEmpty) {
        _notifications.addAll(moreNotifications);
        notifyListeners();
      }
    } catch (e) {
      _error = 'Failed to load more notifications: $e';
      debugPrint(_error);
    } finally {
      _setLoading(false);
    }
  }

  /// Mark a notification as read
  Future<void> markAsRead(String notificationId) async {
    final result = await _service.markAsRead(notificationId);
    if (result.success && result.notification != null) {
      final index = _notifications.indexWhere((n) => n.id == notificationId);
      if (index >= 0) {
        _notifications[index] = result.notification!;
        _unreadCount = await _service.getUnreadCount(_currentUserId!);
        notifyListeners();
      }
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    if (_currentUserId == null) return;

    final count = await _service.markAllAsRead(_currentUserId!);
    if (count > 0) {
      _notifications = _notifications.map((n) => n.markAsRead()).toList();
      _unreadCount = 0;
      notifyListeners();
    }
  }

  /// Archive a notification
  Future<void> archive(String notificationId) async {
    final result = await _service.archiveNotification(notificationId);
    if (result.success) {
      _notifications.removeWhere((n) => n.id == notificationId);
      notifyListeners();
    }
  }

  /// Delete a notification
  Future<void> delete(String notificationId) async {
    final success = await _service.deleteNotification(notificationId);
    if (success) {
      _notifications.removeWhere((n) => n.id == notificationId);
      if (_currentUserId != null) {
        _unreadCount = await _service.getUnreadCount(_currentUserId!);
      }
      notifyListeners();
    }
  }

  /// Delete all notifications
  Future<void> deleteAll() async {
    if (_currentUserId == null) return;

    await _service.deleteAllNotifications(_currentUserId!);
    _notifications.clear();
    _unreadCount = 0;
    notifyListeners();
  }

  /// Get notifications by category
  List<AppNotification> getByCategory(String category) {
    return _notifications.where((n) => n.type.category == category).toList();
  }

  /// Get notifications by type
  List<AppNotification> getByType(NotificationType type) {
    return _notifications.where((n) => n.type == type).toList();
  }

  // ============================================================
  // PREFERENCES
  // ============================================================

  /// Update notification preferences
  Future<void> updatePreferences(NotificationPreferences preferences) async {
    final success = await _service.savePreferences(preferences);
    if (success) {
      _preferences = preferences;
      notifyListeners();
    }
  }

  /// Toggle global notifications
  Future<void> toggleGlobalNotifications(bool enabled) async {
    if (_preferences == null) return;

    final updated = _preferences!.copyWith(
      globalEnabled: enabled,
      updatedAt: DateTime.now(),
    );
    await updatePreferences(updated);
  }

  /// Update quiet hours
  Future<void> updateQuietHours(QuietHours quietHours) async {
    if (_preferences == null) return;

    final updated = _preferences!.copyWith(
      quietHours: quietHours,
      updatedAt: DateTime.now(),
    );
    await updatePreferences(updated);
  }

  /// Update category preferences
  Future<void> updateCategoryPreferences(
    String category,
    CategoryPreferences prefs,
  ) async {
    if (_preferences == null) return;

    final updated = _preferences!.updateCategory(category, prefs);
    await updatePreferences(updated);
  }

  /// Register push token
  Future<void> registerPushToken({
    required String token,
    required String platform,
    required String deviceId,
    String? deviceName,
  }) async {
    if (_currentUserId == null) return;

    final pushToken = PushToken(
      userId: _currentUserId!,
      token: token,
      platform: platform,
      deviceId: deviceId,
      deviceName: deviceName,
      createdAt: DateTime.now(),
    );

    await _service.registerPushToken(pushToken);

    // Update preferences with the token
    if (_preferences != null) {
      final updated = _preferences!.copyWith(
        pushToken: token,
        updatedAt: DateTime.now(),
      );
      await updatePreferences(updated);
    }
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  Future<void> _cleanup() async {
    await _notificationSubscription?.cancel();
    await _unreadCountSubscription?.cancel();
    _notificationSubscription = null;
    _unreadCountSubscription = null;
  }

  /// Clear state on logout
  Future<void> clear() async {
    await _cleanup();
    _currentUserId = null;
    _notifications = [];
    _unreadCount = 0;
    _preferences = null;
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    if (_isLoading != value) {
      _isLoading = value;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}
