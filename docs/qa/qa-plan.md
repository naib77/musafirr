# QA plan — getting Musafir to production grade

Written for: the Musafir owner/engineering team deciding how to test the app
before and after launch.

## 1. What "production grade" can honestly mean

There is no bugless application. What a production-grade release actually has
is (a) every *known class* of failure covered by a check that goes red, (b) the
unknown ones found in staging rather than by a paying guest, and (c) the
ability to see and revert a bad release within minutes. This plan is built
around those three, in that order. Where it says "not built", that is the gap
to close, not a criticism.

## 2. What exists today (inventory)

| Layer | What is there | Verdict |
| --- | --- | --- |
| Static | `flutter analyze`, `dart format`, CI enforces both | Good |
| Unit / widget | ~970 tests, 86 test files, motion and contrast tests with negative controls | Good, deep on search/booking rules |
| Database | 16 SQL test files under `supabase/tests/`, rolled back against live, now also runnable locally (197 PASS / 0 FAIL on 2026-09-18). **Migration chain does not apply from scratch (003).** | Good pattern; chain needs repair |
| Build | `tool/build_web.sh` with registrant guard, `verify_deploy.sh` byte comparison | Good |
| Parity scripts | `verify_phone_parity.sh`, `verify_link_previews.sh`, `verify_address_privacy.sh` | Good, **not in CI** (no node step) |
| Edge functions | 13 functions, no automated tests | Gap |
| End-to-end browser | None. No `integration_test/`, no Playwright | **Gap** |
| Staging environment | None; `stage` and `production` share one project. **Local mirror exists since 2026-09-18** (`tool/local_db_from_live.sh`, catalog-identical to live) | Gap for staging, closed for local |
| Payments | SSLCommerz **production** gateway on live (no sandbox creds exist), IPN re-validates server-side, no automated scenario tests, 27 stale `initiated` rows | Gap |
| Security scanning | Supabase advisors read by hand; no dependency audit in CI | Gap |
| Observability | No error tracker, no uptime check, no alert on cron failure | **Gap** |
| Admin console | `../musafir-admin`, one script check (`check:sms`), no test framework | Gap |
| Load / performance | None. Bundle is 5.6 MB | Gap |
| Agent skills | 12 QA/testing skills installed globally 2026-09-17 (Flutter, Patrol, Playwright, OWASP, QA planner), mapped per layer in §4.0 | Ready, not yet used |

Housekeeping: `test/tmp_h1_test.dart` is a stray file and should be deleted or
renamed.

## 3. Prerequisite: a staging project

Every flow below needs a login, and login sends a real SMS through GenNet.
There is exactly one allow-listed master number, on **production**, kept for
the Play reviewer, and it is unthrottled. Testing against it is both a cost
and a risk. So:

1. Create a second Supabase project (`musafir-stage`). Migrations 001–131
   do **not** apply from scratch (003 is invalid SQL, see
   `docs/qa/REPORT_2026-09-18.md` F5); build it from
   `supabase/baseline/live_baseline.sql` with `tool/local_db_from_live.sh`
   pointed at its connection string, then forward migrations.
2. Point the `stage` GitHub Environment at it via `SUPABASE_URL` /
   `SUPABASE_ANON_KEY` (the workflow already reads them) and `wrangler.jsonc`
   `vars` for the Worker.
3. On staging **only**, set `MASTER_OTP_PHONES` to a short explicit list of
   test numbers (`01700000001`…`01700000005`) and a master code. Never `*`.
   Production keeps its single reviewer entry.
4. Seed script (`supabase/seed/stage.sql`): one admin, three hosts (one
   verified, one pending, one rejected), five guests (verified / unverified),
   listings of every type including a turf, bookings in every
   `booking_status`, a coupon, a suppression row, blocked dates.
5. SSLCommerz sandbox credentials on staging; production credentials never
   leave production.

Without this, "full flow" testing means driving production with real SMS and
real money.

**Until it exists, QA runs on production with the master account**
(01673293542, code 3969), under the rules in `docs/qa/payment-test-plan.md`
section 2: own listings only, never widen the allowlist, never point
production at the sandbox, log every QA booking in `docs/qa/payment-runs.md`.

## 4. The layers, and what goes in each

### 4.0 The skills that drive each layer

Every layer below names the Claude Code skill that does its mechanical part.
They are installed globally under `~/.claude/skills` (installed 2026-09-17
with `npx skills add <owner/repo@skill> -g -y`; refresh with `npx skills
update`) and are invoked as `/<name>` in a session opened in this repo. A
skill is a procedure, not a substitute for the checks themselves: the output
of each one is a file in this repo (a test, a script, a report) that CI then
runs without the skill.

| Layer | Skill | Source | What it is for here |
| --- | --- | --- | --- |
| 4.2 unit | `dart-add-unit-test` | flutter/agent-plugins (official) | pure-function tests with a negative control |
| 4.2 unit | `dart-generate-test-mocks` | flutter/agent-plugins | mockito mocks for `SupabaseClient`, gateways, place lookup |
| 4.2 widget / golden | `flutter-add-widget-test` | flutter/agent-plugins | `WidgetTester` tests and the golden set |
| 4.2 coverage | `dart-collect-coverage` | flutter/agent-plugins | LCOV report, the number the gate in §5 reads |
| 4.2, 4.3 discipline | `tdd`, `verify-and-stop`, `diagnosing-bugs`, `investigate-first` | already installed | red first; prove the fix; feedback loop for hard bugs |
| 4.4, 4.7 security | `api-security-review` | owasp/secure-agent-playbook (official OWASP) | API Top 10 walk over PostgREST and the edge functions: BOLA, mass assignment, rate limiting |
| 4.7 security | `web-security-review` | owasp/secure-agent-playbook | Web Top 10 over the Worker, `_headers`, the admin console |
| 4.7 security | `owasp-security-check`, `security-review` | sergiodxa/agent-skills; built in | per-change security pass on a diff before it merges |
| 4.5 E2E web | `playwright-testing` | alinaqi/maggy | Playwright suites against the staging URL |
| 4.5 E2E Flutter | `flutter-add-integration-test` | flutter/agent-plugins | `integration_test/` flows, driven and recorded through the Flutter MCP |
| 4.5 E2E native | `patrol-write-test`, `patrol-test-architecture` | leancodepl/patrol (official) | Android/iOS flows that cross native dialogs: permissions, share sheet, time pickers |
| 4.8 UX | `ui-ux-pro-max`, `flutter-ui-ux`, `run` | already installed | heuristic checklist, contrast search, screenshot the running app |
| 4.8, §5 QA process | `qa-test-planner` | softaworks/agent-toolkit | manual test cases and regression suite per feature, in the bug-report shape §5 grades |
| §5 triage | `qa`, `to-issues`, `triage` | already installed | turn a conversational bug report into GitHub issues with codebase context |
| every layer | `code-review`, `review` | built in | review of the tests themselves, which are code and rot like code |

Not adopted, and why: the Supabase testing skills on the registry all have
under 130 installs from unknown authors, and this repo's rolled-back SQL test
pattern (§4.3) is already stricter than any of them. Playwright's skill is
from a single author with a large install count; read it before trusting its
defaults, and keep the Semantics-label rule in §4.5 over anything it suggests
about selecting by pixel position.

### 4.1 Static and dependency hygiene (minutes, every push)

- Keep `analyze` + `format`. Add `deno lint` and `deno check` for
  `supabase/functions/` in CI (there is currently no check that an edge
  function even type-checks before deploy).
- `flutter pub outdated --mode=null-safety` weekly; `npm audit` in the admin
  repo. Pin `package_info_plus` 9.x is deliberate; see CLAUDE.md.
- Run the Supabase advisors (`security` and `performance` lints) from the
  Management API on a schedule and diff against an accepted baseline. Two
  lints (`public_profiles` 0010, `spatial_ref_sys` 0013) are accepted on
  purpose; anything new should fail.
- Secret scan (`gitleaks`) in CI. The Google Maps key is already public and
  committed (see memory note); rotation and per-surface restriction is a
  known open item.

Skills: `owasp-security-check` gives the checklist for the CI security
step; `dart-collect-coverage` is the model for the coverage job, and its
LCOV output is what a coverage floor in CI reads.

### 4.2 Unit and widget (exists — keep the discipline)

The repo's rule is the right one: extract the decision into a pure function
and test it with a **negative control** that proves the test can fail. Keep
requiring both for every fix. Two additions:

- Golden tests for the six most-seen screens (Explore desktop, Explore
  mobile, listing detail, booking sheet, host wizard step 1, trips) at 390,
  768, 1440 px and text scale 1.0 / 2.0. Catches overflow and palette
  regressions that widget tests miss.
- Every `AppPalette` already passes contrast. Add the same for `Brand.rose`
  (done) and for any hardcoded colour that carries text.

Skills: `/tdd` for the red-green loop, `/dart-add-unit-test` for a pure
function, `/flutter-add-widget-test` for a widget and for each golden,
`/dart-generate-test-mocks` when the class under test holds a
`SupabaseClient` or a gateway (the existing tests hand-roll fakes; either is
fine, but do not mix both for one dependency), `/dart-collect-coverage` to
find which of the 41 test files is carrying the least. `/verify-and-stop`
closes each fix: run the test, show it red without the change and green
with it, stop.

### 4.3 Database contract tests (extend the pattern)

`supabase/tests/113_*` through `131_*` are the model: a transaction, fixtures,
`set local role`, assertions as rows, rollback. Coverage stops at migration
113. Backfill in priority order:

1. `create_marketplace_booking` — every refusal path: overlap (`23P01`
   both hints), host away, min/max duration, party over cap, blocked dates,
   unverified guest, inactive listing, past dates, reversed window, price
   is server-computed and ignores any client value.
2. Booking state machine — every transition in
   `pending → confirmed → active → completed` and the two exits, who may
   perform each (guest / host / admin / cron), and that `completed` is
   refused while `payment_status <> 'paid'`.
3. `expire_stale_bookings` with a junk `booking_accept_window_hours`.
4. Messaging — `is_conversation_member` / `get_unread_count` still accept a
   caller-supplied `p_user_id` (CLAUDE.md, open). Write the failing row
   first, then the migration.
5. Reviews — reveal rules, one review per booking, aggregates exclude
   unrevealed (117 fixed it; pin it).
6. Coupons / `validate_coupon` + `redeem_coupon` — expiry, usage cap, per-user cap, stacking.
7. Storage — `listing-images` and identity-document buckets: anon read, owner
   write, cross-user write refused, size/MIME limits.
8. The 20 `SECURITY DEFINER` functions with mutable `search_path` — one
   migration (`alter function … set search_path = public, pg_temp`) and one
   test row that walks `pg_proc` and fails on any definer function without
   it.

Run these in CI against staging on every migration change.

Skills: none of the installed skills writes PostgreSQL tests, and none
should be adopted for it; the pattern in `supabase/tests/` is the standard.
Use `/diagnosing-bugs` when a row fails against live and the cause is not
obvious, because it insists on a reproducible loop before a hypothesis, and
`/api-security-review` for the list of refusal paths a booking or messaging
RPC should have before writing the rows in item 1 and item 4.

### 4.4 API black-box authorization matrix (the highest-value new piece)

PostgREST publishes every table and function in `public`. The question "what
can an anonymous visitor / a guest / another host / an admin do to this row"
has to be answered by *request*, not by reading SQL — CLAUDE.md documents two
full account takeovers found exactly this way (116, 117).

Build `tool/authz_matrix.sh` (bash + curl + jq, or a Deno script):

- Enumerate `pg_tables` and `pg_proc` in `public` from the live schema.
- For each of four JWTs (anon key, guest A, host B, admin), attempt
  `GET`, `POST`, `PATCH`, `DELETE` on each table and `POST /rpc/<fn>` with an
  empty body.
- Compare the status codes against a committed expectation file
  (`docs/authz_expected.tsv`). Any drift fails.

Specific probes to include from day one, because each is a known class here:

- PATCH through every view (definer-view write hole, 117).
- Every `admin_*` RPC as anon and as a normal user → must be refused by the
  body guard, not just a missing grant.
- `otp_log_send` and the other three OTP functions → 401/403.
- `spatial_ref_sys` DELETE as anon → refused by trigger (115).
- `user_devices` direct INSERT / `revoked_at` UPDATE → refused (123–125).
- Cross-user reads: another guest's bookings, another host's payouts,
  another user's `notification_preferences`, another conversation's messages.
- Edge functions deployed with `--no-verify-jwt` (`sslcommerz-ipn`,
  `messenger-webhook`, `whatsapp-webhook`): confirm each validates its
  caller some other way (signature, re-validation call), and that a forged
  body cannot change state.

Skills: `/api-security-review` is the checklist this script enumerates
against: BOLA (every `id=eq.` on another user's row), mass assignment (every
PATCH with a column the client should not own, `role` and `payment_status`
first), unrestricted resource consumption (the OTP paths, `search_listings`
with a huge radius), and function-level authorization (every `rpc/`). Run it
once to produce the expectation file, then the script, not the skill, runs
in CI. `/web-security-review` covers the two surfaces PostgREST does not:
the Worker's HTML rewrite and the admin console's routes.

### 4.5 End-to-end browser flows (build this once staging exists)

Use Playwright against the **deployed staging URL**, not `flutter run`,
because CLAUDE.md's stale-registrant bug is invisible in `flutter run` and
only shows in the release bundle. Flutter web renders to a canvas, so drive it
through the semantics tree: enable `SemanticsBinding` on boot in staging
builds (`--dart-define=E2E=true`) and select by `aria-label`. Every control
that a flow needs has to carry a `Semantics` label; the search bar already
does.

Log in with the staging master numbers. Flows, each a script with a
screenshot at every step and a hard assertion at the end:

**Visitor**
1. Land, browse curated rows, open a listing, see amenities and reviews.
2. Search by area, by dates (blocked listing hidden), by party, by turf.
3. Voice search returns a query (mock the recogniser; assert the parse).
4. Tap Reserve → login sheet appears; nothing bookable before login.
5. Share a listing URL → Worker rewrites OG tags (`verify_link_previews.sh`
   already covers the Worker; the E2E confirms the route resolves).

**Guest**
1. OTP login, first time → empty profile, identity gate blocks booking.
2. Submit identity documents → admin approves in the console → booking
   allowed.
3. Book daily stay: dates, party, coupon → request pending → countdown shown.
4. Host accepts → pay via SSLCommerz sandbox success → `paid` shown in Trips.
5. Book hourly turf slot; second guest tries overlapping slot → refused
   with the listing-overlap message; same guest books overlapping stay
   elsewhere → tenant-overlap message.
6. Cancel a pending booking; cancel a confirmed one; check host sees both.
7. Message the host; receive a push (web push on staging) and an in-app
   notification; quiet hours respected for bulk only (known gap for the
   rest — document, do not assert).
8. Leave a review after completion; before completion the control is absent.
9. Wishlist add/remove survives reload.
10. Devices page lists this browser; "Sign out everywhere else" kills a
    second session (open in a second browser context and assert it is
    logged out on next request).
11. Delete account / data export if offered (check `docs/legal`).

**Host**
1. Login, become host, blocked until verification + address proof.
2. Wizard: each listing type; photos required (index-based bug was here);
   turf sport/format/surface; shared amenity no longer duplicates rows.
3. Publish → listing pending → admin approves → visible in search.
4. Block dates → hidden from dated search only, still visible undated.
5. Set `host_available` off → not bookable even by deep link.
6. Receive request → accept / reject / let it expire (shorten the window in
   staging `app_settings` to 1 hour and wait a tick).
7. Check-in, "Service complete" refused unpaid, allowed paid.
8. Payout method add, earnings visible, disbursement record appears
   (whatever the current payout process is — it is manual; assert the record).
9. Edit listing price → existing pending booking keeps its server-computed
   price.
10. Delete listing with active booking → refused or handled; decide which
    and pin it.

**Admin (Next.js console)**
1. Approve/reject verification; user sees the change.
2. Change `app_settings` → app picks it up (theme, radius, accept window,
   `android_min_version_code` = 0 behaviour).
3. Bulk SMS: CSV upload, dedupe count honest, cap refused not truncated,
   suppression honoured, retry only `failed`.
4. Bulk notification: audience preview counts match sent rows; opt-out and
   quiet hours honoured.
5. Every admin action lands in the audit log (`docs/features/audit-log.md` says
   how far that exists).

Run the visitor and guest suites on every deploy to staging; the full set
nightly.

Skills, by surface:

- Web, the primary target: `/playwright-testing` scaffolds the suite. Point
  it at the staging URL and at the Semantics labels; the visitor and guest
  flows in this section are the first two specs.
- Flutter `integration_test/`: `/flutter-add-integration-test` connects to
  the running app through the Flutter MCP, lets the flow be driven click by
  click, and writes what was driven as a permanent test. It runs in
  `flutter test integration_test -d chrome` and does not see the release
  bundle, so it complements Playwright rather than replacing it: use it for
  flows where the assertion is on Dart state (the draft, the notifier's
  commit count) rather than on what shipped.
- Android and iOS: `/patrol-write-test` for a flow, `/patrol-test-architecture`
  before the third one, so the modules (login, search, booking) are shared
  rather than copied. Patrol is the only one of the three that can accept
  the microphone permission dialog for voice search, the share sheet, and
  the native time picker in the hourly flow. Its login step must use the
  staging master OTP only, never a real number (see §3).

### 4.6 Payments (separate, because money is irreversible)

**Live is the production gateway, not the sandbox** (`SSLCZ_API_BASE` is
`securepay`, verified 2026-09-17). How each row below is exercised without a
sandbox, and what one ৳10 live run covers, is in
`docs/qa/payment-test-plan.md`; that document is the runbook, this table is
the contract. In short: the handler decisions become `deno test` rows on an
extracted `settle()`, the authorization rows become rolled-back SQL, and only
the end-to-end success and cancel paths are driven for real, on the master
account's own ৳10-per-hour listing.

Scripted against `sslcommerz-init` and `sslcommerz-ipn`, plus one browser
flow:

| Scenario | Expected |
| --- | --- |
| Success, redirect only (IPN blocked) | `paid` once |
| Success, IPN only (WebView closed) | `paid` once |
| Success, IPN and redirect race | `paid` once, one `validated_at` |
| IPN replayed 5× | idempotent, still one row updated |
| IPN with tampered `amount` | `failed`, booking stays `unpaid` |
| IPN with valid `val_id` from *another* transaction | refused (`tranOk`) |
| Unknown `tran_id` | 404, no state change |
| Gateway FAILED / CANCELLED | row marked, booking `unpaid`, guest sees real error |
| Validation API timeout | `pending`, poll surfaces "still confirming", no `paid` |
| Pay before host accepts | `sslcommerz-init` refuses |
| Pay after `completed` | refuses |
| Pay twice on same booking | second init refused or reuses attempt |
| Currency not BDT | refused |
| Cash payment path (`076`, `086`) | host marks paid; guest cannot mark |
| Amount = server `total_price`, not client | send a lower amount in the init body; ignored |

Refunds and partial payments: confirm whether they exist. If not, the
decision ("no refunds through the app, handled manually") belongs in
`docs/features/sslcommerz.md`, and the UI must not promise one.

Reconciliation: a nightly query comparing `payments.status = 'paid'` totals
against the SSLCommerz merchant report. Any difference is an alert.

Skills: `/api-security-review` for the IPN endpoint specifically, because
webhook verification (signature, replay, amount and currency compared to
the stored booking rather than to the request) is one of its explicit
checks. The scenario script itself is curl; no skill writes it better than
the table above.

### 4.7 Security review (do this as a checklist, then as tests)

Ordered by what has actually bitten this codebase:

1. **Authorization by request**, not by reading SQL (4.4).
2. **`SECURITY DEFINER` inventory**: every one has a body guard, is revoked
   from `public`, `anon` and `authenticated` unless needed by an RLS policy,
   and has a fixed `search_path` (20 still do not).
3. **OTP**: the master path is unthrottled on production. Unset
   `MASTER_OTP_*` the day the Play review passes. Add rate limiting on
   `send-otp` per phone and per IP (edge function + a table), and per phone
   on `verify-otp` attempts. Test: 20 wrong codes → locked for N minutes.
4. **Session and devices**: refresh-token revocation actually ends the
   session (124/125 proves it in SQL; the E2E should prove it in a browser).
5. **Edge functions without JWT verification**: each must authenticate its
   caller another way. IPN does (validation API). Check the two chat
   webhooks verify Meta's `X-Hub-Signature-256`.
6. **Secrets in the bundle**: only the anon key and Maps key belong there.
   `strings build/web/main.*.dart.js | grep -iE 'service_role|secret|sk_'`
   in CI.
7. **Headers**: `web/_headers` should carry a CSP that lists Supabase,
   Google Maps, Firebase and SSLCommerz origins and nothing else, plus
   `X-Frame-Options`/`frame-ancestors`. Check with securityheaders.com after
   deploy; make `verify_deploy.sh` assert the key ones.
8. **Storage buckets**: policies tested in 4.3; also confirm signed-URL
   lifetime for identity documents is short and the bucket is private.
9. **PII**: `profiles` has 31 columns anon can *see by grant* and RLS hides.
   Any new `to public` policy on `profiles` is a leak; the authz matrix
   catches it.
10. **Dependency and supply chain**: `pub outdated`, `npm audit`, pin
    action versions by SHA in the workflow.
11. **Input handling at the edge**: Worker uses `setAttribute` (tested);
    `listingIdFromRoute` is strict (tested). Fuzz `search_listings` with
    reversed windows, huge radii, NaN coordinates, 10 000-guest parties —
    expect empty results, never `5xx`.
12. **Abuse**: listing spam by an unverified host is blocked at INSERT
    (114); booking spam by one guest is bounded by the tenant-overlap
    constraint; message spam has no limit — decide one.

Consider one external penetration test before public launch; it is cheap
relative to the takeover classes already found here.

Skills: run `/api-security-review` over `supabase/functions/` and the
PostgREST surface, and `/web-security-review` over `worker/index.js`,
`web/_headers`, `web/index.html` and `../musafir-admin`, once per release
and once when either changes shape. `/owasp-security-check` or the built-in
`/security-review` on every pending diff that touches an edge function, a
migration or the Worker. All three report; each finding then becomes a row
in §4.3 or a request in §4.4 so it stays checked after the reviewer forgets.

### 4.8 User-experience testing

- **Heuristic pass** on every screen against a fixed checklist: touch
  targets ≥ 44 px, contrast 4.5:1, focus visible, one primary action per
  screen, error text next to the field, loading state for every async
  action, empty state with a next step, no dead ends without a back.
- **Device matrix**: Chrome / Safari / Firefox desktop at 1440 and 1000 px
  (the header breakpoint); iPhone Safari and Android Chrome at 390 px; one
  low-end Android phone on real 4G. Text scale 2.0 on all.
- **Five-user usability sessions**, think-aloud, three tasks each: find a
  room near a hospital and book it; list a turf; pay for a booking. Record
  time-on-task and where they hesitate. This finds what no test can.
- **Bangla**: the UI is English; content is mixed. Check Bangla listing
  titles wrap, ellipsize and render in the card, the OG preview and SMS
  (UCS-2 segment count, 128).
- **Accessibility**: run with a screen reader once per release (VoiceOver on
  Safari, TalkBack on Android). The Semantics labels the E2E suite needs
  double as this.
- **Performance budget**: Lighthouse on staging, mobile profile. Targets:
  LCP < 3 s on 4G, CLS < 0.1. The 5.6 MB main bundle is the first thing to
  attack — deferred imports for the host wizard, admin-ish screens and the
  map; `--tree-shake-icons` is on by default, confirm it is not disabled.

Skills: `/ui-ux-pro-max` holds the heuristic checklist and the contrast and
touch-target rules; `/flutter-ui-ux` covers Flutter-specific rendering
questions (text scale, overflow, `Semantics`). `/run` launches the app and
screenshots it, which is how the device-matrix pass is recorded. Usability
sessions are with people; no skill applies.

### 4.9 Reliability and operations

- **Error tracking**: none today. Add Sentry (Flutter + Deno SDKs) or
  Supabase log drains to a place someone reads. Alert on any edge function
  `5xx` rate > 1 % and any uncaught Dart error spike.
- **Cron health**: `expire_stale_bookings` (15 min), `sweep-sms-campaigns`
  (1 min), device reaper (daily). A cron that stops silently is a booking
  that never expires. Query `cron.job_run_details` for failures in the last
  hour on a schedule and alert.
- **Uptime**: a synthetic check hitting `/`, `/rest/v1/rpc/search_listings`
  (undated, anon) and one edge function every 5 minutes.
- **Backups**: confirm PITR is on for the production project and do one
  restore drill into staging; write down how long it took.
- **Rollback**: `build/web` is committed, so rollback is `git revert` and a
  deploy; migrations are not reversible by default. Every migration from now
  on ships with a `-- down:` block or an explicit "irreversible" note (120
  is one).
- **Deploy proof**: `verify_deploy.sh` after every deploy, automated in the
  workflow's last step.

Skills: `/qa-test-planner` produces the manual regression checklist that
is walked after each production deploy, and the bug-report template that
§5 grades. `/qa` turns what a tester says in conversation into issues.

## 5. Bug severity and release gate

| Severity | Definition | Gate |
| --- | --- | --- |
| S1 | Money wrong, data of another user visible or writable, login bypass, app unusable | Blocks release; hotfix |
| S2 | A main flow (search, book, pay, publish) fails for a class of users | Blocks release |
| S3 | Feature wrong but a workaround exists | Fix before next release |
| S4 | Cosmetic, copy, minor UX | Backlog |

Release only when: CI green, SQL contract tests green on staging, authz
matrix has no drift, visitor + guest E2E green on the staging deploy,
payments table above green in sandbox, `verify_deploy.sh` green after
production deploy, zero open S1/S2.

## 6. Order of work

1. **Week 1** — staging project, seed script, master OTP on staging only.
   Add `deno check`, secret scan and the bundle-secret grep to CI. Delete
   `tmp_h1_test.dart`. Apply migration 131 (132 was applied 2026-09-18 and
   closed the S1 in `docs/qa/payment-test-plan.md` section 7). Run `/dart-collect-coverage`
   once for the baseline number.
2. **Week 2** — `/api-security-review` first, then the authz matrix script
   and expectation file; fix what it finds (expect the `search_path` twenty
   and the two `p_user_id` functions). Payment scenario script against
   sandbox. `/web-security-review` over the Worker and admin console.
3. **Week 3** — Semantics labels on every flow control; `/playwright-testing`
   visitor and guest suites on staging; `/flutter-add-integration-test` for
   the search draft and booking-sheet flows; error tracking and cron alerts
   live.
4. **Week 4** — host and admin suites; `/flutter-add-widget-test` goldens;
   `/patrol-write-test` for voice search and the hourly time picker on a
   real Android phone; device matrix pass with `/run`; `/qa-test-planner`
   regression checklist; five usability sessions; Lighthouse budget and
   first bundle-size cut.
5. **Before launch** — external pen test, backup restore drill, unset the
   production master OTP, CSP in `_headers`, reconciliation query scheduled.

## 7. What this plan does not promise

It will not make the app bugless. It will make every bug class that has
already appeared here — unauthorized writes through views, unenforced
booking rules, stale bundles, silent cron failures, unverified payments —
impossible to reintroduce without a red check, and it will put the unknown
ones in front of you on staging with a screenshot rather than in a guest's
inbox.
