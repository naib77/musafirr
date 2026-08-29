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

**The master OTP is OFF as of 2026-08-26.** `MASTER_OTP` and `MASTER_OTP_PHONES`
were unset from the live project on the owner's explicit instruction, while
preparing the Play submission (`docs/PLAY_STORE_RELEASE.md` §6.4). There is no
login bypass any more; every login needs a real SMS code.

It had been `1234` against `MASTER_OTP_PHONES='*'` — the wildcard, so it really
did log into **any** phone number, not an allowlist. `README.md` still shows the
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

## Conventions

Comments explain *why*, not *what* — see the existing code, which is unusually
heavily commented by design. Match that density; a change that removes the
reasoning is a regression.

Tests are the repo's main safety net for logic that cannot be reached from a
widget test. When fixing a bug, prefer extracting the decision into a pure
function with a real seam (`lib/services/voice/speech_locale.dart`,
`lib/services/camera/selfie_camera.dart`) over testing through the UI.
