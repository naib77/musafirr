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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Locale data for Bangla date formatting in automated guest messages.
  await initializeDateFormatting('bn', null);

  // Initialize Firebase push notifications.
  if (!kIsWeb) {
    // Mobile: config comes from the native google-services.json / plist.
    try {
      await Firebase.initializeApp();
      debugPrint('[Main] Firebase initialized');

      final pushService = FirebasePushNotificationService.instance;
      await pushService.initialize(const PushNotificationConfig());
      PushNotificationServiceFactory.setInstance(pushService);
      debugPrint('[Main] Push notification service initialized');
    } catch (e) {
      debugPrint('[Main] Firebase initialization failed: $e');
      // Fall back to stub service
      PushNotificationServiceFactory.useStub();
    }
  } else if (FirebaseWebConfig.isConfigured) {
    // Web: no native config file — pass the web FirebaseOptions explicitly and
    // use the web-only push service (getToken via VAPID + firebase-messaging-sw.js).
    try {
      await Firebase.initializeApp(options: FirebaseWebConfig.options);
      debugPrint('[Main] Firebase (web) initialized');

      final pushService = WebPushNotificationService.instance;
      await pushService.initialize(const PushNotificationConfig());
      PushNotificationServiceFactory.setInstance(pushService);
      debugPrint('[Main] Web push notification service initialized');
    } catch (e) {
      debugPrint('[Main] Web Firebase initialization failed: $e');
      PushNotificationServiceFactory.useStub();
    }
  } else {
    // Web push not configured yet — keep today's no-op stub behaviour.
    debugPrint('[Main] Web push not configured; using stub. '
        'See docs/web-push-setup.md');
    PushNotificationServiceFactory.useStub();
  }

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
