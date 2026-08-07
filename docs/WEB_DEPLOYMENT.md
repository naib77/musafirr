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

### Option C — Cloudflare Pages (recommended free option)

Free tier has **unlimited bandwidth**, allows commercial use (Vercel's free Hobby
plan does not), and deploys the committed `build/web/` folder straight from git —
no Flutter needed in their CI.

**One-time setup** (the dashboard now routes git repos through the "Create a
Worker" wizard — the repo's [`wrangler.jsonc`](../wrangler.jsonc) tells it to
serve `build/web` as a static site with SPA fallback):

1. [dash.cloudflare.com](https://dash.cloudflare.com) → **Workers & Pages** →
   **Create** → **Import a repository** → authorize GitHub → pick `musafirr`.
2. Configure the build step:
   - Build command: *(leave empty)*
   - Deploy command: **`npx wrangler deploy`** (the default)
   - Path: **`/`** (the default)
   - API token: **Create new token** (automatic)
3. **Deploy.** You get a `musafirr.<account>.workers.dev` URL with HTTPS.
4. (Optional) Project → **Settings** → **Domains & Routes** → add your custom
   domain. SSL is automatic.

**Deploying updates** — your normal flow *is* the deploy pipeline:

```bash
./tool/build_web.sh     # NOT plain `flutter build web` — see note below
git add build/web && git commit -m "web build" && git push
```

Every push to `main` auto-deploys.

> **Always build with `./tool/build_web.sh`.** Flutter skips underscore-prefixed
> files when copying `web/` into `build/web/`, so the script copies
> [`web/_headers`](../web/_headers) in after the build. That file tells Cloudflare
> not to cache `index.html` / `flutter_bootstrap.js` / `flutter_service_worker.js` —
> without it, users can get stuck on stale builds after a deploy.

SPA fallback is automatic on Pages (no 404.html present → unknown routes serve
`index.html`), so deep links just work.

### Option D — Netlify / Vercel

- Build command: none (deploy the committed `build/web`)
- Publish directory: `build/web`
- SPA rewrite: `/*  →  /index.html`
- ⚠️ Vercel's free Hobby plan prohibits commercial use — Musafir would need Pro.

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

---

## 6. Performance / PageSpeed

A Flutter-web (CanvasKit) app renders the whole UI to a `<canvas>` only **after**
a multi-MB bundle downloads and boots (`main.dart.js` ≈ 1.8 MB gzip + `canvaskit.wasm`
≈ 3.3 MB gzip). This makes FCP/LCP inherently weak — a desktop PageSpeed score in the
~50–75 range is normal for Flutter web and is **not** a server misconfiguration. The
items below are the wins that are actually in your control.

> **If you deploy on Cloudflare (Option C — the current production path):** Brotli,
> HTTP/2 and HTTP/3 are applied **automatically** at the edge, and caching is handled
> by [`web/_headers`](../web/_headers). So §6.2 (Brotli), §6.3 (HTTP/2) and the nginx
> config in §6.5 **do not apply to you** — they're only for the self-hosted nginx
> option (§3 Option B). The code-level wins (§6.1 splash, §6.1b `defer`) still apply
> and ship by rebuilding with `./tool/build_web.sh` and pushing to git.

### 6.1 Instant-paint splash (done — biggest FCP win)

[`web/index.html`](../web/index.html) now renders a static logo + spinner splash that
paints on the first frame and is removed on Flutter's `flutter-first-frame` event.
Without it the browser (and Lighthouse's FCP/LCP timers) saw a blank white page for
several seconds. No rebuild of app logic needed — just `flutter build web --release`
and redeploy.

### 6.1b Defer render-blocking `<head>` scripts (done — big mobile FCP win)

[`web/index.html`](../web/index.html) loaded the external Google Maps API and
`passkeys_bundle.js` as **synchronous** `<head>` scripts, so the browser had to fetch
and execute both *before parsing `<body>`* — i.e. before the splash could paint. On
Slow-4G mobile that external Maps fetch alone added several seconds to FCP. Both now
carry `defer`, so they download in parallel and run after parse; Flutter still finds
them ready seconds later when it boots a map or passkey flow.

Measured impact (mobile Lighthouse, Slow-4G/Moto-G): **FCP 9.6 s → 0.6 s**, and
Lighthouse no longer reports any render-blocking resources.

### 6.2 Enable Brotli in nginx

The server currently ships **gzip** only. Brotli is ~20–30% smaller on JS/WASM
(`main.dart.js` 1.79 MB → ~1.3 MB). It needs the `ngx_brotli` module:

```bash
# Ubuntu — install the prebuilt dynamic module for nginx 1.24
sudo apt update
sudo apt install -y libnginx-mod-http-brotli-filter libnginx-mod-http-brotli-static
sudo systemctl restart nginx
# If the package isn't available on your distro, build ngx_brotli from source:
#   https://github.com/google/ngx_brotli  (compile as a dynamic module, then
#   load_module modules/ngx_http_brotli_filter_module.so; in nginx.conf)
```

Then in the `server { … }` block (keep gzip as a fallback for old clients):

```nginx
brotli on;
brotli_comp_level 6;
brotli_types text/plain text/css application/javascript application/json
             application/wasm image/svg+xml application/manifest+json;
```

### 6.3 Enable HTTP/2

ALPN currently negotiates HTTP/1.1, which serializes Flutter's many small asset/font
requests. After certbot has added the TLS (`:443`) block, enable HTTP/2 on it:

```nginx
server {
    listen 443 ssl;
    http2 on;                     # nginx ≥ 1.25.1 directive (1.24: use `listen 443 ssl http2;`)
    server_name yourdomain.com;
    # … ssl_certificate / root / locations as before …
}
```

Reload and verify:

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -sI --http2 https://yourdomain.com/main.dart.js | grep -i "^HTTP/"   # want: HTTP/2 200
curl -sI -H "Accept-Encoding: br" https://yourdomain.com/main.dart.js | grep -i content-encoding  # want: br
```

### 6.4 Renderer (optional, risky — leave as-is unless you test carefully)

The app uses the **canvaskit** renderer (downloads the ~3.3 MB gzip `canvaskit.wasm`).
A `flutter build web --wasm` (skwasm) build can shrink the JS side, but it requires
cross-origin-isolation headers (`COOP: same-origin` + `COEP: require-corp`), which can
**break the inline Google Maps and Corbado passkey scripts** in `index.html`. Only
pursue this with a dedicated test pass.

### 6.5 Deploy + ready-to-paste production config

**1. Push the freshly built `build/web/` to the server** (adjust user / host / path
to yours). `--delete` removes files from old builds so no stale assets linger:

```bash
flutter build web --release
rsync -avz --delete build/web/ USER@app.musaafir.io:/var/www/musafir/
```

**2. Full nginx config for `app.musaafir.io`** — the SPA fallback, cache rules,
Brotli, and HTTP/2 from §6.2–6.3 combined into one block. Paste over your existing
`server {}` (keep the `ssl_certificate` lines certbot already wrote):

```nginx
# HTTP → HTTPS redirect
server {
    listen 80;
    server_name app.musaafir.io;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;                         # nginx 1.24: use `listen 443 ssl http2;` instead
    server_name app.musaafir.io;

    root /var/www/musafir;
    index index.html;

    # --- certbot-managed (leave as certbot wrote them) ---
    ssl_certificate     /etc/letsencrypt/live/app.musaafir.io/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.musaafir.io/privkey.pem;

    # --- compression: brotli first, gzip fallback for old clients ---
    brotli on;
    brotli_comp_level 6;
    brotli_types text/plain text/css application/javascript application/json
                 application/wasm image/svg+xml application/manifest+json;
    gzip on;
    gzip_types text/plain text/css application/javascript application/json
               application/wasm image/svg+xml application/manifest+json;

    # SPA fallback — deep links resolve to the app shell.
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Never cache the entry points / SW, or users get stuck on stale builds.
    location = /index.html                { add_header Cache-Control "no-cache, no-store, must-revalidate" always; }
    location = /flutter_bootstrap.js      { add_header Cache-Control "no-cache, no-store, must-revalidate" always; }
    location = /flutter_service_worker.js { add_header Cache-Control "no-cache, no-store, must-revalidate" always; }
    location = /manifest.json             { add_header Cache-Control "no-cache, no-store, must-revalidate" always; }
    location = /version.json              { add_header Cache-Control "no-cache, no-store, must-revalidate" always; }

    # Hashed build artifacts are safe to cache hard.
    location ~* \.(?:js|css|wasm|png|jpg|jpeg|gif|svg|ico|webp|woff2?)$ {
        expires 30d;
        add_header Cache-Control "public, max-age=2592000, immutable";
    }
}
```

**3. Install Brotli (once), test, reload, verify:**

```bash
sudo apt install -y libnginx-mod-http-brotli-filter libnginx-mod-http-brotli-static
sudo nginx -t && sudo systemctl reload nginx

curl -sI --http2 https://app.musaafir.io/main.dart.js | grep -i "^HTTP/"                 # want HTTP/2 200
curl -sI -H "Accept-Encoding: br" https://app.musaafir.io/main.dart.js | grep -i content-encoding  # want br
```

---

## 7. Measuring performance locally

**Always measure the `--release` build.** `flutter run -d chrome` (debug) is
un-minified and uses a different compiler — its numbers are meaningless for load time.

### 7.1 Build + serve

```bash
flutter build web --release
npx serve build/web -l 8080        # `serve` gzips responses, so byte weight is realistic
# open http://localhost:8080
```

### 7.2 Lighthouse — same metrics as PageSpeed

**DevTools:** open the site in a **new Incognito window** → F12 → **Lighthouse** tab →
**Desktop** → *Analyze page load*.

**CLI (repeatable, good for before/after):**

```bash
npx lighthouse http://localhost:8080 --preset=desktop --view      # desktop
npx lighthouse http://localhost:8080 --view                       # mobile (PageSpeed default)
```

Lighthouse applies **simulated throttling** (slow-4G + 4× CPU) by default, so the score
is comparable to pagespeed.web.dev even though localhost has no real network latency.

### 7.3 Network waterfall & runtime jank

- **Transfer size / waterfall:** F12 → **Network** → *Disable cache* → throttle to
  *Fast 4G* → reload. Watch `main.dart.js`, `canvaskit.wasm`, DOMContentLoaded, Load.
- **Frame times (jank, not load):** `flutter run -d chrome --profile`, then open the
  printed DevTools URL → **Performance**.

### 7.4 Prod-parity testing with Docker (optional)

`npx serve` doesn't replicate Brotli + HTTP/2. To test byte-for-byte against your prod
nginx config, serve `build/web` through nginx in Docker:

```bash
docker run --rm -p 8080:80 \
  -v "$(pwd)/build/web:/usr/share/nginx/html:ro" \
  nginx:1.27
```

### 7.5 Measured results (desktop Lighthouse, 2026-08-06)

| Build | Perf score | FCP | LCP | TBT | CLS |
|---|---|---|---|---|---|
| Live prod `app.musaafir.io` (no splash) | **38** | 5.4 s | 9.4 s | 380 ms | 0 |
| Local release build (**with splash**) | **73** | 2.1 s | 2.1 s | 80 ms | 0 |

**How to read this:** the two runs differ in *two* variables — the splash **and** the
environment (localhost has no network RTT) — so 73 is not the number prod will hit.
The unambiguous signal is the splash: without it, LCP was **9.4 s** (blank white page
until the canvas booted); with it, **FCP == LCP == 2.1 s**, i.e. the splash logo is now
the first and largest paint instead of a blank screen. Byte weight was ~identical
(~4 MB both), so transfer is not what moved the score.

**Expectation for prod once the splash is redeployed:** clearly better than 38 (the
blank-screen FCP/LCP penalty is gone), but below the localhost 73 because real network
latency remains. Adding Brotli + HTTP/2 (§6.2–6.3) pushes it further up.

---

## 8. Fast marketing landing page (static, separate from the app)

Flutter web ships as **one monolithic bundle** — there is no per-route code-splitting
that lets a landing page paint before the ~1.8 MB JS + ~3.3 MB WASM download and boot.
So for a genuinely fast first impression, the landing page is **not built in Flutter at
all**. It's a self-contained static HTML/CSS page ([`landing/index.html`](../landing/index.html))
that arrives in a single request and paints almost instantly. Its CTAs hand off to the
Flutter app.

**Measured (desktop Lighthouse, static landing vs the Flutter app):**

| Page | Perf | FCP | LCP | Transferred |
|---|---|---|---|---|
| Static landing (`landing/index.html`) | **100** | 0.2 s | 0.2 s | 7 KB |
| Flutter app (with splash, localhost) | 73 | 2.1 s | 2.1 s | ~4 MB |

### 8.1 Recommended architecture — subdomain split (least disruptive)

Keep the Flutter app exactly where it is and put the landing page on the apex domain:

- **`musaafir.io` / `www.musaafir.io`** → `landing/` (static)
- **`app.musaafir.io`** → the Flutter app (unchanged; no `--base-href` change needed)

The landing page's buttons already link to `https://app.musaafir.io`.

```nginx
# --- Landing page: musaafir.io + www ---
server {
    listen 443 ssl;
    http2 on;
    server_name musaafir.io www.musaafir.io;

    root /var/www/musaafir-landing;   # copy landing/ here
    index index.html;

    location / { try_files $uri $uri/ =404; }

    # html is tiny and may change; assets are static.
    location = /index.html { add_header Cache-Control "no-cache" always; }
    gzip on;
    gzip_types text/html text/css application/javascript image/svg+xml;
    # ssl_certificate ... (certbot -d musaafir.io -d www.musaafir.io)
}

# app.musaafir.io stays as your existing Flutter server block.
```

Deploy the landing folder:

```bash
rsync -av --delete landing/ user@server:/var/www/musaafir-landing/
sudo certbot --nginx -d musaafir.io -d www.musaafir.io
```

### 8.2 Alternative — same domain, subpath

If you only have `app.musaafir.io`, serve the landing at `/` and move the Flutter app
under `/app/`. This requires rebuilding the app with a base href:

```bash
flutter build web --release --base-href /app/
```

```nginx
server {
    listen 443 ssl;
    http2 on;
    server_name app.musaafir.io;

    # Landing at root
    location = / { root /var/www/musaafir-landing; try_files /index.html =404; }

    # Flutter app under /app/  (note the alias + SPA fallback to /app/index.html)
    location /app/ {
        alias /var/www/musaafir-app/;
        try_files $uri $uri/ /app/index.html;
    }
}
```

> Subpath is more fiddly (base href, `alias`, SPA fallback) and changes the app's URL.
> Prefer the subdomain split in §8.1 unless you can't add a DNS record.

### 8.3 Editing the landing page

It's plain HTML with inline CSS — no build step. Open [`landing/index.html`](../landing/index.html),
edit copy/colors (brand teal `#0B7285` is defined once in `:root`), and redeploy. Icons
are inline SVG; `favicon.png` + `Icon-192.png` are copied from `web/`. Keep it
self-contained (no web fonts, no external scripts) to preserve the 100 score.
