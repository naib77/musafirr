import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/firebase_web_config.dart';
import 'config/supabase_config.dart';
import 'services/app_settings_service.dart';
import 'services/auth/supabase_auth_service.dart';
import 'services/notifications/firebase_push_notification_service.dart';
import 'services/notifications/push_notification_service.dart';
import 'services/notifications/web_push_notification_service.dart';

/// How long boot will wait on Firebase's platform channel before giving up and
/// starting the app without push. Firebase reads local config, so this should
/// never fire — but "should never" is not a reason to let a wedged channel hold
/// the splash screen indefinitely.
const Duration _firebaseInitTimeout = Duration(seconds: 8);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Locale data for Bangla date formatting in automated guest messages.
  await initializeDateFormatting('bn', null);

  await _setUpPushNotifications();

  // Initialize Supabase if configured
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );

    // Initialize Supabase auth service to listen for auth state changes
    SupabaseAuthService.instance.initialize();

    // Load admin-configurable flags (e.g. require_listing_address_proof) in the
    // background — the gate awaits this if it hasn't finished by listing time.
    AppSettingsService.instance.load();
  }

  runApp(const MusafirApp());
}

/// Registers a push-notification service and starts initialising it.
///
/// The service instance is registered synchronously so callers always have
/// one, but `initialize()` is deliberately NOT awaited: it shows the OS
/// permission dialog and then fetches an FCM token over the network. Awaiting
/// that before `runApp` makes booting the app depend on someone tapping
/// "Allow" — ignore the dialog, or be somewhere FCM cannot be reached, and the
/// app sits on its splash screen forever with nothing on screen to explain it.
/// Permission is better asked over a running app anyway.
Future<void> _setUpPushNotifications() async {
  if (!kIsWeb) {
    // Mobile: config comes from the native google-services.json / plist.
    try {
      await Firebase.initializeApp().timeout(_firebaseInitTimeout);
      debugPrint('[Main] Firebase initialized');

      final pushService = FirebasePushNotificationService.instance;
      PushNotificationServiceFactory.setInstance(pushService);
      _initializeInBackground(pushService);
    } catch (e) {
      debugPrint('[Main] Firebase initialization failed: $e');
      // Fall back to stub service
      PushNotificationServiceFactory.useStub();
    }
    return;
  }

  if (FirebaseWebConfig.isConfigured) {
    // Web: no native config file — pass the web FirebaseOptions explicitly and
    // use the web-only push service (getToken via VAPID + firebase-messaging-sw.js).
    try {
      await Firebase.initializeApp(options: FirebaseWebConfig.options)
          .timeout(_firebaseInitTimeout);
      debugPrint('[Main] Firebase (web) initialized');

      final pushService = WebPushNotificationService.instance;
      PushNotificationServiceFactory.setInstance(pushService);
      _initializeInBackground(pushService);
    } catch (e) {
      debugPrint('[Main] Web Firebase initialization failed: $e');
      PushNotificationServiceFactory.useStub();
    }
    return;
  }

  // Web push not configured yet — keep today's no-op stub behaviour.
  debugPrint('[Main] Web push not configured; using stub. '
      'See docs/web-push-setup.md');
  PushNotificationServiceFactory.useStub();
}

/// Fires `initialize()` and forgets it. Errors are logged, never rethrown: a
/// failed token fetch costs push notifications, not the app.
void _initializeInBackground(PushNotificationService service) {
  unawaited(
    service.initialize(const PushNotificationConfig()).then(
          (_) => debugPrint('[Main] Push notification service initialized'),
          onError: (Object e) => debugPrint('[Main] Push init failed: $e'),
        ),
  );
}
