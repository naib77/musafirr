# Device sessions

How Musafir records the devices an account signs in from, and how a limit on
that number would be enforced if one is ever turned on.

All phases are implemented (migrations 123-127). **Nothing is
restricted until an admin types a number**: `max_devices_per_user` is seeded at
0, which means no limit. That ordering was deliberate and is worth keeping in
mind before changing it — you cannot safely cap a number before people can see
and manage what they are using, and you should not pick the number before you
can see the real distribution.

## How it works, end to end

A worked example with the cap set to **2**. Nothing below happens at the
default of 0.

**1. Rahim signs in on his phone.** The app generates a UUID once and keeps it
in `SharedPreferences`; `register_device` upserts a row and stamps
`last_seen_at`. He is one of two.

```
user_devices (Rahim)
  dev-a1b2…  android  "Pixel 8"   last_seen  now
```

**2. He signs in on his wife's phone to show her a listing.** Two of two. Both
work; nothing is evicted.

**3. He opens the site on his laptop.** A third device — but `platform = 'web'`,
and web is not counted, so nothing happens to either phone. The browser gets a
row so it can be listed and signed out, and that is all.

```
dev-a1b2…  android  last_seen 2 min ago   ← counted
dev-c3d4…  android  last_seen 1 hour ago  ← counted
dev-e5f6…  web      last_seen now         ← NOT counted
```

**4. He buys a new phone and signs in.** `verify-otp` — not the app — records
the device and applies the cap before it hands back a session, so this happens
whether or not the client cooperates. Now three counted devices against a limit
of 2. `fn_enforce_device_limit` runs *after* the upsert, ranks the
non-web devices with the arriving one pinned first and the rest by
`last_seen_at` descending, and revokes everything past position 2 — his wife's
phone, unused the longest.

That eviction does two things, and only the second is enforcement:

```sql
update user_devices set revoked_at = now() where id = <wife's row>   -- bookkeeping
delete from auth.sessions  where id = <that row's session_id>        -- the actual sign-out
```

He is told, on whichever device he is holding: *"You reached your device limit,
so Shireen's phone was signed out."* A `security_alert` notification, which the
existing `on_notification_send_push` trigger delivers. An eviction is the one
event here nobody asked for, so it is the one that is announced — a sign-out he
performed himself needs no telling.

**5. His wife picks up her phone an hour later.** Her access token is still
within its lifetime, so the app would keep working on stale data.
`DeviceSessionWatcher` fires on resume (and on cold start), `touch_device`
answers `true`, and the app signs itself out with *"You were signed out of this
device"*. Had it ignored that answer, her next token refresh would have failed
anyway — the refresh token died with the session row. The watcher buys
promptness, not security. Her phone also stops receiving pushes for his
account: revoking a device deactivates the `fcm_tokens` rows carrying its
device id, or a lost phone would keep showing messages after being signed out,
which is most of what he was trying to stop.

**6. Rahim opens "Where you're signed in".** He sees:

```
Pixel 9      This device    Last used just now
Pixel 8                     Last used 3 hours ago
Web browser                 Last used 2 hours ago

Signed out
Pixel 7                     Signed out 4 days ago
```

with *"2 of 2 phones. Browsers are not counted."* at the top. He taps his
wife's row to rename it "Shireen's phone" — `label` is the only column he can
write. Six months after that sign-out, `reap_stale_devices` deletes the row.

**What Rahim never sees: a refusal.** No login is ever blocked. That is the
single most important property here, because the only way back into this app is
an SMS he has to receive.

## What other apps do

| App | Model |
| --- | --- |
| bKash / Nagad | Effectively one active device; a new login deactivates the old and re-verifies by OTP |
| WhatsApp | One primary phone plus four linked devices; linked ones expire after 14 days idle |
| Netflix | No login cap at all — concurrent *streams* are capped, and the device list is manageable |
| Spotify | Unlimited devices, one playback stream |
| Slack / Google | Unlimited sessions, plus "where you're signed in" with remote sign-out |

Five things hold across all of them, and they are the reasons this design looks
the way it does:

- **Device identity is a client-generated opaque UUID in durable storage, never
  a hardware fingerprint.** Android 10+ refuses IMEI and serial to normal apps,
  iOS's IDFV resets when the last app from a vendor is uninstalled, and the web
  has no such identifier at all. Everyone who tried fingerprinting gave it up.
- **The cap is enforced where the token is issued**, never in the client.
- **Eviction beats refusal** for a consumer app. Refusal is for paid content
  where account sharing is the threat being priced against, and refusal without
  a device-management screen is a support queue rather than a feature.
- **The device list ships before the cap does.**
- **A device is not a session.** Reinstalling must not burn a slot forever, so
  rows carry `last_seen_at` and stale ones are reaped — migration 126.

## What this database already had

`auth.sessions` is GoTrue's own registry and it already stores `user_agent`,
`ip`, `created_at` and `refreshed_at`. Two reasons it is not enough on its own:

- It lives in the `auth` schema, so PostgREST does not expose it and none of
  this repo's RLS applies to it. Reading it at all needs a `SECURITY DEFINER`
  wrapper.
- It has **no stable device identity**. A user agent is not a device, and one
  phone produces a fresh session row every time storage is cleared.

`fcm_tokens` (012) looks like a device registry and is not one: it is keyed on
the FCM token, and those rotate, so one phone becomes several rows over time.
It is also the wrong lifecycle — a token exists to be pushed to, a device row
exists to be listed and signed out.

So `user_devices` is a new table that *joins* the two ideas: a stable device id
that the user recognises, carrying the `auth.sessions` id that actually has to
be deleted for a sign-out to mean anything.

## Four constraints specific to this app

These are what make a design copied from any of the apps above wrong here.

- **Web is the primary target and has no durable device id.** A `localStorage`
  UUID dies with clear-site-data and never exists in a private window, so a web
  user silently burns a slot on every visit. Roughly half of the live sessions
  have a non-mobile user agent. Web therefore must not share a tight cap with
  phones — see the note on `max_devices_per_user` below.
- **The only way back into this app is a real SMS.** Every hard lockout costs
  money and support. Worse, the master OTP is an *unthrottled allowlist entry*
  kept live for the Play reviewer (see CLAUDE.md, QA): a device cap must never
  become the thing that locks that account out in the middle of a review.
- **A check in the client is not enforcement.** Same lesson as `host_available`
  and the booking form: the RPC is a public endpoint, and the app is skippable.
  Registration is still a client call, which is the gap documented under
  Phase 2 below. It works for the threat this is aimed at — a shared login, a
  lost phone — and not against an attacker holding the anon key.
- **`build/web` lags migrations, and PostgREST picks its overload by the keys
  present.** Every function here must be additive; changing a signature would
  make a deployed bundle ask for a function that no longer exists, which
  `searchListingsFromDb`-style catches render as a silent empty result.

## Phase 0 — recording (migration 123, implemented)

```sql
create table public.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  device_id text not null,        -- client-generated UUID, opaque
  platform text not null check (platform in ('web','android','ios')),
  label text,                     -- user-editable, Phase 1
  model text, os_version text, app_version text,
  session_id uuid,                -- the auth.sessions row this device holds
  last_ip inet,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (user_id, device_id)
);
```

Writes go through `register_device` and `touch_device`. **The table has no
INSERT policy**, deliberately — the same shape as `listing_availability_blocks`
(110): if a client could write rows through PostgREST it could also write them
for a device it does not hold, and later invent slots for itself under a cap.

Neither function takes a user id. Both read `auth.uid()`, and `session_id` is
read from the JWT (`auth.jwt() ->> 'session_id'`) rather than being passed in —
a caller-supplied identity on a `SECURITY DEFINER` function is exactly the hole
migration 116 was written to close, and 012's `upsert_fcm_token` only avoids it
because a later migration added the `auth.uid() <> p_user_id` guard that the
repo file still does not show.

`session_id` is nullable so that a GoTrue without the claim could not stop a
device being recorded. It is **confirmed present** here — v2.197.0, well past
the v2.44 that added it — and Phase 1's sign-out reports whether it actually
ended a session rather than assuming, so a future regression would show up as
"already signed out" rather than as a silent no-op.

## Phase 1 — the device list (migration 124, implemented)

`DevicesScreen`, reached from Login & security, lists each device with its
name, platform and last-seen time, plus a sign-out per row and a "sign out
everywhere else".

`revoke_device` checks `auth.uid()` owns the row, sets `revoked_at`, and
**deletes the matching `auth.sessions` row**. That deletion is the only part of
a sign-out that means anything: it removes the refresh token, so the device
dies at its next refresh whatever the client does. Everything else is
bookkeeping a signed-out client could ignore — and a signed-out client is
exactly the one you cannot assume will cooperate.

This was verified before it was written, because "permitted" is not "works"
(115's lesson): `auth.sessions` is owned by `supabase_auth_admin`, but
`postgres` holds DELETE on it, and a delete inside a rolled-back transaction
really did take the row count from 39 to 38. GoTrue here is **v2.197.0**, well
past the v2.44 that added `session_id` to the access token, so the claim the
whole mechanism depends on is present.

`revoke_other_devices` keeps the caller's own device, identified by the session
in the JWT and **not** by a device id from the request body — a caller who
could name the device to keep could name one that is not theirs.

Revocation is **soft** (`revoked_at` set, row kept) so the list can say "signed
out on 12 Mar" instead of the device vanishing, which reads as data loss and
hides the very event someone may have come to look for.

`DeviceSessionWatcher` checks on resume and signs the app out locally. That is
**promptness, not enforcement** — the session is already gone. What it buys is
the hour in which a lost phone would otherwise keep showing messages on a
still-valid access token.

## Phase 2 — the cap (migration 125, implemented)

`max_devices_per_user` in `app_settings`, **seeded at 0 = unlimited**, with its
own arm in `fn_validate_app_setting` — adding a key without adding an arm
silently stops validating it, because that function is a CASE.

Zero meaning "no limit" matches `android_min_version_code` (122) and for the
same reason: this is a setting that can take the app away from a user, so
failing open has to mean *don't*.

Enforcement is **eviction**: registering a device beyond the cap revokes the
least recently seen one and deletes its session, and that device is told why on
next resume. Refusal is not used, for the SMS reason above.

**The arriving device is protected by id, not by having the newest
`last_seen_at`.** `now()` is transaction time, so two registrations in one
transaction share a timestamp exactly and the tiebreaker decides who
survives — the test caught the eviction signing out the device that had just
logged in. A user must never be signed out by their own login, so that cannot
rest on a comparison. `fn_enforce_device_limit` takes the row to keep.

Web is exempt from the count **and** from eviction. A browser that cannot keep
an identifier through a cleared cache would consume the whole allowance by
itself, and evicting one is pointless because the next visit arrives as a
different device anyway.

### Where the cap is enforced (127)

**Inside `verify-otp`**, before the session is handed back. It was a client
call through 125, which meant a client that simply never called
`register_device` was never recorded and so never evicted — the cap applied to
cooperating clients and to nothing else, the same class as "the booking form
checks it".

`verify-otp` cannot use `register_device`: that reads `auth.uid()`, and inside
the edge function there is no caller identity yet. `admin_register_device` is
the twin, guarded with the `Only service_role can execute this function` check
every `admin_*` function in this schema carries — without it, it is a public
endpoint for registering a device against any account, which under a cap is a
way to sign strangers out.

It is **non-fatal on purpose**. A device bookkeeping failure must never turn
"you reached your device limit" into "you cannot sign in", which is the same
reason the cap evicts rather than refuses. A bundle that predates the two
device keys still signs in; it is simply not counted.

An eviction also **deactivates that device's push tokens** (`fcm_tokens` gained
a `device_id`, and a trigger retires the rows when a device is revoked), or a
lost phone would keep showing messages and bookings after being signed out —
most of what the user was trying to stop.

## Phase 3 — reaping (migration 126, implemented)

`reap_stale_devices` runs daily under `pg_cron` and deletes revoked rows older
than **180 days** and active rows unseen for **365**. Two windows, because they
are two different problems: a revoked row is history that stops being useful
long before it stops being stored, while an active row nobody has touched in a
year is not a device anyone still has.

365, not 90: a phone left in a drawer over a long trip is still the user's
phone, and reaping it would silently un-name it and — under a cap — hand back a
slot they had not asked for. Neither window can lock anyone out; deleting a row
only means the next sign-in from that device records a new one.

## What is NOT built

- **No web push on eviction.** Web has no FCM token here, so a browser evicted
  while closed finds out on its next visit. It is exempt from the cap anyway,
  so this only matters if that exemption is ever removed.
- **`revoke_device` does not reap the row's FCM tokens on web**, for the same
  reason — there is no token to deactivate.

Everything else in the original plan is built. The enforcement gap that stood
open through 125 is closed by 127: the cap now applies inside `verify-otp`,
before a session is handed back, so a client that never calls `register_device`
is still counted and still evicted.

### What the client is still needed for

`verify-otp` cannot record `session_id` — the session does not exist yet, it is
created when the client redeems the token hash. So the client's own
`register_device` still runs on sign-in and fills that in, along with the model
and OS. Everything it writes coalesces server-side, so a build that cannot read
a field never erases what an earlier one knew.

The split is worth stating plainly: **`verify-otp` owns the rule, the client
owns the detail.** A client that skips its half leaves a device with no
`session_id` — it can still be listed and still be evicted, it just cannot be
remotely signed out until its next launch.

## Retention

`last_ip` is PII. Only the most recent is stored, never a history, and the row
dies with the account through `on delete cascade`. If a device log ever needs
to become an audit trail, that is a separate table with a stated retention
window, not this one growing a history column.
