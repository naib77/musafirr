# Supabase Storage to AWS S3 migration plan

Status: planning only. No application code, database, AWS infrastructure, stored media, permissions or live settings changed by this plan.

Prepared: 2026-09-27. Based on the Flutter app, sibling `musafir-admin`, checked-in live database baseline and official AWS documentation. The baseline is evidence of the last schema snapshot, not a fresh audit of production. Object counts, traffic, AWS account/region, current deployed clients and actual retention scheduling must be measured before implementation.

## 1. Scope and recommendation

Move all application-uploaded files from Supabase Storage to Amazon S3. Keep Supabase PostgreSQL, Auth, Realtime and existing business RPCs. S3 is object storage, not a replacement for transactional database records. Keep Flutter web hosting, its bundled MediaPipe model/WASM and other shipped app assets on Cloudflare; they are deployment artifacts, not uploads. Moving hosting, database backups or logs is a separate project.

Recommended design: a small authenticated storage API, S3 Standard, CloudFront for currently public media, and a provider-neutral metadata registry in PostgreSQL. Use adapters in Flutter and admin. Start with avatars/listing media, then chat, then sensitive documents and face evidence. Keep the Supabase adapter throughout coexistence and rollback.

This is a moderate-to-high effort migration. The difficult parts are authorization equivalence, immutable review evidence, legacy Android clients and existing URLs—not copying files.

A hard constraint: an installed app that directly calls Supabase Storage cannot be redirected to S3 by changing a server setting. Immediate total removal of Supabase Storage and uninterrupted support for those clients are incompatible. Preserve service while clients upgrade; retire the old storage path only after an explicit compatibility decision.

## 2. Behavior that must remain unchanged

- Account authentication, roles, suspension rules and admin privileges.
- Listing creation/editing, gallery ordering, cover images, image compression, avatar replacement and chat send/retry behavior.
- All five identity-document options; NID needs front/back, other options retain their present rules.
- Separate document and face statuses, evidence submission, manual review, mandatory admin approval, revocation and audit history.
- Booking and listing-publishing eligibility, payments, pricing, notifications and messaging authorization.
- Face attempt nonce, expiry, daily attempt limit, capture feature toggle, guided/manual distinction, size limits and evidence-version checks.
- Existing owners, document paths, verdicts, reviewer identities, timestamps and already-issued records.
- Public versus private access semantics, unless a separately approved security change explicitly revises them.

“No business logic change” does not mean “no SQL changes.” Storage-dependent SQL must use a new evidence lookup without weakening the existing validation or altering its state transitions. An upload finishing must never approve a person or submit a business record automatically.

## 3. Current storage inventory

Limits below come from `supabase/baseline/live_baseline.sql`; stricter workflow limits still apply.

| Logical bucket | Access today | Bucket limit | Uses and special constraints |
| --- | --- | --- | --- |
| `avatars` | Public reads | 2 MiB; JPEG/PNG/WebP | App/admin profile photos; stable `{userId}.{ext}` keys; replacement and cache busting |
| `listing-images` | Public reads | 5 MiB; JPEG/PNG/WebP | Listing galleries, cards and social previews; listing ID prefix |
| `chat-attachments` | Public reads | 10 MiB; listed image, PDF, Office and text types | Chat photos/files; conversation prefix; URLs stored in messages |
| `documents` | Owner/admin signed reads | 10 MiB; JPEG/PNG/WebP/PDF | Identity images, legacy selfies and address proofs. Current identity RPC restricts images to JPEG/PNG, 100 bytes–5 MiB; `/nid/` evidence cannot be updated/deleted by clients |
| `face-evidence` | Owner/admin signed reads | 8 MiB; JPEG/WebM/MP4 | Selfie 100 bytes–512 KiB, video 100 bytes–8 MiB; draft-attempt ownership/expiry; immutable capture objects |

Important existing behaviors:

- Chat attachment bytes are publicly accessible by URL even though messages have their own authorization. Making them participant-only is a valuable separate privacy improvement, but is not a behavior-preserving storage migration. Do not silently describe current chat files as private.
- Listing upload authorization calls `can_upload_listing_image()`: publishing eligibility **or an existing owned listing**. It is not simply a target-listing ownership check. Uploads can precede listing creation. Replacing this with “listing row must already exist” would break current flows.
- Chat storage insert currently requires authentication, not conversation membership. Preserve the current baseline in parity tests; flag stronger authorization as a separate decision rather than hiding it in the migration.
- Storage object owner fields drive some update/delete policies. Copying bytes as a migration service must not change logical ownership to that service.
- Public full URLs and private object paths coexist. Signed URLs must never become durable database identifiers.
- Admin upload code uses authorized server-side upload tickets and sends bytes directly from the browser, avoiding Next.js action body limits.

### Code and SQL touchpoints

| Area | Existing locations | Required migration work |
| --- | --- | --- |
| Shared Flutter uploads/downloads/deletes | `lib/services/image_upload_service.dart` | Preserve API/results/progress/compression; delegate storage transport |
| Identity and face uploads | `lib/services/verification/nid_verification_service.dart`, `face_verification_service.dart` | Add authorized upload/finalize operation; retain existing submit RPC calls |
| URL-to-key parsing | `lib/screens/host/edit_listing_screen.dart`, especially `_storagePathFromUrl` | Resolve both legacy URLs and new media references safely; preserve deletion behavior |
| Messaging | `lib/screens/messaging/chat_screen.dart`, messaging service/models | Preserve filename, size, MIME and URL shapes; cover previews and file opening |
| Admin uploads | `musafir-admin/src/lib/storage-actions.ts`, `src/components/image-upload.tsx`, `src/lib/images.ts` | Keep `requireAdmin`; replace signed-upload transport; preserve cleanup and cache behavior |
| Admin private readers | `verifications/page.tsx`, `verifications/faces/page.tsx`, `users/queries.ts` | Batch authorization and URL signing across both providers |
| Evidence SQL | `submit_face_verification`, `submit_identity_document`, `approve_identity_document`, NID compatibility wrappers | Replace direct `storage.objects` evidence reads with trusted provider-aware lookup |
| Retention | `orphan_face_evidence`, `record_face_evidence_deleted`, `supabase/functions/purge-face-evidence/index.ts` | Provider-aware enumeration/deletion, retry and audit synchronization |
| Social previews | `worker/index.js` | Keep absolute public image URLs functional for crawlers; no private URLs in preview tags |

Re-scan all repositories, functions, jobs, tests and actual deployed schema before implementation. Identify any additional upload callers or URL-bearing JSON fields; the table is the known migration surface, not a promise that no other dependency exists.

## 4. Target architecture

```mermaid
flowchart LR
  C[Flutter / Admin] -->|Supabase session JWT| API[Storage API]
  API -->|authorize using existing rules| DB[Supabase Auth / PostgreSQL]
  API -->|short-lived upload ticket| C
  C -->|direct upload| Q[S3 staging]
  API -->|verify and finalize exact version| S[S3 committed media]
  API -->|trusted storage metadata| DB
  C -->|existing submission RPC| DB
  CDN[CloudFront public media] --> S
  C --> CDN
  C -->|authorized short-lived private GET| S
```

Use separate production and staging resources. Prefer separate physical buckets for public media, private documents, face evidence and upload staging so their access/retention policies cannot be confused. Logical bucket names remain unchanged in adapters; public media can share a physical bucket with separate prefixes. All physical S3 buckets have Block Public Access enabled and ACLs disabled. “Public media” means anonymous CloudFront reads, not public S3 buckets.

Use a domain the project owns, such as `media.<owned-domain>`, for public media. If none is available, record that dependency before promising stable portable URLs. CloudFront uses origin access control; its public distribution must not have access to private buckets. Private files initially use S3 signed GETs after server authorization. CloudFront private delivery can be evaluated later if traffic warrants it.

### Storage API hosting choice

Recommended default: API Gateway + Lambda with an execution role for S3, short-lived AWS role credentials, and a narrowly scoped PostgreSQL integration. This adds infrastructure but avoids long-lived AWS access keys in an external runtime.

Lower-infrastructure alternative: Supabase Edge Functions authorize requests and sign S3 operations. It reuses current deployment tooling, but AWS credentials or supported federation need deliberate management. Do not pretend external runtimes automatically receive an AWS role. Decide once during the proof of concept; implement one backend, not both.

In either case, validate Supabase JWT signature, issuer, audience and expiry using the project's actual signing configuration. Support its real JWT/key rotation mechanism; do not assume JWKS works for legacy symmetric signing. An Auth-server validation path is acceptable. Check current database role/suspension/resource rules where existing behavior requires them, rather than trusting client-supplied roles. Pass caller identity through a constrained authorization operation; never use a service credential as a substitute for caller authorization.

## 5. Storage contract and trusted registry

Preserve existing business-facing method signatures where practical. A shared storage contract provides:

- `beginUpload(kind, logicalResource, filename, declaredSize, declaredType, idempotencyKey)`
- direct client upload using the returned form/headers
- `finalizeUpload(uploadId)` returning the existing success/path/public-URL result shape
- `getReadUrls(logicalReferences)` and `deleteObject(logicalReference)`

Clients may name an authorized logical resource, never an arbitrary physical bucket/key, AWS account, URL or object version. The backend derives storage keys and binds tickets to the caller and intended resource. Validate resource IDs without introducing new business prerequisites, such as requiring a draft listing to be saved before an image upload.

Proposed additive tables:

- `storage_upload_intents`: caller, logical bucket/path, staging key, expected MIME/size, idempotency key, expiry, finalization state.
- `storage_assets`: opaque asset ID, logical bucket/path, original owner, active generation, verified MIME/size/checksum, business-created time, retention deadline, deletion state.
- `storage_asset_locations`: asset/generation, provider, physical bucket/key, pinned version, copy checksum and verification state. Multiple verified locations support migration and rollback.
- `storage_operations`: durable copy/delete/outbox work, attempts, failure state and tombstones.

Authenticated clients cannot insert “verified” metadata, choose owners, or mutate provider locations. Use constrained backend-only operations and RLS/revoked grants. A caller cannot make an unuploaded file look real by inserting a database row.

Keep current private logical paths and RPC signatures. Introduce a storage-evidence lookup used by the existing RPCs: verified S3 metadata for migrated assets, existing Supabase metadata for legacy assets. Define precedence explicitly; never accept a conflicting legacy object merely because one exists. Do not insert synthetic S3 rows into Supabase's managed `storage.objects` schema.

## 6. Upload completion and evidence integrity

S3 and PostgreSQL have no shared transaction. Use an explicit state machine:

`authorized → uploaded to staging → verified → committed storage metadata → attached/submitted by existing business RPC`

Recommended initial upload mechanism: short-lived presigned POST to a unique staging key, with exact key/MIME conditions and `content-length-range`. Current files are at most 10 MiB, so multipart complexity is unnecessary initially. Maintain upload progress and cancellation on web/mobile. [AWS POST policy](https://docs.aws.amazon.com/AmazonS3/latest/developerguide/sigv4-HTTPPOSTConstructPolicy.html)

Finalization must:

1. Recheck intent, caller and relevant current authorization/attempt expiry.
2. Obtain object metadata independently from S3, pin the staging version, and verify actual size/checksum and supported content format. Client Content-Type is a claim, not evidence of bytes.
3. Promote that exact version to a backend-only immutable committed key; record the resulting physical version. Lock/idempotently claim the intent so concurrent finalizers cannot attach competing versions.
4. Commit trusted registry metadata only after the final object is confirmed. If the database commit fails, retry finalization without duplicating business submission. Reconcile abandoned committed objects later.
5. Return success to the existing caller, which then uses the existing document/face/message/listing workflow.

Presigned URLs are reusable until expiry; they are not single-use. A same-key upload can replace bytes. Unique staging versions and version-pinned promotion prevent a replay from changing submitted evidence. A direct-to-final PUT alternative needs correctly signed/enforced conditional writes and an independently proven size-control solution; do not assume POST policy conditions apply to PUT. [Presigned URL behavior](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html), [conditional writes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-writes.html)

Admin review URLs must resolve the exact immutable evidence generation/version that approval checks. Existing admin-only, no-self-review and stale-evidence protections remain. Malformed uploads must not become visible or count as submitted. Deep malware scanning for chat Office/PDF files can add delay/new rejection behavior: evaluate it as an explicit security enhancement, not a hidden migration rule.

## 7. Security controls

- Separate API signer, finalizer, migration, retention and deployment roles. Grant only required bucket prefixes/actions; end-user tickets never grant list/delete or private read access.
- HTTPS only. Encryption at rest on every bucket. Evaluate SSE-KMS for private evidence; record KMS request cost, permissions, recovery and key-disable failure scenarios before selecting it. Encryption does not replace access control.
- Preserve private signed-link TTLs per caller: current face queue uses 300 seconds; document readers have their own existing TTLs. Sign again after expiry. Immediate revocation of an already issued bearer URL is not guaranteed; do not promise it.
- Exact allowed web origins/methods/headers in CORS, including checksum/form headers and any conditional headers used. Test admin and Flutter origins. CORS is not authorization and does not protect against native clients.
- No AWS secrets in Dart, browser JavaScript, app config, logs or git. Do not log presigned URLs, bearer tokens, face bytes or document numbers. Use opaque request/asset IDs in logs.
- Preserve all current MIME/size restrictions; configure download headers so supported attachments cannot execute as HTML on the application origin. Never place untrusted uploads on the app's authenticated origin.
- Rate-limit ticket creation and concurrent uploads; bound staging lifetime and storage abuse. Tune operational limits against current valid workloads rather than inventing new verification quotas.
- Public CDN deletion must invalidate affected cached paths when current semantics require removal. Ensure private objects cannot enter a public origin/cache path, including through fallback logic.
- Object Lock is not the default: its deletion restrictions can conflict with face-evidence retention. Use denied overwrite/delete privileges, immutable generations and version-pinned reads instead.

## 8. Existing URLs and older app versions

Inventory `profiles.avatar_url`, listing image arrays, message attachment URLs, document paths, address-proof paths and any JSON-embedded references. Retain an exact before/after mapping and reference counts. Do not blindly replace all occurrences of a hostname in database text or fetch arbitrary external URLs during migration.

A resolver recognizes allowlisted legacy Supabase URL shapes and new media URLs, handles encoding/query parameters once, and returns a logical asset reference. External image URLs remain external. Private signed URLs are not copied as durable references. Update the listing deletion parser as well as image display.

Recommended compatibility sequence:

1. Publish storage-adapter-capable app/admin versions while Supabase remains authoritative.
2. Copy Supabase objects to S3 and reconcile new writes, replacements and deletions. New clients can read verified S3 replicas; old clients keep using Supabase.
3. Keep Supabase as the write authority while old clients remain active. This avoids silently splitting mutable avatar writes across two independent stores.
4. Before S3 becomes write-authoritative, demonstrate that supported active clients understand the new protocol. If old clients persist, extend coexistence. Requiring an upgrade/raising a minimum version is a separate rollout decision, not something this migration silently enables.
5. Cut over by logical bucket/cohort. Preserve legacy URLs and copies for the agreed overlap; then rewrite only verified stored public references with compare-and-swap updates and an undo map.

The project cannot redirect a Supabase-owned hostname using its own DNS. Historical messages/bookmarks/cached payloads with those URLs may require keeping a read-only Supabase copy longer. Document that unavoidable exception. “All storage now on S3” is not an honest completion claim while these dependencies remain.

Supabase read fallback is per-object and only for a verified same-generation replica. Never turn an authorization error or a deletion tombstone into a fallback read. Never accept arbitrary user-provided fallback URLs.

## 9. Data migration and concurrent changes

Preflight: export an object manifest through supported Storage APIs, bucket policies/limits, ownership metadata, reference snapshots, count/byte totals and business verdict fingerprints. Enumerate actual production jobs. Do not download sensitive user media to developer laptops for testing.

Use a restricted server-side migration job, streaming provider-to-provider without loading whole buckets into memory. Record per-object source identity, size, MIME, checksum, observed modification time, original business time and destination version. Verify bytes/checksum; ETag alone is not a universal content hash. Bound concurrency, retry with backoff, checkpoint every object and resume safely.

Copy only: no source deletion in the initial pass. Reconcile changes during copying, including deletes and mutable avatar replacement. For a changed source generation, repeat verification before marking its replica current. A tombstone wins over a delayed copy job. Counts alone are insufficient—verify references and generations as well.

Preserve original retention deadlines; migration time must not restart a 30-day clock. Use conditional database updates so an old manifest cannot overwrite a user's newer avatar or gallery edit. Unreferenced objects require investigation and the existing orphan policy, not automatic deletion simply because one scan found no reference.

## 10. Retention and deletion

The existing face cleanup code targets evidence older than 30 days and abandoned draft/superseded attempts after their expiry grace period, plus orphans. Its actual live scheduling has not been verified for this plan; earlier work left deployment/scheduling pending. Preserve that selection logic, document the current operational gap and test the provider-aware replacement before enabling it.

Use the existing business deadline as the authoritative clock. A durable deletion job marks the object unavailable, deletes every in-scope provider copy/version, retries failures, then records confirmed deletion using the existing audit mechanism. Do not set `media_deleted_at` while bytes remain retrievable. Pending deletions must not be resurrected by reconciliation or rollback.

Versioned S3 deletion often creates a delete marker; noncurrent versions remain unless separately removed. Enumerate/delete versions for sensitive evidence, including staging copies, replicas and any backups containing it. Lifecycle rules are asynchronous cleanup backstops, not an exact business deadline or proof of deletion. Avoid blanket lifecycle rules that remove pending/referenced documents or unexpectedly change historical retention. [AWS lifecycle semantics](https://docs.aws.amazon.com/AmazonS3/latest/userguide/intro-lifecycle-rules.html), [lifecycle timing](https://docs.aws.amazon.com/AmazonS3/latest/userguide/troubleshoot-lifecycle.html)

## 11. Availability and recovery

Use S3 Standard in one selected region initially; compare Bangladesh upload/download performance and Supabase/API round trips before choosing the region. Do not select an archival or single-AZ class for active verification media. Public CloudFront cache hits reduce origin load, but do not make the database, signer or private downloads independent of their dependencies.

S3 provides strong read-after-write consistency; remaining races are primarily application coordination, CDN caching and cross-provider replication, not a reason to add blind sleeps after upload. [AWS consistency model](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html#ConsistencyModel)

Proposed operational targets, to validate in staging rather than promise as an SLA:

- Upload/read-control API availability target: 99.9% monthly, excluding deliberate authorization rejections.
- A completed new upload means its selected provider bytes and registry metadata are confirmed. Pending upload intents must remain retryable after process failure.
- For control-plane failures, preserve retryable user state and show a clear error; never fall back to public private-file access.
- Reconcile migration/delete backlogs with age alarms; initial mirror-lag target under five minutes, measured under expected load.
- Rehearse reverting a read/write routing configuration within 30 minutes. A complete return to Supabase is conditional on reverse-copy verification and may take longer.

CloudFront cache policies must respect avatar version URLs or use unique immutable physical keys. Support video HTTP Range requests and seeking, signed URL expiry during playback, browser redirects, and mobile network changes. Test DNS, certificate, IAM/KMS denial, S3/API throttling and DB outage separately.

Cross-region replication is optional disaster recovery, not an initial prerequisite or instantaneous failover. It adds transfer/storage expense, asynchronous lag, credential/key management and deletion obligations. If adopted, define regional-outage RPO/RTO and test replica/deletion behavior explicitly.

## 12. Rollout stages and exit gates

| Stage | Deliverable | Exit gate |
| --- | --- | --- |
| 0: inventory | Fresh live schema/policies, object/reference counts, old-client usage, cost inputs | Complete known storage surface; business invariants signed off |
| 1: compatibility seam | Supabase-backed adapters, characterization tests, URL resolver | Existing provider behavior unchanged across app/admin |
| 2: AWS staging | Infrastructure as code, IAM, storage API, metadata registry | Cross-user/admin/anonymous access tests and failure injection pass |
| 3: migration rehearsal | Copy/reconcile jobs, deletion ledger, rollback procedure | Full fixture inventory reconciles; interrupted jobs resume without duplicates |
| 4: public media pilot | Avatars/listing reads, then chat; small eligible cohort | No broken old URLs, stale avatars, lost messages or unauthorized writes |
| 5: private media pilot | Documents/address proof, then face evidence | Exact evidence approved, immutable bytes, parity of all status/eligibility results |
| 6: S3 write cutover | Compatible client coverage, per-bucket routing, observation | Successful controlled uploads/reads/deletes; measured error/latency acceptable |
| 7: retirement | Legacy-client/URL closure and separately approved deletion | All retained objects/references accounted for; rollback window closed explicitly |

Deploy backward-compatible SQL expansion before new upload clients. Compare live definitions with the baseline and take snapshots; this repository's historical migration chain is not safely replayable from scratch. Use the project's baseline workflow and existing rolled-back SQL test pattern. Schema deployment and final destructive retirement need separate authorization during implementation; this document does not authorize them.

Use server-controlled per-bucket read/write routing with explicit generations. Do not ask clients to dual-upload as the only backup mechanism. Keep changes additive until retirement; no bulk deletion on a flag flip.

## 13. Rollback that actually works

Before S3 writes: disable S3 reads and return to the still-authoritative Supabase provider. Preserve copied objects for investigation.

After S3 writes: a feature flag alone is insufficient. Keep the dual-provider reader and metadata expansion deployed. Stop admitting new S3 upload intents; drain or explicitly expire existing tickets (presigned tickets cannot be assumed revoked instantly). Inventory S3-only generations, replay copy operations into Supabase through supported APIs, verify them, preserve original ownership/authorization, and reconcile tombstones. Then route compatible new writes back. Never restore pre-migration SQL while any submitted evidence exists only in S3.

If S3 is unavailable before an unmirrored object can be copied, that object cannot magically be served from Supabase. Document degraded access; do not claim zero-data-loss provider rollback for asynchronous mirrors. If immediate independent-provider recoverability becomes a requirement, require a confirmed second copy before reporting upload success and budget the latency/availability tradeoff explicitly.

Use field-level undo mappings for URL rewrites, not restoration of an old whole database snapshot that would discard new bookings/messages/approvals. Retain new business transactions and audit records during recovery.

## 14. Acceptance tests

Required before production cutover:

- Anonymous, owner, other user, admin and suspended-user matrix for every upload/read/update/delete category, compared with current policies and RPC outcomes.
- Upload-before-listing-save, existing-host eligibility, admin upload to another user's profile/listing, avatar extension replacement and cleanup.
- Every allowed MIME/size boundary, malformed file, expired token, substituted key, replay, duplicate finalization, interrupted upload and cancellation.
- Missing file, missing registry record, forged metadata, attempt expiry, stale evidence, self-review and cross-user review all remain denied.
- NID/passport/driving/student/office ID workflows; manual/guided face submission; existing approval, rejection and revocation behavior unchanged.
- Booking/publishing decisions and relevant profile/document/attempt audit fingerprints unchanged by migration itself.
- Chat send failure/retry, original filenames, PDF/Office downloads, image previews and existing public-link behavior.
- Listing display, editing/deletion and social previews for legacy URLs, new URLs and external images; preserve image order/cover.
- Signed-link expiry/renewal, video seeking, narrow/mobile UI, CORS, physical Android/iPhone and current web browsers.
- Upload succeeds but DB commit fails; DB commits but response is lost; deletion partially succeeds; copy races overwrite/delete; IAM/KMS denies access.
- Entire test inventory checksum/reference reconciliation, original-owner preservation, rollback after S3-only writes, no deleted-object resurrection.
- Release builds/tests in both repositories; rebuilt tracked Flutter web artifacts using `sh tool/build_web.sh`.

No real identity media is needed for automated tests; use fixtures. A reviewed small production canary should observe counts/errors without exporting private content.

## 15. Effort and cost

Planning estimate for one engineer familiar with both repositories, with AWS access available. These are engineering estimates, not a quote:

| Work | Engineer-days |
| --- | ---: |
| Inventory, authorization characterization, compatibility design | 2–3 |
| AWS infrastructure, storage API, registry, upload finalization | 4–6 |
| Flutter/admin adapters, URL compatibility, reader changes | 3–5 |
| SQL evidence abstraction and retention integration | 3–5 |
| Copy/reconciliation/rollback tooling | 3–4 |
| Integration, security, device tests and staged rollout work | 4–6 |
| Total | 19–29 |

Allow roughly 4–6 working weeks plus app-store review, observed client adoption and the agreed rollback window. Live inventory may expand this estimate. A public-images-only pilot is smaller but is not completion of “all storage.”

S3 is not guaranteed cheaper or free. Model stored GB-months, object requests, public/private download GB, CloudFront requests/egress, API/Lambda, KMS, logs, versions, replication, temporary staging and Supabase egress during copying. Coexistence temporarily pays for two copies/providers. Use measured traffic and selected-region prices; no defensible monthly amount is available yet. [AWS S3 pricing](https://aws.amazon.com/s3/pricing/)

Cost controls: budgets/alerts, bounded temporary storage, appropriate cache hit rates, clean abandoned multipart uploads if introduced, scoped data-event logging and lifecycle rules aligned with actual retention. Avoid architecture changes merely to claim a lower per-GB headline price.

## 16. Decisions needed before implementation

1. AWS account, budget owner, preferred region/data-location constraints and an owned media domain.
2. Confirmation that “all storage” means uploaded files; this plan keeps database/auth and Cloudflare app hosting.
3. Accepted legacy-client support window. With no forced upgrade, full Supabase retirement has no guaranteed date.
4. Storage API hosting choice and acceptable provider-outage recovery targets.
5. Whether to keep existing public chat attachment semantics for strict parity or approve a separate participant-only privacy change.
6. Actual retention requirements/scheduling and whether backup/replication copies may retain sensitive evidence at all.

These decisions do not block documenting the plan. Until answered, use the defaults above, keep existing behavior, and do not provision or migrate production resources.
