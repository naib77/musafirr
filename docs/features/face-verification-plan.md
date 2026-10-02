# Identity documents and live face review with mandatory admin approval

Updated: 2026-09-27. The user requires the full previous identity-document choice plus live face review. NID must not be the only option. This supersedes both the face-only and NID-only scopes.

## User flow

Profile → Settings → **ID & face verification** opens a two-step checklist:

1. **Identity document:** choose NID, passport, driving license, student/admission/exam ID, or office/employee ID; enter the document number and upload clear JPG/PNG images. NID requires both sides; other documents require a front/photo page with an optional back. Consent to private admin review, then submit. Rejected or revoked submissions can be uploaded again. A failed upload or database write never claims submission succeeded.
2. **Live face check:** consent, blink and turn in the server-issued order, then submit the short recording and selfie. The existing accessible manual exception remains explicit to the reviewer.

Both steps display independent statuses. A pending NID does not hide the face step, and Document approval never counts as face approval. An admin must approve both before booking or publishing. Revoking Document approval blocks eligibility even when face approval remains valid. Historical Document approvals remain on record but do not substitute for a new face approval.

## Admin flow

All document types use the existing Verifications queue. Only NID requires both front and back for approval. Approval checks the exact paths the reviewer saw, stamps both documents, and updates the NID verdict atomically. Rejected cases can be moved back to pending for re-review, or the user can upload again. Face evidence remains in the separate Face reviews queue with explicit admin decisions.

## Privacy and costs

NID images remain in the private documents bucket; new NID evidence cannot be overwritten by a client during review. Face evidence remains private and follows the existing retention plan. No paid verification service or government database lookup is used. Document review is manual, not authoritative validation of an NID number. Hosting, storage, bandwidth and admin labor still consume resources.

## Rollout status

Migrations 141 and **142_nid_and_face_review.sql** are live in `bojkmonskqlhuakxhzcb`, applied with explicit user approval on 2026-09-27. Face capture remains disabled. The combined Flutter/admin changes still require deployment. The local baseline is regenerated from live after 142.

Migration 142 now requires existing NID-approved users to complete face review before new bookings or listing publication. All 37 document records and 13 existing Document approvals were preserved. Because face capture is still disabled, NID-only accounts cannot yet complete this requirement. App/admin deployment, face assets, retention scheduling and the consented physical-device pilot remain necessary before enabling captures.

See [implementation notes](face-verification.md) for the original capture implementation and remaining deployment checks.

## Restoration follow-up (live, migration 143)

Migration 143 restores all five historical document types and optional backs for non-NID submissions. Existing rows are not changed by this migration. New submissions preserve the selected type and number; a replacement with no back clears only the old current back slot so it cannot be mistaken for part of the new document. Historical storage files are not deleted. Admin approval checks both type and paths. Existing NID RPC signatures remain compatible. The legacy `nid_front`/`nid_back` slots and `nid_verified` flag continue to represent the selected identity document, matching the original application.

Migration 143 was deployed to live project `bojkmonskqlhuakxhzcb` with explicit user approval on 2026-09-27. All 37 document records, saved document types/numbers and 13 existing approvals were unchanged. The updated Flutter/admin builds still need deployment. Live face capture remains disabled.
