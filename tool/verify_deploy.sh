#!/bin/sh
# Is what I committed actually what Cloudflare is serving?
#
# Answers the question that keeps coming up after a deploy. Three things can go
# wrong and they look identical from a browser:
#
#   1. The commit was source-only, so build/web still holds the previous bundle
#      (wrangler uploads ./build/web verbatim — it cannot compile Dart).
#   2. Nothing deployed. CI reports SUCCESS while SKIPPING the deploy when the
#      GitHub Environment has no Cloudflare credentials.
#   3. It did deploy, and an edge or browser cache is serving a stale copy of
#      the entry points. The site is only on workers.dev, which has no zone, so
#      the cache-purge API is unavailable — hence every request below carries a
#      cache-busting query string to read the ORIGIN, not a cached copy.
#
# Usage:  sh tool/verify_deploy.sh [host]
# Exit:   0 = live matches the working tree, 1 = it does not.

set -u

HOST="${1:-https://musafirr.knaib77.workers.dev}"
CB="cb=$(date +%s)$$"
LOCAL_DIR="build/web"

say() { printf '%s\n' "$*"; }
fail=0

say "host      : $HOST"

# ---- what the working tree expects -----------------------------------------
LOCAL_BUNDLE=$(ls "$LOCAL_DIR"/main.*.dart.js 2>/dev/null | head -1)
if [ -z "$LOCAL_BUNDLE" ]; then
  say "ERROR: no $LOCAL_DIR/main.*.dart.js — run 'sh tool/build_web.sh' first."
  exit 1
fi
LOCAL_BUNDLE_NAME=$(basename "$LOCAL_BUNDLE")
LOCAL_STAMP=$(cat "$LOCAL_DIR/build_stamp.json" 2>/dev/null)

say "local     : $LOCAL_BUNDLE_NAME"
say "local stamp: $LOCAL_STAMP"

# Hint at the source-only-commit trap: Dart newer than the built bundle.
#
# ADVISORY ONLY — never fails the run. mtimes are not reliable evidence: a
# fresh clone or any `git checkout` stamps every file with the checkout time,
# which would make this fire on a perfectly good tree. The authoritative check
# is the live-vs-local byte comparison below.
NEWEST_SRC=$(find lib -name '*.dart' -newer "$LOCAL_BUNDLE" -print 2>/dev/null | head -1)
if [ -n "$NEWEST_SRC" ]; then
  say ""
  say "NOTE: $NEWEST_SRC has a newer mtime than the built bundle."
  say "      build/web is a COMMITTED artifact that wrangler uploads verbatim,"
  say "      so if you really did edit Dart since building, rebuild first"
  say "      (sh tool/build_web.sh) or you will ship stale code."
  say "      Harmless if you just cloned or switched branches."
fi

# ---- what the origin is actually serving ------------------------------------
LIVE_BOOTSTRAP=$(curl -fsS "$HOST/flutter_bootstrap.js?$CB" 2>/dev/null)
if [ -z "$LIVE_BOOTSTRAP" ]; then
  say ""
  say "RESULT: RED - could not fetch $HOST/flutter_bootstrap.js"
  exit 1
fi
LIVE_BUNDLE_NAME=$(printf '%s' "$LIVE_BOOTSTRAP" \
  | grep -o 'main\.[a-f0-9]*\.dart\.js' | head -1)
LIVE_STAMP=$(curl -fsS "$HOST/build_stamp.json?$CB" 2>/dev/null)

say ""
say "live      : ${LIVE_BUNDLE_NAME:-<none found>}"
say "live stamp: ${LIVE_STAMP:-<none>}"
say ""

# ---- compare ----------------------------------------------------------------
if [ "$LIVE_BUNDLE_NAME" != "$LOCAL_BUNDLE_NAME" ]; then
  say "MISMATCH: the live bundle is not the one in $LOCAL_DIR."
  say "          Either nothing deployed, or the deploy shipped an older tree."
  fail=1
else
  say "OK: live bundle name matches the working tree."
fi

if [ -n "$LIVE_STAMP" ] && [ "$LIVE_STAMP" != "$LOCAL_STAMP" ]; then
  say "MISMATCH: build_stamp differs."
  fail=1
fi

# Byte-identity is the only proof that survives a coincidentally-equal name.
if [ "$LIVE_BUNDLE_NAME" = "$LOCAL_BUNDLE_NAME" ]; then
  TMP=$(mktemp)
  if curl -fsS "$HOST/$LIVE_BUNDLE_NAME?$CB" -o "$TMP" 2>/dev/null; then
    if cmp -s "$TMP" "$LOCAL_BUNDLE"; then
      say "OK: live bundle is byte-identical to $LOCAL_BUNDLE_NAME."
    else
      say "MISMATCH: same filename, different bytes."
      fail=1
    fi
  else
    say "WARNING: could not download the live bundle to compare bytes."
  fi
  rm -f "$TMP"
fi

# The entry points are marked no-store, yet workers.dev may still report a
# cache HIT. Worth surfacing: a HIT serving OLD content is exactly the
# "my changes aren't live" illusion, and it cannot be purged without a zone.
CACHE_STATUS=$(curl -s -o /dev/null -D - "$HOST/build_stamp.json" 2>/dev/null \
  | grep -i '^cf-cache-status' | tr -d '\r')
[ -n "$CACHE_STATUS" ] && say "edge      : $CACHE_STATUS (uncached read used above)"

say ""
if [ "$fail" -eq 0 ]; then
  say "RESULT: GREEN - Cloudflare is serving exactly what is in $LOCAL_DIR."
  say "        If a browser still shows old UI, it is a CLIENT cache:"
  say "        hard-reload (Cmd/Ctrl+Shift+R) or clear site data."
  exit 0
fi
say "RESULT: RED - live does not match the working tree (see above)."
exit 1
