# Musafir — working notes

Flutter 3.44.4 marketplace (guest ↔ host stays, Bangladesh). Web is the primary
deploy target; Android (`co.iobytes.musafir`) builds from `android/`.

Domain vocabulary lives in `CONTEXT.md`. Design docs live in `docs/`. This file
is only the things that will bite you.

## Commands

```sh
flutter analyze          # must be clean
dart format lib/ test/   # must be clean
flutter test             # 41 test files
sh tool/build_web.sh     # the ONLY correct way to build for deploy
sh tool/verify_deploy.sh # is Cloudflare serving what I committed?
```

## `build/web` is a committed artifact

`wrangler` uploads `./build/web` verbatim — it cannot compile Dart. So a
**source-only commit ships stale code**, and the working tree passing tests
tells you nothing about what users get.

Any change under `lib/` or `web/` that should reach users must be followed by
`sh tool/build_web.sh`, with the rebuilt `build/web` committed alongside the
source. Never `flutter build web` directly: the script also fingerprints the
bundle for immutable caching, copies `web/_headers` (Flutter skips
underscore-prefixed files), strips `.symbols`, writes `build_stamp.json`, and
runs the registrant guard below.

`docs/WEB_DEPLOYMENT.md` predates the script and still says to run
`flutter build web --release`. Follow this file instead.

## The stale plugin registrant trap

Flutter caches a generated `web_plugin_registrant.dart` per build configuration
and **has been observed reusing a stale one** — a registrant produced before a
plugin was added. Everything looks fine: the build succeeds, tests pass, and
`flutter run -d chrome` works (different build directory, fresh registrant).
Only the deployed bundle is broken, and only at runtime:

```
MissingPluginException(No implementation found for method initialize
                       on channel plugin.csdcorp.com/speech_to_text)
```

This shipped once — voice search was live for a day with `speech_to_text`
unregistered. `tool/build_web.sh` now refuses to fingerprint such a bundle. **If
that guard fires, believe it:** `flutter clean && sh tool/build_web.sh`.

Corollary for debugging: "works in `flutter run -d chrome`, broken when
deployed" is this bug's signature. Check the release bundle, not the source.

## Deploying

CI runs `sh tool/build_web.sh` (so the guard protects CI too) and deploys per
branch from a GitHub Environment. When that environment has no
`CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID`, the workflow logs a warning
and **skips the deploy while still reporting success** — a green run is not
evidence anything shipped. This has bitten before.

Wrangler is typically not authenticated locally either. Either way, the only
proof is `sh tool/verify_deploy.sh`, which compares live bytes against
`build/web`.

The site is on `workers.dev`, which has no zone, so the cache-purge API is
unavailable — entry points can serve a stale edge copy despite `no-store`.
`verify_deploy.sh` reads through the cache; a browser showing old UI after it
reports GREEN is a client cache, not a failed deploy.

## Supabase

Migrations in `supabase/migrations/`, applied in order. The **live database has
drifted from the repo** in the past, so verify against it rather than assuming;
`docs/live_schema.sql` is a snapshot, not the truth. Live SQL can be run through
the Management API (`POST /v1/projects/{ref}/database/query`) with the token in
the `Supabase CLI` keychain entry.

Migrations are not automatically applied by any pipeline. Applying one to the
live database is a real, outward-facing action — say so and confirm first.

## Availability rules belong in the database, not the booking form

Migration 070 moved the *price* server-side because the client was deciding it.
It left every other booking rule in Dart, and each one turned out to be
unenforced. Migrations 110–111 close that; the pattern is worth remembering,
because **"the booking form checks it" is not enforcement** — the form is
skippable, and the RPC is a public endpoint.

What 111 fixed, and what to check before adding a rule:

- **`host_available` (038) was never enforced at booking time.** That
  migration's own comment claims it is "enforced at the Reserve step". It was
  not — it was only ever a search/browse filter, so a guest with the listing
  already open, deep-linked, or reached from wishlist/trips booked an away host
  fine. Do not trust that comment; it predates the fix.
- **Per-plan min/max duration (055) was form-only.** `BookingLimits.minFor`'s
  `?? 1` and the RPC's `coalesce(v_min, 1)` are now two implementations of one
  rule. A test in `booking_limits_test.dart` pins the default so they can't
  drift; if you change one, change both.
- **`is_booking_available` was `SECURITY INVOKER`.** `bookings` has RLS and no
  policy admits another guest's row, so the function the client calls
  "server-authoritative" returned **true for slots that were already taken**.
  The guest was told the dates were free and only found out at checkout. It is
  `SECURITY DEFINER` now. Any function that has to see across users needs the
  same, and the Dart-side comment claiming a plain RPC "sees ALL bookings" was
  simply wrong.

Two exclusion constraints are the real backstop, not the RPC's `if exists`
guards — those are check-then-insert and lose races by construction:
`bookings_no_overlap` (078, per listing) and `bookings_no_tenant_overlap` (111,
per guest). Both raise `23P01`.

**Never tell the two conflicts apart by their message text.** That is what the
repository used to do (`contains('already have a booking')`), matching English
written in a SQL file — rewording a migration silently showed guests the wrong
message. Both raises now carry a `hint` (`listing_overlap` / `tenant_overlap`)
and `bookingConflictTypeFrom` reads it, with the constraint name and then the
legacy prose as ordered fallbacks. It has tests; keep them passing.

Host date blocks live in `listing_availability_blocks` (110). Writes go through
`block_listing_dates` / `unblock_listing_dates` — the table has **no** INSERT
policy, deliberately, so the "are these dates already booked?" check can't be
skipped by writing through PostgREST. The host's `note` is private, which is
why the SELECT policy is owner-scoped and guests read
`listing_blocked_ranges()` instead. Every range in the schema is half-open
`'[)'`: a block ending when a stay begins does not collide.

There is deliberately **no** constraint spanning blocks and bookings — a block
is not a `bookings` row. A host blocking dates in the same millisecond a guest
commits can lose; the cost is one booking to decline by hand, and the
alternative (blocks as `bookings` rows under a sentinel status) would drag them
through earnings, commission, payouts and the reservations list.

### Search filters on dates through `is_booking_available`, not its own copy

`search_listings` took no date until 112, so a guest searching 10-15 September
was shown listings blocked for exactly those days and listings already booked
solid — then refused at Reserve. `SearchFilters` had carried `checkIn`/`checkOut`
all along; the client simply never sent them.

A block hides a listing **only from searches whose dates overlap it**. Do not
"fix" this into hiding the listing outright: one blocked weekend would then cost
the host every other booking, which is the problem 110 was built to solve, and
`host_available` (038) plus `is_active` already exist for stepping out entirely.
An undated search — including the default explore feed, which is
`searchListingsFromDb(const SearchFilters())` — filters on nothing.

Three things about it that are easy to undo by accident:

- **The predicate lives in the `base` CTE, not the outer `where`.** `chosen`
  (the smallest radius tier holding a match) reads `base`, so a blocked listing
  must not be allowed to win a tier and then be filtered out of it — a dated
  tiered search would answer with an **empty ring**. Verified: moving the
  predicate outward turns one scenario from two results into zero.
- **It is a `case`, not an `or` chain.** Postgres does not promise
  left-to-right `or` evaluation, and a reversed window reaches
  `tstzrange(lower > upper)`, which aborts the whole search with `22000`.
  `searchDateWindowFor` drops such a window client-side too, but a public RPC
  cannot lean on that.
- **112 grants `is_booking_available` to `anon`** because `search_listings` is
  `SECURITY INVOKER` and open to `anon`, and 111 had granted it to
  `authenticated` only. On a *plain* Postgres that grant is load-bearing —
  without it a not-signed-in dated search dies with `42501` and the client's
  `catch` renders it as "no results". On **this** database it is not: see the
  default-privileges note below. Keep it anyway; it stops the repo depending on
  an accident.

**Do not reason about anon access from the migrations alone.** Supabase's
`ALTER DEFAULT PRIVILEGES` on schema `public` grants `anon` and `authenticated`
at CREATE time, and the `revoke all ... from public` this repo writes after a
`SECURITY DEFINER` function strips only the PUBLIC pseudo-role — it leaves that
explicit anon grant untouched. Verified on live via `pg_proc.proacl` /
`pg_class.relacl`: anon already holds EXECUTE on `is_booking_available` and
`listing_blocked_ranges`, and SELECT on `listing_ratings`, in flat
contradiction of what 110/111/016 appear to say.

So **an RLS policy is the only one of the two that actually gates `anon`.**
Default privileges hand out the grant; nothing hands out a policy. That is why
`facilities` was the single thing broken for signed-out visitors (113) — it was
a `to authenticated` *policy*, not a missing grant. When you need to know what a
visitor can read, impersonate one (`begin; set local role anon; …; rollback;`)
rather than reading the SQL.

### PostGIS lives in `public`, and its tables are not ours to fix

001 runs `create extension if not exists postgis` with no schema, so PostGIS's
reference tables land in the schema PostgREST exposes, carrying the extension's
own grants: `anon=arwdDxtm` on `spatial_ref_sys` — INSERT, UPDATE, DELETE **and
TRUNCATE**, not just read. Verified, not inferred: `DELETE
/rest/v1/spatial_ref_sys` with the compiled-in anon key answered **204**. An
emptied table is a full search outage, because geography operations resolve
their spheroid through it and every one of them then raises `Cannot find SRID
(4326)` — `search_listings`, the radius tiers, the landmark ring, the geog
trigger, the default explore feed.

115 closes it, and the shape of that migration is the lesson. Three obvious
fixes are all refused here — the table is owned by `supabase_admin`, and our
`postgres` is neither a superuser nor a member of it:

| Attempt | Result |
| --- | --- |
| `enable row level security` | `42501: must be owner` — the linter's own advice |
| `owner to postgres` | `42501: must be owner` |
| `alter extension postgis set schema` | refused; postgis is `extrelocatable = false` |

**The `revoke` is the dangerous one: it is permitted, reports success, and does
nothing.** A non-owner may only revoke grants it made itself, and these were
made by `supabase_admin`, so `relacl` comes back byte-identical. A migration
built on it applies green and records itself as done with the hole untouched.
`postgres` holds `t` (TRIGGER) and nothing else useful, so the guard is a
trigger — **two** of them, because TRUNCATE does not fire row-level triggers
and a row-only guard loses the table to a one-word statement. Reads stay open
deliberately: search runs as `anon` and needs them.

So when a Supabase lint names a table you did not create, check who owns it
before writing the fix — and check `relacl` *after* applying it, because
"succeeded" is not evidence.

### Party capacity is sub-caps under a total, and pets default to deny

118 gave `listings` four nullable columns — `max_adults`, `max_children`,
`max_infants`, `max_pets` — and `search_listings` four matching arguments. Three
things about the model are easy to get wrong later:

- **They sit beneath `max_guests`, they do not replace it.** The total is still
  the backstop, still what `create_marketplace_booking` enforces, and still the
  only number a booking carries. They are deliberately **not** constrained to be
  `<= max_guests` and do not have to sum to it: "up to 4 people, at most 2
  adults, at most 3 children" is a coherent thing for a host to mean, and every
  obvious constraint forbids it. `PartyLimits.clampedTo` trims a *counted* cap
  when the host lowers the total, because a sub-cap above the total can never
  bind — it does not touch infants or pets, which the total never gated.
- **`null` means "no separate limit", not zero.** That is what makes the
  migration invisible to the listings that already existed: a null column drops
  out of the predicate entirely. Zero is a different, stated rule ("no
  children"), and the two must never be collapsed — `supabase/tests/118…`
  rows 02b/06/06b are the pair that pins it. It is also why the host control is
  a stepper whose floor is **"Any"** rather than an `int` stepper beside a
  switch: a host has to be able to take a cap back *off*, and `PartyLimits`
  therefore needs explicit `clear*` flags where `SearchFilters.copyWith` reads
  null as "unchanged".
- **Pets are the exception and default to deny.** Unlike the other three they
  already had a switch — `pets_allowed` (053), `not null default false` — so
  silence means no, and `max_pets` is only consulted for a host who said yes.
  Searching with an animal must not surface a place that never agreed to one.
  Nothing ties the toggle and the number together, so a host switching pets off
  needs no cleanup: the predicate reads the toggle first and never reaches the
  number. `partyLimitsSentence` does the same, or a listing page would advertise
  a pet limit for a place that no longer takes pets.

**The four RPC keys are omitted unless the guest actually narrowed**
(`searchPartyParams`), for exactly the reason 112 omits `p_check_in`: PostgREST
picks the overload by the keys *present*, so sending them against a database
without 118 demands a function that does not exist, and
`searchListingsFromDb`'s catch turns every search on the site into "no results".
`build/web` always lags a migration, so that window is real.

The split still stops at search. A stay found as "2 adults, 1 child, 1 infant,
1 pet" is booked as **3 guests** — bookings carry one number, and carrying the
breakdown through means a bookings migration plus the booking sheet, the price
breakdown and the host's reservation list.

### A SECURITY DEFINER function is public unless you say otherwise

Same root cause as the note above, one level down: `ALTER DEFAULT PRIVILEGES`
grants `anon` and `authenticated` EXECUTE on **every function created in
`public`**, and PostgREST publishes anything in `public` at
`/rest/v1/rpc/<name>`. So a `SECURITY DEFINER` function is a public,
unauthenticated endpoint running as `postgres` from the moment it is created,
and the only thing standing between it and the internet is a check you wrote
inside its body.

116 found fourteen with no such check. The worst was **`otp_log_send`**, and it
was full account takeover:

- it inserts into `otp_attempts` with a **caller-supplied** `otp_hash`,
- `hashOtp` (`supabase/functions/_shared/otp.ts`) is unsalted, unpeppered
  SHA-256 of the code, so the hash for `1234` is a public constant,
- `verify-otp` picks its row with `order by created_at desc limit 1`, so a row
  inserted just now **outranks the code that was actually texted**.

Three requests with the anon key that ships in the bundle — `otp_log_send`,
`verify-otp`, redeem the token — and you hold anyone's session, admin included.
Verified live to step one (HTTP 200 + row id, for a nonexistent phone, row
deleted immediately); the chain was not completed. This is not the master-OTP
risk in the QA section — that needs the number allowlisted; this needed nothing.

Two rules follow, and 116 is the worked example:

- **Revoke from `public` AND `anon` AND `authenticated`.** Nearly every one of
  these carried both a PUBLIC `=X/postgres` and an explicit `anon=X/postgres`.
  Dropping either alone leaves EXECUTE intact through the other — 115's lesson
  exactly inverted.
- **The grant is not the control if the body already guards.** `admin_*`
  raise `Only service_role can execute this function` and were left alone;
  functions checking `auth.uid()` likewise. Don't revoke blind: three
  (`is_admin`, `can_see_listing_address`, `get_listing_owner`) are called from
  inside RLS policy expressions, where a role lacking EXECUTE gets an **error
  instead of an empty result**, and `is_conversation_member` is the same for
  `authenticated`. Check `pg_policy` before touching a grant.

Safe to revoke the OTP four because the live login path never calls them: both
OTP edge functions build their client with `SUPABASE_SERVICE_ROLE_KEY` and hit
`otp_attempts` through PostgREST directly. The Dart callers in
`lib/services/otp_service.dart` sit behind
`OtpState._useSupabase => SupabaseConfig.isConfigured`, true in every shipped
build, so that branch is the mock path. Login was **not** driven to test this —
see the QA section on why automating a login can send a real SMS.

Still open after 116, in rough priority order: **20 `SECURITY DEFINER`
functions with a mutable `search_path`** (a schema-shadowing escalation vector,
mechanical to fix with `alter function … set search_path`), and
`get_unread_count` / `is_conversation_member` never checking that `p_user_id`
is the caller, so one signed-in user can still read another's counts.

### A SECURITY DEFINER *view* can be written through, as postgres

The three `security_definer_view` advisor ERRORs looked cosmetic and one was a
full **anon → admin escalation** (117). A view with neither `security_invoker=on`
nor an owner clause runs as its OWNER — `postgres` — for reads *and writes*, and
a single-table view is auto-updatable, so PostgREST accepts a PATCH on it and
the write lands on the base table **as postgres, outside RLS and before any
guard trigger**. `public_profiles` is `select <safe columns> from profiles`, so:

```
PATCH /rest/v1/public_profiles?id=eq.<host>  {"role":"admin"}   →  204
```

with the bundled anon key promoted any account to admin. The direct path is
safe — `update profiles` as anon hits RLS (no matching row) and an
authenticated self-`role` change is stopped by `fn_guard_verification_verdicts`
— but the definer view launders the actor into `postgres` and slips both. Fix
was to **revoke INSERT/UPDATE/DELETE on the view**; reads run as postgres either
way, so nothing broke.

Two rules from it:

- **A definer view over an RLS table is a write hole unless you revoke writes
  on the view.** Auto-updatability is silent — nothing in the view definition
  says "writable".
- **`security_invoker=on` is the lint's fix but not always yours.**
  `listing_ratings`/`guest_ratings` are aggregates (not updatable), and flipping
  them to invoker cleared the lint *and* fixed a real leak — as definer they
  averaged in **unrevealed** reviews (`reviews_select_revealed` is `to public`,
  so reading as the caller drops them; live count went 37→36). But flipping
  **`public_profiles`** to invoker would read as the caller: an anon caller sees
  zero rows and every host name in the app vanishes. Making it work again needs
  a `to public using(true)` SELECT policy on `profiles`, and anon holds column
  SELECT on all 31 columns (mobile, nid, email included — only RLS hides them),
  so that policy would leak PII instantly. **`public_profiles` stays a definer
  view on purpose; its lint (0010) does not clear**, same category as
  `spatial_ref_sys`'s 0013 (see 115). 117 also revoked anon's now-purposeless
  direct grants on `profiles` (it reads through the definer view, never the
  table) so those PII column grants stop being one careless policy away from a
  leak.

The rule itself is *not* reimplemented — search calls `is_booking_available`,
same as the booking form. `searchDateWindowFor`
(`lib/services/search/search_date_window.dart`) is the only place that decides
whether a search has a usable window, and it has tests.

The client omits `p_check_in`/`p_check_out` **entirely** when there is no
window rather than sending nulls, so the deploy order between `build/web` and
this migration does not matter: PostgREST picks the overload by the keys
present, so a null key would still demand the 19-argument function and, against
a pre-112 database, resolve to nothing and empty out every search.

`searchListings` (synchronous, cache-local, `supabase_musafir_repository.dart`)
has **no callers** and cannot see blocks at all — they are not in the listing
cache. `search_listings_by_location` is likewise dead in both the app and the
admin portal. Neither is a live discovery path; do not add one without giving it
the same date filter.

## Nothing user-tunable belongs in Dart

App-wide knobs live in the `app_settings` table and are edited from the admin
portal — reads are public, writes are admin-only. `AppSettingsService` loads
them at startup and **fails open** to compiled-in defaults.

Current keys include the proof-of-address requirement, cash payments, the
search area (`search_radius_tiers_m`, `search_landmark_radius_m`,
`search_nearest_fallback_limit`), and the colour theme (`active_theme`).
Migration 097 validates the search keys on write, so a bad value is refused at
the source rather than silently sanitised.

`active_theme` names one of the palettes in `lib/core/theme/app_palettes.dart`.
The app can only wear a palette it was compiled with, so **adding one means
adding its id to `AppPalettes.all` AND to `fn_validate_setting_active_theme`
(created in 105, id list last extended by 106)** — a test
pins the slug list so the two drifting apart fails rather than silently shipping
a theme no admin can select. That test also holds every palette to WCAG: 4.5:1
for tokens that carry text, 3:1 for ones that only ever tint an icon. There are
no exemptions and the tiers are not advisory — a new palette that fails is a
failing build, so pick colours against a background, not in isolation.

It holds one more axis, added after selection turned out to be invisible: **a
selected chip has to clear 3:1 against an unselected one**, and its label 4.5:1
against its own fill. `chipTheme` used to tint the brand at 14% alpha over
`surfaceMuted`, which works for a colourful brand and not at all for
`coral_ink`, whose brand is #222222 — the tint flattened to #E0E0E0 beside a
#EBEBEB chip, 1.11:1, with `side: BorderSide.none` leaving no second cue. Seven
of the nine selectable chips in the app take their colours from that theme
alone, so all seven read as permanently unselected. Selection is a solid
`brand` fill now, label and checkmark in `surface`; that pairing needs no new
guarantee because brand-on-surface at 4.5:1 *is* surface-on-brand at 4.5:1.

Two traps if you touch it. **Flatten alpha before measuring** — Flutter's
`computeLuminance()` reads only r/g/b, so contrast against a translucent fill
reports the ratio of the tint's source colour, a healthy 13:1 for something
invisible; the test composites with `Color.alphaBlend` first, and without that
line it passes on the bug it exists for. And **`RawChip` resolves only the
label's `color` against widget states**, not the rest of the TextStyle
(`chip.dart` calls `resolveAs<Color?>` on `effectiveLabelStyle.color` alone), so
a `WidgetStateColor` is the single hook a theme has for a selected label and a
`WidgetStateTextStyle` would be read as a plain style. A call site may add its
own size or weight — `merge` only overrides non-null fields — but a `color:` of
its own defeats that hook and paints an ink label on the dark fill.

### The boot chain is brand rose, not the palette

Seven surfaces hardcode **`#C35063`** and cannot follow `active_theme`, because
the OS or the browser paints them before any Dart runs: `values/colors.xml`,
`values-v31/styles.xml`, `LaunchScreen.storyboard`, `web/manifest.json`, the
`web/index.html` boot splash, `tool/gen_brand_assets.py`, and — by choice, to
end the chain in the same colour — `SplashScreen` via
[`Brand.rose`](lib/core/theme/brand.dart). That file lists all seven; if the
brand colour changes they all change together, and nothing can automate it.

`SplashScreen` used to paint `colorScheme.primary`. With the default
`ocean_teal` palette that meant a rose launch window flipped to a **teal**
screen, which reads as a broken load rather than a brand. Do not "fix" it back
to the theme.

The `index.html` splash also had no business having a `prefers-color-scheme:
dark` variant — it was `#0E1F23`, a dark green-teal, and since that background
paints the instant the CSS parses while the icon is still loading, a dark-mode
browser opened on a greenish blank window. A brand colour has no dark variant.

Before hardcoding a number a human might want to change, check whether it
belongs here instead.

## Brand assets are generated, not hand-made

`python3 tool/gen_brand_assets.py` derives all of these from the artwork
committed in `assets/brand/source/`:

| Output | Surface |
| --- | --- |
| `assets/brand/logo.png` | in-app `BrandLogo` — splash, login, sidebar rail |
| `assets/brand/icon*.png` | masters for the generators below |
| `mipmap-*/ic_launcher*` | Android launcher: legacy, round, adaptive, monochrome |
| `drawable-*/ic_notification.png` | Android status bar / notification shade |
| `LaunchImage*.png` | iOS launch screen |
| `web/social-card.png` | link previews (og:image) |
| `store/play/icon-512.png` | Play listing |

The iOS **app** icon and the web icons come from
`dart run flutter_launcher_icons` afterwards, in that order — it reads
`icon.png`, which the script writes.

Two of those exist because a launcher icon cannot be reused as they are:

- **`ic_notification`** — Android draws a notification's small icon from the
  **alpha channel alone**, discarding colour. `ic_launcher` is a rounded square
  that is 96% opaque, so pointing a notification at it renders a featureless
  white blob. This app shipped that bug. Wired in `AndroidManifest.xml` *and*
  twice in `firebase_push_notification_service.dart` — all three must agree.
- **`LaunchImage`** — Flutter's template is a 1×1 transparent PNG on a white
  storyboard, so an unbranded iOS cold start is a blank white screen. The
  storyboard background carries the rose; the image is the mark on
  transparency, mirroring how Android layers its launch window.

So **never hand-edit or hand-resize one of those files**: the next regeneration
silently reverts it. Change the script or the source artwork instead.

The source is flat rose on opaque white with a soft, faintly rose-tinted drop
shadow. Keying that cleanly is genuinely fiddly and the reasoning is written up
in `assets/brand/README.md` — read it before touching the pipeline, in
particular why there is a levels floor before the bounding box is measured.

Two footguns after any regeneration: `flutter_launcher_icons` strips the
trailing newline from `web/manifest.json`, and `landing/favicon.png` +
`landing/Icon-192.png` are separate copies that it does not touch.

**The favicon needs a URL change, not a cache header.** Browsers keep favicons
in a private store that ignores `Cache-Control`, so a correct deploy still
leaves the old icon in the tab. `tool/build_web.sh` therefore appends
`?v=<content hash>` to every icon URL in `index.html`; `assets/brand/README.md`
explains it, along with why `web/favicon.ico` has to exist at all (the SPA
not-found rule made `/favicon.ico` answer 200 with an HTML page).

## The admin portal is a separate repo

`../musafir-admin` — Next.js App Router, **Base UI** (the `render` prop), *not*
Radix (`asChild` does not exist here). It has no deploy config at all;
deployment is manual.

## Android

**Do not strip `RECORD_AUDIO`.** Voice search needs it — Android's recogniser
refuses without it — and `speech_to_text` does *not* declare it in its own
manifest, so the app manifest is the only thing supplying it.
`camera_android_camerax` happens to declare it too, which makes it look
redundant. It is not.

`CAMERA` is the opposite case: `camera_android_camerax` declares it and the
merger folds it in, so it needs no entry of its own.

## QA

**The master OTP is ON as of 2026-09-03, scoped to one number.**
`MASTER_OTP_PHONES` is the single entry `01673293542` — an explicit allowlist,
never `*` — because a Play reviewer cannot receive a Bangladeshi SMS and the
Console's *Sign in details* declaration needs credentials that work. That number
is the existing `naib1` account (verified host, real listings and bookings), so
the reviewer sees a populated app; `verify-otp` resolves it to the **legacy**
identity `phone.1673293542@musaafir.app`, not a fresh empty account.  otp = 3969

It had been OFF since 2026-08-26, when the secrets were unset on the owner's
instruction. Both functions read secrets at runtime, so neither the re-enable nor
a future unset needs a redeploy.

**The master path is not rate-limited, and cannot be given a longer code.** A
wrong guess makes `isMasterOtp` return false and falls through to the normal
path, which finds no `otp_attempts` row and answers "No active code" *without
incrementing anything* — so `OTP_MAX_ATTEMPTS` never applies. `OTP_LENGTH` is 4
and `OtpInputField` renders exactly 4 auto-submitting boxes, so the keyspace is
10,000 and a five-digit code could not be typed. Anyone who guesses that this
number is allowlisted can brute-force it unthrottled and take the account. Unset
the two secrets once a review passes, and re-set them for the next one.

Before the 2026-08-26 shutdown it was `1234` against `MASTER_OTP_PHONES='*'` —
the wildcard, so it really did log into **any** phone number, not an allowlist. `README.md` still shows the
command that set it to a single number; that is stale, and the live value was
confirmed by hashing candidates against the Management API's SHA-256 of the
secret. The secret is server-side: `OtpConfig.masterOtpEnabled` defaults to
false, so a plain `flutter build` never carried a bypass regardless.

If you re-enable it — the Play reviewer needs a login that does not require
receiving a Bangladeshi SMS, so you probably will — use an **explicit allowlist,
never `*`**, and mind the format. `masterOtpAllowlist()` runs each entry through
`normalizePhone()`, which reduces every spelling to the **11-digit leading-`0`**
form, so `01673293542`, `+8801673293542` and now the bare `1673293542` all match
the same entry. The bare form used to match nothing, which is the likeliest
reason the allowlist was widened to `*` in the first place — see the section
below for the account-duplication bug that same gap caused. The stale
`README.md` command still shows the pre-fix single-number form.

Login goes through the `send-otp` Supabase edge function rather than the Dart
`ConsoleSmsGateway`, so driving a login can attempt a real SMS — do not automate
it against a number you do not own. That is also why the unset above was *not*
verified by attempting a login.

## One phone number, one account

`normalizePhone` in `supabase/functions/_shared/otp.ts` is not formatting — it
**decides which account a login lands on.** `verify-otp` turns its output into
the synthetic auth identity `phone.<canonical>@musaafir.app` and creates one
account per distinct value, so two spellings of one number that canonicalise
differently are two different people: separate listings, separate bookings, and
a separate identity verification to submit and have approved.

It shipped with a hole. `+880…`, `880…` and an already-canonical `01…` were all
handled, but a **bare 10-digit** number matched no branch and passed through
unchanged — while `phone_input_field.dart` renders `+880` as a decorative
`prefixIcon` and submits the raw field text, so the UI actively invites you to
omit the zero. Four production accounts were duplicated before anyone noticed,
with users submitting documents twice and their listings split across two
logins. Migration 109 merged them (**applied 2026-08-27**).

Two things guard it now, and both matter:

- **`lib/services/auth/phone_number.dart` is the only Dart implementation.**
  There used to be three — `OtpService`, a diverged private copy on
  `SupabaseAuthService`, and `MockAuthService` — plus the TypeScript one, and
  **none had a test**. A shared "keep these in step" comment was already false.
- **`sh tool/verify_phone_parity.sh`** runs the same 16 inputs through the Dart
  and the TypeScript and diffs them. Run it whenever you touch either side; it
  is not in CI, which has no node step.

Existing rows are deliberately **not** renamed to the canonical form. The stored
email is an opaque key that `admin.generateLink` consumes and the client echoes
back to redeem the token, so a bulk rename would have to land in the same
instant as the function deploy — every returning user in the gap gets a brand-new
empty account, and 33 of 38 accounts are the legacy spelling. `verify-otp` reads
the canonical identity and then the legacy one instead, which is
order-independent and needs no data change.

For the same reason `otpLookupPhones` makes `verify-otp` accept an `otp_attempts`
row stored under **either** spelling. `send-otp` writes that row and `verify-otp`
reads it, but they are separate deploys — without this, the minutes between them
fail every bare-form login with "No active code".

## Browsing is public; acting is not

The whole app used to sit behind one `switch` arm — `unauthenticated →
AuthNavigator` in `app.dart` — so nothing rendered without a session. It now
renders `MainShell` for a visitor too, and login is reached from whatever they
tried to do.

**Return the same widget type from both post-`initializing` arms.** Flutter
updates an element in place when the type and key match, so signing in
mid-session keeps `MainShell`'s state: the selected tab, each tab's scroll
offset, the `_LazyIndexedStack`'s already-built children. Branching to a
different widget would rebuild all of it, which is what the old arm did on
every login.

**Login is a pushed route, and that IS the "return them to what they were
doing" mechanism.** `AuthFlow.ensureSignedIn` pushes and awaits; the listing
detail screen with its dates chosen stays mounted underneath, so the caller
just carries on. There is no pending-intent store to keep in sync — do not add
one. It works because `MainShell` has **no Navigator of its own** (it is a
`_LazyIndexedStack`), so pushes land on the root navigator as siblings of
`home:`, where an auth-driven rebuild of `home:` cannot touch them.

Three gates, all shaped alike — `false` means stop, and the gate has already
said why:

| Gate | Question |
| --- | --- |
| `AuthFlow.ensureSignedIn` | is there a session? |
| `IdentityGate.ensure` | is the identity admin-approved? |
| `PublishGate.ensure` | may this person publish? (composes the other two + address proof) |

`PublishGate` exists because `CreateListingScreen` is pushed from **three**
places and two of them — the host dashboard and the profile screen — were bare
`Navigator.push` calls with no checks at all. Duplicating the guard would have
left the same trap for the fourth caller. Never push that screen directly.

**`if (userId != null)` is not a gate, it is a bypass.** Both identity checks
were written that way, which was safe only while the app was unreachable
without a login: a null user took the `else` branch and got the whole booking
sheet — dates, guests, coupon, Confirm — before a dead-end "Please log in to
book". Require the login; do not tolerate its absence.

`_goToGuestTab` refuses any tab but Explore while signed out, centrally, so a
new shortcut cannot reintroduce that hole. The signed-out nav bar is a
*separate* two-item bar rather than a filter over the five-item list, because
`_guestTabIndex` is a logical id that `_buildGuestContent`,
`_goToGuestTab(0..4)` and `ShellNavState.openGuestTrips()` all index with —
renumbering the destinations would silently repoint every one of them.

### Desktop wears a top header, not a rail

Above `Responsive.wide` (1000px) the shell renders [`DesktopTopNav`
](lib/widgets/desktop_top_nav.dart) — brand, centred destinations, account
menu, plus a Where/When/Who search pill on Explore. It replaced an extended
`NavigationRail`, which spent ~220px of every viewport on five fixed labels and
left the search field buried inside a scrolling tab.

Below that breakpoint **nothing changes** — the bottom bar and Explore's own
in-page search row are untouched. There is deliberately no drawer fallback in
that file; the hamburger is the account affordance, not a responsive collapse.

Three things there that are easy to break:

- **The header owns no state.** Destinations, actions and menu items all come
  from `MainShell`, and every selection goes back through `_goToGuestTab` so it
  keeps that gate. A header that tracked its own index is a second navigation
  model, which is exactly what the shared `_guestTabIndex` above exists to
  prevent.
- **`selectedIndex: -1` is a real state, not a bug.** Profile is logical tab 4
  and lives in the account menu rather than the strip, so while it is showing,
  no destination is current — `accountHighlighted` rings the account button
  instead. Do not "fix" it by adding Profile as a fifth destination; the
  indices are shared with the bottom bar (see above).
- **`ExploreScreen.searchInShell` is passed, not re-derived.** The header
  carries the search pill, the leaderboard trophy and the notification bell, so
  Explore hides its whole in-page header row on desktop. The shell decides when
  it draws a header; a second copy of `Responsive.isWide` inside Explore would
  be a second thing to keep in step. The pill drives Explore's *existing*
  search through three public methods on its state — there is one search
  implementation and the header is a remote for it.

`searchPillSummaryFor` (`lib/services/search/search_summary.dart`) is the only
place that renders a whole `SearchFilters` into one line, and it has tests. It
shows nothing for `guestCount == 1`, matching `hasActiveFilters` — otherwise
every untouched pill would look like it was already narrowing the feed. The ✕,
though, keys off `hasActiveFilters` rather than the summary, because a property
type or an amenity is an active search the pill has no segment for.

### The search bar is four panels over one draft

`lib/widgets/search/` is the desktop search: Where / When / Who each open their
own popover anchored under that segment, plus a Filters button for type and
purpose. **`_SearchSheet` in `explore_screen.dart` is still the whole of
mobile**, but it is no longer a parallel implementation of everything: the
guest rows and the calendar are now the same widgets the desktop panels use,
and only the Where field is still written twice. The cure the earlier note
described — rebuilding the sheet as a stack of these panels — has been paid for
piece by piece as each duplicate actually cost something.

### The mobile sheet folds; the desktop bar does not

`_SearchSheet` is an accordion of three [`SearchSection`
](lib/widgets/search/search_section.dart) cards — Where / When / Who, exactly
one open, the closed ones showing what that step currently holds. Before that
it was every control at once: a text field, a suggestion list, a mode toggle,
two date cards, two time cards and four guest steppers down one scroll.

Three things worth keeping:

- **The sheet owns which section is open, not the cards.** Two open sections
  would put the month grid and the guest steppers on screen together and undo
  the point; a card that tracked its own expansion could not prevent that. Same
  reasoning as `MainShell` owning the selected tab.
- **The collapsed summaries come from `searchPillSummaryFor`** — the desktop
  pill's function, so the two surfaces cannot describe one search differently.
  Only the `SearchFilters` handed to it is built locally (`_summaryFilters`),
  and that is deliberately **not** `_applySearch`'s projection: that one layers
  over the live filters with clear flags because it is about to be committed.
- **The date dialogs are gone.** `showDateRangePicker` / `showDatePicker` are
  full-screen modals on a phone, launched from inside a bottom sheet — two
  layers of chrome for one decision, with the sheet invisible behind. The
  inline `DateCalendar` is simply there instead. The two clock times keep their
  native picker: a two-thumb time control is its own build, and a dialog is a
  fair answer for a value with no spatial meaning.

`DateCalendar` grew two things for this. **`DateCalendarMode.singleDay`**,
because hourly search is one date and driving it as a range meant the second
tap silently did nothing visible (it produced `range(5, 8)` and the caller kept
`.start`). And a **width-adaptive cell**: the grid was a hard 7 × 40px, which
overflows a 320px phone once the sheet's padding and the card's are taken out.
The measurement lives in `DateCalendar.build`, **not** in `_MonthGrid` — the
grid sits in a `Row`, and a `Row` lays out a non-flexible child with unbounded
width, so a `LayoutBuilder` down there is handed infinity and learns nothing.
The first attempt did exactly that and still overflowed by 40px.

The guest counter is the first control that drift actually cost, and it is now
the worked example of the cure. Mobile's version was a lone 1..16 number, so
when Who grew to adults / children / infants / pets there was nowhere on the
phone to say three of the four. The rows moved into
[`GuestPartyFields`](lib/widgets/search/guest_party_fields.dart), stateless over
a `GuestParty` value and a callback — the one shape a `SearchDraft` and a plain
`setState` can both hold — and both surfaces render it. Neither knows how many
rows there are or what the caps are. **Do not add a fifth category to one of
them.**

Two things in that widget are load-bearing and have negative-controlled tests:
adults and children share **one** budget (their sum is `guestCount`, so both
`+` buttons must stop together, or the party can be walked past the cap one row
at a time), while infants and pets have their own ceilings because the database
counts them separately. Each row's `max` is its own value plus the remaining
headroom rather than a bare limit, so a party restored from a wider cap can
still be brought down instead of being stranded above a `max` below its value.

- **Every `SearchStateNotifier` mutator runs a search immediately.** So the
  panels write to a `SearchDraft` and exactly **one** `updateFilters` fires,
  from the Search button. Three panels committing on close would be three
  `search_listings` round trips for one search. `search_pill_test.dart` asserts
  the commit count, not just the result — keep it that way.
- **`filtersFromDraft` is pure and wipes before it sets.** The two date modes
  store their shapes side by side, and passing `null` for the inactive one does
  *not* clear it (`copyWith` reads null as "unchanged"), so a range picked after
  an hourly window used to leave a stale `singleDate` keeping
  `hasActiveFilters` true. It clears both modes' fields first, then writes back
  only the active one. Three tests go red if that is undone.
- **`OverlayPortalController.show()` must never be called from build.** It
  asserts on it, and an assertion thrown inside the overlay child paints a
  **full-screen dark red `ErrorWidget`** — that child covers the window, which
  is what "the whole screen goes red" was. `_setOpen` is the only writer of
  which segment is open and the only caller of `show`/`hide`, and every caller
  of it is an event handler.
- **Nothing reads layout during build.** The scrim used to be positioned from a
  `localToGlobal` inside `build`. `SearchPill` now measures the bar and each
  segment in a post-frame callback and holds the rectangles in state (guarded
  on `attached` as well as `hasSize`, since it runs a frame late). The panel is
  an `AnimatedPositioned` over those numbers.
- **Every panel is the same width, and that is load-bearing.** They differed
  per segment and the card animated between them — but the cross-fade lays
  *both* panels out during the transition, so the calendar got laid out at the
  Who panel's width and its fixed 40px month grid overflowed by 45 pixels. Any
  width one panel cannot survive is a width neither can use.
- **Switching segments is a slide and a cross-fade, not a swap.** Position,
  width and contents all changing in one frame is what "it flicks" described.
  `search_pill_motion_test.dart` asserts on the frames *between* states; four
  of its five tests go red if the durations are zeroed.
- **`CallbackShortcuts` needs something focused inside it.** The panel's
  `FocusScope` is `autofocus: true` or Escape does nothing in a panel with no
  text field (Who, Filters).
- **Focusing a text field notifies its controller with unchanged text.** The
  Where panel's listener therefore treats an empty query as "show the default
  destinations", not "show nothing" — the earlier version emptied the list the
  instant the panel opened.
- The landmark picker is a route-level modal sheet, so `SearchPill` closes the
  popover, awaits the pick and reopens it. A bottom sheet over a dropdown reads
  as two competing surfaces.

`SearchFilters` gained `adults`/`children`/`infants`. `guestCount` is still the
only one that reaches the RPC, derived through `guestCountFor` (infants never
count, floor 1, cap `maxSearchGuests`). **The split is search-only** — bookings,
the price breakdown and the host's reservation list all still carry one number,
so a stay found as "2 adults, 1 child, 1 infant" is booked as 3 guests.

### What the database had to change, and what it did not

Almost nothing: `listings`, `listing_facilities`, `reviews` (revealed),
`app_settings`, `landmarks`, `public_profiles` and the `listing-images` bucket
were already `to public`. Search, voice search and the Supabase client needed no
changes at all — the compiled-in key is already the `anon` role.

**113** fixed the one real gap: `facilities` had a `to authenticated` policy, so
a visitor saw **no amenity chips anywhere and got zero results from any search
with an amenity ticked** — silently, because the inner join just collapsed. See
the default-privileges note under Supabase for why a *policy* was the only
thing that could have been broken.

**114** moved the identity gate into the database. Before it, live had 8
bookings from guests with `verification_status = 'none'` and 3 listings owned by
a `role='tenant'` account with no verification — the client gate leaked, and the
live listings INSERT policy checked only `owner_id` (001's version, with the
role clause, never ran here). It is INSERT-time only, so existing rows are
untouched; two owners must finish verification before publishing again.

Both are verified by `supabase/tests/113_114_public_browse_and_identity_test.sql`
— a rolled-back impersonation matrix, 16 rows, run against live. Six of them go
red without the migrations; keep it that way.

### Shareable listing URLs

`/listing/<uuid>` is the only named route; everything else still navigates by
pushing a constructed screen, which is fine — those have no shareable identity.
A card tap passes the `Listing` through `arguments` so nothing re-fetches;
`ListingRoute` fetches by id only when the id came from a pasted link.

`listingIdFromRoute` (`lib/core/routing/listing_path.dart`) is deliberately
strict about the uuid shape, because `not_found_handling:
"single-page-application"` means Cloudflare answers **every** unknown path with
`index.html` — so that function is handed whatever a crawler or a probe asked
for, and a loose pattern would turn `/wp-admin` into a PostgREST query
comparing a uuid column against junk. It has tests; they include the junk.

### The site is now a Worker, for link previews only

`worker/index.js` rewrites the Open Graph tags on `/listing/<uuid>` so a stay
shared to WhatsApp previews as itself. This *has* to happen at the edge: a
crawler reads the HTML and never runs the Dart, so the app cannot set a `<meta>`
in time.

Nothing else changed cost. With both `main` and `assets` set, Cloudflare serves
any request matching a file straight from the asset store **without invoking the
Worker** — `/`, the bundle and every image are exactly as before. Only paths
with no file behind them reach it, and everything but a listing URL is handed
back to `env.ASSETS.fetch` immediately.

Four things in there that are not obvious, and one of them is a security
property:

- **`setAttribute`, never string concatenation.** A listing title is
  host-supplied and lands inside `content="…"`. `HTMLRewriter` escapes it;
  a template string would have injected into every crawler and chat client
  that renders the card. Proven, not assumed — the verify script feeds it a
  `"><script>` title through a stub and a control that swaps in `el.replace`
  goes red.
- **Fetch the shell as `/`, not `/index.html`.** The asset server answers
  `/index.html` with a **307 to `/`**, and returning that redirect verbatim
  sends the crawler to the un-rewritten home page — which looks exactly like
  the Worker never running.
- **A handler object must not have a `text` field.** `HTMLRewriter` reads
  `element`/`text`/`comments` off whatever it is given, so a class with
  `this.text` is silently taken to be declaring a text handler and the whole
  transform dies with *"the provided value is not of type 'function'"*. Hence
  plain handlers.
- **Cache the lookup, never the rewritten HTML.** Caching the page at the edge
  would pin the `main.<hash>.dart.js` reference inside it, and the next deploy
  would hand visitors a shell pointing at a bundle that no longer exists.

It reads `listings.address`, which is the **area** label — 093 moved exact
addresses behind a booking check. Never widen that select to a door number: this
string goes on a public card.

`SUPABASE_URL`/`SUPABASE_ANON_KEY` are `vars` in `wrangler.jsonc` for the same
reason `SupabaseConfig` takes them as `--dart-define`: the two deploy branches
go to different Cloudflare accounts and may point at different projects. Point a
build elsewhere and these need pointing too, or previews describe the wrong
database.

**`sh tool/verify_link_previews.sh`** is the loop — real listing from live, then
the hostile-title stub. Like `verify_phone_parity.sh` it is not in CI, which has
no node step.

## Conventions

Comments explain *why*, not *what* — see the existing code, which is unusually
heavily commented by design. Match that density; a change that removes the
reasoning is a regression.

Tests are the repo's main safety net for logic that cannot be reached from a
widget test. When fixing a bug, prefer extracting the decision into a pure
function with a real seam (`lib/services/voice/speech_locale.dart`,
`lib/services/camera/selfie_camera.dart`) over testing through the UI.
