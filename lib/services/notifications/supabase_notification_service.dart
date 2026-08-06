import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../models/notification.dart';
import '../../models/notification_preferences.dart';
import 'notification_service.dart';

/// Supabase-backed implementation of [NotificationService].
///
/// Uses Supabase Realtime for live notification updates.
class SupabaseNotificationService implements NotificationService {
  SupabaseNotificationService._();

  static SupabaseNotificationService? _instance;
  static SupabaseNotificationService get instance {
    _instance ??= SupabaseNotificationService._();
    return _instance!;
  }

  SupabaseClient get _client => Supabase.instance.client;

  // Stream controllers for real-time updates
  final Map<String, StreamController<AppNotification>> _notificationStreams =
      {};
  final Map<String, StreamController<int>> _unreadCountStreams = {};

  // Realtime subscriptions
  final Map<String, RealtimeChannel> _channels = {};

  // ============================================================
  // NOTIFICATION CRUD
  // ============================================================

  @override
  Future<List<AppNotification>> getNotifications(
    String userId, {
    NotificationFilter? filter,
  }) async {
    try {
      var query = _client
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .neq('status', 'deleted');

      // Apply filters
      if (filter?.types != null && filter!.types!.isNotEmpty) {
        query =
            query.inFilter('type', filter.types!.map((t) => t.name).toList());
      }
      if (filter?.status != null) {
        query = query.eq('status', filter!.status!.name);
      }
      if (filter?.priority != null) {
        // Filter by priority level or higher
        final priorities = NotificationPriority.values
            .where((p) => p.index >= filter!.priority!.index)
            .map((p) => p.name)
            .toList();
        query = query.inFilter('priority', priorities);
      }
      if (filter?.startDate != null) {
        query = query.gte('created_at', filter!.startDate!.toIso8601String());
      }
      if (filter?.endDate != null) {
        query = query.lte('created_at', filter!.endDate!.toIso8601String());
      }

      // Apply ordering and pagination (these return PostgrestTransformBuilder)
      var orderedQuery = query.order('created_at', ascending: false);

      // Apply pagination
      if (filter?.limit != null) {
        final offset = filter?.offset ?? 0;
        orderedQuery = orderedQuery.range(offset, offset + filter!.limit! - 1);
      }

      final response = await orderedQuery;
      return (response as List)
          .map((json) => _notificationFromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
      return [];
    }
  }

  @override
  Future<AppNotification?> getNotification(String notificationId) async {
    try {
      final response = await _client
          .from('notifications')
          .select()
          .eq('id', notificationId)
          .maybeSingle();

      if (response == null) return null;
      return _notificationFromJson(response);
    } catch (e) {
      debugPrint('Error fetching notification: $e');
      return null;
    }
  }

  @override
  Future<NotificationResult> createNotification(
    AppNotification notification,
  ) async {
    try {
      final response = await _client
          .from('notifications')
          .insert(_notificationToJson(notification))
          .select()
          .single();

      final created = _notificationFromJson(response);

      // Emit to local streams (Realtime will also emit, but this ensures immediate feedback)
      _emitNotification(notification.userId, created);
      _emitUnreadCount(notification.userId);

      return NotificationResult.success(created);
    } catch (e) {
      debugPrint('Error creating notification: $e');
      return NotificationResult.failure('Failed to create notification: $e');
    }
  }

  @override
  Future<NotificationResult> markAsRead(String notificationId) async {
    try {
      final response = await _client
          .from('notifications')
          .update({
            'status': 'read',
            'read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', notificationId)
          .select()
          .single();

      final updated = _notificationFromJson(response);
      _emitUnreadCount(updated.userId);

      return NotificationResult.success(updated);
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
      return NotificationResult.failure('Failed to mark as read: $e');
    }
  }

  @override
  Future<int> markAllAsRead(String userId) async {
    try {
      // Use RPC function for efficiency
      final result = await _client.rpc(
        'mark_all_notifications_read',
        params: {'p_user_id': userId},
      );

      final count = result as int? ?? 0;
      _emitUnreadCount(userId);

      return count;
    } catch (e) {
      debugPrint('Error marking all as read: $e');
      return 0;
    }
  }

  @override
  Future<NotificationResult> archiveNotification(String notificationId) async {
    try {
      final response = await _client
          .from('notifications')
          .update({'status': 'archived'})
          .eq('id', notificationId)
          .select()
          .single();

      return NotificationResult.success(_notificationFromJson(response));
    } catch (e) {
      debugPrint('Error archiving notification: $e');
      return NotificationResult.failure('Failed to archive: $e');
    }
  }

  @override
  Future<bool> deleteNotification(String notificationId) async {
    try {
      // Soft delete by setting status
      await _client
          .from('notifications')
          .update({'status': 'deleted'}).eq('id', notificationId);

      return true;
    } catch (e) {
      debugPrint('Error deleting notification: $e');
      return false;
    }
  }

  @override
  Future<int> deleteAllNotifications(String userId) async {
    try {
      final result = await _client
          .from('notifications')
          .update({'status': 'deleted'})
          .eq('user_id', userId)
          .neq('status', 'deleted')
          .select('id');

      final count = (result as List).length;
      _emitUnreadCount(userId);

      return count;
    } catch (e) {
      debugPrint('Error deleting all notifications: $e');
      return 0;
    }
  }

  @override
  Future<int> getUnreadCount(String userId) async {
    try {
      // Use RPC function for efficiency
      final result = await _client.rpc(
        'get_unread_notification_count',
        params: {'p_user_id': userId},
      );

      return result as int? ?? 0;
    } catch (e) {
      debugPrint('Error getting unread count: $e');
      return 0;
    }
  }

  // ============================================================
  // PREFERENCES
  // ============================================================

  @override
  Future<NotificationPreferences?> getPreferences(String userId) async {
    try {
      final response = await _client
          .from('notification_preferences')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) return null;
      return _preferencesFromJson(response);
    } catch (e) {
      debugPrint('Error fetching preferences: $e');
      return null;
    }
  }

  @override
  Future<bool> savePreferences(NotificationPreferences preferences) async {
    try {
      await _client.from('notification_preferences').upsert(
            _preferencesToJson(preferences),
            onConflict: 'user_id',
          );

      return true;
    } catch (e) {
      debugPrint('Error saving preferences: $e');
      return false;
    }
  }

  // ============================================================
  // PUSH TOKENS
  // ============================================================

  @override
  Future<bool> registerPushToken(PushToken token) async {
    try {
      await _client.from('push_tokens').upsert(
        {
          'user_id': token.userId,
          'token': token.token,
          'platform': token.platform,
          'device_id': token.deviceId,
          'device_name': token.deviceName,
          'is_active': true,
          'last_used_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,device_id',
      );

      debugPrint('Push token registered for device: ${token.deviceId}');
      return true;
    } catch (e) {
      debugPrint('Error registering push token: $e');
      return false;
    }
  }

  @override
  Future<bool> unregisterPushToken(String deviceId, String userId) async {
    try {
      await _client
          .from('push_tokens')
          .update({'is_active': false})
          .eq('user_id', userId)
          .eq('device_id', deviceId);

      return true;
    } catch (e) {
      debugPrint('Error unregistering push token: $e');
      return false;
    }
  }

  // ============================================================
  // REALTIME SUBSCRIPTIONS
  // ============================================================

  @override
  Stream<AppNotification> subscribeToNotifications(String userId) {
    _notificationStreams[userId] ??=
        StreamController<AppNotification>.broadcast();

    // Set up Supabase Realtime subscription if not already active
    _setupRealtimeSubscription(userId);

    return _notificationStreams[userId]!.stream;
  }

  @override
  Stream<int> subscribeToUnreadCount(String userId) {
    _unreadCountStreams[userId] ??= StreamController<int>.broadcast();

    // Emit current count immediately
    getUnreadCount(userId).then((count) {
      if (_unreadCountStreams[userId] != null &&
          !_unreadCountStreams[userId]!.isClosed) {
        _unreadCountStreams[userId]!.add(count);
      }
    });

    // Set up Supabase Realtime subscription if not already active
    _setupRealtimeSubscription(userId);

    return _unreadCountStreams[userId]!.stream;
  }

  void _setupRealtimeSubscription(String userId) {
    final channelName = 'notifications:$userId';

    // Don't create duplicate subscriptions
    if (_channels.containsKey(channelName)) return;

    final channel = _client.channel(channelName);

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            _handleRealtimeInsert(userId, payload.newRecord);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            _handleRealtimeUpdate(userId, payload.newRecord);
          },
        )
        .subscribe();

    _channels[channelName] = channel;
    debugPrint('Realtime subscription active for user: $userId');
  }

  void _handleRealtimeInsert(String userId, Map<String, dynamic> record) {
    try {
      final notification = _notificationFromJson(record);
      _emitNotification(userId, notification);
      _emitUnreadCount(userId);

      debugPrint('Realtime: New notification received - ${notification.title}');
    } catch (e) {
      debugPrint('Error handling realtime insert: $e');
    }
  }

  void _handleRealtimeUpdate(String userId, Map<String, dynamic> record) {
    try {
      final notification = _notificationFromJson(record);
      _emitNotification(userId, notification);
      _emitUnreadCount(userId);
    } catch (e) {
      debugPrint('Error handling realtime update: $e');
    }
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

  /// Unsubscribe from realtime updates for a user
  void unsubscribe(String userId) {
    final channelName = 'notifications:$userId';
    final channel = _channels.remove(channelName);
    channel?.unsubscribe();

    _notificationStreams[userId]?.close();
    _notificationStreams.remove(userId);

    _unreadCountStreams[userId]?.close();
    _unreadCountStreams.remove(userId);

    debugPrint('Unsubscribed from notifications for user: $userId');
  }

  @override
  void dispose() {
    // Close all channels
    for (final channel in _channels.values) {
      channel.unsubscribe();
    }
    _channels.clear();

    // Close all stream controllers
    for (final controller in _notificationStreams.values) {
      controller.close();
    }
    _notificationStreams.clear();

    for (final controller in _unreadCountStreams.values) {
      controller.close();
    }
    _unreadCountStreams.clear();
  }

  // ============================================================
  // JSON CONVERSION
  // ============================================================

  AppNotification _notificationFromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: _notificationTypeFromString(json['type'] as String?),
      title: json['title'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      status: _notificationStatusFromString(json['status'] as String?),
      priority: _notificationPriorityFromString(json['priority'] as String?),
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

  Map<String, dynamic> _notificationToJson(AppNotification notification) {
    return {
      'user_id': notification.userId,
      'type': _camelToSnake(notification.type.name),
      'title': notification.title,
      'body': notification.body,
      'status': notification.status.name,
      'priority': notification.priority.name,
      'data': notification.data,
      'image_url': notification.imageUrl,
      'action_url': notification.actionUrl,
      'group_key': notification.groupKey,
      'expires_at': notification.expiresAt?.toIso8601String(),
    };
  }

  /// Convert camelCase to snake_case
  String _camelToSnake(String input) {
    return input.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    );
  }

  NotificationType _notificationTypeFromString(String? value) {
    if (value == null) return NotificationType.systemAlert;
    // Handle snake_case from database (e.g., 'booking_request' -> 'bookingRequest')
    final normalizedValue = _snakeToCamel(value);
    return NotificationType.values.firstWhere(
      (t) => t.name == normalizedValue || t.name == value,
      orElse: () => NotificationType.systemAlert,
    );
  }

  /// Convert snake_case to camelCase
  String _snakeToCamel(String input) {
    final parts = input.split('_');
    if (parts.length == 1) return input;
    return parts.first +
        parts
            .skip(1)
            .map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1))
            .join();
  }

  NotificationStatus _notificationStatusFromString(String? value) {
    if (value == null) return NotificationStatus.unread;
    return NotificationStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => NotificationStatus.unread,
    );
  }

  NotificationPriority _notificationPriorityFromString(String? value) {
    if (value == null) return NotificationPriority.normal;
    return NotificationPriority.values.firstWhere(
      (p) => p.name == value,
      orElse: () => NotificationPriority.normal,
    );
  }

  NotificationPreferences _preferencesFromJson(Map<String, dynamic> json) {
    // Parse category preferences from JSONB
    Map<String, CategoryPreferences> categoryPrefs = {};
    if (json['category_preferences'] != null) {
      final catJson = json['category_preferences'] as Map<String, dynamic>;
      categoryPrefs = catJson.map(
        (k, v) => MapEntry(
            k, CategoryPreferences.fromJson(v as Map<String, dynamic>)),
      );
    }

    // Parse quiet hours
    QuietHours quietHours = const QuietHours();
    if (json['quiet_hours_enabled'] == true) {
      quietHours = QuietHours(
        enabled: true,
        startTime: _parseTime(json['quiet_hours_start'] as String?),
        endTime: _parseTime(json['quiet_hours_end'] as String?),
        allowUrgent: json['quiet_hours_allow_urgent'] as bool? ?? true,
      );
    }

    return NotificationPreferences(
      userId: json['user_id'] as String,
      globalEnabled: json['global_enabled'] as bool? ?? true,
      quietHours: quietHours,
      categoryPreferences: categoryPrefs,
      email: json['email'] as String?,
      phoneNumber: json['phone_number'] as String?,
      whatsAppNumber: json['whatsapp_number'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> _preferencesToJson(NotificationPreferences prefs) {
    return {
      'user_id': prefs.userId,
      'global_enabled': prefs.globalEnabled,
      'quiet_hours_enabled': prefs.quietHours.enabled,
      'quiet_hours_start':
          '${prefs.quietHours.startTime.hour.toString().padLeft(2, '0')}:${prefs.quietHours.startTime.minute.toString().padLeft(2, '0')}',
      'quiet_hours_end':
          '${prefs.quietHours.endTime.hour.toString().padLeft(2, '0')}:${prefs.quietHours.endTime.minute.toString().padLeft(2, '0')}',
      'quiet_hours_allow_urgent': prefs.quietHours.allowUrgent,
      'category_preferences': prefs.categoryPreferences.map(
        (k, v) => MapEntry(k, v.toJson()),
      ),
      'email': prefs.email,
      'phone_number': prefs.phoneNumber,
      'whatsapp_number': prefs.whatsAppNumber,
    };
  }

  TimeOfDay _parseTime(String? timeStr) {
    if (timeStr == null) return const TimeOfDay(hour: 22, minute: 0);
    final parts = timeStr.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 22,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
  }
}
