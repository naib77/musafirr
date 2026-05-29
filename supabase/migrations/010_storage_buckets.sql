-- Storage buckets for file uploads
-- Run this migration in Supabase dashboard or via CLI

-- 1. Create storage buckets
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('listing-images', 'listing-images', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp']),
  ('avatars', 'avatars', true, 2097152, ARRAY['image/jpeg', 'image/png']),
  ('documents', 'documents', false, 10485760, ARRAY['image/jpeg', 'image/png', 'application/pdf'])
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 2. Storage policies for listing-images bucket (public read, owner write)

-- Anyone can view listing images
CREATE POLICY "listing_images_public_read"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'listing-images');

-- Authenticated users can upload to their own listing folder
CREATE POLICY "listing_images_owner_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'listing-images'
  AND (storage.foldername(name))[1] IN (
    SELECT id::text FROM public.listings WHERE owner_id = auth.uid()
  )
);

-- Owners can update their own listing images
CREATE POLICY "listing_images_owner_update"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'listing-images'
  AND (storage.foldername(name))[1] IN (
    SELECT id::text FROM public.listings WHERE owner_id = auth.uid()
  )
);

-- Owners can delete their own listing images
CREATE POLICY "listing_images_owner_delete"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'listing-images'
  AND (storage.foldername(name))[1] IN (
    SELECT id::text FROM public.listings WHERE owner_id = auth.uid()
  )
);

-- 3. Storage policies for avatars bucket (public read, owner write)

-- Anyone can view avatars
CREATE POLICY "avatars_public_read"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'avatars');

-- Users can upload their own avatar (file named as user_id)
CREATE POLICY "avatars_owner_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'avatars'
  AND (storage.filename(name) LIKE auth.uid()::text || '.%')
);

-- Users can update their own avatar
CREATE POLICY "avatars_owner_update"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.filename(name) LIKE auth.uid()::text || '.%')
);

-- Users can delete their own avatar
CREATE POLICY "avatars_owner_delete"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.filename(name) LIKE auth.uid()::text || '.%')
);

-- 4. Storage policies for documents bucket (private - owner + admin only)

-- Users can view their own documents, admins can view all
CREATE POLICY "documents_owner_or_admin_read"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'documents'
  AND (
    -- Owner can view their own documents
    (storage.foldername(name))[1] = auth.uid()::text
    -- Admin can view all documents
    OR EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  )
);

-- Users can upload to their own folder
CREATE POLICY "documents_owner_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'documents'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Users can update their own documents
CREATE POLICY "documents_owner_update"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'documents'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Users can delete their own documents
CREATE POLICY "documents_owner_delete"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'documents'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Summary:
-- listing-images: 5MB max, JPEG/PNG/WebP, public read, owner write
-- avatars: 2MB max, JPEG/PNG, public read, owner write
-- documents: 10MB max, JPEG/PNG/PDF, private (owner + admin read)
