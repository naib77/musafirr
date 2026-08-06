-- 083 — Allow webp avatars.
--
-- The app compresses avatars to webp (ImageCompressionService, CompressFormat.webp)
-- but the avatars bucket only allowed image/jpeg + image/png, so every avatar
-- upload failed with "mime type image/webp is not supported". webp is already
-- allowed on listing-images; align avatars with it (keep jpeg/png for the
-- image-package JPEG fallback path).
update storage.buckets
set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
where id = 'avatars';
