#!/bin/sh
# Drive the LOCAL stack the way the apps do — real GoTrue logins, PostgREST,
# Storage and edge-function HTTP — and print PASS/FAIL per scenario.
#
#   supabase start
#   sh tool/local_db_from_live.sh
#   supabase functions serve --env-file supabase/functions/.env.local --no-verify-jwt
#   sh tool/qa/http_smoke.sh
#
# Why this exists next to the SQL tests: the SQL files prove what the DATABASE
# refuses; this proves what the client actually sees through the API — the
# `[]` PostgREST answers for an RLS-filtered update, the 42501 body a refused
# trigger produces, the 400/415 Storage answers, the shape of an edge
# function's error. Every row here is also covered one layer down, so a red
# row is a wiring fault, not a rule fault.
#
# LOCAL ONLY. Uses the qa_seed accounts (password `qa-password`; re-run the
# `update auth.users set encrypted_password …` in qa_seed.sql if a login 401s)
# and writes nothing that survives — every mutation targets a row it created
# or is refused.
set -u
cd "$(dirname "$0")/../.."
API=${SUPABASE_LOCAL_URL:-http://127.0.0.1:54321}
ANON=$(supabase status -o json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['ANON_KEY'])")
[ -n "$ANON" ] || { echo "supabase status gave no anon key — is the stack running?"; exit 2; }
pass=0; fail=0
ok()   { pass=$((pass+1)); printf "PASS  %s\n" "$1"; }
bad()  { fail=$((fail+1)); printf "FAIL  %s\n      got: %s\n" "$1" "$2"; }
login() { curl -s -X POST "$API/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d "{\"email\":\"$1\",\"password\":\"qa-password\"}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
rest() { # rest <token> <method> <path> [json]
  tok=$1; m=$2; p=$3; body=${4:-}
  if [ -n "$body" ]; then
    curl -s -w "\n%{http_code}" -X "$m" "$API/rest/v1/$p" -H "apikey: $ANON" -H "Authorization: Bearer $tok" -H "Content-Type: application/json" -H "Prefer: return=representation" -d "$body"
  else
    curl -s -w "\n%{http_code}" -X "$m" "$API/rest/v1/$p" -H "apikey: $ANON" -H "Authorization: Bearer $tok"
  fi
}
HOST1=11111111-1111-1111-1111-111111111111
GUESTV=33333333-3333-3333-3333-333333333333
GUESTU=44444444-4444-4444-4444-444444444444
L1=aaaaaaaa-0000-0000-0000-000000000001
B3=bbbbbbbb-0000-0000-0000-000000000003   # GUESTV on L1, confirmed, unpaid
B1=bbbbbbbb-0000-0000-0000-000000000001   # GUESTV on L2, completed, paid

TH=$(login phone.1700000001@musaafir.app); TG=$(login phone.1700000003@musaafir.app); TU=$(login phone.1700000004@musaafir.app)
[ -n "$TH" ] && [ -n "$TG" ] && [ -n "$TU" ] || { echo "login failed — reset the qa passwords (see qa_seed.sql)"; exit 2; }
ok "the three seeded accounts log in with a password"

# 1. A signed-out visitor browses; a signed-out visitor cannot read profiles.
r=$(curl -s -w "\n%{http_code}" "$API/rest/v1/listings?select=id&is_active=eq.true" -H "apikey: $ANON"); code=$(echo "$r" | tail -1)
n=$(echo "$r" | sed '$d' | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)
[ "$code" = 200 ] && [ "$n" -ge 3 ] && ok "anon sees the active listings ($n)" || bad "anon sees the active listings" "$r"
r=$(curl -s -w "\n%{http_code}" "$API/rest/v1/profiles?select=mobile" -H "apikey: $ANON"); code=$(echo "$r" | tail -1)
[ "$code" = 401 ] || [ "$code" = 403 ] && ok "anon cannot read profiles (no grant)" || bad "anon cannot read profiles" "$r"

# 2. A guest's RLS-filtered UPDATE is not an error: PostgREST answers [].
r=$(rest "$TG" PATCH "bookings?id=eq.$B3" '{"host_message":"x"}'); code=$(echo "$r" | tail -1); body=$(echo "$r" | head -1)
echo "$body" | grep -q "host_columns_protected" && ok "guest writing the host's message is refused with a hint (138)" || bad "guest writing host_message refused" "$r"

# 3. Guest raises guest_count → refused with the 138 hint.
r=$(rest "$TG" PATCH "bookings?id=eq.$B3" '{"guest_count":50}'); echo "$r" | head -1 | grep -q "booking_columns_protected" && ok "guest cannot raise guest_count after booking (138)" || bad "guest_count frozen" "$r"

# 4. Guest tries to pay themselves: payment_status protected (132).
r=$(rest "$TG" PATCH "bookings?id=eq.$B3" '{"payment_status":"paid"}'); echo "$r" | head -1 | grep -q "payment_columns_protected" && ok "guest cannot mark own booking paid (132)" || bad "payment_status protected" "$r"

# 5. A stranger's PATCH on someone else's booking: 200 and [] — measure, do not trust the status.
r=$(rest "$TU" PATCH "bookings?id=eq.$B3" '{"booking_status":"cancelled"}'); code=$(echo "$r" | tail -1); body=$(echo "$r" | head -1)
[ "$code" = 200 ] && [ "$body" = "[]" ] && ok "a stranger's PATCH matches nothing and PostgREST says 200 [] (the trap)" || bad "stranger PATCH -> 200 []" "$r"

# 6. Host resurrects a cancelled booking → 138 refuses.
B6=bbbbbbbb-0000-0000-0000-000000000006
r=$(rest "$TH" PATCH "bookings?id=eq.$B6" '{"booking_status":"confirmed"}'); echo "$r" | head -1 | grep -q "booking_transition_forbidden" && ok "host cannot re-open a cancelled booking (138)" || bad "transition guard" "$r"

# 7. Self-promotion to admin (133).
r=$(rest "$TG" PATCH "profiles?id=eq.$GUESTV" '{"role":"admin"}'); echo "$r" | head -1 | grep -q "role_change_forbidden" && ok "self-promotion to admin refused (133)" || bad "self-promotion" "$r"

# 8. Host paints stars on own listing (138).
r=$(rest "$TH" PATCH "listings?id=eq.$L1" '{"rating":5,"review_count":999}'); echo "$r" | head -1 | grep -q "reputation_columns_protected" && ok "host cannot set own rating/review_count (138)" || bad "reputation guard" "$r"

# 9. Unverified guest books → 42501 identity_unverified (114).
r=$(curl -s -w "\n%{http_code}" -X POST "$API/rest/v1/rpc/create_marketplace_booking" -H "apikey: $ANON" -H "Authorization: Bearer $TU" -H "Content-Type: application/json" \
  -d "{\"p_listing_id\":\"$L1\",\"p_starts_at\":\"2026-12-01T04:00:00Z\",\"p_ends_at\":\"2026-12-01T06:00:00Z\",\"p_pricing_unit\":\"hour\",\"p_guest_count\":1}")
echo "$r" | head -1 | grep -q "identity_unverified" && ok "unverified guest cannot book (114)" || bad "identity gate" "$r"

# 10. Verified guest books a free slot, then cancels it; the row is theirs and cancelled_by is stamped.
r=$(curl -s -w "\n%{http_code}" -X POST "$API/rest/v1/rpc/create_marketplace_booking" -H "apikey: $ANON" -H "Authorization: Bearer $TG" -H "Content-Type: application/json" \
  -d "{\"p_listing_id\":\"$L1\",\"p_starts_at\":\"2026-12-02T04:00:00Z\",\"p_ends_at\":\"2026-12-02T06:00:00Z\",\"p_pricing_unit\":\"hour\",\"p_guest_count\":1,\"p_tenant_name\":\"QA Guest Verified\"}")
NEWB=$(echo "$r" | head -1 | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null)
[ -n "$NEWB" ] && ok "verified guest books a free slot (৳20, pending)" || bad "guest booking" "$r"
if [ -n "$NEWB" ]; then
  r=$(rest "$TG" PATCH "bookings?id=eq.$NEWB&select=booking_status,cancelled_by" '{"booking_status":"cancelled"}')
  echo "$r" | head -1 | grep -q "\"cancelled_by\":\"$GUESTV\"" && ok "a bare cancel is stamped with the guest (138)" || bad "cancelled_by stamped" "$r"
  # The host was told — through the notifications table the host can read.
  r=$(rest "$TH" GET "notifications?select=type&type=eq.booking_cancelled&data->>booking_id=eq.$NEWB")
  echo "$r" | head -1 | grep -q booking_cancelled && ok "and the host got a booking_cancelled notification" || bad "host notified of guest cancel" "$r"
  curl -s -o /dev/null -X DELETE "$API/rest/v1/bookings?id=eq.$NEWB" -H "apikey: $ANON" -H "Authorization: Bearer $(supabase status -o json | python3 -c 'import sys,json; print(json.load(sys.stdin)["SERVICE_ROLE_KEY"])')"
fi

# 11. Storage: a guest cannot upload into listing-images (134); the mime allowlist refuses HTML on chat-attachments (138).
r=$(curl -s -w "\n%{http_code}" -X POST "$API/storage/v1/object/listing-images/qa-smoke/x.png" -H "apikey: $ANON" -H "Authorization: Bearer $TU" -H "Content-Type: image/png" --data-binary 'xx')
echo "$r" | tail -1 | grep -qE "^(400|403)$" && ok "a guest who hosts nothing cannot upload a listing image (134)" || bad "listing-images insert gate" "$r"
r=$(curl -s -w "\n%{http_code}" -X POST "$API/storage/v1/object/chat-attachments/qa-smoke/x.html" -H "apikey: $ANON" -H "Authorization: Bearer $TG" -H "Content-Type: text/html" --data-binary '<b>x</b>')
echo "$r" | head -1 | grep -q "invalid_mime_type" && ok "HTML is refused by the chat-attachments allowlist (138)" || bad "chat-attachments mime allowlist" "$r"

# 12. Edge functions: payment init refuses a stranger's booking and an unpaid-but-pending one.
r=$(curl -s -w "\n%{http_code}" -X POST "$API/functions/v1/sslcommerz-init" -H "apikey: $ANON" -H "Authorization: Bearer $TU" -H "Content-Type: application/json" -d "{\"booking_id\":\"$B3\"}")
echo "$r" | tail -1 | grep -q "^403$" && ok "sslcommerz-init refuses a booking that is not yours" || bad "init 403" "$r"
r=$(curl -s -w "\n%{http_code}" -X POST "$API/functions/v1/sslcommerz-init" -H "apikey: $ANON" -H "Authorization: Bearer $TG" -H "Content-Type: application/json" -d "{\"booking_id\":\"$B1\"}")
echo "$r" | tail -1 | grep -q "^409$" && ok "sslcommerz-init refuses a booking already paid" || bad "init 409" "$r"

# 13. IPN: unknown tran_id, no auth — a 404, never a 500.
r=$(curl -s -w "\n%{http_code}" -X POST "$API/functions/v1/sslcommerz-ipn" -d "tran_id=NOPE&val_id=x&status=VALID")
echo "$r" | tail -1 | grep -q "^404$" && ok "IPN with an unknown tran_id answers 404" || bad "IPN unknown tran" "$r"

# 14. touch_device is authenticated-only: the anon key alone gets 401/403 (the pre-fix client did this on every launch).
r=$(curl -s -w "\n%{http_code}" -X POST "$API/rest/v1/rpc/touch_device" -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" -d '{"p_device_id":"qa-smoke-device-0001"}')
echo "$r" | tail -1 | grep -qE "^(401|403)$" && ok "touch_device without a session is refused" || bad "touch_device anon" "$r"

# 15. Suspension (140): the RPC is service-role only; a suspended number is refused at login
#     (the local master OTP works for the five seed numbers); lifting it lets them back in.
SVC=$(supabase status -o json | python3 -c 'import sys,json; print(json.load(sys.stdin)["SERVICE_ROLE_KEY"])')
r=$(curl -s -w "\n%{http_code}" -X POST "$API/rest/v1/rpc/admin_suspend_user" -H "apikey: $ANON" -H "Authorization: Bearer $TG" -H "Content-Type: application/json" -d "{\"p_user_id\":\"$GUESTU\",\"p_reason\":\"smoke\"}")
echo "$r" | tail -1 | grep -qE "^(401|403|404)$" && ok "admin_suspend_user is not callable with a user's JWT (140)" || bad "admin_suspend_user grant" "$r"
r=$(curl -s -w "\n%{http_code}" -X POST "$API/rest/v1/rpc/admin_suspend_user" -H "apikey: $SVC" -H "Authorization: Bearer $SVC" -H "Content-Type: application/json" -d "{\"p_user_id\":\"$GUESTU\",\"p_reason\":\"QA smoke: suspension round trip\"}")
echo "$r" | head -1 | grep -q "sessions_ended" && ok "service role suspends the unverified guest" || bad "suspend via service role" "$r"
r=$(curl -s -w "\n%{http_code}" -X POST "$API/functions/v1/verify-otp" -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" -d '{"phone":"01700000004","otp":"3969"}')
echo "$r" | head -1 | grep -q '"suspended":true' && ok "verify-otp refuses a suspended account's login (140)" || bad "suspended login refused" "$r"
r=$(rest "$TU" PATCH "listings?id=eq.$L1" '{"title":"x"}'); echo "$r" | head -1 | grep -q "account_suspended\|^\[\]$" && ok "a suspended token cannot write (or matches nothing)" || bad "suspended write" "$r"
curl -s -o /dev/null -X POST "$API/rest/v1/rpc/admin_unsuspend_user" -H "apikey: $SVC" -H "Authorization: Bearer $SVC" -H "Content-Type: application/json" -d "{\"p_user_id\":\"$GUESTU\"}"
r=$(curl -s -w "\n%{http_code}" -X POST "$API/functions/v1/verify-otp" -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" -d '{"phone":"01700000004","otp":"3969"}')
echo "$r" | head -1 | grep -q '"success":true' && ok "and logs in again once the suspension is lifted" || bad "unsuspended login" "$r"

# 16. No-show (139/140): reported before check-in time → the hint names the reason.
r=$(curl -s -X POST "$API/rest/v1/bookings" -H "apikey: $SVC" -H "Authorization: Bearer $SVC" -H "Content-Type: application/json" -H "Prefer: return=representation" \
  -d "{\"listing_id\":\"$L1\",\"tenant_id\":\"$GUESTV\",\"tenant_name\":\"QA Guest Verified\",\"starts_at\":\"2026-12-03T04:00:00Z\",\"ends_at\":\"2026-12-03T05:00:00Z\",\"booking_status\":\"confirmed\",\"pricing_unit\":\"hour\",\"unit_count\":1,\"total_price\":10,\"guest_count\":1}")
NS=$(echo "$r" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if isinstance(d,list) and d else '')" 2>/dev/null)
if [ -n "$NS" ]; then
  r=$(rest "$TH" PATCH "bookings?id=eq.$NS" '{"booking_status":"no_show"}'); echo "$r" | head -1 | grep -q "no_show_too_early" && ok "host cannot report a no-show before check-in time (140)" || bad "no_show_too_early" "$r"
  r=$(rest "$TG" PATCH "bookings?id=eq.$NS" '{"booking_status":"no_show"}'); echo "$r" | head -1 | grep -q "booking_transition_forbidden" && ok "guest cannot mark their own booking a no-show" || bad "guest no_show refused" "$r"
  curl -s -o /dev/null -X DELETE "$API/rest/v1/bookings?id=eq.$NS" -H "apikey: $SVC" -H "Authorization: Bearer $SVC"
else
  bad "no-show fixture booking" "$r"
fi

# 17. IPN redirect hardening (140 round): a `?redirect=cancel` on a PAID tran_id changes nothing.
PAYID=$(curl -s -X POST "$API/rest/v1/payments" -H "apikey: $SVC" -H "Authorization: Bearer $SVC" -H "Content-Type: application/json" -H "Prefer: return=representation" \
  -d "{\"booking_id\":\"$B1\",\"user_id\":\"$GUESTV\",\"tran_id\":\"QA-SMOKE-PAID-$$\",\"amount\":10,\"currency\":\"BDT\",\"status\":\"paid\"}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if isinstance(d,list) and d else '')" 2>/dev/null)
if [ -n "$PAYID" ]; then
  curl -s -o /dev/null -X POST "$API/functions/v1/sslcommerz-ipn?redirect=cancel" -d "tran_id=QA-SMOKE-PAID-$$&status=CANCELLED"
  r=$(curl -s "$API/rest/v1/payments?id=eq.$PAYID&select=status" -H "apikey: $SVC" -H "Authorization: Bearer $SVC")
  echo "$r" | grep -q '"status":"paid"' && ok "a guessed cancel redirect cannot un-pay a settled payment" || bad "IPN cancel on paid" "$r"
  curl -s -o /dev/null -X DELETE "$API/rest/v1/payments?id=eq.$PAYID" -H "apikey: $SVC" -H "Authorization: Bearer $SVC"
else
  bad "payments fixture" "no id"
fi

# 18. Rate limiting (140): the counter is not a client endpoint, and a call through a limited
#     function leaves a bucket behind — proof the function actually consults it.
r=$(curl -s -w "\n%{http_code}" -X POST "$API/rest/v1/rpc/fn_rate_limit_hit" -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" -d '{"p_bucket":"x","p_limit":1,"p_window_seconds":60}')
echo "$r" | tail -1 | grep -qE "^(401|403|404)$" && ok "fn_rate_limit_hit is not callable with the anon key" || bad "rate limit rpc grant" "$r"
curl -s -o /dev/null -X POST "$API/functions/v1/google-directions" -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" -H "x-forwarded-for: 203.0.113.77" -d '{"origin":"23.8,90.4","destination":"23.7,90.4"}'
r=$(curl -s "$API/rest/v1/edge_rate_limits?select=bucket,hits&bucket=like.google-directions:ip:*" -H "apikey: $SVC" -H "Authorization: Bearer $SVC")
echo "$r" | grep -q '"bucket":"google-directions:ip:' && ok "google-directions counted the anonymous call against its IP bucket" || bad "rate limit bucket" "$r"
curl -s -o /dev/null -X DELETE "$API/rest/v1/edge_rate_limits?bucket=like.google-directions:ip:*" -H "apikey: $SVC" -H "Authorization: Bearer $SVC"

echo; echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
