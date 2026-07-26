import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../config/firebase_web_config.dart';
import 'push_notification_service.dart';

/// Firebase Cloud Messaging implementation for **Flutter web**.
///
/// Deliberately does NOT import `dart:io` or `flutter_local_notifications`
/// (neither exists on web) — it relies only on `firebase_messaging`, whose web
/// backend (`firebase_messaging_web`) implements `getToken`, `onMessage` and
/// permission handling on top of the browser Push API + the service worker at
/// `web/firebase-messaging-sw.js`.
///
/// Division of labour on web:
///  - **Background / tab-closed** notifications are shown by the service
///    worker's `onBackgroundMessage` (OS-level popup). This class isn't even
///    running then.
///  - **Foreground** messages arrive via [FirebaseMessaging.onMessage]; the
///    browser suppresses the OS popup for these, so we forward them to
///    [onForegroundNotification] and the app surfaces its in-app toast (same
///    path the realtime channel already uses).
class WebPushNotificationService implements PushNotificationService {
  WebPushNotificationService._();

  static WebPushNotificationService? _instance;
  static WebPushNotificationService get instance =>
      _instance ??= WebPushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  final _tokenRefreshController = StreamController<String>.broadcast();
  final _foregroundNotificationController =
      StreamController<PushNotificationPayload>.broadcast();
  final _notificationTapController =
      StreamController<PushNotificationPayload>.broadcast();

  String? _token;
  PushPermissionStatus _permissionStatus = PushPermissionStatus.notDetermined;
  bool _initialized = false;

  @override
  Future<void> initialize(PushNotificationConfig config) async {
    if (_initialized) return;
    debugPrint('[FCM-web] Initializing web push service');

    if (config.requestPermissionOnInit) {
      await requestPermission();
    }

    // Foreground messages: the browser does not raise an OS notification for
    // these while the tab is focused, so forward them to the in-app toast.
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // A notification click that brings the PWA to the foreground.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    _token = await _safeGetToken();
    debugPrint('[FCM-web] Token: $_token');

    _messaging.onTokenRefresh.listen((token) {
      _token = token;
      debugPrint('[FCM-web] Token refreshed');
      _tokenRefreshController.add(token);
    });

    _initialized = true;
    debugPrint('[FCM-web] Initialization complete');
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[FCM-web] Foreground message: ${message.messageId}');
    _foregroundNotificationController.add(
      PushNotificationPayload(
        title: message.notification?.title,
        body: message.notification?.body,
        data: message.data,
        imageUrl: message.notification?.web?.image,
      ),
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('[FCM-web] Notification tapped: ${message.messageId}');
    _notificationTapController.add(
      PushNotificationPayload(
        title: message.notification?.title,
        body: message.notification?.body,
        data: message.data,
        imageUrl: message.notification?.web?.image,
      ),
    );
  }

  /// Web `getToken` needs the VAPID key and can throw if the service worker
  /// isn't registered yet or permission was denied — never let that break app
  /// startup.
  Future<String?> _safeGetToken() async {
    try {
      return await _messaging.getToken(vapidKey: FirebaseWebConfig.vapidKey);
    } catch (e) {
      debugPrint('[FCM-web] getToken failed: $e');
      return null;
    }
  }

  @override
  Future<PushPermissionStatus> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    _permissionStatus = _map(settings.authorizationStatus);
    debugPrint('[FCM-web] Permission status: $_permissionStatus');
    return _permissionStatus;
  }

  @override
  Future<PushPermissionStatus> getPermissionStatus() async {
    final settings = await _messaging.getNotificationSettings();
    _permissionStatus = _map(settings.authorizationStatus);
    return _permissionStatus;
  }

  PushPermissionStatus _map(AuthorizationStatus status) {
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
    _token ??= await _safeGetToken();
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
    // Topic subscriptions aren't supported by the FCM JS SDK from the client;
    // this app targets tokens directly, so this is a no-op on web.
    debugPrint('[FCM-web] subscribeToTopic is a no-op on web ($topic)');
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    debugPrint('[FCM-web] unsubscribeFromTopic is a no-op on web ($topic)');
  }

  @override
  Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('[FCM-web] deleteToken failed: $e');
    }
    _token = null;
  }

  @override
  void dispose() {
    _tokenRefreshController.close();
    _foregroundNotificationController.close();
    _notificationTapController.close();
  }
}
