# Payments, QA round 2 hardening, refunds, suspension (136-140)

Moved verbatim from `CLAUDE.md` on 2026-10-01 to keep that file small.
The short rule for each section is still in `CLAUDE.md`; the reasoning is here.

### A flagged payment is not a settled payment (136, applied 2026-09-19)

**The migration is live and the two edge functions are NOT redeployed yet.**
That order is the safe one and the reverse is not: the functions write
`pending_review` and `abandoned`, which the CHECK constraint refused before
136. Until they are deployed, online payments still send the wrong
notification type and a risk-flagged payment still settles as paid.

SSLCommerz sets `risk_level` non-zero with a `risk_title` on an otherwise
VALID transaction when its fraud screen fires, and its own guidance is to hold
that payment for review before delivering the service. `sslcommerz-ipn` stored
both fields and marked it paid anyway, which unlocks Service complete and
posts the host's earning at once.

- Such a payment is now `pending_review`, **and the booking stays unpaid** —
  that second half is the enforcement; the payment row is bookkeeping. The
  guest is told their money arrived and is being checked, and every admin gets
  a `security_alert`.
- It is resolved from the **Held** tab of the console's Payments screen, which
  calls `admin_release_payment` / `admin_reject_payment` with the
  service-role client. Both carry `fn_require_service_role()` like every other
  `admin_*`: an admin's own JWT is deliberately not enough, because releasing
  is the one action there that moves money. `admin_release_payment` raises
  `musafir.settlement_write` around its booking write, exactly as 132 requires
  of any new writer of those columns.
- **Attempts are closed now, in two places.** `sslcommerz-init` abandons this
  booking's earlier `initiated` rows before creating another and refuses after
  six in an hour; `expire_stale_payment_attempts` sweeps anything `initiated`
  for over an hour every 15 minutes. Live carried 27 such rows worth ৳52,420
  from July and August. Neither ever touches `paid` or `pending_review`, and a
  guest who pays after the sweep still settles — the IPN finds the row by
  `tran_id`.
- The window is hardcoded at 60 minutes, unlike `booking_accept_window_hours`
  (119). That one is a setting because it is visible to guests as a countdown
  and a host argued about it; this one only decides when a dead row stops
  being called `initiated`.

### The rules that lived only in Dart (138, applied 2026-09-26)

The second QA round (`docs/qa/REPORT_ROUND2_2026-09-19.md`, sixty
scenarios, twenty-eight failed) found the same class of hole seven more times:
a rule the client enforced and the database did not. 138 closes them all;
`supabase/tests/138_qa_round2_test.sql` (57 rows) goes red with it reverted.
It is on live as of 2026-09-26, so each bullet below describes what the
database *used* to allow. **The suite cannot verify live**: it impersonates
`qa_seed` accounts that exist only on the mirror. Live was checked instead
with a rolled-back probe — a real host was refused `42501` reopening a
rejected booking, and the rating backfill matched the revealed reviews.

- **A host could rewrite a booking's history.** `enforce_booking_update_rules`
  returned `new` for the listing owner unconditionally — the state machine
  was `BookingLifecycleService` (Dart). Measured: cancelled → confirmed,
  rejected → confirmed, confirmed → completed with no check-in. The
  accept-after-cancel race ends the same way: two PATCHes, last one wins.
  The trigger now holds the table the Dart service documents (pending →
  confirmed | rejected | cancelled; confirmed → active | completed |
  cancelled; active → completed | cancelled; terminal states immutable).
  `confirmed → completed` stays allowed because `auto_complete_elapsed_bookings`
  takes exactly that step. Admins and the service role are still exempt.
- **A guest could edit anything the RPC decided.** `guest_count`,
  `unit_count`, `pricing_unit`, the coupon columns, the `listing_*` copies
  and `tenant_name` are frozen for non-admins now; host-side columns
  (`host_message`, `confirmed_at`, …) are the host's. `cancelled_by` must be
  the caller and is stamped when omitted — the repository's bare cancel sent
  the status alone, `notify_on_booking_lifecycle` keys on `cancelled_by`, so
  that path notified nobody, and a guest who set it to the HOST's id was told
  "Cancelled by host".
- **A paid cancellation told nobody money was owed.** `trg_alert_paid_cancellation`
  puts "Refund due" in every admin's inbox and tells the guest; the console
  has a **Refund due** tab (Bookings). There is still no refund policy — this
  only makes the ৳ visible.
- **Either participant could swap the other out of a conversation.** The
  UPDATE policy has no WITH CHECK; a guest replaced the host with a stranger,
  who then read the host's messages. Participant ids are frozen by trigger.
- **Blocks were a client-side filter.** `user_blocks` hid threads on the
  blocker's phone; the blocked person kept messaging, kept raising pushes,
  and could book the blocker's listing. `fn_users_blocked` is consulted on
  message insert, `get_or_create_conversation` and
  `create_marketplace_booking` — both directions, `42501 blocked`. Automated
  sends (null uid) still deliver: a host who blocks a guest mid-stay still
  owes them the checkout message. `fn_users_blocked` and `fn_identity_phone`
  are revoked from every client role; the triggers that call them are
  SECURITY DEFINER for that reason.
- **The double-blind reveal never worked for the second reviewer.**
  `check_and_reveal_reviews` was SECURITY INVOKER; its UPDATE ran as the
  reviewer, and `reviews_update_own` let them flip only their own row. Both
  stayed hidden until the 14-day sweep. Definer now. Live has 3 hidden
  reviews on 3 bookings and no pair yet.
- **`listings.rating` never changed.** `update_listing_rating()` averaged a
  column reviews does not have and was attached to nothing; the explore card
  reads `listings.rating`. `fn_refresh_listing_rating` recomputes from
  **revealed** `guest_to_host` reviews on every review write (backfilled
  once), announcing itself with `musafir.rating_write` — 132's flag pattern —
  so `fn_freeze_listing_reputation` can refuse an owner's own `rating` /
  `review_count` / `is_superhost` write and zero them on insert. The backfill
  rounds to two places but **the column is `numeric(2,1)`**, so a computed
  4.81 is stored as 4.8 — do not read that one-decimal difference as the
  backfill having missed a review. On apply it set 8 of 20 listings and
  nulled the other 12, which have no revealed review.
- **Review reminders reached 1 stay in 24.** A one-hour `completed_at` window
  inside a once-a-day cron. Day-wide now, deduplicated per booking per day.
- **Automated message dates were UTC.** A stay from midnight Dhaka on 1 Oct
  is 18:00 UTC on 30 Sept, so `to_char(starts_at, …)` said September 30.
  `send_precheckin_for_booking` / `send_checkout_for_booking` render
  `at time zone 'Asia/Dhaka'`; Bangladesh has one zone and no DST.
- **A rejected applicant never re-entered the queue.** `set_verification_pending`
  fired on INSERT only and moved only `none`; a re-scan is an upsert. INSERT
  or UPDATE of `file_path`, from `none` or `rejected`.
- **`redeem_coupon` took the discount as a parameter.** One call burnt a
  limited coupon's single use on a booking that never carried it. It must now
  match `bookings.coupon_code`, records the booking's own `discount_amount`,
  and is revoked from `anon`.
- **The contact card handed over `profiles.mobile`**, which its owner can
  type anything into. `fn_identity_phone` derives the number from the auth
  identity (`phone.<n>@musaafir.app`), the same way `admin_sms_audience`
  does; `mobile` is only the fallback for email-only accounts.
- **A guest who booked a now-hidden listing could not open it.** The SELECT
  policy was "active or mine"; `listings_select_booked_guest` adds "or I have
  a booking on it".
- **`admin_release_payment` would pay a cancelled booking.** It checked only
  the payment's status. It refuses unless the booking is confirmed or active;
  Reject is the only move on a closed booking.
- **Live's realtime publication does not include `bookings`.** The app
  subscribes to it; the subscription reports active and never fires. 138
  adds it, idempotently, plus the four live already has — the local mirror
  had none, because the catalog dump does not carry publication membership.
- **`chat-attachments` accepted any file type.** Mime allowlist set (images,
  PDF, office formats, text); the picker offers the same list
  (`ImageUploadService.chatAttachmentExtensions`, pinned by a test); the
  delete policy checks `owner_id` as well as `owner`.

**`sslcommerz-ipn` holds a payment that lands on a closed booking.** A guest
who starts paying, whose booking is cancelled while the bank page is open,
and who completes the payment, used to get the cancelled booking marked
paid and the host an earning. The decision is `_shared/settlement.ts`
(`decideSettlement`), a pure function with its own Deno tests that CI runs;
the booking's state is checked BEFORE the fraud flag on purpose, because the
admin's next step differs (refund, never release). Driven for real on the
sandbox. **Not yet redeployed.**

Two things about running the SQL suites, learned the expensive way this
round: **most of them do not roll themselves back.** They were written to be
pasted into the Management API inside a transaction a human opens. `psql -f`
commits them; so does `psql -1`. Twelve listings, eight bookings, eleven
devices and forty-four notifications were left in the local mirror, and the
seed hosts came out unverified. Use `sh tool/qa/run_sql_tests.sh`, which
wraps each file. And `tool/qa/http_smoke.sh` is the same round one layer up
— real logins, real PostgREST — for the things only the API shows (a
stranger's PATCH answering `200 []`).

### Refunds, no-shows, suspension and a rate limit (139/140, applied 2026-09-26)

The follow-up to the second round closed the four items 138 left open
(`docs/qa/REPORT_ROUND2_2026-09-19.md` §7). `supabase/tests/139_140_open_items_test.sql`
(57 rows) goes red with 140 reverted. **139 must be COMMITTED before 140
runs** — it adds `no_show` to `booking_status`, and a new enum label cannot
be used in the transaction that added it (55P04, the 120/121 shape). Not
reversible.

- **The refund policy is two settings and one pure function.**
  `refund_full_window_hours` (48) and `refund_late_pct` (50);
  `fn_refund_policy_pct(status, cancelled_by, tenant, starts_at, at)`.
  Host or admin cancels → 100. Guest cancels ≥ window before check-in → 100;
  inside it → late pct; after check-in time → 0. No-show → 0. A BEFORE
  trigger (`trg_stamp_refund_policy`) writes `refund_pct` / `refund_amount`
  on a PAID booking as it closes; both columns are in the frozen list, so a
  client cannot pre-fill them. **Trigger order is by name and it matters:**
  `trg_enforce…` runs before `trg_stamp…`, so the guard sees what the client
  sent, then the stamp fills it in. Rename either and check that still holds.
- **The admin alert fires only when money is owed; the guest is always
  told.** A silent zero reads as a forgotten refund. The alert title carries
  the amount (`Refund due: ৳500.00`) — a test that matches the old bare
  title now fails, which is how 138's row 17 was found.
- **"Mark refunded" reverses the refunded SHARE.** `fn_post_booking_ledger`
  used to negate the host's whole entry whatever went back to the guest; it
  is `refund_pct` of it now, null meaning all (rows that closed before 140).
  A 0% policy posts nothing — the CHECK forbids a zero-amount row anyway.
- **`no_show` is `confirmed → no_show`, host only, after `starts_at`.**
  Early is refused with hint `no_show_too_early` (its own hint, because the
  client wants to say "not yet" rather than "not allowed"). Terminal. Nothing
  else needed teaching: both exclusion constraints, `is_booking_available`,
  `can_see_listing_address`, `reviews_insert`, the leaderboard and the
  auto-complete sweep already filter on `pending|confirmed|active` or on
  `completed`. The test pins that a no-show frees the slot and opens no
  review, so a future rewrite of any of those lists fails loudly.
- **`BookingStatus.noShow` is the first value whose Dart name and label
  differ.** The repository sent `.name` to PostgREST; it sends `.wire` now
  and parses with `BookingStatusWire.fromWire`, which reads an unknown label
  as pending rather than throwing. Three exhaustive switches had to grow an
  arm (`booking_status.dart`, the host reservations screen twice, the trips
  screen twice); the analyzer finds them.
- **Suspension is a deleted session, not a flag.** `admin_suspend_user`
  (service role only — an admin's own JWT cannot end another person's access
  from a table write) sets `suspended_at/_reason/_by`, deletes
  `auth.sessions` for the user, deactivates their push tokens, hides their
  live listings (`listings.suspended_hidden` remembers which, so
  `admin_unsuspend_user` restores exactly those), declines pending requests
  on their listings and withdraws their own. An admin cannot be suspended;
  change the role first. **The flag alone stops nothing for an hour** — an
  access token already issued is valid until it expires — so every write
  path is guarded: `fn_refuse_suspended_writer` on messages, conversations,
  listings, reviews; `enforce_booking_update_rules`;
  `create_marketplace_booking` and `get_or_create_conversation` (either
  party); `sslcommerz-init`; `verify-otp` refuses the next login BEFORE
  rotating the password; and `touch_device` answers "revoked" so
  `DeviceSessionWatcher` signs the device out on resume. `fn_is_suspended` is
  revoked from every client role; the guards are SECURITY DEFINER.
- **The rate limit is a table, and it fails open.** `fn_rate_limit_hit`
  (service role only) counts fixed windows in `edge_rate_limits`;
  `_shared/rate_limit.ts` keys by the JWT `sub` when `role` is
  `authenticated` and by IP otherwise — the anon key is itself a JWT with no
  `sub`, so checking for a token would put every signed-out visitor in one
  bucket. **Per-IP limits are deliberately several times the per-user
  ones**: Bangladeshi operators put thousands of subscribers behind one
  CGNAT address. An unreachable counter logs and lets the request through; a
  limiter that can take search down is the worse outage. 429 carries
  `Retry-After`. Reaped daily.
- **The IPN's `?redirect=fail|cancel` may only close an `initiated`
  attempt.** Those redirects are unsigned browser POSTs; anyone with a
  tran_id could rename a settled row before. The success path still skips
  only `paid` and `pending_review`, so a real IPN settles over a spoofed
  cancel.
- `validate-discount` is gone from the repo and the console's registry; it
  is still deployed on live (v20) until someone runs
  `supabase functions delete validate-discount`.

Running 139_140 also found the local mirror carrying `whenever` and `lots`
in `booking_accept_window_hours` / `max_devices_per_user` — 119's and 125's
tests write junk past the validator to prove the fallback, and had once been
run without a rollback. `run_sql_tests.sh` exists so that cannot recur; if a
setting on the mirror looks wrong, that is why.
