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
failing build, so pick colours against a background, not in isolation. Note that `web/manifest.json` and the
`index.html` spinner still hardcode the teal brand: those are the browser's
splash/chrome colours, baked into the static shell, so they do not follow the
theme.

Before hardcoding a number a human might want to change, check whether it
belongs here instead.

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
`normalizePhone()`, which collapses `+880…`/`880…` to a **leading `0`**. So
`01673293542` and `+8801673293542` both work; **`1673293542` without the leading
zero never matches anything** and the bypass silently fails to apply. The stale
`README.md` command has exactly that bug, which is the likeliest reason it was
widened to `*` in the first place.

Login goes through the `send-otp` Supabase edge function rather than the Dart
`ConsoleSmsGateway`, so driving a login can attempt a real SMS — do not automate
it against a number you do not own. That is also why the unset above was *not*
verified by attempting a login.

## Conventions

Comments explain *why*, not *what* — see the existing code, which is unusually
heavily commented by design. Match that density; a change that removes the
reasoning is a regression.

Tests are the repo's main safety net for logic that cannot be reached from a
widget test. When fixing a bug, prefer extracting the decision into a pure
function with a real seam (`lib/services/voice/speech_locale.dart`,
`lib/services/camera/selfie_camera.dart`) over testing through the UI.
