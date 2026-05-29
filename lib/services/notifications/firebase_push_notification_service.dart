import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../models/notification.dart';
import 'push_notification_service.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message: ${message.messageId}');
  // Note: Don't show notification here - FCM handles it automatically for data+notification messages
}

/// Firebase Cloud Messaging implementation of push notification service
class FirebasePushNotificationService implements PushNotificationService {
  FirebasePushNotificationService._();

  static FirebasePushNotificationService? _instance;
  static FirebasePushNotificationService get instance {
    _instance ??= FirebasePushNotificationService._();
    return _instance!;
  }

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final _tokenRefreshController = StreamController<String>.broadcast();
  final _foregroundNotificationController =
      StreamController<PushNotificationPayload>.broadcast();
  final _notificationTapController =
      StreamController<PushNotificationPayload>.broadcast();

  String? _token;
  PushPermissionStatus _permissionStatus = PushPermissionStatus.notDetermined;
  late PushNotificationConfig _config;
  bool _initialized = false;

  /// Android notification channel
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'musafir_notifications',
    'Musafir Notifications',
    description: 'Notifications from Musafir app',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  @override
  Future<void> initialize(PushNotificationConfig config) async {
    if (_initialized) return;

    _config = config;
    debugPrint('[FCM] Initializing Firebase Push Notification Service');

    // Set up background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Initialize local notifications for foreground
    await _initializeLocalNotifications();

    // Create notification channel (Android)
    if (!kIsWeb && Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    }

    // Request permission if configured
    if (config.requestPermissionOnInit) {
      await requestPermission();
    }

    // Get initial token
    _token = await _messaging.getToken();
    debugPrint('[FCM] Token: $_token');

    // Listen for token refresh
    _messaging.onTokenRefresh.listen((token) {
      _token = token;
      debugPrint('[FCM] Token refreshed: $token');
      _tokenRefreshController.add(token);
    });

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification taps when app is in background/terminated
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Check for initial message (app opened from terminated state via notification)
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      // Delay slightly to ensure app is fully initialized
      Future.delayed(const Duration(milliseconds: 500), () {
        _handleNotificationTap(initialMessage);
      });
    }

    _initialized = true;
    debugPrint('[FCM] Initialization complete');
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('[FCM] Local notification tapped: ${response.payload}');
        // Parse payload and emit tap event
        if (response.payload != null) {
          _notificationTapController.add(
            PushNotificationPayload(
              title: '',
              body: '',
              data: {'action_url': response.payload},
            ),
          );
        }
      },
    );
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[FCM] Foreground message: ${message.messageId}');
    debugPrint('[FCM] Title: ${message.notification?.title}');
    debugPrint('[FCM] Body: ${message.notification?.body}');
    debugPrint('[FCM] Data: ${message.data}');

    final payload = PushNotificationPayload(
      title: message.notification?.title,
      body: message.notification?.body,
      data: message.data,
      imageUrl: message.notification?.android?.imageUrl ??
          message.notification?.apple?.imageUrl,
    );

    _foregroundNotificationController.add(payload);

    // Show local notification if configured
    if (_config.showForegroundNotifications) {
      _showLocalNotification(message);
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('[FCM] Notification tapped: ${message.messageId}');

    final payload = PushNotificationPayload(
      title: message.notification?.title,
      body: message.notification?.body,
      data: message.data,
      imageUrl: message.notification?.android?.imageUrl ??
          message.notification?.apple?.imageUrl,
    );

    _notificationTapController.add(payload);
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      details,
      payload: message.data['action_url'] as String?,
    );
  }

  @override
  Future<PushPermissionStatus> requestPermission() async {
    debugPrint('[FCM] Requesting permission');

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
    );

    _permissionStatus = _mapAuthorizationStatus(settings.authorizationStatus);
    debugPrint('[FCM] Permission status: $_permissionStatus');

    return _permissionStatus;
  }

  @override
  Future<PushPermissionStatus> getPermissionStatus() async {
    final settings = await _messaging.getNotificationSettings();
    _permissionStatus = _mapAuthorizationStatus(settings.authorizationStatus);
    return _permissionStatus;
  }

  PushPermissionStatus _mapAuthorizationStatus(AuthorizationStatus status) {
    switch (status) {
      case AuthorizationStatus.authorized:
        return PushPermissionStatus.granted;
      case AuthorizationStatus.denied:
        return PushPermissionStatus.denied;
      case AuthorizationStatus.notDetermined:
        return PushPermissionStatus.notDetermined;
      case AuthorizationStatus.provisional:
        return PushPermissionStatus.provisional;
    }
  }

  @override
  Future<String?> getToken() async {
    _token ??= await _messaging.getToken();
    debugPrint('[FCM] Token: $_token');
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
    await _messaging.subscribeToTopic(topic);
    debugPrint('[FCM] Subscribed to topic: $topic');
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    await _messaging.unsubscribeFromTopic(topic);
    debugPrint('[FCM] Unsubscribed from topic: $topic');
  }

  @override
  Future<void> deleteToken() async {
    await _messaging.deleteToken();
    _token = null;
    debugPrint('[FCM] Token deleted');
  }

  @override
  void dispose() {
    _tokenRefreshController.close();
    _foregroundNotificationController.close();
    _notificationTapController.close();
  }
}
