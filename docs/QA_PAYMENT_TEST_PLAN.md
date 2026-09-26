# QA on production with the master account, and how payments get tested

Written for: the Musafir owner and whoever runs QA, deciding how to exercise
the full booking and payment flow before a staging project exists.

Decision recorded here: QA logs in with **01673293542** and the master code
**3969**. That is the production master OTP entry, so every step below runs
against the live database, the live SSLCommerz store and real notification
channels. The plan is built so that this is safe, cheap and leaves a trail
that accounting can subtract.

Status 2026-09-18 evening: the refusal matrix AND the success, risk, fail and
cancel outcomes ran locally against a mirror of live through the real
SSLCommerz sandbox store (`docs/qa/REPORT_2026-09-18.md` section 4b;
driver `tool/qa/sandbox_pay.js`). Only the server-to-server IPN race and the
Flutter screens remain. Two more findings there: online payments never
notify (enum mismatch) and init has no per-booking cap.

## 1. What that account is, verified against live (2026-09-17)

| Fact | Value |
| --- | --- |
| Auth identity | `phone.1673293542@musaafir.app` (legacy spelling; `verify-otp` resolves it) |
| Profile | role `owner`, `verification_status = verified` |
| Listings | 3, two active: **cozy room 1** (seat, **৳10 per hour**, ৳1500 per day) and Osman Tower (৳150 per hour); one inactive |
| Bookings as guest | 25 |
| Master path | unthrottled; a wrong code falls through to "No active code" without counting (CLAUDE.md, QA section) |

Three things about the environment that decide the shape of this plan:

1. **SSLCommerz on live is the production gateway.** `SSLCZ_API_BASE` on the
   project resolves to `https://securepay.sslcommerz.com` (checked by hashing
   the two candidate URLs against the Management API's secret value, not by
   reading a doc). `docs/sslcommerz.md` still says "sandbox" in its first
   line; that is stale. There are no sandbox credentials anywhere in this
   project. Every online payment made during QA is real money.
2. **Small real payments have already been made on live**, by other accounts:
   four bKash payments of ৳10 and ৳20 between 4 and 14 August 2026, all
   settled to `paid`, plus eight `failed` and one `cancelled` at ৳10. So a
   ৳10 QA payment is a repeat of an established practice, not a new one.
3. **A host can book their own listing.** `create_marketplace_booking` has no
   owner check (the function body was read from `pg_proc`; it raises for
   unverified identity, dates, availability, capacity, duration, overlap,
   blocks and coupons, and never compares `owner_id` to `auth.uid()`). And
   `enforce_booking_update_rules` puts a caller who is both tenant and owner
   on the **owner** branch, so the same account can accept, check in and
   complete. One login therefore drives the whole loop: request, accept, pay,
   complete, refund. This is convenient for QA and is also a product finding
   (section 7).

## 2. Rules for running QA on production

These are not optional. Each one exists because of something in CLAUDE.md
that has already gone wrong here.

- **Book only the master account's own listings.** A request against any
  other host's listing sends that host a real push and a real SMS, and lands
  in their reservations list. `cozy room 1` at ৳10 per hour is the fixture;
  it is already the cheapest active listing on the platform.
- **Never widen `MASTER_OTP_PHONES`.** One number. If a second account is
  needed (section 5), it is a real phone that receives a real SMS.
- **Never point production at the SSLCommerz sandbox**, even for an hour. A
  guest paying during that hour would complete a sandbox transaction, see
  "Paid", and no money would arrive. The sandbox belongs to the staging
  project (`docs/QA_PLAN.md` section 3) and nowhere else.
- **Never post a forged IPN at a `tran_id` you do not own.** The IPN
  function is deployed without JWT verification on purpose, so it accepts
  anything. Posting `status=FAILED` against a real guest's in-flight
  payment marks their row `failed`. Tampering tests run against QA-owned
  rows only, and only the failure side (section 4.3).
- **Record every QA booking id** in `docs/qa/payment-runs.md` (create on the
  first run: date, booking id, `tran_id`, amount, outcome, who ran it). The
  account's earnings ledger, the payouts screen and any revenue report will
  otherwise count these as income.
- **Unset `MASTER_OTP` and `MASTER_OTP_PHONES` when QA and the Play review
  are both finished**, and re-set them for the next round. Both functions
  read secrets at runtime; no redeploy.

## 3. One live run of the complete loop (about 15 minutes, ৳10)

Do this on the deployed web build first, because web is the primary target
and the payment return path (`window.open`, the auto-closing page, the
**I've paid** button, the settlement poll) only exists there. Repeat on
Android afterwards for the WebView variant.

1. **Sign in.** Web, 01673293542, code 3969. Confirm the app lands on the
   existing account (Trips shows past bookings, Host dashboard shows three
   listings), not on a fresh empty one. An empty account means `verify-otp`
   resolved the identity wrongly; stop and report.
2. **Request.** Open `cozy room 1`, choose hourly, pick a one-hour slot
   tomorrow, one guest, Reserve. Expected: booking `pending`, guest
   countdown visible, price ৳10 computed by the server (the sheet shows the
   same number the `bookings.total_price` row holds).
3. **Accept as host.** Host dashboard, Reservations, Accept. Expected:
   `confirmed`; the guest side now shows **Pay ৳10**. Two real SMS go to
   01673293542 here (`send_booking_accept_messages` sends the guest and the
   host copy to the same number); that is the cost of a real channel.
4. **Pay online.** Trips, Pay, choose Online (the cash toggle is on, so the
   chooser appears), Open payment page. New tab: choose bKash, pay ৳10.
   Return, tap **I've paid**. Expected: the tab closed itself, the booking
   flips to Paid within the poll window, a notification arrives.
5. **Check the row**, admin console, Payments: one row for this booking,
   `status = paid`, `val_id` and `validated_at` set, `amount = 10.00`,
   `bank_tran_id`, `card_type` starting `BKASH`, `risk_level` populated,
   `gateway_response` present. `bookings.payment_status = paid`.
6. **Complete.** Host side, Service complete. Expected: `completed`. Then
   check the ledger posted an earning of ৳10 to this account
   (`fn_post_booking_ledger`).
7. **Refund switch.** Admin console, booking page, Mark refunded. Expected
   once finding 6 is fixed: `payment_status = refunded`, a reversing ledger
   entry, a second click is a no-op. Today it reports "Only a paid booking
   can be marked refunded" against a paid booking; that is finding 6, not a
   test failure. This moves no money; the ৳10 stays with the store unless
   refunded in the SSLCommerz merchant panel. For QA amounts, leave it and
   record it.
8. **Log it** in `docs/qa/payment-runs.md`.

Variants, each a separate booking so the rows stay readable:

| Variant | How | Expected |
| --- | --- | --- |
| Gateway cancel | On the bKash page press Cancel | `payments.status = cancelled`, booking `unpaid`, Pay button still there, next attempt makes a new `tran_id` |
| Gateway fail | Wrong bKash PIN three times, or an account with ৳0 | `failed`, booking `unpaid`, guest sees a real error rather than a spinner |
| Close the tab mid-payment | Pay in bKash, close the tab before the redirect | booking flips to Paid anyway **only if** IPN is enabled in the merchant panel; if it stays `unpaid` and `initiated`, IPN is off (section 7) |
| I've paid too early | Tap it before paying | "Still confirming", no `paid`; complete the payment; poll picks it up |
| Cash | Pay, choose Hand cash | `payment_method = cash`, booking still `unpaid`; host taps Confirm cash received; `paid`, a `CASH-<id>` payments row, guest notified |
| Pay before accept | Skip step 3, try to pay | No Pay button; `sslcommerz-init` refuses if called directly |
| Pay after complete | Complete an unpaid cash booking is refused; pay a completed booking is refused | both refusals visible |

Cost of the full table: about ৳40 in real payments plus a handful of SMS.

## 4. The scenario matrix without money

Most of the payments table in `docs/QA_PLAN.md` section 4.6 is about the
IPN handler's decisions, and those do not need a gateway at all.

### 4.1 Deno unit tests on the settlement logic (do this first)

`supabase/functions/sslcommerz-ipn/index.ts` is one `serve` closure. Extract
its body into `settle(body, deps)` in `_shared/sslcommerz_settle.ts` where
`deps` is `{ db, validate }`, and test it with `deno test` using an in-memory
`db` and a stubbed `validate`. Rows to write, each with a negative control:

- replayed IPN five times: one update, `neq('status','paid')` guard holds
- tampered `amount`: `failed`, booking untouched
- `val_id` from another transaction (`tran_id` mismatch): `failed`
- unknown `tran_id`: 404, nothing written
- FAILED and CANCELLED from the gateway: rows marked, booking `unpaid`
- validation API timeout or non-JSON: no `paid`, row left for the poll
- validation says `VALID` but amount differs by one poisha: `failed`
- redirect and IPN arriving together: exactly one `validated_at`

Same treatment for `sslcommerz-init`: refuses `pending`, `completed`,
already `paid`, zero amount, and ignores any amount in the request body.

Add `deno test supabase/functions` to CI next to `deno check`. This is the
piece the current suite has none of, and it is where a wrong decision costs
money.

### 4.2 SQL contract tests, rolled back against live

The repo pattern (`supabase/tests/`, `set local role`, rollback). Rows:

- `mark_cash_payment` as the tenant, not the owner: `42501`
- `mark_cash_payment` twice: one row, `on conflict do nothing`
- `set_booking_payment_method('cash')` with `cash_payment_enabled = false`:
  refused
- direct `insert into payments` as `authenticated`: refused (the table has
  only a SELECT policy; that must stay true)
- direct `update bookings set payment_status = 'paid'` as the tenant, and
  as the owner: refused; `payment_status` is not in the owner's allowed set,
  confirm it, because `enforce_booking_update_rules` returns `new` for an
  owner and the column list it protects does not name `payment_status`
- Service complete while `payment_status <> 'paid'`: refused
- `markBookingRefunded` twice: second is a no-op
- a `payments` row visible to its guest, to the listing's host, to admin,
  and to nobody else

### 4.3 Live IPN probes, QA rows only

Two probes are safe on production because the function cannot be talked
into `paid` without a genuine `val_id`, and they run only against a
`tran_id` from a QA booking made minutes earlier:

- POST with the QA `tran_id`, `status=VALID`, an invented `val_id`:
  expected `validation failed`, row `failed`. Then pay for real on a new
  attempt to confirm recovery.
- POST with a `tran_id` that does not exist: expected 404.

Everything on the success side (a real `val_id` replayed, amount tampering
with a real `val_id`) waits for the staging project and its sandbox store.

## 5. What one account cannot show

- **Two different people.** Guest-side refusals against a host's actions
  (a guest trying to accept, a stranger trying to read the payment) need a
  second identity. Until staging exists, use the SQL impersonation rows in
  4.2, which set `auth.uid()` to any id; do not create a second live account
  for it.
- **Another host's notification.** That is exactly what the rules forbid.
- **Refund money movement.** Nothing in the app moves money back; the
  admin action flips a status and posts a reversing ledger entry, and the
  refund itself is manual in the merchant panel or a disbursement. Test the
  status; the manual step is a runbook item, not a test.

## 6. Cleanup after each round

- Every QA booking is `completed` and either `refunded` or logged as a
  known ৳10. Nothing left `pending` (it would auto-reject after 24 hours and
  send another SMS) and nothing left `confirmed` and `unpaid`.
- The account's earnings for the round are subtracted in any payout: the
  ledger will show them as due to the host, who is the tester.
- `docs/qa/payment-runs.md` updated.
- When the round and the Play review are done: unset the two master secrets.

## 7. Findings from preparing this plan

Not fixed here; each is a candidate row in `docs/QA_PLAN.md`.

1. **A host can book their own listing.** No check in
   `create_marketplace_booking`. Harmless for QA, odd for a marketplace: a
   host can post earnings to themselves by paying themselves, and the
   listing shows as booked. Decide whether to refuse it (one `raise` with
   its own hint, plus the client message) or keep it.
2. **27 `initiated` payments totalling ৳52,420 have sat since July and
   August.** Nothing expires an abandoned attempt, so the payments table
   carries every closed tab forever and any "attempts vs. settled" report
   is wrong. A 24-hour sweep marking `initiated` older than a day as
   `abandoned` (or `failed` with a reason) is one migration and one cron
   entry, same shape as `expire_stale_bookings`.
3. **IPN may not be enabled in the merchant panel.** `docs/sslcommerz.md`
   calls it optional. Without it, a guest who pays and closes the tab
   before the redirect has paid and is shown `unpaid` until they tap I've
   paid; and if the redirect is lost, forever. The variant in section 3
   tells you which state you are in. Turn it on.
4. **`docs/sslcommerz.md` says sandbox; live is production.** Update the
   first line and the Testing section, and add the section 2 rules.
5. **A guest or a host can mark their own booking `paid` with one
   PostgREST PATCH. Confirmed live, rolled back, 2026-09-17. S1.
   Migration 132 APPLIED to live 2026-09-18 on the owner's instruction;
   the eight-row test passed against the applied state. CLOSED.** Three things line
   up: `authenticated` holds column UPDATE on `bookings.payment_status`;
   the RLS update policies admit the tenant (`auth.uid() = tenant_id`, no
   WITH CHECK) and the listing owner; and `enforce_booking_update_rules`
   protects tenant, listing, price and dates but never `payment_status`.
   Impersonating the tenant of a real `completed, unpaid` booking and
   running `update bookings set payment_status = 'paid'` succeeded; so did
   the same as the host. That fires `trg_post_booking_ledger`, so the host
   is owed a payout for money that never moved, and Service complete
   unlocks.

   `supabase/migrations/132_guard_payment_columns.sql` adds a guard to the
   trigger for `payment_status`, `payment_method` and `paid_at`, and lets
   the two SECURITY DEFINER payment RPCs through by a transaction-local flag
   they raise around their own write. It is a trigger guard rather than a
   column revoke because the admin console writes `payment_status` with the
   admin's JWT; the revoke is the follow-up once that write moves to the
   service-role client. `supabase/tests/132_guard_payment_columns_test.sql`
   is eight rows, run rolled back against live: rows 1 to 3 are red without
   the migration and green with it; rows 4 to 8 (cash choice, cash confirm,
   admin exemption, guest cancel, service-role settle) are green both ways.
   Applied 2026-09-18; bookings 106 / payments 51 / paid 15 unchanged by the apply.
6. **The admin console's "Mark refunded" is a no-op on live today.**
   `bookings` has two UPDATE policies, host and tenant, and none for
   admins; the console updates the row with the admin's own JWT, so the
   PATCH matches zero rows and the action reports "Only a paid booking can
   be marked refunded" for a booking that is paid. Found while writing test
   row 6, which had to switch to testing the trigger's admin exemption as
   `postgres` for exactly this reason. Fix is in the admin repo: use the
   service-role client (`createServiceClient` already exists in
   `lib/supabase/server.ts`) or an `admin_*` RPC. Section 3 step 7 will
   show this until it is fixed.

## 8. Order

0. Done 2026-09-18: migration 132 applied to live, test green on the
   applied state. It is the one item here where a stranger costs the
   platform money today.
1. Section 4.1 Deno tests, in CI. No money, covers most of the table.
2. Section 4.2 SQL rows, especially the `payment_status` one.
3. One live run of section 3, web, then the variants. ৳40.
4. Same on Android.
5. Then finding 6 in the admin repo, findings 2 and 3 as a migration and a
   panel setting, 1 and 4 as decisions.
