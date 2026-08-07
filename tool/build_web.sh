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
