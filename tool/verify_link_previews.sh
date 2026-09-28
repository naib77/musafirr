#!/bin/sh
# Does /listing/<id> actually preview as itself?
#
# The Worker in worker/index.js rewrites the Open Graph tags for one listing at
# the edge. Nothing in `flutter test` can see that — it is JavaScript running in
# workerd, reading PostgREST — and this repo has no JS test runner (CI has no
# node step either, same as tool/verify_phone_parity.sh). So this is the loop.
#
#   sh tool/verify_link_previews.sh
#
# It runs two checks against a local `wrangler dev`:
#
#   1. REAL DATA. Picks an active listing out of the live database and asserts
#      the served HTML carries that listing's title, not the site's.
#   2. HOSTILE DATA. Points the Worker at a stub PostgREST that returns a title
#      containing `"><script>`, and asserts it comes back escaped. A listing
#      title is host-supplied and lands inside an HTML attribute, so this is
#      the check that matters most — and it needs a stub, because the
#      alternative is writing an XSS payload into the live database.
#
# Needs the `Supabase CLI` keychain token for step 1 only.
set -e

PORT_APP=${PORT_APP:-8791}
PORT_STUB=${PORT_STUB:-8792}
PORT_STUB_APP=${PORT_STUB_APP:-8793}
TMP=$(mktemp -d)
PIDS=""

cleanup() {
  # shellcheck disable=SC2086
  [ -n "$PIDS" ] && kill $PIDS 2>/dev/null || true
  # wrangler leaves a workerd child behind on SIGTERM.
  pkill -f "workerd.*$PORT_APP" 2>/dev/null || true
  pkill -f "workerd.*$PORT_STUB_APP" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

fail() { printf '\033[31mFAIL\033[0m %s\n' "$1"; exit 1; }
pass() { printf '\033[32mok\033[0m   %s\n' "$1"; }

wait_for() {
  i=0
  while [ "$i" -lt 60 ]; do
    if curl -sf -o /dev/null "http://127.0.0.1:$1/" 2>/dev/null; then return 0; fi
    i=$((i + 1)); sleep 1
  done
  fail "wrangler dev never became ready on :$1 (see $TMP)"
}

[ -f build/web/index.html ] || fail "build/web/index.html missing — run sh tool/build_web.sh"

# ---------------------------------------------------------------------------
# 1. A real listing
# ---------------------------------------------------------------------------
echo "== real data =="
TOKEN=$(security find-generic-password -s "Supabase CLI" -w 2>/dev/null || true)
[ -n "$TOKEN" ] || fail "no Supabase CLI token in the keychain (npx supabase login)"

ROW=$(curl -s -X POST \
  "https://api.supabase.com/v1/projects/bojkmonskqlhuakxhzcb/database/query" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"query":"select id, title from public.listings where is_active order by created_at desc limit 1;"}')
LISTING_ID=$(printf '%s' "$ROW" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["id"])')
LISTING_TITLE=$(printf '%s' "$ROW" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["title"])')
echo "   subject: $LISTING_TITLE ($LISTING_ID)"

npx wrangler dev --port "$PORT_APP" --local >"$TMP/app.log" 2>&1 &
PIDS="$PIDS $!"
wait_for "$PORT_APP"

curl -s "http://127.0.0.1:$PORT_APP/listing/$LISTING_ID" >"$TMP/listing.html"
grep -q "content=\"$LISTING_TITLE\"" "$TMP/listing.html" \
  || fail "og:title is not the listing's own title (see $TMP/listing.html)"
pass "og:title is the listing's title"

grep -q "<title>$LISTING_TITLE</title>" "$TMP/listing.html" || fail "<title> not rewritten"
pass "<title> is the listing's title"

grep -qE 'property="og:image" content="https://[^"]*supabase\.co/storage' "$TMP/listing.html" \
  || fail "og:image is not the listing's own photo"
pass "og:image is the listing's photo"

# The home page and in-app routes must be left exactly alone.
curl -s "http://127.0.0.1:$PORT_APP/" >"$TMP/home.html"
grep -q 'content="Musaafir — find your perfect stay"' "$TMP/home.html" \
  || fail "the home page's og:title was altered"
pass "the home page is untouched"

curl -s "http://127.0.0.1:$PORT_APP/trips" >"$TMP/trips.html"
grep -q 'content="Musaafir — find your perfect stay"' "$TMP/trips.html" \
  || fail "an in-app route lost the default card"
pass "in-app routes keep the default card"

# A dead link must still serve a working page, not a 500.
CODE=$(curl -s -o "$TMP/missing.html" -w '%{http_code}' \
  "http://127.0.0.1:$PORT_APP/listing/00000000-0000-0000-0000-000000000000")
[ "$CODE" = "200" ] || fail "a missing listing returned $CODE, not 200"
grep -q 'content="Musaafir — find your perfect stay"' "$TMP/missing.html" \
  || fail "a missing listing did not fall back to the default card"
pass "a missing listing falls back, still 200"

kill $PIDS 2>/dev/null || true
pkill -f "workerd.*$PORT_APP" 2>/dev/null || true
PIDS=""
sleep 1

# ---------------------------------------------------------------------------
# 2. A hostile title
# ---------------------------------------------------------------------------
echo "== hostile data =="
cat >"$TMP/stub.py" <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, sys

HOSTILE = {
    "title": '"><script>alert(document.domain)</script>',
    "address": "Uttara, Dhaka",
    "city": "Dhaka",
    "max_guests": 3,
    "daily_rate": 1750.0,
    "monthly_rate": 29500.0,
    "image_urls": ['https://example.com/a.jpg" onerror="alert(1)'],
}

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps([HOSTILE]).encode()
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):
        pass

HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
python3 "$TMP/stub.py" "$PORT_STUB" &
PIDS="$PIDS $!"
sleep 1

npx wrangler dev --port "$PORT_STUB_APP" --local \
  --var "SUPABASE_URL:http://127.0.0.1:$PORT_STUB" \
  --var "SUPABASE_ANON_KEY:stub" >"$TMP/stub_app.log" 2>&1 &
PIDS="$PIDS $!"
wait_for "$PORT_STUB_APP"

curl -s "http://127.0.0.1:$PORT_STUB_APP/listing/$LISTING_ID" >"$TMP/hostile.html"

# The payload must appear ESCAPED and never as live markup. The quote is what
# would break out of content="…"; inside a quoted attribute < and > cannot.
grep -q 'og:title" content="&quot;>' "$TMP/hostile.html" \
  || fail "the quote in og:title was not escaped (see $TMP/hostile.html)"
pass "og:title escapes the attribute-breaking quote"

grep -q 'og:image" content="https://example.com/a.jpg&quot; onerror=&quot;' "$TMP/hostile.html" \
  || fail "og:image did not escape its injected onerror="
pass "og:image escapes an injected onerror="

grep -q '<title>"&gt;&lt;script&gt;' "$TMP/hostile.html" \
  || fail "<title> did not escape the script tag"
pass "<title> escapes the script tag"

# Belt and braces: the payload must not be MARKUP anywhere.
#
# Deliberately parsed rather than grepped. `<script>alert(` does appear in the
# raw bytes — inside content="…", where it is attribute text and inert — so a
# grep for it fails on correct output. The question is whether a parser sees a
# script ELEMENT, which is what a browser or a scraper would act on.
python3 - "$TMP/hostile.html" <<'PY' || fail "the payload parsed as live markup"
import sys
from html.parser import HTMLParser

class Check(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_script = False
        self.executable = []
    def handle_starttag(self, tag, attrs):
        if tag == 'script':
            self.in_script = True
    def handle_endtag(self, tag):
        if tag == 'script':
            self.in_script = False
    def handle_data(self, data):
        if self.in_script and 'alert(' in data:
            self.executable.append(data.strip()[:60])

c = Check()
c.feed(open(sys.argv[1], encoding='utf-8').read())
if c.executable:
    print('  executable script content found:', c.executable)
    sys.exit(1)
PY
pass "no parser sees the payload as a script element"

echo
printf '\033[32mRESULT: GREEN\033[0m — /listing/<id> previews as itself, and a hostile title stays inert.\n'
