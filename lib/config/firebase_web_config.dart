import 'package:firebase_core/firebase_core.dart';

/// Firebase **web** configuration for FCM web push.
///
/// Mobile (Android/iOS) reads its Firebase config from the native
/// `google-services.json` / `GoogleService-Info.plist`. The web build has no
/// such file, so the values below are the web equivalent — they come from
/// registering a **Web app** in the Firebase console.
///
/// ── HOW TO FILL THIS IN (one-time) ────────────────────────────────────────
/// Firebase console (project `musafir-200107`):
///   1. Project settings → General → Your apps → **Add app → Web (</>)**.
///      Register it (e.g. "Musaafir Web"). Copy the `firebaseConfig` values into
///      [options] below — [apiKey] and [appId] are the two that are still
///      placeholders here (the rest are already filled from the Android config).
///   2. Project settings → **Cloud Messaging** → "Web configuration" →
///      **Web Push certificates** → *Generate key pair*. Copy that public key
///      into [vapidKey].
///   3. Mirror the same six [options] values into
///      `web/firebase-messaging-sw.js` (plain JS — it can't import this file).
///
/// Until every `REPLACE_WITH_*` below is replaced, [isConfigured] is false and
/// the app falls back to the no-op stub on web (exactly today's behaviour — no
/// crash, just no web push). See `docs/web-push-setup.md`.
class FirebaseWebConfig {
  FirebaseWebConfig._();

  /// Values prefixed `REPLACE_WITH_` are unfilled placeholders. Keep this
  /// sentinel in sync with [isConfigured].
  static const String _placeholderPrefix = 'REPLACE_WITH_';

  /// Web Firebase options. `projectId`, `messagingSenderId`, `storageBucket`
  /// and `authDomain` are already correct for project `musafir-200107`; only
  /// `apiKey` and `appId` need the web-app values from step 1 above.
  static const FirebaseOptions options = FirebaseOptions(
    apiKey: 'AIzaSyD3jQPcuZPkR1ueTcEVz9qq539ykttkFEs',
    appId: '1:814163045663:web:b163b2216d65bb9bfd542a',
    messagingSenderId: '814163045663',
    projectId: 'musafir-200107',
    authDomain: 'musafir-200107.firebaseapp.com',
    storageBucket: 'musafir-200107.firebasestorage.app',
  );

  /// Web Push certificate public key ("VAPID key") from step 2. Required by
  /// `FirebaseMessaging.getToken(vapidKey: ...)` on web — without it the token
  /// request throws.
  static const String vapidKey =
      'BCt2NBAdEBrpdB0wRIWkRsE9VmRJcQYphy6oluqlCTMkFzZtabTBmPMIWSaMfBvfRo9FDw7gNkXKyw96jPQnRXQ';

  /// True only once the placeholders have been replaced with real values.
  /// Gates web-push initialisation so an unconfigured build cleanly degrades to
  /// the stub instead of throwing at `Firebase.initializeApp`.
  static bool get isConfigured =>
      !options.apiKey.startsWith(_placeholderPrefix) &&
      !options.appId.startsWith(_placeholderPrefix) &&
      !vapidKey.startsWith(_placeholderPrefix);
}
