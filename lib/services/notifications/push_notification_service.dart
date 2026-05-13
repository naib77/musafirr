import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/notification.dart';

/// Configuration for push notifications
class PushNotificationConfig {
  const PushNotificationConfig({
    this.requestPermissionOnInit = true,
    this.showForegroundNotifications = true,
    this.defaultIcon,
    this.defaultChannelId = 'default',
    this.defaultChannelName = 'Default',
    this.defaultChannelDescription = 'Default notification channel',
  });

  /// Whether to request permission when initializing
  final bool requestPermissionOnInit;

  /// Whether to show notifications when app is in foreground
  final bool showForegroundNotifications;

  /// Default notification icon (Android)
  final String? defaultIcon;

  /// Default channel ID (Android)
  final String defaultChannelId;

  /// Default channel name (Android)
  final String defaultChannelName;

  /// Default channel description (Android)
  final String defaultChannelDescription;
}

/// Permission status for push notifications
enum PushPermissionStatus {
  granted,
  denied,
  notDetermined,
  provisional,
}

/// Payload received from a push notification
class PushNotificationPayload {
  const PushNotificationPayload({
    this.title,
    this.body,
    this.data,
    this.imageUrl,
  });

  final String? title;
  final String? body;
  final Map<String, dynamic>? data;
  final String? imageUrl;

  /// Extract notification type from payload
  NotificationType? get notificationType {
    final typeStr = data?['type'] as String?;
    if (typeStr == null) return null;

    try {
      return NotificationType.values.firstWhere(
        (t) => t.name == typeStr,
      );
    } catch (_) {
      return null;
    }
  }

  /// Extract action URL from payload
  String? get actionUrl => data?['action_url'] as String?;

  /// Extract notification ID from payload
  String? get notificationId => data?['notification_id'] as String?;

  factory PushNotificationPayload.fromMap(Map<String, dynamic> map) {
    return PushNotificationPayload(
      title: map['title'] as String? ?? map['notification']?['title'] as String?,
      body: map['body'] as String? ?? map['notification']?['body'] as String?,
      data: map['data'] as Map<String, dynamic>? ?? map,
      imageUrl: map['image'] as String? ?? map['notification']?['image'] as String?,
    );
  }
}

/// Abstract interface for push notification service
abstract class PushNotificationService {
  /// Initialize the push notification service
  Future<void> initialize(PushNotificationConfig config);

  /// Request notification permissions
  Future<PushPermissionStatus> requestPermission();

  /// Get current permission status
  Future<PushPermissionStatus> getPermissionStatus();

  /// Get the FCM token for this device
  Future<String?> getToken();

  /// Subscribe to token refresh events
  Stream<String> get onTokenRefresh;

  /// Subscribe to foreground notifications
  Stream<PushNotificationPayload> get onForegroundNotification;

  /// Subscribe to notification tap events
  Stream<PushNotificationPayload> get onNotificationTap;

  /// Subscribe to a topic
  Future<void> subscribeToTopic(String topic);

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic);

  /// Delete the FCM token (for logout)
  Future<void> deleteToken();

  /// Dispose resources
  void dispose();
}

/// Stub implementation for development without Firebase
class StubPushNotificationService implements PushNotificationService {
  StubPushNotificationService._();

  static StubPushNotificationService? _instance;
  static StubPushNotificationService get instance {
    _instance ??= StubPushNotificationService._();
    return _instance!;
  }

  final _tokenRefreshController = StreamController<String>.broadcast();
  final _foregroundNotificationController = StreamController<PushNotificationPayload>.broadcast();
  final _notificationTapController = StreamController<PushNotificationPayload>.broadcast();

  String? _token;
  PushPermissionStatus _permissionStatus = PushPermissionStatus.notDetermined;
  final Set<String> _subscribedTopics = {};

  @override
  Future<void> initialize(PushNotificationConfig config) async {
    debugPrint('📱 [Stub] Push notification service initialized');

    // Generate a fake token
    _token = 'stub_fcm_token_${DateTime.now().millisecondsSinceEpoch}';

    if (config.requestPermissionOnInit) {
      await requestPermission();
    }
  }

  @override
  Future<PushPermissionStatus> requestPermission() async {
    // Simulate permission request delay
    await Future.delayed(const Duration(milliseconds: 500));

    _permissionStatus = PushPermissionStatus.granted;
    debugPrint('📱 [Stub] Push notification permission granted');

    return _permissionStatus;
  }

  @override
  Future<PushPermissionStatus> getPermissionStatus() async {
    return _permissionStatus;
  }

  @override
  Future<String?> getToken() async {
    debugPrint('📱 [Stub] FCM Token: $_token');
    return _token;
  }

  @override
  Stream<String> get onTokenRefresh => _tokenRefreshController.stream;

  @override
  Stream<PushNotificationPayload> get onForegroundNotification =>
      _foregroundNotificationController.stream;

  @override
  Stream<PushNotificationPayload> get onNotificationTap =>
      _notificationTapController.stream;

  @override
  Future<void> subscribeToTopic(String topic) async {
    _subscribedTopics.add(topic);
    debugPrint('📱 [Stub] Subscribed to topic: $topic');
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    _subscribedTopics.remove(topic);
    debugPrint('📱 [Stub] Unsubscribed from topic: $topic');
  }

  @override
  Future<void> deleteToken() async {
    _token = null;
    debugPrint('📱 [Stub] FCM token deleted');
  }

  @override
  void dispose() {
    _tokenRefreshController.close();
    _foregroundNotificationController.close();
    _notificationTapController.close();
  }

  // ============================================================
  // TEST HELPERS
  // ============================================================

  /// Simulate receiving a foreground notification (for testing)
  void simulateForegroundNotification(PushNotificationPayload payload) {
    debugPrint('📱 [Stub] Simulating foreground notification: ${payload.title}');
    _foregroundNotificationController.add(payload);
  }

  /// Simulate a notification tap (for testing)
  void simulateNotificationTap(PushNotificationPayload payload) {
    debugPrint('📱 [Stub] Simulating notification tap: ${payload.title}');
    _notificationTapController.add(payload);
  }

  /// Simulate token refresh (for testing)
  void simulateTokenRefresh() {
    _token = 'stub_fcm_token_${DateTime.now().millisecondsSinceEpoch}';
    debugPrint('📱 [Stub] Token refreshed: $_token');
    _tokenRefreshController.add(_token!);
  }

  /// Get subscribed topics (for testing)
  Set<String> get subscribedTopics => Set.unmodifiable(_subscribedTopics);
}

/// Factory to get the appropriate push notification service
class PushNotificationServiceFactory {
  PushNotificationServiceFactory._();

  static PushNotificationService? _instance;

  /// Get the push notification service instance
  ///
  /// In production, this would return FirebasePushNotificationService.
  /// For now, it returns the stub implementation.
  static PushNotificationService get instance {
    _instance ??= StubPushNotificationService.instance;
    return _instance!;
  }

  /// Set a custom instance (for testing or switching implementations)
  static void setInstance(PushNotificationService service) {
    _instance = service;
  }
}

/// Helper class for handling notification deep links
class NotificationDeepLinkHandler {
  NotificationDeepLinkHandler._();

  /// Parse action URL and return navigation parameters
  static DeepLinkResult? parseActionUrl(String? actionUrl) {
    if (actionUrl == null || actionUrl.isEmpty) return null;

    // Parse the URL path
    final uri = Uri.tryParse(actionUrl);
    if (uri == null) return null;

    final pathSegments = uri.pathSegments;
    if (pathSegments.isEmpty) return null;

    switch (pathSegments.first) {
      case 'trips':
        return DeepLinkResult(
          route: '/trips',
          arguments: pathSegments.length > 1 ? {'bookingId': pathSegments[1]} : null,
        );
      case 'host':
        if (pathSegments.length > 1 && pathSegments[1] == 'reservations') {
          return DeepLinkResult(
            route: '/host/reservations',
            arguments: pathSegments.length > 2 ? {'bookingId': pathSegments[2]} : null,
          );
        }
        return DeepLinkResult(route: '/host');
      case 'messages':
        return DeepLinkResult(
          route: '/messages',
          arguments: pathSegments.length > 1 ? {'conversationId': pathSegments[1]} : null,
        );
      case 'explore':
        return DeepLinkResult(route: '/explore');
      case 'profile':
        return DeepLinkResult(
          route: '/profile',
          arguments: pathSegments.length > 1 ? {'section': pathSegments[1]} : null,
        );
      case 'listings':
        return DeepLinkResult(
          route: '/listings',
          arguments: pathSegments.length > 1 ? {'listingId': pathSegments[1]} : null,
        );
      case 'review':
        return DeepLinkResult(
          route: '/review',
          arguments: pathSegments.length > 1 ? {'bookingId': pathSegments[1]} : null,
        );
      default:
        return DeepLinkResult(route: '/${pathSegments.first}');
    }
  }
}

/// Result of parsing a deep link
class DeepLinkResult {
  const DeepLinkResult({
    required this.route,
    this.arguments,
  });

  final String route;
  final Map<String, dynamic>? arguments;

  @override
  String toString() => 'DeepLinkResult(route: $route, arguments: $arguments)';
}
