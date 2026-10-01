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

### Local database

The migration chain does not rebuild the database (pieces were never
committed); **the live baseline is the build and the chain is history**. Read
`supabase/migrations/README.md` before adding a migration: bump
`NEWER_MIGRATIONS` in `tool/local_db_from_live.sh`, and regenerate the baseline
after applying to live. Run SQL suites with `sh tool/qa/run_sql_tests.sh` —
most files do not roll themselves back. Details, ports, seed accounts:
[docs/notes/local-database.md](docs/notes/local-database.md).

## Rules, with the reasoning in `docs/notes/`

Each line is a rule that has been broken before. Read the linked note before
changing that area; it records what was measured and why.

**Database — booking, availability, search**
([database-booking-and-search.md](docs/notes/database-booking-and-search.md))
- "The booking form checks it" is not enforcement. Every booking rule lives in
  `create_marketplace_booking` / triggers; exclusion constraints
  `bookings_no_overlap` and `bookings_no_tenant_overlap` are the real backstop.
- Tell booking conflicts apart by `hint` (`listing_overlap` / `tenant_overlap`),
  never by message text.
- Search filters dates through `is_booking_available`, inside the `base` CTE,
  as a `case`. Omit optional RPC keys (dates, party caps) when unused —
  PostgREST picks the overload by keys present.
- Party caps: `null` = no limit, `0` = none allowed; pets default to deny.
- Adding an enum value is two migrations (55P04), committed between, and is
  not reversible.
- A lost booking race can deadlock (`40P01`); the client retries once.

**Database — security**
([database-security.md](docs/notes/database-security.md))
- Do not reason about `anon` access from migrations: default privileges grant
  anon/authenticated EXECUTE and SELECT at create time. Only RLS policies gate
  anon. Impersonate (`set local role anon`) to check.
- A `SECURITY DEFINER` function is a public endpoint: revoke from `public`,
  `anon` AND `authenticated`, unless the body already guards. Check
  `pg_policy` before revoking helpers used inside policies.
- A definer view over an RLS table is writable as postgres unless writes are
  revoked. `public_profiles` stays definer on purpose.
- Settlement columns are written only by RPCs that set
  `musafir.settlement_write`; `current_user` inside a definer trigger is always
  postgres.
- `profiles` is self-service: every privileged column needs a trigger guard
  (133 allows only `tenant -> owner`).
- Storage ownership is `storage.objects.owner`, not the path.
- PostGIS tables in `public` are not ours; a `revoke` there succeeds and does
  nothing. Check `relacl` after applying.
- Measure the effect, never the exception: an RLS-filtered UPDATE returns
  `[]` and raises nothing. Clear `request.jwt.claims` when dropping back to
  postgres in tests.

**Payments and QA hardening (136–140)**
([payments-and-qa-hardening.md](docs/notes/payments-and-qa-hardening.md))
- Risk-flagged payments are `pending_review`; the booking stays unpaid.
- Booking state machine, frozen columns, block checks, reveal, rating refresh,
  refund policy, `no_show`, suspension and rate limits all live in the database.
  Trigger order is by name and matters (`trg_enforce…` before `trg_stamp…`).

**Devices** ([devices.md](docs/notes/devices.md)) — device id is a client
UUID; functions read `auth.uid()`, never a user-id parameter; sign-out is a
deleted `auth.sessions` row; the cap evicts, never refuses; web is exempt;
`verify-otp` owns the cap.

**Bulk SMS / notifications** ([bulk-messaging.md](docs/notes/bulk-messaging.md))
— SMS is a claim-before-send queue with a fail-closed cap; notifications are
one insert, LEFT join preferences, quiet hours cross midnight.

**Edge functions and accessibility**
([edge-functions-and-accessibility.md](docs/notes/edge-functions-and-accessibility.md))
— pin `supabase-js@2.45.4`; CI runs `deno check`. A `Tooltip` does not name a
control: wrap in `Semantics(button: true, label: …)`.

**Settings and theme**
([app-settings-and-theme.md](docs/notes/app-settings-and-theme.md))
- Nothing user-tunable belongs in Dart: use `app_settings`. Adding a key means
  adding an arm to `fn_validate_app_setting`, recreated in full.
- Only the cron job expires bookings.
- A new palette goes in `AppPalettes.all` AND the validator; WCAG tests are not
  advisory. Flatten alpha before measuring contrast.
- The boot chain is `#C35063` (`Brand.rose`) in seven places, not the palette.

**Brand assets** ([brand-assets.md](docs/notes/brand-assets.md)) — generated by
`python3 tool/gen_brand_assets.py`; never hand-edit outputs.

**Android** ([android.md](docs/notes/android.md))
- **Do not strip `RECORD_AUDIO`** — voice search needs it and no plugin
  declares it.
- `android_min_version_code`: Play's answer is checked before the floor; do not
  reorder. Zero forces nobody. `package_info_plus` pinned to 9.x.

**QA login and phone numbers**
([qa-and-phone-login.md](docs/notes/qa-and-phone-login.md))
- **The master OTP is ON, allowlisted to one number, and not rate-limited.**
  Never use `*`. Unset it after each Play review. Driving a login can send a
  real SMS — do not automate against a number you do not own.
- `normalizePhone` decides which account a login lands on.
  `lib/services/auth/phone_number.dart` is the only Dart copy; run
  `sh tool/verify_phone_parity.sh` after touching either side.

**Shell and navigation** ([shell-and-navigation.md](docs/notes/shell-and-navigation.md))
- Browsing is public; acting goes through `AuthFlow.ensureSignedIn`,
  `IdentityGate.ensure`, `PublishGate.ensure`. Never push
  `CreateListingScreen` directly. `if (userId != null)` is a bypass.
- Tab indices are shared logical ids; the desktop header owns no state.

**Search UI** ([search-ui.md](docs/notes/search-ui.md))
- Panels write a `SearchDraft`; exactly one `updateFilters` per search.
- Never call `OverlayPortalController.show()` from build; never read layout in
  build; never animate to/from `Colors.transparent`.
- Turf and purpose are mutually exclusive (`search_scope.dart`).
- The guest party split is search-only.

**Listing cards and Explore**
([listing-cards-and-explore.md](docs/notes/listing-cards-and-explore.md)) — one
card size (`kListingCardMaxExtent` / `kListingCardAspectRatio`); text block is
intrinsic height; the rate line is a `Text.rich` hierarchy.

**Public browse and link previews**
([public-browse-and-link-previews.md](docs/notes/public-browse-and-link-previews.md))
- `listingIdFromRoute` stays strict about uuid shape.
- The Worker uses `setAttribute`, never string concatenation; fetches the
  shell as `/`; caches the lookup, never the HTML; reads only the area
  `address`. Run `sh tool/verify_link_previews.sh`.

## The admin portal is a separate repo

`../musafir-admin` — Next.js App Router, **Base UI** (the `render` prop), *not*
Radix (`asChild` does not exist here). It has no deploy config at all;
deployment is manual.

## Conventions

Comments explain *why*, not *what* — see the existing code, which is unusually
heavily commented by design. Match that density; a change that removes the
reasoning is a regression.

Tests are the repo's main safety net for logic that cannot be reached from a
widget test. When fixing a bug, prefer extracting the decision into a pure
function with a real seam (`lib/services/voice/speech_locale.dart`,
`lib/services/camera/selfie_camera.dart`) over testing through the UI.
