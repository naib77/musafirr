# Devices and remote sign-out (123-127)

Moved verbatim from `CLAUDE.md` on 2026-10-01 to keep that file small.
The short rule for each section is still in `CLAUDE.md`; the reasoning is here.

### Devices are recorded, nothing is capped (123)

`user_devices` records which devices an account signs in from. Phase 0 of
`docs/features/device-sessions.md` — read that before extending this, particularly why
the device list has to ship before any limit does, and why web cannot share a
tight cap with phones.

- **It is not `fcm_tokens` (012) and not `auth.sessions`.** The first is keyed
  on the FCM token, and those rotate, so one phone becomes several rows. The
  second is GoTrue's, in the `auth` schema — PostgREST does not expose it, none
  of this repo's RLS applies, and it has no stable device identity.
- **The device id is a client-generated UUID, never a hardware id.** Android
  10+ refuses IMEI and serial, iOS's IDFV resets on uninstall, the web has
  nothing. The bound (8..128 chars) is enforced in both halves — the client
  should not send what the server will refuse with `22023`, and the server
  cannot trust the client to have checked.
- **Neither function takes a user id.** `register_device` and `touch_device`
  read `auth.uid()`, and `session_id` comes from `auth.jwt() ->> 'session_id'`
  rather than a parameter. A caller-supplied identity on a `SECURITY DEFINER`
  function is the hole 116 exists to close; 012's `upsert_fcm_token` takes
  `p_user_id` and is only safe because a later migration added the guard the
  repo file still does not show.
- **The table has no INSERT policy and no DELETE policy**, the shape
  `listing_availability_blocks` (110) uses. A client that could write rows
  could invent slots for itself under a cap. `update` is revoked and re-granted
  **column-wise on `label` alone** — the USING clause by itself would have let
  the client write `revoked_at`, `last_seen_at` and `session_id`, which are
  exactly what a cap depends on.
- **Registration is a client call only because Phase 0 enforces nothing.** The
  moment a cap exists it moves into `verify-otp`, the only place a session is
  minted and the only one running as service role. A client that can choose
  whether to register can choose not to.
- **`touch_device` answers false for an unknown device.** A device that has
  never registered is not a revoked one, and answering true would sign out a
  perfectly good session.
- `session_id` is nullable because a GoTrue without that claim must not stop a
  device being recorded — but **Phase 1 cannot ship until it is confirmed
  present**, or a remote sign-out has no row to delete and is theatre.
- Model and OS are **not** collected: that needs `device_info_plus`, a
  dependency and an Android manifest surface Phase 0 does not need. The columns
  exist so the build that adds it needs no migration, and `register_device`
  coalesces so a null never erases what an earlier launch knew.

### A device sign-out is a deleted auth.sessions row (124, 125)

`revoke_device` sets `revoked_at` **and deletes the `auth.sessions` row**. Only
the second half is enforcement: it removes the refresh token, so the device
dies at its next refresh whatever the client does. `revoked_at` alone is
bookkeeping a signed-out client could ignore, and a signed-out client is
precisely the one that will.

That works because `postgres` holds DELETE on `auth.sessions` even though
`supabase_auth_admin` owns it — **checked by doing it**, not by reading
`has_table_privilege`, because 115's whole lesson is that a permitted-looking
write can report success and change nothing. A delete inside a rolled-back
transaction took the count from 39 to 38.

- **`fn_revoke_device_row` and `fn_enforce_device_limit` take ids and do no
  ownership check**, because their callers already did. They are revoked from
  `public`, `anon` AND `authenticated` — PostgREST publishes everything in
  `public` at `/rest/v1/rpc/<name>`, so a grant left on either of them is a
  stranger ending your session. A test row asserts they are unreachable.
- **`revoke_other_devices` identifies the device to keep from the JWT**, never
  from a parameter. A caller who could name the device to keep could keep one
  that is not theirs.
- **The arriving device is protected by id, not by timestamp.** `now()` is
  transaction time, so two registrations in one transaction share a
  `last_seen_at` exactly and the tiebreaker decides who survives — the test
  caught the eviction signing out the device that had just logged in. A user
  must never be signed out by their own login, so that cannot rest on a
  comparison.
- **`max_devices_per_user` evicts, it never refuses.** The only way back into
  this app is a real SMS, and the master OTP is an unthrottled allowlist entry
  kept live for the Play reviewer — a device cap must never be what locks that
  account out mid-review. Seeded 0 = unlimited, the same fail-open as
  `android_min_version_code` (122), and its arm was added to
  `fn_validate_app_setting` by recreating that CASE in full.
- **Web is exempt from the count and from eviction.** A browser loses its id
  whenever site data is cleared, so it would consume the whole allowance by
  itself, and evicting one is pointless because the next visit is a new device.
- **The cap is enforced inside `verify-otp` (127), not in the client.** It was
  a client call through 125, so a client that never called `register_device`
  was never counted — the "booking form checks it" class. `admin_register_device`
  is the service-role twin (`register_device` reads `auth.uid()`, and inside
  the edge function there is no caller yet) and carries the same
  `Only service_role can execute this function` guard as every other `admin_*`.
  It is **non-fatal**: a bookkeeping failure must never turn "you reached your
  device limit" into "you cannot sign in".
- **`verify-otp` cannot record `session_id`** — the session is created when the
  client redeems the token hash, after the function returns. The client's own
  `register_device` fills it in, along with model and OS, and everything
  coalesces. So: **verify-otp owns the rule, the client owns the detail.** A
  device with no `session_id` can still be listed and evicted; it just cannot
  be remotely signed out until its next launch.
- **`upsert_fcm_token` gained a fifth parameter and the 4-arg version was
  DROPPED.** Two overloads where one has a default is ambiguous to PostgREST
  ("Could not choose the best candidate function"); one function with a default
  resolves a four-key call cleanly, so a deployed bundle keeps working. A test
  row pins exactly that.
- **Revoking a device deactivates its push tokens.** Without it a lost phone
  keeps showing messages after being signed out, which is most of what the user
  wanted stopped.

**126 reaps.** A revoked row is deleted after 180 days and an active one
unseen for 365 — two windows because they are two different problems, and 365
rather than 90 because a phone left in a drawer over a long trip is still the
user's phone. Reaping it would silently un-name it and hand back a slot nobody
asked for. Daily under `pg_cron`; contrast `expire_stale_bookings`, which runs
every 15 minutes because its window can be set to one hour.

`supabase/tests/123_user_devices_test.sql` is 13 rows,
`supabase/tests/124_125_device_limit_test.sql` is 20 and
`supabase/tests/126_reap_stale_devices_test.sql` is 6 and
`supabase/tests/127_device_limit_at_login_test.sql` is 7, all run rolled back
against live. Their negative controls are the point: direct insert, `revoked_at` write,
cross-user read, cross-user touch, cross-user revoke, short id, anon, the
internal functions being ungranted, and a malformed setting falling back to
"no limit" rather than to a lockout.

### `DeviceSessionWatcher` asks before anyone is signed in

`isRevoked()` returns early with no session now. It is called at startup and
on every resume without asking whether anyone is logged in, so every
signed-out visitor made a `touch_device` call the database refuses — the
function is granted to `authenticated` only and carries no `anon` grant. It
failed open and nothing broke, which is exactly why it went unnoticed for so
long: it showed up only as a red 401 in the console on every launch, and would
become one error-tracking event per visitor the moment Sentry is added.
