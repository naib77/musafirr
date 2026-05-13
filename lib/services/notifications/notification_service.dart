import '../../models/notification.dart';
import '../../models/notification_preferences.dart';

/// Result of a notification operation
class NotificationResult {
  const NotificationResult({
    required this.success,
    this.notification,
    this.error,
  });

  final bool success;
  final AppNotification? notification;
  final String? error;

  factory NotificationResult.success(AppNotification notification) {
    return NotificationResult(success: true, notification: notification);
  }

  factory NotificationResult.failure(String error) {
    return NotificationResult(success: false, error: error);
  }
}

/// Filter options for querying notifications
class NotificationFilter {
  const NotificationFilter({
    this.types,
    this.status,
    this.categories,
    this.priority,
    this.startDate,
    this.endDate,
    this.limit,
    this.offset,
  });

  /// Filter by notification types
  final List<NotificationType>? types;

  /// Filter by status
  final NotificationStatus? status;

  /// Filter by categories
  final List<String>? categories;

  /// Filter by minimum priority
  final NotificationPriority? priority;

  /// Filter by start date
  final DateTime? startDate;

  /// Filter by end date
  final DateTime? endDate;

  /// Limit number of results
  final int? limit;

  /// Offset for pagination
  final int? offset;

  /// Create a filter for unread notifications only
  factory NotificationFilter.unreadOnly({int? limit}) {
    return NotificationFilter(
      status: NotificationStatus.unread,
      limit: limit,
    );
  }

  /// Create a filter for a specific category
  factory NotificationFilter.forCategory(String category, {int? limit}) {
    return NotificationFilter(
      categories: [category],
      limit: limit,
    );
  }
}

/// Abstract notification service interface
abstract class NotificationService {
  /// Get notifications for a user
  Future<List<AppNotification>> getNotifications(
    String userId, {
    NotificationFilter? filter,
  });

  /// Get a single notification by ID
  Future<AppNotification?> getNotification(String notificationId);

  /// Create a new notification
  Future<NotificationResult> createNotification(AppNotification notification);

  /// Mark a notification as read
  Future<NotificationResult> markAsRead(String notificationId);

  /// Mark all notifications as read for a user
  Future<int> markAllAsRead(String userId);

  /// Archive a notification
  Future<NotificationResult> archiveNotification(String notificationId);

  /// Delete a notification
  Future<bool> deleteNotification(String notificationId);

  /// Delete all notifications for a user
  Future<int> deleteAllNotifications(String userId);

  /// Get unread count for a user
  Future<int> getUnreadCount(String userId);

  /// Get notification preferences for a user
  Future<NotificationPreferences?> getPreferences(String userId);

  /// Save notification preferences
  Future<bool> savePreferences(NotificationPreferences preferences);

  /// Register a push token
  Future<bool> registerPushToken(PushToken token);

  /// Unregister a push token
  Future<bool> unregisterPushToken(String deviceId, String userId);

  /// Subscribe to real-time notification updates
  Stream<AppNotification> subscribeToNotifications(String userId);

  /// Subscribe to unread count changes
  Stream<int> subscribeToUnreadCount(String userId);

  /// Dispose of resources
  void dispose();
}

/// Notification delivery service interface (for sending via different channels)
abstract class NotificationDeliveryService {
  /// Send a push notification
  Future<bool> sendPush({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? imageUrl,
  });

  /// Send an email notification
  Future<bool> sendEmail({
    required String email,
    required String subject,
    required String body,
    String? htmlBody,
  });

  /// Send an SMS notification
  Future<bool> sendSms({
    required String phoneNumber,
    required String message,
  });

  /// Send a WhatsApp notification
  Future<bool> sendWhatsApp({
    required String phoneNumber,
    required String templateName,
    required Map<String, String> parameters,
  });
}

/// Notification scheduler for delayed/scheduled notifications
abstract class NotificationScheduler {
  /// Schedule a notification for future delivery
  Future<String> scheduleNotification({
    required AppNotification notification,
    required DateTime deliveryTime,
  });

  /// Cancel a scheduled notification
  Future<bool> cancelScheduledNotification(String scheduleId);

  /// Get pending scheduled notifications
  Future<List<AppNotification>> getPendingNotifications(String userId);
}
