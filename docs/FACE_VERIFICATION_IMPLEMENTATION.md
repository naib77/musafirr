# Identity document and face review implementation

## Restored document choices (latest change)

The NID-only upload restriction was an unintended regression. The UI again offers NID, passport, driving license, student/admission/exam ID, and office/employee ID, including document number. NID requires two sides; other IDs support a front/photo page with an optional back. All types use explicit admin document approval plus the separate face approval. Existing records and approvals were not deleted.

Migration 143 was deployed with explicit user approval on 2026-09-27, with new type-aware submission and approval RPCs and compatibility wrappers for the NID-only endpoints. It does not rewrite existing rows or enable capture. A submitted replacement can supersede the current document slots but does not delete stored historical image bytes. The live database is on migration 143. The revised app/admin builds still require deployment.

## Latest scope: NID plus face review

The user restored NID review on 2026-09-27. Profile now opens a two-step NID/face checklist. New private NID submissions upload both sides and use an atomic submission RPC; the admin approval RPC validates the two reviewed paths. Independent statuses prevent an old NID approval from being mislabeled as face approval. Migration 142 changes the shared booking/publishing predicate to require both decisions. It preserves records but removes the earlier legacy-identity-only exemption. It was deployed to live project `bojkmonskqlhuakxhzcb` with explicit user approval on 2026-09-27.

Migration 142 is live, while the new Flutter/admin deployment and capture/retention rollout remain pending. Face capture remains disabled, so existing NID-only users are currently blocked from new bookings/publication. A rollback should preserve documents, captures, and verdicts; restore the 141 function definitions only after reviewing the intended eligibility policy. Do not restore document auto-approval.

The face screen still collects no documents itself; the separate NID screen collects front/back JPG or PNG images under 5 MB each, with explicit consent. NID review is manual and does not perform government-database validation. Privacy copy now covers current NID collection.

## Original face capture implementation

The face-capture route collects a face capture. Guided capture asks for blink, left turn, and right turn in a server-randomized order. Each action requires a neutral/action/neutral transition, with continuous single-face framing. The session expires after 10 minutes; each recording lasts at most 35 seconds. Face loss, multiple faces, stale frames, and backgrounding reset or stop the capture. Smile is not compulsory. The accessible manual route records only a photo and is visibly distinguished from guided capture.

MediaPipe Tasks Vision 0.10.32 and its float16 face model run locally. Pinned runtime files, license, upstream links, and hashes are in `web/face/`. No paid provider or biometric inference API is called. Web embeds the local capture page; Android/iOS use the same HTTPS page through the existing WebView plugin, with native camera permission handling. `FACE_CAPTURE_ORIGIN` can select a staging HTTPS origin for native builds. Deploy `/face/` before building/releasing native apps against that origin.

The UI uses the existing theme palette and typography, a two-column desktop layout, scrollable mobile layout, and explicit consent. Size transitions are disabled when reduced motion is requested. NID upload is on the separate NID review screen.

Capture completion is not approval. Migration 141 creates immutable, private evidence paths and an admin-only review RPC with evidence-version checking, reviewer identity, decision time, and exception notes. The separate `musafir-admin` project has `/verifications/faces`, linked from Verifications. Admins can approve, reject, or request another attempt; manual approval requires a reason. A submitted recording must be watched before the portal enables approval.

Migration 141 originally permitted face or historical identity approval; migration 142 now requires both NID and face approval. Face approval never changes `profiles.verification_status`, `nid_verified`, or the public identity badge. Historical records are preserved. The old document-stamp auto-approval trigger is removed. Existing address and role guards remain intact.

## Deployment order

Implementation and local migration tests do not deploy anything. The repository requires explicit confirmation before a live migration.

1. Review live schema drift, especially `create_marketplace_booking`, `can_publish_listings`, storage policies, and profile guards. Migration 141 includes the complete booking function from the local live baseline with only its approval predicate changed. Abort deployment if the live definition has additional changes.
2. Apply `141_face_review.sql` to the approved environment. It inserts `face_review_enabled=false`; do not enable it yet. Regenerate the baseline after live application, then remove 141 from the local newer-migrations default.
3. Deploy the Flutter web artifact built with `sh tool/build_web.sh`, including `/face/` and its WASM/model files. Deploy the admin portal. Check that each deployment targets the same Supabase environment.
4. Deploy `purge-face-evidence`, configure a dedicated random `FACE_RETENTION_SECRET`, and schedule POST requests at least daily using the `x-retention-secret` header. Store that scheduler secret in a secret store, never `app_settings`, URLs, app code, or logs. The function uses its server-only Supabase service key. If `morePossible` is true, invoke again until the batch is drained. Monitor non-2xx responses and missed runs.
5. Verify the retention job in staging: reviewed captures older than 30 days, abandoned attempts after expiry plus one day, and orphaned files after account deletion must be removed through the Storage API. Retain decision metadata. A pending attempt whose media expires becomes superseded and can be retried. Concurrent approval must not be overwritten by cleanup.
6. Run a consenting participant pilot on low-cost Android, iOS Safari, Android/iOS WebViews, desktop browsers, poor lighting, glasses, and accessibility cases. Confirm direction/mirroring, genuine blink thresholds, cancellation, rejected permissions, and replay limitations. Native camera behavior still needs physical-device testing.
7. Enable `app_settings.face_review_enabled='true'` only after those checks pass. Turning it back to `false` stops new captures; existing submitted attempts remain reviewable. Never bypass admin approval to recover from an outage.

Migration 141 was applied to live project `bojkmonskqlhuakxhzcb` on 2026-09-27 with user approval. Live function definitions matched the baseline before application. The migration committed, and the REST schema now resolves `face_verification_status`. Rolled-back authenticated checks verified status reads, preservation of existing approvals, disabled capture, booking/publishing gates, and rejection of non-admin review. All 14 historical approvals remain; the new evidence bucket is private and the attempts table has RLS enabled. No attempts were created.

`face_review_enabled` remains `false`. App/admin deployment, retention deployment and scheduling, and the physical-device pilot remain pending. No account creation or paid service activation was performed.

If rollout must be paused, keep `face_review_enabled=false`; preserve attempts and review metadata. Existing booking/publishing functions were saved before deployment in `/tmp/musafirr-face-141/before-functions.json`. Do not drop evidence tables or restore the old document auto-approval trigger as a routine rollback. Any function rollback needs review against the current live schema.

## Costs and assurance

There are no per-check provider fees. First capture downloads roughly 15 MB of runtime/model assets; the complete shipped files include two WASM variants, but the browser chooses one. Runtime/model download, hosting, private media storage, and review labor are not guaranteed free. Each video is limited to 8 MiB, each photo to 512 KiB, and starts to five per user per 24 hours.

This is gesture-guided capture, not certified presentation-attack detection. A modified client can fabricate gesture results or upload fabricated media. The backend never trusts a client liveness score. Admin review can still miss sophisticated replay, deepfake, or camera-injection attacks. There is no face recognition, identity matching, uniqueness check, or identity-document validation.

## Validation

- Flutter analysis and complete regression suite; focused consent, failure/retry, pending/admin status, server switch, narrow/large-text and reduced-motion tests.
- `node --test test/verification/face_challenge_test.mjs`: gesture transitions, wrong direction, static face, face loss/multiple faces, stale frames, malformed sequence.
- `supabase/tests/141_face_review_test.sql`: rolled-back local RLS/RPC tests for protected verdicts, media immutability, cross-user access, stale evidence, admin audit, manual exceptions, expiry, and rollout switch.
- Browser smoke test using synthetic camera frames loads the actual local model, blocks a missing face, and stops camera on interruption. This is not a human liveness validation.
- Admin TypeScript checking, focused ESLint, and production build.
- Deno type checking of the retention function.

Screenshots were inspected for desktop, mobile, and capture guidance. Keep physical-device and adversarial pilot results separate from automated checks; automated test success does not establish biometric accuracy.

## Build notes

The Android wrapper was 8.9 while the existing Android Gradle Plugin is 8.11.1, which requires Gradle 8.13. The wrapper now uses 8.13; the Android plugin and application dependencies were not upgraded. The two WebView platform packages were already present transitively and now appear as direct dependencies for camera playback configuration, at their existing locked versions.

This machine has Command Line Tools rather than a full Xcode installation. iOS compilation, camera permissions, inline preview, and foreground/background recovery require validation on an Xcode-equipped machine and physical devices before rollout.

Latest automated results: 1,015 Flutter tests passed (one pre-existing skipped test), five JavaScript challenge tests passed, and 37 local database assertions passed. Flutter analysis, web release build, admin type/lint/build, and retention type checks passed. The synthetic browser also completed the manual photo path without sending any media to Supabase.

Android debug APK build passed after aligning the Gradle wrapper. Existing plugin deprecation warnings remain; no new plugin versions were introduced.

## NID and face follow-up validation (2026-09-27)

The combined implementation passes Flutter analysis and 1,021 Flutter tests (one existing skip), including failed NID submission, consent/both-side requirements, revoked resubmission, status outages, and both entry points at narrow widths with 2× text. Web release and admin production builds pass; admin TypeScript and focused ESLint checks pass. Migration 142 was first validated in the local database. Its 26 rolled-back assertions cover independent approvals, immutable evidence, cross-user and stale-path denial, atomic submission, revocation, and renewed admin review after resubmission.

Migration 142 was subsequently deployed with user approval on 2026-09-27. All seven checked live dependency definitions matched the baseline. All 37 documents, 13 NID approvals and existing verdict fingerprints were preserved; no face attempts were created. Rolled-back live checks passed for authenticated NID/face/combined status, the requested revoked account, booking/publishing restrictions, missing-image rejection, admin-only approval, immutable-evidence policies and disabled capture. REST probes confirmed the new endpoints resolve and reject anonymous access.

The updated application/admin deployment and face enablement remain pending. Physical-device capture validation and face-retention scheduling remain required. Pre-migration definitions and schema snapshots are saved in `/tmp/musafirr-nid-142/` for comparison; do not restore the old approval policy without an explicit decision.

Restoration validation: Flutter analysis and 27 focused Flutter tests passed. All five document types passed local submission and admin-approval checks (12 reported checks); all 26 migration-142 regression checks still passed. Web and admin production builds, admin TypeScript, and focused ESLint passed. Migration 143 was first tested locally, then deployed with user approval. Seven live dependency definitions matched the baseline before application. Document-record and identity-record fingerprints were unchanged afterward: all 37 documents and 13 approvals were preserved. Live checks confirm all five document types reach evidence validation, unsupported types and missing images are rejected, nonadmins cannot approve, and the NID compatibility endpoint still works. REST probes confirm both new endpoints resolve and reject anonymous access. No live documents were submitted or user verdicts changed by these checks.

## Admin capture switch

The admin portal now includes **Settings → Verification → Allow new face captures**. It uses the existing admin-only boolean settings action and writes `face_review_enabled` as `true` or `false`. The displayed value matches the capture RPC's exact `true` check. The control permits guided and manual capture starts; it does not approve submissions or change document requirements. Disabling it preserves existing attempts and approvals. Users can refresh their verification screen after a setting change.

The toggle's TypeScript, focused ESLint, and admin production build checks passed. No new database migration is needed. The admin code must be deployed before this switch appears in the hosted portal; adding the control did not change the live flag.

## Capture reliability fixes (2026-09-27)

The guided page now starts its check automatically after camera/model readiness, following the consent and Start action in Flutter. Browsers that block playback show a **Start camera** button that resumes the same stream. Manual review still requires an explicit photo action. Camera permission is requested before model initialization, and a recorder codec that fails to initialize falls back to another supported codec.

Head-turn coaching calibrates a neutral nose position, measures displacement along the eye axis with the camera aspect ratio, and tolerates small fluctuations during a sustained turn. Whole-face bounds replace the shrinking eye-width framing gate. The preview uses `contain` so the person sees the complete recorded frame. A tracking interruption shorter than 400 ms keeps completed actions but invalidates the current gesture and requires a fresh neutral pose. Multiple faces, longer loss, invalid input and stale frames reset progress. These are coaching heuristics, not proof of identity or certified liveness.

Every asynchronous capture operation and recorder callback is bound to its camera session. Cancelling during photo encoding can no longer return stale success or interfere with a retry. Recording stops before asynchronous photo encoding completes. Failure/exit cleanup releases tracks and the model; disconnected/frozen video and malformed configuration show recoverable errors. The existing 35-second video limit, media size limits, explicit submission and mandatory admin approval remain in place.

Regression commands:

```sh
node --test test/verification/face_challenge_test.mjs test/verification/face_metrics_test.mjs
# Requires Playwright on NODE_PATH and Chrome installed; uses synthetic camera data.
node --test test/verification/face_capture_browser_test.cjs
# Exercise the exact deployable files after the mandatory build:
FACE_TEST_ROOT="$PWD/build/web" node --test test/verification/face_capture_browser_test.cjs
```

The browser suite includes real bundled-model initialization on a synthetic camera, deterministic gesture fixtures, automatic start, autoplay recovery, codec fallback, permission errors, cancellation races, inference failures/retry, missing/multiple faces and full photo/video completion. It does not measure real-face accuracy. Android/iOS physical-device and varied lighting/face testing remain necessary; these local fixes are not a production deployment. Native capture uses the hosted `/face/` page, so its hosted web assets must also be deployed for native users to receive the fixes. No database migration is required.

Validation for this reliability patch: 14 challenge/landmark tests, 11 browser tests against the rebuilt `build/web` assets, and 27 focused Flutter verification tests passed. Flutter analysis and `sh tool/build_web.sh` passed. Capture source and built modules match byte-for-byte. Existing WebAssembly dry-run and Cupertino font warnings remain. No live biometric media or user verification records were modified during testing.
