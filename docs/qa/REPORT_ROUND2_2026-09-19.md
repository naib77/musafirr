# QA round 2 — sixty scenarios as guests, hosts and the admin would live them

Written for: the Musafir owner and whoever ships the next release. Read
section 1 if you have two minutes; section 3 is the list you asked for.

Date: 2026-09-19. Environment: the local mirror built from the live catalog
(`tool/local_db_from_live.sh`, identical to live after 137), the local edge
runtime, and the SSLCommerz **sandbox** store. Nothing here touched
production. Everything in section 4 is written and tested locally; **nothing
is applied to live or deployed** — that is the remaining step and it is
yours to call.

The previous rounds are `REPORT_2026-09-18.md` (payments, S1–S3),
`REPORT_FULL_2026-09-18.md` (capability matrix, race, lifecycle, interface)
and `FIXES_2026-09-19.md`. This round deliberately went where those did not:
messaging, blocking, reviews, the booking state machine as a HOST drives it,
what a guest can edit after booking, automated messages, reminders,
timezone, identity resubmission, coupons, wishlists, hidden listings, chat
attachments, realtime, and the admin's own actions.

## 1. What matters

Sixty scenarios, driven for real rather than read. **Twenty-eight failed**
(one of them mitigated rather than fixed outright), two of them in ways a
guest would call theft or spying, and all of them are closed in this working
tree with a test that goes red without the fix. A same-day follow-up (§7)
then took the six rows this report had filed as notes — no refund policy, no
no-show outcome, no suspension, no rate limit, the unsigned IPN redirect, the
dead function — and closed those too, so **thirty-four of sixty** are now
fixes rather than observations.

The two that matter most:

- **Any participant could swap the other person out of a conversation**
  (scenario 8). One PATCH on `conversations` replaced the host with a
  stranger; the stranger then read the host's entire message history and the
  host lost the thread. RLS let it through because the UPDATE policy had no
  WITH CHECK and nothing froze the two ids.
- **A host could rewrite a booking's history** (14, 18, 19). Set a
  guest-cancelled booking back to confirmed, mark a booking complete without
  the guest ever checking in, un-reject a request. The whole booking state
  machine lived in Dart. This is also how the accept-after-cancel race ends:
  two PATCHes, last one wins, and the guest who cancelled is booked again.

Three more you will feel in support tickets:

- **Both parties reviewed; neither review ever appeared** (25). The
  double-blind reveal ran as the second reviewer and RLS let them flip only
  their own row. Live has not hit this yet — three hidden reviews, no pair —
  so it would have shown up with the first host who reviewed back.
- **Listings' star ratings never changed** (26). The recompute function
  existed, averaged a column that does not exist, and was attached to
  nothing. And the host could PATCH `rating = 5, review_count = 999` themselves (27).
- **A paid booking cancelled by either side told nobody money was owed** (20).
  The host's earning stayed posted; the guest saw a "Paid" pill on a
  cancelled trip.

And one that is a production fact rather than a code fault: **the live
realtime publication does not include `bookings`** (44). The app subscribes
to it; the subscription connects, reports active, and never fires. Hosts see
new requests only because the notification row arrives.

## 2. How it was driven

Five layers, each proving something the others cannot:

| Layer | What it proves | Where |
| --- | --- | --- |
| Rolled-back SQL impersonation | what the **database** refuses or allows, measured by **effect** (probe before/after), never by exception | `supabase/tests/138_qa_round2_test.sql`, 57 rows; every older suite re-run through `tool/qa/run_sql_tests.sh` |
| Real HTTP through GoTrue / PostgREST / Storage / functions | what the **client actually sees** — the `200 []` an RLS-filtered PATCH returns, a trigger's hint in the body, Storage's 415 | `tool/qa/http_smoke.sh`, 20 rows |
| Deno unit tests | the payment settlement decision, which cannot be exercised without a gateway session | `supabase/functions/_shared/settlement_test.ts`, 9 |
| A real SSLCommerz sandbox payment, twice | the plumbing end to end, including scenario 41 (cancel while the bank page is open) | `tool/qa/sandbox_pay.js` |
| Flutter analyze + 985 unit/widget tests | the client edits | `flutter test` |

The rule that keeps coming back: **an UPDATE whose rows RLS filters out matches
nothing and raises nothing.** Every write here probes a value before and
after. The smoke script has one row (5) that exists only to show PostgREST
answering `200 []` to a stranger's PATCH, because that is the trap.

Fixtures: the seeded accounts in `supabase/baseline/qa_seed.sql` — two hosts
(one with a seat and a room, one with a turf and a hidden house), a verified
guest, an unverified guest, eight racer guests and one admin — standing in
for the 80 guests and 50 hosts. Every scenario names which one acted.

## 3. The scenarios

Severity: **S1** money or identity; **S2** privacy or a broken core flow;
**S3** wrong information shown; **S4** hygiene. "Fixed" means fixed in this
tree with a test.

### Guest, browsing and booking

| # | Scenario | Result |
| --- | --- | --- |
| 1 | Signed-out visitor browses, filters by amenity, sees facilities chips | PASS — 3 active listings, 29 facilities, amenity search returns rows |
| 2 | Signed-out visitor reads profiles, bookings, exact addresses | PASS — refused outright (no grant / 0 rows) |
| 3 | Unverified guest presses Reserve | PASS — `42501 identity_unverified` (114) |
| 4 | Verified guest books a free hourly slot | PASS — pending, ৳20, host notified |
| 5 | Guest books over capacity, in the past, with reversed dates | PASS — refused (135 and earlier) |
| 6 | Guest books a host who switched to Away after the page was open | PASS — refused at the RPC |
| 7 | Turf: 3 hours at max 3 (৳6,000), then 4 hours | PASS — 4 hours refused "Maximum booking is 3 hours" |
| 60 | Daily and monthly bookings at Dhaka midnight: nights and months counted | PASS — 2 nights ৳3,000; Oct→Nov and Dec→Jan both 1 month ৳30,000 |

### Messaging and blocking

| # | Scenario | Result |
| --- | --- | --- |
| 8 | Guest swaps the host out of their conversation for a stranger | **FAIL S2 → fixed.** Stranger read the host's message. Participant ids are frozen (trigger). |
| 9 | Stranger plants a typing indicator / read cursor in a conversation they are not in | **FAIL S4 → fixed.** Policies now require membership. |
| 10 | Host blocks a guest; guest keeps messaging | **FAIL S2 → fixed.** Messages, new threads and bookings are refused across a block, both directions. |
| 11 | Conversation set to "blocked"; the other side flips it back to active | **FAIL S4 → mitigated.** Status is cosmetic now that the block itself is enforced server-side. |
| 12 | Blocked guest books the host who blocked them | **FAIL S2 → fixed.** `42501 blocked` from the booking RPC. |
| 13 | Guest cancels through the app (coordinator path) | PASS — host gets the cancellation message and notification |
| 30 | Host blocks a guest mid-stay; the automated checkout message | PASS — automated sends (null uid) still deliver |
| 40 | Guest sets their profile `mobile` to the host's own number and takes the host's name | **FAIL S3 → fixed.** The contact card and the "📞 Contact details" message now use the number the account logged in with (auth identity), falling back to `mobile` only for email-only accounts. |

### The booking lifecycle, as a host drives it

| # | Scenario | Result |
| --- | --- | --- |
| 14 | Host sets a guest-cancelled booking back to confirmed | **FAIL S1 → fixed.** Terminal states are terminal. |
| 15 | Guest cancels through the fallback path (status only) | **FAIL S3 → fixed.** Nobody was notified because `cancelled_by` was null; the trigger now stamps the caller and the client sends it. |
| 16 | Guest edits `guest_count` to 50, `listing_title`, `discount_amount` on their own booking | **FAIL S3 → fixed.** Everything the RPC decided is frozen. |
| 17 | Guest cancels with `cancelled_by` = the host's id | **FAIL S3 → fixed.** Told the guest "Cancelled by host", told the host nothing. `cancelled_by` must be the caller. |
| 18 | Host un-rejects a request; host completes a booking nobody checked in to | **FAIL S1 → fixed** (un-reject). Confirmed → completed stays allowed: the auto-complete sweep takes the same step. |
| 19 | Guest cancels and host accepts at the same moment | **FAIL S1 → fixed.** Last write won and the booking ended confirmed with `cancelled_by` set. Cancelled is terminal now. |
| 20 | Host cancels a PAID booking | **FAIL S1 → fixed.** Payment stayed `paid`, ledger kept the earning, nobody told. Now: every admin gets "Refund due", the guest is told a refund is coming, the console has a **Refund due** tab, and the guest's cancel dialog says what happens to their money. |
| 21 | Guest tries to accept their own request | PASS — refused |
| 22 | Host accepts: map, pre-check-in, contacts messages | PASS — three automated messages |
| 23 | Guest writes `host_message`, `confirmed_at`, `actual_check_in` | **FAIL S3 → fixed.** Host-side columns are the host's. |
| 24 | Confirmed booking, guest never checks in, never pays; 24h after checkout | **FAIL S3 → fixed (139/140, same day).** Auto-completed as if the stay happened, both sides prompted to review, counted toward the leaderboard. Now: the host has **Guest Didn't Arrive** from check-in time until the sweep; the booking becomes `no_show`, frees the slot, opens no review window, tells the guest, and returns nothing under the refund policy. Reporting it early is refused (`no_show_too_early`). |
| 31 | Guest cancels via the repository's bare update | **FAIL → fixed** (see 15) |

### Reviews and reputation

| # | Scenario | Result |
| --- | --- | --- |
| 25 | Guest and host both review the same stay | **FAIL S2 → fixed.** Neither review revealed. `check_and_reveal_reviews` is SECURITY DEFINER now. |
| 26 | After reveal, the listing card's stars | **FAIL S3 → fixed.** `listings.rating` never changed (unattached function averaging a missing column). Recomputed from revealed guest reviews on every review write; existing rows backfilled. |
| 27 | Host PATCHes `rating = 5, review_count = 999, is_superhost = true` on own listing | **FAIL S3 → fixed.** Refused; admins may still award the badge; a new listing starts at null/0/false whatever was sent. |
| 28 | Stay completed 3 days 5 hours ago; daily reminder sweep | **FAIL S3 → fixed.** Window was one hour wide at a once-a-day job — 23 of 24 completions never got a reminder. Day-wide now, idempotent on re-run. |

### Automated messages

| # | Scenario | Result |
| --- | --- | --- |
| 29 | Daily booking from 1 Oct 00:00 Dhaka; pre-check-in message | **FAIL S3 → fixed.** Said "check-in on Wednesday, September 30" (UTC). Dates render in Asia/Dhaka. |

### Identity and profile

| # | Scenario | Result |
| --- | --- | --- |
| 32 | Guest sets own `verification_status = verified` | PASS — refused (095/133) |
| 33 | Rejected applicant re-scans their NID | **FAIL S2 → fixed.** Stayed `rejected` (trigger fired on INSERT only, only from `none`; a re-scan is an upsert). The app worked around it by writing `pending` itself; the database does it now. |
| 34 | Host reads a guest's identity documents | PASS — 0 rows |
| 35 | Guest sets own role to admin | PASS — refused (133) |

### Coupons

| # | Scenario | Result |
| --- | --- | --- |
| 36 | Guest calls `redeem_coupon` on a booking made with no coupon, discount 99,999 | **FAIL S1 → fixed.** Burnt the coupon's single use and recorded ৳99,999. Redemption must match the booking's own coupon; the amount is the booking's; anon revoked. |
| 37 | Percentage coupon with a cap, below minimum amount | PASS |

### Listings, as a host manages them

| # | Scenario | Result |
| --- | --- | --- |
| 38 | Unverified account publishes | PASS — refused (114) |
| 39 | Host hides a listing while a guest holds a confirmed booking on it | **FAIL S3 → fixed.** Search hid it (right) and the guest's "View listing" came back empty (wrong). A guest who has booked a place can read it hidden or not. |
| 42 | Host deletes a listing with paid history | **FAIL S4 → fixed** in the client: the raw `host_ledger_entries_booking_id_fkey` text is now "has payment history … hide it instead". The refusal itself is correct — deleting would cascade payments and reviews away. |
| 43 | Wishlist entry on a listing the host later hides | **FAIL S4 → fixed (same day).** The card fell out of the grid without a word. Now a "No longer available" card with Remove stands in for it. |

### Payments

| # | Scenario | Result |
| --- | --- | --- |
| 41 | Guest starts paying; booking is cancelled while the bank page is open; guest completes payment | **FAIL S1 → fixed, and driven for real on the sandbox.** The IPN marked the cancelled booking paid and posted the host's earning. Now the payment is **held** (`pending_review`), the booking stays unpaid, admins are told to reject and refund, the guest is told a refund is coming — and `admin_release_payment` refuses to release onto a closed booking, so the wrong console button is dead. Decision extracted to `_shared/settlement.ts` with 9 tests. |
| 46 | Sandbox payment, clean card, confirmed booking | PASS — validated, settled, host + guest notified (`payment_received`). One of two sandbox runs came back `risk_level = 1` from the sandbox itself and was correctly held. |
| 47 | Second IPN / browser redirect after a hold | PASS (new) — answers "already held", no second alert |
| 48 | `sslcommerz-init` for a stranger's, a paid, a pending booking; 7th attempt in an hour | PASS — 403 / 409 / 409 / 429 |
| 49 | IPN `?redirect=cancel` with a guessed `tran_id`, no auth | **FAIL S4 → fixed (same day).** The unsigned redirect could rename any non-settled attempt. It may now close only an attempt still `initiated`; a settled, held or abandoned row is untouched (smoke row: a cancel redirect on a paid tran_id changes nothing). |

### Realtime and storage

| # | Scenario | Result |
| --- | --- | --- |
| 44 | Host's reservations screen while a guest books (postgres_changes on `bookings`) | **FAIL S2 on LIVE → fixed by migration.** Live's `supabase_realtime` publication carries conversations, messages, notifications, typing_indicators — not bookings. 138 adds it. The local mirror had none of them (the catalog dump does not carry publication membership); 138 also restores the four. |
| 45 | Guest uploads a 9 MB blob labelled PNG and a `text/html` "Musafir login" page to `chat-attachments`; tries to delete them | **FAIL S3 → fixed.** Both uploaded (no mime allowlist, unlike the other three buckets); Storage served the HTML as `text/plain` so it did not render, but an `.apk` would be offered to the other party as a download. Owner could not delete (policy checks `owner`, this Storage stamps `owner_id`). Allowlist set; picker restricted to match; delete policy checks both columns. |
| 59 | Hostile HTML in a public bucket, fetched | PASS — Storage rewrites to `text/plain` |

### Admin

| # | Scenario | Result |
| --- | --- | --- |
| 50 | Approve / reject / re-queue identity; resubmission | PASS (with 33) |
| 51 | Admin presses **Release** on a held payment whose booking was cancelled | **FAIL S1 → fixed.** Would have marked the cancelled booking paid. Refused with `booking_not_open`; Reject still works. |
| 52 | Admin marks a paid booking refunded | PASS — ledger reversal posted (101/137) |
| 53 | Admin wants to suspend a fraudulent account | **FAIL S2 → fixed (140, same day).** `admin_suspend_user` (service role): deletes the auth sessions, hides and remembers the listings, declines pending requests, withdraws the account's own; `verify-otp` refuses the next login; messages, threads, listings, reviews and booking moves are refused with `account_suspended`; the session watcher signs the device out on resume. Console: **Suspension** section on the user page with reason, plus badges. `admin_unsuspend_user` restores exactly what was hidden. |
| 54 | Non-admin signs into the console | PASS — signed straight back out; every dashboard page calls `requireAdmin` |
| 55 | Admin looks for cancelled-but-paid bookings | **new** — Bookings → **Refund due** tab |

### Platform

| # | Scenario | Result |
| --- | --- | --- |
| 56 | Call `geocode`, `places-search`, `google-directions`, `voice-parse` with only the anon key that ships in the bundle | **FAIL S3 → fixed (140 + `_shared/rate_limit.ts`, same day).** Fixed windows counted in `edge_rate_limits` through a service-role RPC; keyed by user id when signed in and by IP otherwise, with a wider per-IP allowance because CGNAT puts thousands behind one address. Over the limit is 429 with `Retry-After`; an unreachable counter fails open. Not deployed. |
| 57 | `validate-discount` | **FAIL S4 → source removed (same day).** Read tables that do not exist. Deleted from the repo and from the console's deployed-functions registry; still deployed on live as v20 until `supabase functions delete validate-discount` is run (production action, not done). |
| 58 | Signed-out launch calls `touch_device` | PASS — the client no longer calls it without a session (previous round); the RPC still refuses the anon key |

## 4. What was changed

**`supabase/migrations/138_qa_round2_guards.sql`** — not applied to live.
Bookings: host state machine (pending → confirmed/rejected/cancelled;
confirmed → active/completed/cancelled; active → completed/cancelled;
terminal states immutable), every RPC-decided column frozen, `cancelled_by`
must be the caller and is stamped when omitted, guest cannot touch host-side
columns, paid-cancellation alerts. Messaging: participant ids frozen, blocks
enforced on message insert, thread creation and booking, membership required
for typing indicators and read cursors, contact card uses the auth identity's
phone. Reviews: reveal runs as definer, listing rating recomputed from
revealed guest reviews (backfilled once), reputation columns frozen for
owners. Reminders day-wide and idempotent. Automated message dates in
Asia/Dhaka. Identity resubmission re-queues on INSERT or UPDATE from `none`
or `rejected`. `redeem_coupon` bound to the booking's own coupon. A guest who
booked a listing can read it hidden. `admin_release_payment` refuses a closed
booking. `bookings` added to the realtime publication. `chat-attachments`
mime allowlist and delete policy.

**Edge functions** — not deployed. `_shared/settlement.ts` (new, tested) and
`sslcommerz-ipn` uses it: holds a payment on a closed or already-paid
booking, distinct wording per reason, idempotent on "already held". CI runs
`deno test` on `_shared`.

**Client** — not built or deployed. Bare cancel sends `cancelled_by` /
`cancelled_at`; cancel dialog explains the refund when paid; chat paperclip
offers only what the bucket accepts; listing delete with payment history
explains itself.

**Admin console** — `Bookings → Refund due` tab. Type-checks and lints clean.

**Tests** — `138_qa_round2_test.sql` (57 rows), `http_smoke.sh` (20),
`settlement_test.ts` (9), `chat_attachment_allowlist_test.dart` (2);
`qa_reservation_lifecycle_test.sql` step 8 corrected (it passed only
because the reveal was broken).

## 5. What is still open, in order

Everything left is a production action; nothing is a code change.

1. **Apply 138, then 139 (commit), then 140 to live.** Until then every
   FAIL above is live behaviour. 139 adds an enum label and must be
   committed before 140 runs (55P04). Then regenerate the baseline and
   clear `NEWER_MIGRATIONS`.
2. **Redeploy the edge functions**: `sslcommerz-ipn` (the settlement hold and
   the redirect hardening), `sslcommerz-init` and `verify-otp` (suspension),
   `geocode`, `places-search`, `google-directions`, `voice-parse` (rate
   limits). Deploy AFTER 140 — the rate limiter calls `fn_rate_limit_hit`
   and fails open without it, so the order is safe but pointless reversed.
3. **Rebuild and deploy `build/web`** for the client fixes (this round's, the
   previous round's, and the no-show / wishlist work from the follow-up).
4. **Delete `validate-discount` from live** (57).

The two product decisions that were open — a refund policy and a no-show
outcome — are decided in §7 with defaults an admin can change.

## 6. Notes on method, for the next round

- Three of the older SQL suites failed on local leftovers, not on code:
  fixture rows a previous run had not rolled back (a payout method, nine
  device rows, seven notifications). Cleaned. A suite that writes outside
  `begin … rollback` will lie the second time it runs.
- `113_114_public_browse_and_identity_test.sql` resolves its subjects "from
  live data" with predicates the seed does not satisfy; rows 15–16 report
  BLOCKED for a null subject. Not a regression; the file needs seed-aware
  resolution before it can run locally.
- The SSLCommerz sandbox returned `risk_level = 1` on one of two identical
  "Success" runs. Do not read a held sandbox payment as a bug.
- The local Storage stamps `owner_id`, live stamps `owner`. Any storage
  policy on ownership must check both (134 did; the chat bucket's did not).

## 7. Follow-up, the same day: the open items

Section 5 used to list four code items. All four are closed in the working
tree, with the same standard as the rest of the round — a test that goes red
without the change — and none is applied, deployed or committed.

**A refund policy (20).** Two admin settings, `refund_full_window_hours`
(48) and `refund_late_pct` (50), validated like every other key. The rule in
one sentence: cancel at least the window before check-in and you get
everything back; cancel inside it and you get the late percentage; cancel
after check-in time, or do not turn up, and you get nothing; if the HOST (or
an admin) cancels you always get everything back. `fn_refund_policy_pct` is
the pure function; a BEFORE trigger stamps `refund_pct` / `refund_amount` on
a paid booking the moment it closes; the admin alert quotes the amount and
fires only when money is owed; the guest is always told what was decided,
including "no refund", because a silent zero reads as a forgotten refund.
The ledger reversal on "Mark refunded" is now the refunded SHARE of the
host's entry — it used to negate the whole earning whatever went back to the
guest, which left the platform holding half the money and the host none of
it. The console shows the stamp on the booking, the Refund due tab and the
refund dialog, and the Refund due queue excludes closures the policy priced
at zero.

**A no-show outcome (24).** 139 adds `no_show` to `booking_status`
(two files, because a new enum label cannot be used in the transaction that
adds it, and it is not reversible). 140 teaches the state machine
(`confirmed → no_show`, host only, after `starts_at`, refused early with
`no_show_too_early`), the lifecycle notifier, the refund policy (0%) and the
client: `BookingStatus.noShow` with an explicit wire name (the first value
whose Dart name and label differ — `.name` used to go straight to
PostgREST), `BookingRules.canMarkNoShow`, `BookingLifecycleService.markNoShow`,
a **Guest Didn't Arrive** button on the host's confirmed card, a trips hint
for the guest, a console badge, tab and timeline event. Everything that
already filtered on `pending|confirmed|active` or on `completed` — the two
exclusion constraints, `is_booking_available`, the address entitlement, the
review policy, the leaderboard, the auto-complete sweep — needed no change,
and the test pins that a no-show frees the slot and opens no review.

**Account suspension (53).** `profiles.suspended_at / _reason / _by`, frozen
for the account itself; `admin_suspend_user` / `admin_unsuspend_user` behind
`fn_require_service_role()`. Suspending deletes the account's `auth.sessions`
rows (the enforcement — the same move `revoke_device` makes), deactivates
its push tokens, hides its live listings and marks them so lifting restores
exactly those, declines requests waiting on it as a host and withdraws its
own as a guest. `verify-otp` refuses the next login before touching the
account. A token already issued is good for up to an hour, so every write
path it could reach is guarded: a trigger on messages, conversations,
listings and reviews; `enforce_booking_update_rules`;
`create_marketplace_booking` (either party); `get_or_create_conversation`
(either party); `sslcommerz-init`; and `touch_device` answers "revoked" so
the session watcher signs the device out on resume. Driven end to end in
`http_smoke.sh`: suspend the seeded guest through the RPC, watch the local
master OTP be refused, lift it, watch it log in.

**Rate limits (56).** `edge_rate_limits` + `fn_rate_limit_hit` (service
role only, fixed windows, counts past the limit so a hammering client keeps
seeing 429) and `_shared/rate_limit.ts` in the four functions. Per user
when the JWT has a `sub`, per IP otherwise; the per-IP allowance is wider
on purpose (CGNAT). Fails open with a log line. Limits per minute: geocode
60/240, places-search 120/600, google-directions 30/120, voice-parse 20/60
(user/IP). Reaped daily by pg_cron.

**Also closed:** the wishlist placeholder (43), the IPN redirect hardening
(49), the removal of `validate-discount` (57), and — found on the way — the
local mirror's `booking_accept_window_hours` and `max_devices_per_user`
held the junk values an older suite writes to prove the fallback, because
that suite had once been run without a rollback. Reset to 24 and 0.

**Verification, this follow-up:** `139_140_open_items_test.sql` 57/57;
`138_qa_round2_test.sql` 57/57 after four expectations moved with the code
(two refusals gained the 42501 hint the others had; the alert title now
carries the amount); all 22 SQL suites 414 rows green; `http_smoke.sh`
30/30; `deno check` on all twelve functions and 15 Deno tests;
`flutter analyze` clean, 1004 Dart tests; admin console `tsc` and `eslint`
clean.
