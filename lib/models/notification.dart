/// Helper to convert snake_case to camelCase
String _snakeToCamel(String input) {
  final parts = input.split('_');
  if (parts.length == 1) return input;
  return parts.first +
      parts.skip(1).map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1)).join();
}

/// Helper to convert camelCase to snake_case
String _camelToSnake(String input) {
  return input.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (match) => '_${match.group(0)!.toLowerCase()}',
  );
}

/// Types of notifications in the system
enum NotificationType {
  /// Booking-related notifications
  bookingRequest,
  bookingConfirmed,
  bookingCancelled,
  bookingReminder,
  checkInReminder,
  checkOutReminder,

  /// Payment-related notifications
  paymentReceived,
  paymentFailed,
  refundProcessed,

  /// Review-related notifications
  reviewReceived,
  reviewReminder,

  /// Promotion-related notifications
  promotionAvailable,
  discountExpiring,
  referralReward,

  /// Message-related notifications
  newMessage,
  messageRead,

  /// System notifications
  systemAlert,
  accountUpdate,
  securityAlert,
}

/// Priority levels for notifications
enum NotificationPriority {
  low,
  normal,
  high,
  urgent,
}

/// Status of a notification
enum NotificationStatus {
  unread,
  read,
  archived,
  deleted,
}

/// Extension to get notification type properties
extension NotificationTypeExtension on NotificationType {
  /// Human-readable title for the notification type
  String get title {
    switch (this) {
      case NotificationType.bookingRequest:
        return 'Booking Request';
      case NotificationType.bookingConfirmed:
        return 'Booking Confirmed';
      case NotificationType.bookingCancelled:
        return 'Booking Cancelled';
      case NotificationType.bookingReminder:
        return 'Booking Reminder';
      case NotificationType.checkInReminder:
        return 'Check-in Reminder';
      case NotificationType.checkOutReminder:
        return 'Check-out Reminder';
      case NotificationType.paymentReceived:
        return 'Payment Received';
      case NotificationType.paymentFailed:
        return 'Payment Failed';
      case NotificationType.refundProcessed:
        return 'Refund Processed';
      case NotificationType.reviewReceived:
        return 'New Review';
      case NotificationType.reviewReminder:
        return 'Review Reminder';
      case NotificationType.promotionAvailable:
        return 'New Promotion';
      case NotificationType.discountExpiring:
        return 'Discount Expiring';
      case NotificationType.referralReward:
        return 'Referral Reward';
      case NotificationType.newMessage:
        return 'New Message';
      case NotificationType.messageRead:
        return 'Message Read';
      case NotificationType.systemAlert:
        return 'System Alert';
      case NotificationType.accountUpdate:
        return 'Account Update';
      case NotificationType.securityAlert:
        return 'Security Alert';
    }
  }

  /// Icon name for the notification type
  String get iconName {
    switch (this) {
      case NotificationType.bookingRequest:
      case NotificationType.bookingConfirmed:
      case NotificationType.bookingCancelled:
      case NotificationType.bookingReminder:
        return 'calendar_today';
      case NotificationType.checkInReminder:
        return 'login';
      case NotificationType.checkOutReminder:
        return 'logout';
      case NotificationType.paymentReceived:
      case NotificationType.paymentFailed:
      case NotificationType.refundProcessed:
        return 'payment';
      case NotificationType.reviewReceived:
      case NotificationType.reviewReminder:
        return 'star';
      case NotificationType.promotionAvailable:
      case NotificationType.discountExpiring:
        return 'local_offer';
      case NotificationType.referralReward:
        return 'card_giftcard';
      case NotificationType.newMessage:
      case NotificationType.messageRead:
        return 'message';
      case NotificationType.systemAlert:
        return 'info';
      case NotificationType.accountUpdate:
        return 'person';
      case NotificationType.securityAlert:
        return 'security';
    }
  }

  /// Whether this notification type is high priority by default
  bool get isHighPriorityByDefault {
    switch (this) {
      case NotificationType.bookingRequest:
      case NotificationType.paymentFailed:
      case NotificationType.securityAlert:
        return true;
      default:
        return false;
    }
  }

  /// Category for grouping notifications
  String get category {
    switch (this) {
      case NotificationType.bookingRequest:
      case NotificationType.bookingConfirmed:
      case NotificationType.bookingCancelled:
      case NotificationType.bookingReminder:
      case NotificationType.checkInReminder:
      case NotificationType.checkOutReminder:
        return 'booking';
      case NotificationType.paymentReceived:
      case NotificationType.paymentFailed:
      case NotificationType.refundProcessed:
        return 'payment';
      case NotificationType.reviewReceived:
      case NotificationType.reviewReminder:
        return 'review';
      case NotificationType.promotionAvailable:
      case NotificationType.discountExpiring:
      case NotificationType.referralReward:
        return 'promotion';
      case NotificationType.newMessage:
      case NotificationType.messageRead:
        return 'message';
      case NotificationType.systemAlert:
      case NotificationType.accountUpdate:
      case NotificationType.securityAlert:
        return 'system';
    }
  }
}

/// Represents a notification in the system
class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.status = NotificationStatus.unread,
    this.priority = NotificationPriority.normal,
    this.data,
    this.imageUrl,
    this.actionUrl,
    this.readAt,
    this.expiresAt,
    this.groupKey,
  });

  /// Unique identifier
  final String id;

  /// User this notification belongs to
  final String userId;

  /// Type of notification
  final NotificationType type;

  /// Notification title
  final String title;

  /// Notification body text
  final String body;

  /// When the notification was created
  final DateTime createdAt;

  /// Current status
  final NotificationStatus status;

  /// Priority level
  final NotificationPriority priority;

  /// Additional data payload (e.g., booking ID, listing ID)
  final Map<String, dynamic>? data;

  /// Optional image URL for rich notifications
  final String? imageUrl;

  /// Deep link URL for when notification is tapped
  final String? actionUrl;

  /// When the notification was read
  final DateTime? readAt;

  /// When the notification expires (for time-sensitive notifications)
  final DateTime? expiresAt;

  /// Group key for collapsing similar notifications
  final String? groupKey;

  /// Whether the notification is unread
  bool get isUnread => status == NotificationStatus.unread;

  /// Whether the notification has expired
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// Time elapsed since creation
  Duration get age => DateTime.now().difference(createdAt);

  /// Human-readable relative time
  String get relativeTime {
    final duration = age;
    if (duration.inMinutes < 1) {
      return 'Just now';
    } else if (duration.inMinutes < 60) {
      return '${duration.inMinutes}m ago';
    } else if (duration.inHours < 24) {
      return '${duration.inHours}h ago';
    } else if (duration.inDays < 7) {
      return '${duration.inDays}d ago';
    } else {
      return '${(duration.inDays / 7).floor()}w ago';
    }
  }

  /// Create a copy with updated fields
  AppNotification copyWith({
    String? id,
    String? userId,
    NotificationType? type,
    String? title,
    String? body,
    DateTime? createdAt,
    NotificationStatus? status,
    NotificationPriority? priority,
    Map<String, dynamic>? data,
    String? imageUrl,
    String? actionUrl,
    DateTime? readAt,
    DateTime? expiresAt,
    String? groupKey,
  }) {
    return AppNotification(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      data: data ?? this.data,
      imageUrl: imageUrl ?? this.imageUrl,
      actionUrl: actionUrl ?? this.actionUrl,
      readAt: readAt ?? this.readAt,
      expiresAt: expiresAt ?? this.expiresAt,
      groupKey: groupKey ?? this.groupKey,
    );
  }

  /// Mark as read
  AppNotification markAsRead() {
    return copyWith(
      status: NotificationStatus.read,
      readAt: DateTime.now(),
    );
  }

  /// Archive the notification
  AppNotification archive() {
    return copyWith(status: NotificationStatus.archived);
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'type': _camelToSnake(type.name),
      'title': title,
      'body': body,
      'created_at': createdAt.toIso8601String(),
      'status': status.name,
      'priority': priority.name,
      'data': data,
      'image_url': imageUrl,
      'action_url': actionUrl,
      'read_at': readAt?.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'group_key': groupKey,
    };
  }

  /// Create from JSON
  factory AppNotification.fromJson(Map<String, dynamic> json) {
    // Handle snake_case type from database (e.g., 'booking_request' -> 'bookingRequest')
    final typeStr = json['type'] as String;
    final normalizedType = _snakeToCamel(typeStr);

    return AppNotification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: NotificationType.values.firstWhere(
        (t) => t.name == normalizedType || t.name == typeStr,
        orElse: () => NotificationType.systemAlert,
      ),
      title: json['title'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      status: NotificationStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => NotificationStatus.unread,
      ),
      priority: NotificationPriority.values.firstWhere(
        (p) => p.name == json['priority'],
        orElse: () => NotificationPriority.normal,
      ),
      data: json['data'] as Map<String, dynamic>?,
      imageUrl: json['image_url'] as String?,
      actionUrl: json['action_url'] as String?,
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      groupKey: json['group_key'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppNotification &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'AppNotification(id: $id, type: $type, title: $title, status: $status)';
  }
}

/// Grouped notifications for display
class NotificationGroup {
  const NotificationGroup({
    required this.key,
    required this.notifications,
    required this.category,
  });

  final String key;
  final List<AppNotification> notifications;
  final String category;

  /// Number of notifications in the group
  int get count => notifications.length;

  /// Number of unread notifications
  int get unreadCount => notifications.where((n) => n.isUnread).length;

  /// Most recent notification
  AppNotification get latestNotification => notifications.first;

  /// Summary text for collapsed view
  String get summary {
    if (count == 1) {
      return notifications.first.body;
    }
    return '${count} ${category} notifications';
  }
}
