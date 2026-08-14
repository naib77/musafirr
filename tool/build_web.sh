#!/bin/sh
# Builds the production web bundle. Use this instead of calling
# `flutter build web --release` directly: Flutter skips underscore-prefixed
# files in web/, so the Cloudflare `_headers` file must be copied in after the
# build, and we fingerprint the app bundle so it can be cached immutably.
set -e
cd "$(dirname "$0")/.."
flutter build web --release "$@"

# ── Content-hash the app bundle (main.dart.js) ──────────────────────────────
# main.dart.js is ~1.2 MB over the wire and is the load-time bottleneck (the
# CanvasKit engine is served from the gstatic CDN, not our origin). Because its
# filename is stable across builds, it could not be cached without revalidating
# on every load. We rename it to main.<contenthash>.dart.js and rewrite the one
# reference the runtime uses (the `mainJsPath` in flutter_bootstrap.js's build
# config). The hash changes whenever the code changes, so we can cache it
# `immutable` (see web/_headers) with ZERO risk of stranding a client on a stale
# bundle: index.html and flutter_bootstrap.js are always revalidated (no-cache),
# so every page load after a deploy discovers the new hash and fetches the new
# bundle. A returning user with an old tab is handled separately by
# WebUpdateService (build_stamp.json polling).
#
# Drop any hashed bundles left by previous builds (but not the fresh
# main.dart.js this build just produced).
find build/web -maxdepth 1 -name 'main.*.dart.js' ! -name 'main.dart.js' -delete
HASH="$(shasum -a 256 build/web/main.dart.js | cut -c1-16)"
HASHED="main.$HASH.dart.js"
mv build/web/main.dart.js "build/web/$HASHED"
# Rewrite the entrypoint reference(s) inside the bootstrap to the hashed name.
sed "s/\"main\.dart\.js\"/\"$HASHED\"/g" build/web/flutter_bootstrap.js > build/web/flutter_bootstrap.js.tmp
mv build/web/flutter_bootstrap.js.tmp build/web/flutter_bootstrap.js
# Preload the (now immutable) entrypoint so the browser starts fetching it in
# parallel with parsing flutter_bootstrap.js, instead of discovering it a
# round-trip later when the bootstrap injects the <script> tag.
sed "s#</head>#  <link rel=\"preload\" as=\"script\" href=\"$HASHED\"></head>#" build/web/index.html > build/web/index.html.tmp
mv build/web/index.html.tmp build/web/index.html
echo "Fingerprinted app bundle -> $HASHED (preloaded, immutable)"

# Symbol maps are only used to symbolicate stack traces offline; they are never
# fetched by the running app and add ~13 MB of dead weight to the deploy.
find build/web -name '*.symbols' -delete
echo "Removed *.symbols debug maps from build/web"

cp web/_headers build/web/_headers
echo "Copied web/_headers into build/web/"

# Unique per-build stamp (git commit + build time). The app polls this file
# (WebUpdateService) to offer open tabs a refresh after a deploy — version.json
# only changes on a pubspec version bump, so it can't serve this purpose.
STAMP="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)-$(date +%s)"
printf '{"build":"%s"}\n' "$STAMP" > build/web/build_stamp.json
echo "Stamped build/web/build_stamp.json ($STAMP)"
