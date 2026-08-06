# Musafir — Web Deployment Guide

How to run Musafir as a web app locally and deploy the web build to a server.

> **Good news:** web is already enabled (`web/` exists) and all config is baked in —
> the Supabase URL + anon key are hardcoded in [`lib/config/supabase_config.dart`](../lib/config/supabase_config.dart),
> and the Google Maps key is present both in [`web/index.html`](../web/index.html) and as
> the `GOOGLE_MAPS_API_KEY` dart-define default in [`lib/config/api_keys.dart`](../lib/config/api_keys.dart).
> **A web build needs no extra flags to work.**

---

## 1. Run locally

```bash
flutter run -d chrome
```

No `--dart-define` needed. To preview an actual production build locally:

```bash
flutter build web --release
cd build/web && python3 -m http.server 8080   # open http://localhost:8080
```

---

## 2. Build for production

```bash
flutter clean && flutter pub get
flutter build web --release
```

Output lands in **`build/web/`** — that entire folder is your deployable static site.

- **Subpath deploy** (e.g. `example.com/app/`): add `--base-href /app/`. For a root
  domain the default (`/`) is fine.
- **WASM renderer** (optional, faster): add `--wasm`. Test passkeys + maps first;
  CanvasKit (the default) is the safe choice.

---

## 3. Deploy to a server — pick one

### Option A — Firebase Hosting (recommended)

Firebase is already wired into this project, so this is the natural fit. HTTPS is automatic.

```bash
npm i -g firebase-tools
firebase login
firebase init hosting     # public dir: build/web | single-page app: YES | don't overwrite index.html
firebase deploy --only hosting
```

> **"single-page app: YES" is required** — it adds the rewrite so Flutter's
> client-side routes resolve instead of 404-ing.

### Option B — Your own VPS with nginx

Copy `build/web/` to the server (e.g. `/var/www/musafir`), then drop this into something like `/etc/nginx/conf.d/musafir.conf`:

```nginx
server {
   listen 80;
   server_name yourdomain.com;

   root /var/www/musafir;
   index index.html;

   # Flutter web is a single-page app, so deep links must fall back to index.html.
   location / {
      try_files $uri $uri/ /index.html;
   }

   # Never cache the entry points or the service worker, or users can get stuck on stale builds.
   location = /index.html {
      add_header Cache-Control "no-cache, no-store, must-revalidate" always;
   }

   location = /flutter_bootstrap.js {
      add_header Cache-Control "no-cache, no-store, must-revalidate" always;
   }

   location = /flutter_service_worker.js {
      add_header Cache-Control "no-cache, no-store, must-revalidate" always;
   }

   location = /manifest.json {
      add_header Cache-Control "no-cache, no-store, must-revalidate" always;
   }

   location = /version.json {
      add_header Cache-Control "no-cache, no-store, must-revalidate" always;
   }

   # Static build artifacts can be cached normally.
   location ~* \.(?:js|css|wasm|png|jpg|jpeg|gif|svg|ico|webp)$ {
      expires 30d;
      add_header Cache-Control "public, max-age=2592000, immutable";
   }

   gzip on;
   gzip_types text/plain text/css application/javascript application/json application/wasm image/svg+xml;
}
```

Then enable HTTPS:

```bash
sudo certbot --nginx
```

### Option C — Netlify / Vercel / Cloudflare Pages

- Build command: `flutter build web --release`
- Publish directory: `build/web`
- SPA rewrite: `/*  →  /index.html`

---

## 4. Post-deploy config — project-specific gotchas

These are specific to what Musafir uses, not generic Flutter steps. Skipping them
causes login/maps/push to silently fail on the deployed site.

1. **HTTPS is mandatory.** Passkeys (Corbado), Firebase web push, and service workers
   all refuse to run over plain HTTP (only `localhost` is exempt). Firebase Hosting
   provides it free; on a VPS use certbot.

2. **Corbado passkeys** ([`passkeys_bundle.js`](../web/index.html)) are bound to a
   relying-party **domain**. Register your deployed domain in the Corbado dashboard,
   or passkey login fails on the web build.

3. **Supabase Auth URL config.** Supabase dashboard → Authentication → URL Configuration:
   add your domain as the **Site URL** and to **Redirect URLs**.

4. **Lock down the Google Maps key.** It is public and currently unrestricted.
   Google Cloud Console → Credentials → add an **HTTP-referrer restriction** for your
   domain(s), and confirm *Maps JavaScript API* + *Directions API* are enabled.

5. **Web push.** `firebase-messaging-sw.js` must be served from the site **root**
   (it is, in `build/web/`). Web push is already configured — nothing else to do.

---

## 5. ⚠️ Before going to real production

Confirm the QA master-OTP is disabled **server-side**. Currently `MASTER_OTP_PHONES='*'`
lets OTP `1234` log into **any** phone number on the live project. This is a Supabase
secret, not part of the web build, but a public web URL makes it far more exposed:

```bash
supabase secrets unset MASTER_OTP MASTER_OTP_PHONES --project-ref bojkmonskqlhuakxhzcb
```
