#!/bin/sh
# Builds the production web bundle. Use this instead of calling
# `flutter build web --release` directly: Flutter skips underscore-prefixed
# files in web/, so the Cloudflare Pages `_headers` file must be copied in
# after the build.
set -e
cd "$(dirname "$0")/.."
flutter build web --release "$@"
cp web/_headers build/web/_headers
echo "Copied web/_headers into build/web/"

# Unique per-build stamp (git commit + build time). The app polls this file
# (WebUpdateService) to offer open tabs a refresh after a deploy — version.json
# only changes on a pubspec version bump, so it can't serve this purpose.
STAMP="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)-$(date +%s)"
printf '{"build":"%s"}\n' "$STAMP" > build/web/build_stamp.json
echo "Stamped build/web/build_stamp.json ($STAMP)"
