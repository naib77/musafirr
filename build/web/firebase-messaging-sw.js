/* Firebase Cloud Messaging service worker — WEB PUSH (background notifications).
 *
 * Served from the site root as /firebase-messaging-sw.js. firebase_messaging_web
 * registers it automatically; it shows the OS notification when the tab is
 * backgrounded or closed (foreground messages are handled in-app by Dart).
 *
 * ⚠️ Two values are still placeholders: apiKey and appId. Get them from the
 * Firebase console → Project settings → Your apps → Web app → SDK config, and
 * keep them IN SYNC with lib/config/firebase_web_config.dart. See
 * docs/web-push-setup.md.
 */
importScripts(
  "https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js",
);
importScripts(
  "https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js",
);

firebase.initializeApp({
  apiKey: "AIzaSyD3jQPcuZPkR1ueTcEVz9qq539ykttkFEs",
  authDomain: "musafir-200107.firebaseapp.com",
  projectId: "musafir-200107",
  storageBucket: "musafir-200107.firebasestorage.app",
  messagingSenderId: "814163045663",
  appId: "1:814163045663:web:b163b2216d65bb9bfd542a",
});

const messaging = firebase.messaging();

// Background message → show an OS notification.
messaging.onBackgroundMessage((payload) => {
  const n = payload.notification || {};
  const data = payload.data || {};
  self.registration.showNotification(n.title || "Musafir", {
    body: n.body || "",
    icon: "/icons/Icon-192.png",
    badge: "/icons/Icon-192.png",
    data: data,
    // Collapse duplicates for the same entity (e.g. a booking) into one.
    tag: data.action_url || data.notification_id || undefined,
  });
});

// Focus an existing tab (or open one) when the notification is clicked.
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.action_url) || "/";
  event.waitUntil(
    clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then((windowClients) => {
        for (const client of windowClients) {
          if ("focus" in client) return client.focus();
        }
        if (clients.openWindow) return clients.openWindow(target);
      }),
  );
});
