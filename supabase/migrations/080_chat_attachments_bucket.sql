-- Migration 080: storage bucket for chat image/file attachments.
--
-- Chat previously had no bucket for shared media (only listing-images, avatars,
-- documents existed), so the image/file buttons were stubbed. This adds a
-- dedicated public bucket, mirroring the existing listing-images/avatars posture
-- (public read + authenticated write). Paths use unguessable UUIDs.
--
-- NOTE ON PRIVACY: this is a PUBLIC bucket, consistent with the app's other
-- user-content buckets — anyone with the (unguessable) URL can fetch the file.
-- If chat attachments must be strictly participant-only, switch to a private
-- bucket + a participant-scoped read policy + signed URLs on render.

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('chat-attachments', 'chat-attachments', true, 10485760)  -- 10 MB
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS chat_attachments_authenticated_insert ON storage.objects;
CREATE POLICY chat_attachments_authenticated_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'chat-attachments');

DROP POLICY IF EXISTS chat_attachments_public_read ON storage.objects;
CREATE POLICY chat_attachments_public_read ON storage.objects
    FOR SELECT TO public
    USING (bucket_id = 'chat-attachments');

DROP POLICY IF EXISTS chat_attachments_owner_delete ON storage.objects;
CREATE POLICY chat_attachments_owner_delete ON storage.objects
    FOR DELETE TO authenticated
    USING (bucket_id = 'chat-attachments' AND owner = auth.uid());
