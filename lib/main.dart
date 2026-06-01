import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/supabase_config.dart';
import 'services/auth/supabase_auth_service.dart';
import 'services/notifications/firebase_push_notification_service.dart';
import 'services/notifications/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (skip on web for now)
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
      debugPrint('[Main] Firebase initialized');

      // Initialize Firebase push notification service
      final pushService = FirebasePushNotificationService.instance;
      await pushService.initialize(const PushNotificationConfig());
      PushNotificationServiceFactory.setInstance(pushService);
      debugPrint('[Main] Push notification service initialized');
    } catch (e) {
      debugPrint('[Main] Firebase initialization failed: $e');
      // Fall back to stub service
      PushNotificationServiceFactory.useStub();
    }
  } else {
    // Use stub on web
    PushNotificationServiceFactory.useStub();
  }

  // Initialize Supabase if configured
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );

    // Initialize Supabase auth service to listen for auth state changes
    SupabaseAuthService.instance.initialize();
  }

  runApp(const MusafirApp());
}
