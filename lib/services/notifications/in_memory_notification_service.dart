import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/notification.dart';
import '../../models/notification_preferences.dart';
import 'notification_service.dart';

/// In-memory implementation of NotificationService for development/testing
class InMemoryNotificationService implements NotificationService {
  InMemoryNotificationService._();

  static InMemoryNotificationService? _instance;
  static InMemoryNotificationService get instance {
    _instance ??= InMemoryNotificationService._();
    return _instance!;
  }

  /// Storage for notifications
  final Map<String, AppNotification> _notifications = {};

  /// Storage for preferences
  final Map<String, NotificationPreferences> _preferences = {};

  /// Storage for push tokens
  final Map<String, PushToken> _pushTokens = {};

  /// Stream controllers for real-time updates
  final Map<String, StreamController<AppNotification>> _notificationStreams =
      {};
  final Map<String, StreamController<int>> _unreadCountStreams = {};

  @override
  Future<List<AppNotification>> getNotifications(
    String userId, {
    NotificationFilter? filter,
  }) async {
    var notifications = _notifications.values
        .where((n) => n.userId == userId)
        .where((n) => n.status != NotificationStatus.deleted)
        .toList();

    // Apply filters
    if (filter != null) {
      if (filter.types != null && filter.types!.isNotEmpty) {
        notifications =
            notifications.where((n) => filter.types!.contains(n.type)).toList();
      }
      if (filter.status != null) {
        notifications =
            notifications.where((n) => n.status == filter.status).toList();
      }
      if (filter.categories != null && filter.categories!.isNotEmpty) {
        notifications = notifications
            .where((n) => filter.categories!.contains(n.type.category))
            .toList();
      }
      if (filter.priority != null) {
        notifications = notifications
            .where((n) => n.priority.index >= filter.priority!.index)
            .toList();
      }
      if (filter.startDate != null) {
        notifications = notifications
            .where((n) => n.createdAt.isAfter(filter.startDate!))
            .toList();
      }
      if (filter.endDate != null) {
        notifications = notifications
            .where((n) => n.createdAt.isBefore(filter.endDate!))
            .toList();
      }
    }

    // Sort by creation time (newest first)
    notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Apply pagination
    if (filter?.offset != null) {
      notifications = notifications.skip(filter!.offset!).toList();
    }
    if (filter?.limit != null) {
      notifications = notifications.take(filter!.limit!).toList();
    }

    return notifications;
  }

  @override
  Future<AppNotification?> getNotification(String notificationId) async {
    return _notifications[notificationId];
  }

  @override
  Future<NotificationResult> createNotification(
      AppNotification notification) async {
    _notifications[notification.id] = notification;

    // Emit to stream
    _emitNotification(notification.userId, notification);
    _emitUnreadCount(notification.userId);

    // Log for development
    debugPrint('📬 Notification created: ${notification.title}');
    debugPrint('   Type: ${notification.type.name}');
    debugPrint('   Body: ${notification.body}');

    return NotificationResult.success(notification);
  }

  @override
  Future<NotificationResult> markAsRead(String notificationId) async {
    final notification = _notifications[notificationId];
    if (notification == null) {
      return NotificationResult.failure('Notification not found');
    }

    final updated = notification.markAsRead();
    _notifications[notificationId] = updated;

    _emitUnreadCount(notification.userId);

    return NotificationResult.success(updated);
  }

  @override
  Future<int> markAllAsRead(String userId) async {
    var count = 0;
    for (final id in _notifications.keys.toList()) {
      final notification = _notifications[id]!;
      if (notification.userId == userId && notification.isUnread) {
        _notifications[id] = notification.markAsRead();
        count++;
      }
    }

    _emitUnreadCount(userId);

    return count;
  }

  @override
  Future<NotificationResult> archiveNotification(String notificationId) async {
    final notification = _notifications[notificationId];
    if (notification == null) {
      return NotificationResult.failure('Notification not found');
    }

    final updated = notification.archive();
    _notifications[notificationId] = updated;

    return NotificationResult.success(updated);
  }

  @override
  Future<bool> deleteNotification(String notificationId) async {
    final notification = _notifications[notificationId];
    if (notification == null) return false;

    _notifications[notificationId] = notification.copyWith(
      status: NotificationStatus.deleted,
    );

    _emitUnreadCount(notification.userId);

    return true;
  }

  @override
  Future<int> deleteAllNotifications(String userId) async {
    var count = 0;
    for (final id in _notifications.keys.toList()) {
      final notification = _notifications[id]!;
      if (notification.userId == userId) {
        _notifications[id] = notification.copyWith(
          status: NotificationStatus.deleted,
        );
        count++;
      }
    }

    _emitUnreadCount(userId);

    return count;
  }

  @override
  Future<int> getUnreadCount(String userId) async {
    return _notifications.values
        .where((n) => n.userId == userId && n.isUnread)
        .length;
  }

  @override
  Future<NotificationPreferences?> getPreferences(String userId) async {
    return _preferences[userId];
  }

  @override
  Future<bool> savePreferences(NotificationPreferences preferences) async {
    _preferences[preferences.userId] = preferences.copyWith(
      updatedAt: DateTime.now(),
    );
    return true;
  }

  @override
  Future<bool> registerPushToken(PushToken token) async {
    final key = '${token.userId}_${token.deviceId}';
    _pushTokens[key] = token.copyWith(
      createdAt: token.createdAt ?? DateTime.now(),
      lastUsedAt: DateTime.now(),
    );

    debugPrint('📱 Push token registered for device: ${token.deviceId}');

    return true;
  }

  @override
  Future<bool> unregisterPushToken(String deviceId, String userId) async {
    final key = '${userId}_$deviceId';
    if (_pushTokens.containsKey(key)) {
      _pushTokens[key] = _pushTokens[key]!.copyWith(isActive: false);
      return true;
    }
    return false;
  }

  @override
  Stream<AppNotification> subscribeToNotifications(String userId) {
    _notificationStreams[userId] ??=
        StreamController<AppNotification>.broadcast();
    return _notificationStreams[userId]!.stream;
  }

  @override
  Stream<int> subscribeToUnreadCount(String userId) {
    _unreadCountStreams[userId] ??= StreamController<int>.broadcast();

    // Emit current count immediately
    getUnreadCount(userId).then((count) {
      if (!_unreadCountStreams[userId]!.isClosed) {
        _unreadCountStreams[userId]!.add(count);
      }
    });

    return _unreadCountStreams[userId]!.stream;
  }

  void _emitNotification(String userId, AppNotification notification) {
    final controller = _notificationStreams[userId];
    if (controller != null && !controller.isClosed) {
      controller.add(notification);
    }
  }

  void _emitUnreadCount(String userId) {
    final controller = _unreadCountStreams[userId];
    if (controller != null && !controller.isClosed) {
      getUnreadCount(userId).then((count) {
        if (!controller.isClosed) {
          controller.add(count);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _notificationStreams.values) {
      controller.close();
    }
    for (final controller in _unreadCountStreams.values) {
      controller.close();
    }
    _notificationStreams.clear();
    _unreadCountStreams.clear();
  }

  /// Clear all data (for testing)
  void clear() {
    _notifications.clear();
    _preferences.clear();
    _pushTokens.clear();
  }

  /// Add sample notifications for testing
  void addSampleNotifications(String userId) {
    final now = DateTime.now();

    final samples = [
      AppNotification(
        id: 'notif_1',
        userId: userId,
        type: NotificationType.bookingRequest,
        title: 'New Booking Request',
        body: 'John Doe wants to book your listing "Cozy Room in Gulshan"',
        createdAt: now.subtract(const Duration(minutes: 5)),
        priority: NotificationPriority.high,
        data: {'booking_id': 'booking_123', 'listing_id': 'listing_456'},
        actionUrl: '/bookings/booking_123',
      ),
      AppNotification(
        id: 'notif_2',
        userId: userId,
        type: NotificationType.paymentReceived,
        title: 'Payment Received',
        body: 'You received ৳1,500 for booking #123',
        createdAt: now.subtract(const Duration(hours: 2)),
        priority: NotificationPriority.normal,
        data: {'booking_id': 'booking_123', 'amount': 1500},
      ),
      AppNotification(
        id: 'notif_3',
        userId: userId,
        type: NotificationType.reviewReceived,
        title: 'New Review',
        body: 'Sarah left you a 5-star review!',
        createdAt: now.subtract(const Duration(days: 1)),
        priority: NotificationPriority.normal,
        data: {'review_id': 'review_789'},
      ),
      AppNotification(
        id: 'notif_4',
        userId: userId,
        type: NotificationType.promotionAvailable,
        title: 'Weekend Sale',
        body: 'Use code WEEKEND20 for 20% off your next booking',
        createdAt: now.subtract(const Duration(days: 2)),
        priority: NotificationPriority.low,
        data: {'promo_code': 'WEEKEND20'},
        expiresAt: now.add(const Duration(days: 5)),
      ),
    ];

    for (final notification in samples) {
      _notifications[notification.id] = notification;
    }
  }
}
