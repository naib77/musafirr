#!/bin/sh
# Do the Dart and TypeScript phone canonicalisers agree?
#
# They have to, and nothing else checks it. `verify-otp` (TypeScript) derives
# the Supabase auth identity that decides which account a login lands on, while
# the Flutter client (Dart) normalises the same number for its rate-limit keys,
# the master-OTP allowlist and profiles.mobile. Both files carry a comment
# telling you to keep them in step; that comment was already false when the
# duplicate-account bug was found — there were FOUR implementations, three of
# them drifted, and none had a test.
#
# A shared comment is not a check. This is.
#
#   sh tool/verify_phone_parity.sh
#
# Requires node (for the .ts, via type stripping). Not wired into CI because CI
# has no node step; run it whenever you touch either implementation.
set -e
cd "$(dirname "$0")/.."

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not found — cannot evaluate the TypeScript side." >&2
  exit 0
fi

OUT="${TMPDIR:-/tmp}/phone_parity.$$"
mkdir -p "$OUT"
trap 'rm -rf "$OUT" .dart_tool/phone_parity_main.dart' EXIT

# The inputs that matter: every way a Bangladeshi user can type one number,
# plus the shapes that must NOT be rewritten.
cat > "$OUT/cases.txt" <<'CASES'
01711165212
1711165212
+8801711165212
+880 1711165212
8801711165212
+880 1711-165212
01711 165212
(017) 1116-5212
01673293542
1673293542
1311165212
1911165212
1211165212
171116521
17111652123
+11234567890
CASES

# --- TypeScript side -------------------------------------------------------
cat > "$OUT/ts.mjs" <<'EOF'
import { readFileSync } from 'node:fs';
import { normalizePhone } from process.env.OTP_TS;
// Same rule as the Dart side: split, then drop a single trailing empty
// element if the file ends with a newline. Getting this subtly different
// between the two readers misaligns the lists and reports a false mismatch.
const cases = readFileSync(process.env.CASES, 'utf8').split('\n');
if (cases.length && cases[cases.length - 1] === '') cases.pop();
for (const c of cases) console.log(JSON.stringify(normalizePhone(c)));
EOF
# `import` needs a literal, so inline the resolved path.
sed -i.bak "s#process.env.OTP_TS#'$PWD/supabase/functions/_shared/otp.ts'#" "$OUT/ts.mjs"
CASES="$OUT/cases.txt" node "$OUT/ts.mjs" > "$OUT/ts.out"

# --- Dart side -------------------------------------------------------------
# Written under .dart_tool (gitignored) rather than the temp dir: a script
# outside the package cannot resolve `package:musafir`, and phone_number.dart
# imports nothing, so a relative import from inside the repo is enough — no
# Flutter, no pub resolution, just `dart run`.
DART_MAIN=".dart_tool/phone_parity_main.dart"
mkdir -p .dart_tool
cat > "$DART_MAIN" <<'EOF'
import 'dart:convert';
import 'dart:io';

import '../lib/services/auth/phone_number.dart';

void main() {
  final cases = File(Platform.environment['CASES']!).readAsLinesSync();
  // Same rule as the JS side. readAsLinesSync already omits a trailing empty
  // element for a file ending in a newline; the guard keeps the two readers
  // identical rather than relying on that asymmetry.
  if (cases.isNotEmpty && cases.last.isEmpty) cases.removeLast();
  for (final c in cases) {
    stdout.writeln(jsonEncode(canonicalBdPhone(c)));
  }
}
EOF
CASES="$OUT/cases.txt" dart run "$DART_MAIN" > "$OUT/dart.out" 2>"$OUT/dart.err" || {
  echo "FAIL: could not run the Dart side:" >&2
  cat "$OUT/dart.err" >&2
  exit 1
}

# --- Compare ---------------------------------------------------------------
if diff -u "$OUT/ts.out" "$OUT/dart.out" > "$OUT/diff" 2>&1; then
  n=$(wc -l < "$OUT/ts.out" | tr -d ' ')
  echo "PARITY OK: Dart and TypeScript agree on all $n inputs."
else
  echo "PARITY BROKEN: the two canonicalisers disagree." >&2
  echo "Left = supabase/functions/_shared/otp.ts, right = lib/services/auth/phone_number.dart" >&2
  echo >&2
  paste -d'|' "$OUT/cases.txt" "$OUT/ts.out" "$OUT/dart.out" \
    | awk -F'|' '$2 != $3 { printf "  %-20s ts=%-16s dart=%s\n", $1, $2, $3 }' >&2
  exit 1
fi
