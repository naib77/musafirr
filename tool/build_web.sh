#!/bin/sh
# Builds the production web bundle. Use this instead of calling
# `flutter build web --release` directly: Flutter skips underscore-prefixed
# files in web/, so the Cloudflare `_headers` file must be copied in after the
# build, and we fingerprint the app bundle so it can be cached immutably.
set -e
cd "$(dirname "$0")/.."

# Point the build at a specific Supabase project when the environment names one
# (the deploy workflow feeds these from the per-target GitHub Environment).
# Unset means "use the default compiled into lib/config/supabase_config.dart",
# which keeps a plain local build byte-identical to what it always produced.
DEFINES=""
if [ -n "${SUPABASE_URL:-}" ]; then
  DEFINES="$DEFINES --dart-define=SUPABASE_URL=$SUPABASE_URL"
  echo "Supabase URL      -> $SUPABASE_URL"
fi
if [ -n "${SUPABASE_ANON_KEY:-}" ]; then
  # Never echoed: it is public, but printing it into CI logs invites copy-paste
  # into places that are not.
  DEFINES="$DEFINES --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY"
  echo "Supabase anon key -> (supplied via environment)"
fi

# $DEFINES is deliberately unquoted: it must word-split into separate flags.
# shellcheck disable=SC2086
flutter build web --release $DEFINES "$@"

# ── Guard: the generated web plugin registrant must be current ──────────────
# Flutter caches a generated web_plugin_registrant.dart per build configuration,
# and has been observed reusing a STALE one — a registrant produced before a
# plugin was added to the project. Nothing catches this: the build succeeds,
# every test passes, and `flutter run -d chrome` works (it uses a different
# build directory with a fresh registrant). Only the deployed bundle is broken,
# and only at runtime:
#
#   MissingPluginException(No implementation found for method initialize
#                          on channel plugin.csdcorp.com/speech_to_text)
#
# That shipped once already — voice search was deployed for a day with
# speech_to_text unregistered, working perfectly in debug the whole time. This
# check compares the registrant that produced THIS bundle against the plugin
# list the build itself resolved, and refuses to fingerprint a bundle that is
# missing any of them.
REGISTRANT=""
for d in .dart_tool/flutter_build/*/; do
  [ -f "${d}main.dart.js" ] || continue
  if cmp -s "${d}main.dart.js" build/web/main.dart.js; then
    REGISTRANT="${d}web_plugin_registrant.dart"
    break
  fi
done

if [ -z "$REGISTRANT" ] || [ ! -f "$REGISTRANT" ] || [ ! -f .flutter-plugins-dependencies ]; then
  # Not a failure: a future Flutter may lay the build out differently. Say so
  # loudly rather than reporting a check that did not actually run.
  echo "NOTE: could not locate this bundle's plugin registrant — staleness check SKIPPED."
else
  MISSING="$(python3 - "$REGISTRANT" <<'PYEOF'
import json, sys
registrant = open(sys.argv[1]).read()
plugins = json.load(open('.flutter-plugins-dependencies'))['plugins'].get('web', [])
print(' '.join(p['name'] for p in plugins if p['name'] not in registrant))
PYEOF
)"
  if [ -n "$MISSING" ]; then
    echo ""
    echo "BUILD REJECTED: these web plugins are NOT registered in the bundle:"
    for m in $MISSING; do echo "  - $m"; done
    echo ""
    echo "Flutter reused a stale web_plugin_registrant.dart. Deploying this would"
    echo "fail at runtime with MissingPluginException, while debug builds keep"
    echo "working. Fix it with a clean build:"
    echo ""
    echo "    flutter clean && sh tool/build_web.sh"
    echo ""
    exit 1
  fi
  echo "Plugin registrant OK ($(grep -c registerWith "$REGISTRANT") web plugins registered)"
fi

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
# sha256sum on Linux (CI), shasum on macOS. Both print "<hash>  <file>", so the
# same cut works either way — don't let the build differ between a laptop and
# the runner, or the two produce different filenames for identical code.
if command -v sha256sum >/dev/null 2>&1; then
  HASH="$(sha256sum build/web/main.dart.js | cut -c1-16)"
else
  HASH="$(shasum -a 256 build/web/main.dart.js | cut -c1-16)"
fi
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
