/* Firebase Cloud Messaging service worker — WEB PUSH (background notifications).
 *
 * ⚠️ TEMPLATE: fill in the config below with YOUR Firebase *web app* values
 * (Firebase console → Project settings → General → Your apps → Web app → SDK
 * setup and configuration). This file must sit at web/firebase-messaging-sw.js
 * so it's served from the site root as /firebase-messaging-sw.js.
 *
 * It is NOT yet registered by the app — wiring happens in the Flutter push
 * service once the config + VAPID key are in place (see docs/web-push-setup.md).
 */
importScripts(
  "https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js",
);
importScripts(
  "https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js",
);

firebase.initializeApp({
  apiKey: "REPLACE_WITH_WEB_API_KEY",
  authDomain: "REPLACE_WITH_AUTH_DOMAIN",
  projectId: "REPLACE_WITH_PROJECT_ID",
  storageBucket: "REPLACE_WITH_STORAGE_BUCKET",
  messagingSenderId: "REPLACE_WITH_SENDER_ID",
  appId: "REPLACE_WITH_APP_ID",
});

const messaging = firebase.messaging();

// Background message → show an OS notification.
messaging.onBackgroundMessage((payload) => {
  const n = payload.notification || {};
  self.registration.showNotification(n.title || "Musafir", {
    body: n.body || "",
    icon: "/icons/Icon-192.png",
    data: payload.data || {},
  });
});
