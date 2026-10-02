# Musafir docs

Start with [ONBOARDING.md](ONBOARDING.md). The repo-root `CLAUDE.md` holds the
rules that have been broken before; [notes/](notes/) holds the reasoning behind
each one. Domain vocabulary is in `../CONTEXT.md`.

Where a doc and the live database disagree, the database wins — see
`CLAUDE.md` → Supabase.

| Folder | What lives there |
| --- | --- |
| [architecture/](architecture/) | How the app is put together: [architecture](architecture/architecture.md), [guest search flow](architecture/guest-search-flow.md). |
| [schema/](schema/) | [live_schema.sql](schema/live_schema.sql) — a snapshot of the live database, written by `scripts/dump_live_schema.py`. [backend-schema](schema/backend-schema.md) and [supabase_schema.sql](schema/supabase_schema.sql) are older (May 2026) and predate most migrations. |
| [features/](features/) | One reference per feature: [audit log](features/audit-log.md), [bulk notifications](features/bulk-notifications.md), [bulk SMS](features/bulk-sms.md), [coupons](features/coupons.md), [device sessions](features/device-sessions.md), [face verification](features/face-verification.md) (+ [plan](features/face-verification-plan.md)), [safety](features/safety.md), [SSLCommerz payments](features/sslcommerz.md), [voice search](features/voice-search.md), [web push](features/web-push-setup.md). |
| [release/](release/) | Shipping: [Google Play](release/play-store-release.md), [web deployment](release/web-deployment.md). The web guide predates `tool/build_web.sh` — follow `CLAUDE.md` where they differ. |
| [plans/](plans/) | Roadmaps and proposals, some done, some not: [feature roadmap v2](plans/feature-roadmap-v2.md), [first MVP](plans/firstmvp-plan.md), [booking notifications PRD](plans/prd-booking-notifications.md), [S3 storage migration](plans/aws-s3-storage-migration.md). |
| [qa/](qa/) | [QA plan](qa/qa-plan.md), [payment test plan](qa/payment-test-plan.md), and dated reports and fix logs from each round. |
| [notes/](notes/) | The why behind each `CLAUDE.md` rule. Read before changing that area. |
| [legal/](legal/) | Markdown sources of the legal pages. |
