import 'package:flutter/material.dart';

import 'notification.dart';

/// Delivery channels for notifications
enum NotificationChannel {
  /// In-app notifications
  inApp,

  /// Push notifications (FCM)
  push,

  /// Email notifications
  email,

  /// SMS notifications
  sms,

  /// WhatsApp notifications
  whatsApp,
}

extension NotificationChannelExtension on NotificationChannel {
  String get displayName {
    switch (this) {
      case NotificationChannel.inApp:
        return 'In-App';
      case NotificationChannel.push:
        return 'Push Notifications';
      case NotificationChannel.email:
        return 'Email';
      case NotificationChannel.sms:
        return 'SMS';
      case NotificationChannel.whatsApp:
        return 'WhatsApp';
    }
  }

  String get description {
    switch (this) {
      case NotificationChannel.inApp:
        return 'Notifications within the app';
      case NotificationChannel.push:
        return 'Notifications on your device';
      case NotificationChannel.email:
        return 'Notifications to your email';
      case NotificationChannel.sms:
        return 'Notifications via text message';
      case NotificationChannel.whatsApp:
        return 'Notifications via WhatsApp';
    }
  }

  IconData get icon {
    switch (this) {
      case NotificationChannel.inApp:
        return Icons.notifications;
      case NotificationChannel.push:
        return Icons.phone_android;
      case NotificationChannel.email:
        return Icons.email;
      case NotificationChannel.sms:
        return Icons.sms;
      case NotificationChannel.whatsApp:
        return Icons.chat;
    }
  }
}

/// Quiet hours configuration
class QuietHours {
  const QuietHours({
    this.enabled = false,
    this.startTime = const TimeOfDay(hour: 22, minute: 0),
    this.endTime = const TimeOfDay(hour: 7, minute: 0),
    this.allowUrgent = true,
  });

  /// Whether quiet hours are enabled
  final bool enabled;

  /// Start time of quiet hours
  final TimeOfDay startTime;

  /// End time of quiet hours
  final TimeOfDay endTime;

  /// Whether to allow urgent notifications during quiet hours
  final bool allowUrgent;

  /// Check if current time is within quiet hours
  bool isActiveNow() {
    if (!enabled) return false;

    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final startMinutes = startTime.hour * 60 + startTime.minute;
    final endMinutes = endTime.hour * 60 + endTime.minute;

    // Handle overnight quiet hours (e.g., 22:00 - 07:00)
    if (startMinutes > endMinutes) {
      return nowMinutes >= startMinutes || nowMinutes < endMinutes;
    }
    return nowMinutes >= startMinutes && nowMinutes < endMinutes;
  }

  QuietHours copyWith({
    bool? enabled,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    bool? allowUrgent,
  }) {
    return QuietHours(
      enabled: enabled ?? this.enabled,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      allowUrgent: allowUrgent ?? this.allowUrgent,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'start_hour': startTime.hour,
      'start_minute': startTime.minute,
      'end_hour': endTime.hour,
      'end_minute': endTime.minute,
      'allow_urgent': allowUrgent,
    };
  }

  factory QuietHours.fromJson(Map<String, dynamic> json) {
    return QuietHours(
      enabled: json['enabled'] as bool? ?? false,
      startTime: TimeOfDay(
        hour: json['start_hour'] as int? ?? 22,
        minute: json['start_minute'] as int? ?? 0,
      ),
      endTime: TimeOfDay(
        hour: json['end_hour'] as int? ?? 7,
        minute: json['end_minute'] as int? ?? 0,
      ),
      allowUrgent: json['allow_urgent'] as bool? ?? true,
    );
  }
}

/// Per-category notification settings
class CategoryPreferences {
  const CategoryPreferences({
    this.enabled = true,
    this.channels = const {
      NotificationChannel.inApp,
      NotificationChannel.push,
    },
    this.sound = true,
    this.vibration = true,
  });

  /// Whether notifications for this category are enabled
  final bool enabled;

  /// Channels to deliver notifications on
  final Set<NotificationChannel> channels;

  /// Whether to play sound
  final bool sound;

  /// Whether to vibrate
  final bool vibration;

  CategoryPreferences copyWith({
    bool? enabled,
    Set<NotificationChannel>? channels,
    bool? sound,
    bool? vibration,
  }) {
    return CategoryPreferences(
      enabled: enabled ?? this.enabled,
      channels: channels ?? this.channels,
      sound: sound ?? this.sound,
      vibration: vibration ?? this.vibration,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'channels': channels.map((c) => c.name).toList(),
      'sound': sound,
      'vibration': vibration,
    };
  }

  factory CategoryPreferences.fromJson(Map<String, dynamic> json) {
    return CategoryPreferences(
      enabled: json['enabled'] as bool? ?? true,
      channels: (json['channels'] as List<dynamic>?)
              ?.map((c) => NotificationChannel.values.firstWhere(
                    (ch) => ch.name == c,
                    orElse: () => NotificationChannel.inApp,
                  ))
              .toSet() ??
          {NotificationChannel.inApp, NotificationChannel.push},
      sound: json['sound'] as bool? ?? true,
      vibration: json['vibration'] as bool? ?? true,
    );
  }
}

/// User's notification preferences
class NotificationPreferences {
  const NotificationPreferences({
    required this.userId,
    this.globalEnabled = true,
    this.quietHours = const QuietHours(),
    this.categoryPreferences = const {},
    this.pushToken,
    this.email,
    this.phoneNumber,
    this.whatsAppNumber,
    this.updatedAt,
  });

  /// User ID
  final String userId;

  /// Master toggle for all notifications
  final bool globalEnabled;

  /// Quiet hours configuration
  final QuietHours quietHours;

  /// Per-category preferences
  final Map<String, CategoryPreferences> categoryPreferences;

  /// FCM push token for this device
  final String? pushToken;

  /// Email for email notifications
  final String? email;

  /// Phone number for SMS
  final String? phoneNumber;

  /// WhatsApp number
  final String? whatsAppNumber;

  /// Last updated timestamp
  final DateTime? updatedAt;

  /// Get preferences for a specific category
  CategoryPreferences getForCategory(String category) {
    return categoryPreferences[category] ?? const CategoryPreferences();
  }

  /// Check if a notification type should be delivered
  bool shouldDeliver(NotificationType type, NotificationPriority priority) {
    if (!globalEnabled) return false;

    // Check quiet hours
    if (quietHours.isActiveNow()) {
      if (priority != NotificationPriority.urgent || !quietHours.allowUrgent) {
        return false;
      }
    }

    // Check category preferences
    final categoryPrefs = getForCategory(type.category);
    return categoryPrefs.enabled;
  }

  /// Get channels for a notification type
  Set<NotificationChannel> getChannels(NotificationType type) {
    if (!globalEnabled) return {};
    return getForCategory(type.category).channels;
  }

  NotificationPreferences copyWith({
    String? userId,
    bool? globalEnabled,
    QuietHours? quietHours,
    Map<String, CategoryPreferences>? categoryPreferences,
    String? pushToken,
    String? email,
    String? phoneNumber,
    String? whatsAppNumber,
    DateTime? updatedAt,
  }) {
    return NotificationPreferences(
      userId: userId ?? this.userId,
      globalEnabled: globalEnabled ?? this.globalEnabled,
      quietHours: quietHours ?? this.quietHours,
      categoryPreferences: categoryPreferences ?? this.categoryPreferences,
      pushToken: pushToken ?? this.pushToken,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      whatsAppNumber: whatsAppNumber ?? this.whatsAppNumber,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Update category preferences
  NotificationPreferences updateCategory(
    String category,
    CategoryPreferences prefs,
  ) {
    return copyWith(
      categoryPreferences: {
        ...categoryPreferences,
        category: prefs,
      },
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'global_enabled': globalEnabled,
      'quiet_hours': quietHours.toJson(),
      'category_preferences': categoryPreferences.map(
        (k, v) => MapEntry(k, v.toJson()),
      ),
      'push_token': pushToken,
      'email': email,
      'phone_number': phoneNumber,
      'whatsapp_number': whatsAppNumber,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      userId: json['user_id'] as String,
      globalEnabled: json['global_enabled'] as bool? ?? true,
      quietHours: json['quiet_hours'] != null
          ? QuietHours.fromJson(json['quiet_hours'] as Map<String, dynamic>)
          : const QuietHours(),
      categoryPreferences:
          (json['category_preferences'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(
                  k,
                  CategoryPreferences.fromJson(v as Map<String, dynamic>),
                ),
              ) ??
              {},
      pushToken: json['push_token'] as String?,
      email: json['email'] as String?,
      phoneNumber: json['phone_number'] as String?,
      whatsAppNumber: json['whatsapp_number'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  /// Create default preferences for a user
  factory NotificationPreferences.defaultFor(String userId) {
    return NotificationPreferences(
      userId: userId,
      globalEnabled: true,
      quietHours: const QuietHours(),
      categoryPreferences: {
        'booking': const CategoryPreferences(
          enabled: true,
          channels: {NotificationChannel.inApp, NotificationChannel.push},
        ),
        'payment': const CategoryPreferences(
          enabled: true,
          channels: {
            NotificationChannel.inApp,
            NotificationChannel.push,
            NotificationChannel.email,
          },
        ),
        'review': const CategoryPreferences(
          enabled: true,
          channels: {NotificationChannel.inApp, NotificationChannel.push},
        ),
        'promotion': const CategoryPreferences(
          enabled: true,
          channels: {NotificationChannel.inApp},
        ),
        'message': const CategoryPreferences(
          enabled: true,
          channels: {NotificationChannel.inApp, NotificationChannel.push},
        ),
        'system': const CategoryPreferences(
          enabled: true,
          channels: {NotificationChannel.inApp, NotificationChannel.push},
        ),
      },
      updatedAt: DateTime.now(),
    );
  }
}

/// Push token registration
class PushToken {
  const PushToken({
    required this.userId,
    required this.token,
    required this.platform,
    required this.deviceId,
    this.deviceName,
    this.createdAt,
    this.lastUsedAt,
    this.isActive = true,
  });

  final String userId;
  final String token;
  final String platform; // 'android', 'ios', 'web'
  final String deviceId;
  final String? deviceName;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
  final bool isActive;

  PushToken copyWith({
    String? userId,
    String? token,
    String? platform,
    String? deviceId,
    String? deviceName,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    bool? isActive,
  }) {
    return PushToken(
      userId: userId ?? this.userId,
      token: token ?? this.token,
      platform: platform ?? this.platform,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'token': token,
      'platform': platform,
      'device_id': deviceId,
      'device_name': deviceName,
      'created_at': createdAt?.toIso8601String(),
      'last_used_at': lastUsedAt?.toIso8601String(),
      'is_active': isActive,
    };
  }

  factory PushToken.fromJson(Map<String, dynamic> json) {
    return PushToken(
      userId: json['user_id'] as String,
      token: json['token'] as String,
      platform: json['platform'] as String,
      deviceId: json['device_id'] as String,
      deviceName: json['device_name'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      lastUsedAt: json['last_used_at'] != null
          ? DateTime.parse(json['last_used_at'] as String)
          : null,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
