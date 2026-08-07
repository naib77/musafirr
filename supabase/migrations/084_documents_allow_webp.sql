-- 084 — Allow webp in the documents (identity verification) bucket.
--
-- Verification uploads (selfie, NID front/back) deliberately skip compression
-- to preserve fidelity, so the file keeps its original format. A user picking
-- a webp image from their gallery therefore uploads image/webp — which the
-- bucket rejected with "mime type image/webp is not supported" (same failure
-- avatars had before 083). Align with avatars/listing-images; keep pdf for
-- document scans.
update storage.buckets
set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
where id = 'documents';
