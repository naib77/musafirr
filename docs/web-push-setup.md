# Web push (FCM) setup — final step

Background/OS web push via Firebase Cloud Messaging is now **fully wired in
code**. The app compiles for web with the push path in place; it stays dormant
(falls back to the in-app-toast-only stub) until you paste **three values** from
the Firebase console. No code changes remain on our side.

## Status
- ✅ In-app toast on new realtime notification (works on web now) — `app.dart`.
- ✅ Web push service — [`web_push_notification_service.dart`](../lib/services/notifications/web_push_notification_service.dart) (VAPID `getToken`, foreground → toast).
- ✅ `main.dart` web branch: initialises Firebase with web options + selects the web push service **when configured**, else the stub (no regression).
- ✅ Service worker with background-notification + click-to-focus — [`web/firebase-messaging-sw.js`](../web/firebase-messaging-sw.js).
- ✅ Config guard — [`firebase_web_config.dart`](../lib/config/firebase_web_config.dart) (`isConfigured`).
- ⏳ Blocked only on **you** pasting the 3 real values below.

## What you do (Firebase console, project `musafir-200107`)

Most of the config is already filled from the Android app. You need **three**
values that only exist after registering a Web app:

1. **Register a Web app**: Project settings → General → *Your apps* →
   **Add app → Web (`</>`)**. Register it (e.g. "Musafir Web"). From its
   `firebaseConfig`, grab:
   - `apiKey`  → the **web API key** (differs from the Android key)
   - `appId`   → looks like `1:814163045663:web:xxxxxxxx`
2. **VAPID key**: Project settings → **Cloud Messaging** → *Web configuration* →
   **Web Push certificates** → *Generate key pair*. Copy the public key
   (starts with `B…`).

These are publishable client config, not secrets.

## Where they go (two files, same values)

| Value | `lib/config/firebase_web_config.dart` | `web/firebase-messaging-sw.js` |
|-------|----------------------------------------|--------------------------------|
| web API key | `options.apiKey` | `apiKey` |
| web app id | `options.appId` | `appId` |
| VAPID key | `vapidKey` | — (not needed in SW) |

The other four values (`projectId`, `messagingSenderId`, `storageBucket`,
`authDomain`) are **already correct** in both files. Once the three placeholders
(`REPLACE_WITH_*`) are replaced, `FirebaseWebConfig.isConfigured` flips to true
and the next `flutter build web` ships real web push.

> You can paste the three values to me and I'll drop them in, or edit the two
> files yourself — either works.

## Server side — nothing to change
`send-push-notification` reads `fcm_tokens` and sends via the FCM HTTP v1 API to
**every** active token regardless of `device_type`. Web tokens (saved with
`device_type = 'web'` by `FcmTokenService`) are delivered identically. The
message already includes a `notification` block, which the service worker
renders as an OS notification.

## Behaviour once configured
- **Tab closed/backgrounded** → OS notification from the service worker; clicking
  it focuses an open tab or opens the app.
- **Tab focused (foreground)** → the browser suppresses the OS popup; the app
  shows its in-app toast instead (driven by the realtime channel, same as today).
- Requires **HTTPS or `localhost`** — fine for `flutter run -d chrome` and prod.
  Plain `http://` over LAN will not grant notification permission.

## Test checklist
1. Fill the 3 values, `flutter run -d chrome`, log in.
2. Grant the browser notification prompt.
3. Confirm a row in `fcm_tokens` with `device_type = 'web'`.
4. Background the tab; trigger a notification (e.g. have another account book /
   message you). An OS notification should appear.
