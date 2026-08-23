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

Current keys include the proof-of-address requirement, cash payments, and the
search area (`search_radius_tiers_m`, `search_landmark_radius_m`,
`search_nearest_fallback_limit`). Migration 097 validates the search keys on
write, so a bad value is refused at the source rather than silently sanitised.

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

A master OTP (`1234`) logs into **any** phone number, kept on deliberately for
QA. It must be unset before production, and must not be turned off without
asking. Login goes through the `send-otp` Supabase edge function rather than the
Dart `ConsoleSmsGateway`, so driving a login can attempt a real SMS — do not
automate it against a number you do not own.

## Conventions

Comments explain *why*, not *what* — see the existing code, which is unusually
heavily commented by design. Match that density; a change that removes the
reasoning is a regression.

Tests are the repo's main safety net for logic that cannot be reached from a
widget test. When fixing a bug, prefer extracting the decision into a pure
function with a real seam (`lib/services/voice/speech_locale.dart`,
`lib/services/camera/selfie_camera.dart`) over testing through the UI.
