-- Schema changes for image uploads and owner verification

-- 1. Add image_urls array to listings table
ALTER TABLE public.listings
ADD COLUMN IF NOT EXISTS image_urls TEXT[] DEFAULT '{}';

-- 2. Create verification status enum
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'verification_status') THEN
    CREATE TYPE public.verification_status AS ENUM ('none', 'pending', 'verified', 'rejected');
  END IF;
END$$;

-- 3. Add verification_status to profiles table
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS verification_status public.verification_status DEFAULT 'none';

-- 4. Create owner_documents table for NID and other verification documents
CREATE TABLE IF NOT EXISTS public.owner_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  document_type TEXT NOT NULL CHECK (document_type IN ('nid_front', 'nid_back')),
  file_path TEXT NOT NULL,
  file_name TEXT,
  file_size INTEGER,
  mime_type TEXT,
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  verified_at TIMESTAMPTZ,
  verified_by UUID REFERENCES public.profiles(id),
  rejection_reason TEXT,
  UNIQUE(user_id, document_type)
);

-- 5. Indexes for owner_documents
CREATE INDEX IF NOT EXISTS owner_documents_user_id_idx ON public.owner_documents(user_id);
CREATE INDEX IF NOT EXISTS owner_documents_verified_at_idx ON public.owner_documents(verified_at) WHERE verified_at IS NULL;

-- 6. RLS for owner_documents
ALTER TABLE public.owner_documents ENABLE ROW LEVEL SECURITY;

-- Users can view their own documents
CREATE POLICY "owner_documents_select_own"
ON public.owner_documents FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  )
);

-- Users can insert their own documents
CREATE POLICY "owner_documents_insert_own"
ON public.owner_documents FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- Users can update their own documents (before verification)
CREATE POLICY "owner_documents_update_own"
ON public.owner_documents FOR UPDATE
TO authenticated
USING (
  user_id = auth.uid() AND verified_at IS NULL
)
WITH CHECK (
  user_id = auth.uid() AND verified_at IS NULL
);

-- Users can delete their own documents (before verification)
CREATE POLICY "owner_documents_delete_own"
ON public.owner_documents FOR DELETE
TO authenticated
USING (
  user_id = auth.uid() AND verified_at IS NULL
);

-- Admins can update any document (for verification)
CREATE POLICY "owner_documents_admin_update"
ON public.owner_documents FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  )
);

-- 7. Function to update profile verification status when documents are verified
CREATE OR REPLACE FUNCTION public.update_profile_verification_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Check if both NID documents are verified
  IF NEW.verified_at IS NOT NULL THEN
    -- Check if both front and back are now verified
    IF EXISTS (
      SELECT 1 FROM public.owner_documents
      WHERE user_id = NEW.user_id
        AND document_type = 'nid_front'
        AND verified_at IS NOT NULL
    ) AND EXISTS (
      SELECT 1 FROM public.owner_documents
      WHERE user_id = NEW.user_id
        AND document_type = 'nid_back'
        AND verified_at IS NOT NULL
    ) THEN
      UPDATE public.profiles
      SET verification_status = 'verified'
      WHERE id = NEW.user_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger to auto-update verification status
DROP TRIGGER IF EXISTS on_document_verified ON public.owner_documents;
CREATE TRIGGER on_document_verified
AFTER UPDATE OF verified_at ON public.owner_documents
FOR EACH ROW
WHEN (NEW.verified_at IS NOT NULL AND OLD.verified_at IS NULL)
EXECUTE FUNCTION public.update_profile_verification_status();

-- 8. Function to set profile to pending when documents are uploaded
CREATE OR REPLACE FUNCTION public.set_verification_pending()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Set profile to pending if both documents exist
  IF EXISTS (
    SELECT 1 FROM public.owner_documents
    WHERE user_id = NEW.user_id
      AND document_type = 'nid_front'
  ) AND EXISTS (
    SELECT 1 FROM public.owner_documents
    WHERE user_id = NEW.user_id
      AND document_type = 'nid_back'
  ) THEN
    UPDATE public.profiles
    SET verification_status = 'pending'
    WHERE id = NEW.user_id AND verification_status = 'none';
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger to set pending status when documents uploaded
DROP TRIGGER IF EXISTS on_document_uploaded ON public.owner_documents;
CREATE TRIGGER on_document_uploaded
AFTER INSERT ON public.owner_documents
FOR EACH ROW
EXECUTE FUNCTION public.set_verification_pending();

-- Summary:
-- - listings.image_urls: TEXT[] for multiple image URLs
-- - profiles.verification_status: 'none' | 'pending' | 'verified' | 'rejected'
-- - owner_documents: stores NID front/back with verification tracking
-- - Auto-triggers update verification_status when documents are verified
