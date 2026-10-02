# Bulk SMS and bulk notifications (128, 129)

Moved verbatim from `CLAUDE.md` on 2026-10-01 to keep that file small.
The short rule for each section is still in `CLAUDE.md`; the reasoning is here.

### Bulk SMS is a queue, and the phone column is a gate (128)

The console can send one message to many people. `docs/features/bulk-sms.md` is the
whole design; the parts that will bite you:

- **`profiles.mobile` is not a send key.** 44 profiles, 40 distinct numbers,
  one row holding the literal string `pending_<uuid>` and one holding an
  unassigned prefix — **38 are actually reachable**. So
  `fn_canonical_bd_phone` is a *gate* that returns null for junk, deliberately
  unlike `normalizePhone` (otp.ts) and `canonicalBdPhone`
  (phone_number.dart), which are *routers* and must pass junk through so a
  mistyped login fails cleanly. Do not "keep them in step" by making this one
  permissive.
- **The audience prefers the auth identity to `profiles.mobile`.** The identity
  is the number that actually received an OTP; `mobile` is typed and displayed.
- **Claim-before-send, on purpose.** `admin_claim_sms_batch` marks rows
  `sending` and commits *before* GenNet is called, so a crash loses a message
  rather than repeating one, and such a row is never picked up again. Retry
  covers `failed` only. Test row 19 is the negative control and goes red the
  moment retry is made "helpful" enough to include `sending`.
- **Dedupe is the unique index on (campaign_id, phone)**, not the form. The
  form's count exists to be honest to the admin; the index exists to be safe.
- **`sms_bulk_max_recipients` fails CLOSED and 0 means DISABLED** — the
  opposite of `max_devices_per_user` (125) and `android_min_version_code`
  (122). Those fail open because they can lock a user out; this one fails
  closed because it can spend money irreversibly. Over the cap is **refused,
  never truncated**. Check which way the damage runs before copying the
  0-means-unlimited idiom again.
- **Opt-out is `sms_suppressions(phone)`, not a column on `profiles`** — a CSV
  number has no profile row, and that is the case most likely to need it.
  `transactional` bypasses the list and is not a marketing loophole.
- **Bangla is UCS-2: 70 characters per segment against 160.** The segment
  estimate is conservative (anything non-ASCII counts as Unicode) because
  over-estimating cost is the safe direction.
- **The pg_cron sweep must send an `Authorization` bearer AND
  `x-sms-worker-secret`.** The edge-function gateway 401s a request with no
  auth header *before* the function's own code runs, so the secret alone is a
  silent failure every minute — and the anon bearer alone is no authentication
  at all, since that key ships inside `build/web`. Same pair, same reason, as
  `send_push_on_notification_insert`. Needs `sms_worker_url`,
  `sms_worker_secret` and `sms_worker_auth` in `app_secrets`; missing any one
  makes the sweep a deliberate no-op.
- The Flutter app needs nothing from this — no client change, no `build/web`
  rebuild. `supabase/tests/128_sms_campaigns_test.sql` is 30 rows;
  `../musafir-admin` has `npm run check:sms` for the CSV parser, which is the
  only piece with no SQL test behind it.

### Bulk notifications are NOT the bulk-SMS design (129)

`docs/features/bulk-notifications.md`. Same console, deliberately different machinery,
because delivery already existed: `on_notification_send_push` fires on every
insert into `notifications`, so a campaign is one `insert … select` in one
transaction. **No queue, no worker, no cron sweep, no retry** — there is no
partway state to recover from, and adding 128's machinery here would be cargo
cult. `user_id` is the key, so a primary key does the deduplication a canonical
phone needed a unique index for. Reach is 44 of 44, against SMS's 38.

- **`notification_preferences` is LEFT joined and that is the whole ballgame.**
  Exactly ONE of 44 accounts has a row; an inner join reduces every campaign to
  **1 recipient** (measured). Absent row = the app's defaults.
- **Quiet hours cross midnight.** The default is 22:00–07:00, so
  `between start and end` is false for the entire window and pushes at 3am. An
  earlier version of the test used `now ± 1 hour`, which never wraps, and
  **passed against the broken implementation** — if you touch this, check the
  test can still fail.
- **`fn_notification_category` must cover every enum label**, or an unmapped
  type silently ignores the user's setting. The enums have already drifted:
  `booking_rejected`, `checked_in` and `review_prompt` exist in the database and
  not in the Dart enum. Test row 1 walks `enum_range` so the next addition
  fails loudly.
- **`data->>'suppress_push'` is a per-recipient flag, not a preferences check
  inside the trigger.** The key is absent from all 787 existing rows, so every
  notification the app already raises is untouched. A trigger that consulted
  preferences for everything would change booking and message delivery as a side
  effect of a marketing feature.
- **Known gap, not closed here: nothing outside bulk campaigns honours
  `notification_preferences` at all.** `shouldDeliver` in Dart is a client-side
  read and the push goes out regardless — the "the booking form checks it"
  pattern again.
- `notification_bulk_max_recipients` seeded 2000, fail-closed, 0 = disabled.
  `supabase/tests/129_notification_campaigns_test.sql` is 25 rows.
