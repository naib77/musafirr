-- 068_identity_selfie_and_approval.sql
--
-- Identity verification now stores a face selfie alongside the ID document, and
-- the identity gate requires ADMIN APPROVAL (profiles.verification_status =
-- 'verified') instead of mere document presence.
--
-- The approval machinery already exists from earlier migrations:
--   * profiles.verification_status enum (none | pending | verified | rejected)
--   * owner_documents.verified_at / verified_by / rejection_reason
--   * RLS: admins_update_any_profile, owner_documents_admin_update / _select_own
--   * is_admin()
--
-- The only schema change required is allowing a third document slot, 'selfie',
-- on owner_documents. Everything else is wired up in the Flutter client.

alter table public.owner_documents
  drop constraint if exists owner_documents_document_type_check;

alter table public.owner_documents
  add constraint owner_documents_document_type_check
  check (document_type = any (array['nid_front'::text, 'nid_back'::text, 'selfie'::text]));
