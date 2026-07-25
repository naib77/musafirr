# Web push (FCM) setup — what's needed to finish it

The app already has **in-app realtime notification toasts** that work on web
(shown for every live notification, since OS push is unavailable there). This
doc covers the remaining **background/OS web push** via Firebase Cloud
Messaging, which needs a few values from your Firebase console before the code
can be wired.

## Status
- ✅ In-app toast on new realtime notification (works on web now) — `app.dart`.
- ✅ Service worker template — [`web/firebase-messaging-sw.js`](../web/firebase-messaging-sw.js) (placeholders).
- ⏳ Blocked on **you** providing the Firebase web config + VAPID key (below).
- ⏳ Flutter code path (web `getToken(vapidKey:)` + factory) — intentionally NOT
  wired yet, so the working web build isn't broken by a half-configured Firebase.

## What I need from you (Firebase console)
The app already uses Firebase for Android push, so the project exists. For web:

1. **Register a Web app** (if not already): Firebase console → Project settings →
   General → *Your apps* → add a **Web** app. Copy its config:
   ```
   apiKey, authDomain, projectId, storageBucket, messagingSenderId, appId
   ```
2. **Web Push certificate (VAPID key)**: Project settings → **Cloud Messaging** →
   *Web configuration* → *Web Push certificates* → **Generate key pair**. Copy the
   public key (starts with `B…`).

Paste those 6 config values + the VAPID key to me (they are publishable client
config, not secrets — but I'll still keep them out of source where possible).

## Then I'll wire (one focused pass)
1. Fill `web/firebase-messaging-sw.js` with the config.
2. Initialize Firebase on web (`Firebase.initializeApp` with the web options).
3. Add a **web** push path: on `kIsWeb`, call
   `FirebaseMessaging.instance.getToken(vapidKey: <VAPID>)`, register the service
   worker, and save the token to `fcm_tokens` (the existing table) with
   `platform = 'web'`.
4. Flip [`push_notification_service.dart`](../lib/services/notifications/push_notification_service.dart)
   so web uses the real FCM service instead of the stub **only when** the web
   config is present (else keep the stub — no regression).

## Server side
`send-push-notification` already reads `fcm_tokens` and sends via FCM. FCM tokens
are platform-agnostic, so **web tokens are delivered the same way** — no Edge
Function change expected (we'll confirm the payload shows a `notification` block
so the service worker can render it).

## Notes
- Web push only fires when the browser tab is closed/backgrounded; when the app
  is open, the in-app toast already covers it.
- Requires HTTPS (or `localhost`) — fine for `flutter run -d chrome` and prod.
