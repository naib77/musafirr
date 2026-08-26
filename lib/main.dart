import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/firebase_web_config.dart';
import 'config/supabase_config.dart';
import 'core/theme/theme_controller.dart';
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

  _useAndroidPhotoPicker();

  // Locale data for Bangla date formatting in automated guest messages.
  await initializeDateFormatting('bn', null);

  // Paint the theme the admin had chosen as of the last launch, from the local
  // cache. Awaited — unlike the settings load below — because it is a local read
  // with its own timeout, and the alternative is a visible flash of the default
  // palette on every single start. See ThemeController for why the cache exists.
  await ThemeController.instance.hydrate();

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
    //
    // The theme is confirmed off the back of it: load() swallows its own errors,
    // so this always runs, and adopt(null) is the correct outcome of a failed
    // load anyway (fall back to the default palette). This is also what corrects
    // the cached theme after an admin has changed it.
    unawaited(
      AppSettingsService.instance.load().then(
            (_) => ThemeController.instance
                .adopt(AppSettingsService.instance.activeThemeId),
          ),
    );
  }

  runApp(const MusafirApp());
}

/// Routes gallery picks through the Android Photo Picker instead of
/// ACTION_GET_CONTENT.
///
/// This is a Play policy decision, not a UX one. `useAndroidPhotoPicker`
/// defaults to false, and the fallback path needs READ_MEDIA_IMAGES — broad
/// access to the user's whole library, which puts the app under Play's Photo and
/// Video Permissions policy and a declaration Google only grants where that
/// breadth is core to the app. The Photo Picker returns a per-URI grant for just
/// the images the user tapped, so the permission disappears from
/// AndroidManifest.xml entirely.
///
/// Must run before the first pick. Called from `main` rather than lazily in
/// ImageUploadService because the platform instance is process-global and
/// setting it twice from different call sites is how this silently regresses.
void _useAndroidPhotoPicker() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  final platform = ImagePickerPlatform.instance;
  if (platform is ImagePickerAndroid) {
    platform.useAndroidPhotoPicker = true;
  }
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
