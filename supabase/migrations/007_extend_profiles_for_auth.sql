-- Migration: Extend profiles table for auth service
-- This migration adds additional profile fields needed for the auth service:
-- - NID verification
-- - Phone verification
-- - Registration method tracking
-- - Host status and details

-- Add NID and verification fields
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS nid TEXT,
ADD COLUMN IF NOT EXISTS nid_verified BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS phone_verified BOOLEAN DEFAULT FALSE;

-- Add registration method tracking
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS registration_method TEXT DEFAULT 'phone';

-- Add host-related fields
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS is_host BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS host_since TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS bio TEXT,
ADD COLUMN IF NOT EXISTS response_rate INTEGER,
ADD COLUMN IF NOT EXISTS response_time TEXT;

-- Add constraints for new fields
ALTER TABLE public.profiles
ADD CONSTRAINT response_rate_range CHECK (response_rate IS NULL OR (response_rate >= 0 AND response_rate <= 100));

-- Update the handle_new_user trigger to include new fields
-- Uses a unique mobile suffix to avoid UNIQUE constraint violations
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mobile TEXT;
BEGIN
  -- Get mobile from metadata, phone, or generate a unique placeholder
  v_mobile := COALESCE(
    new.raw_user_meta_data ->> 'mobile',
    new.phone,
    'pending_' || new.id::text  -- Unique placeholder using user ID
  );

  INSERT INTO public.profiles (
    id,
    role,
    full_name,
    mobile,
    registration_method,
    phone_verified,
    nid,
    nid_verified
  )
  VALUES (
    new.id,
    COALESCE((new.raw_user_meta_data ->> 'role')::public.app_role, 'tenant'),
    COALESCE(new.raw_user_meta_data ->> 'full_name', 'New User'),
    v_mobile,
    COALESCE(new.raw_user_meta_data ->> 'registration_method', 'phone'),
    CASE WHEN new.phone IS NOT NULL OR new.raw_user_meta_data ->> 'mobile' IS NOT NULL THEN TRUE ELSE FALSE END,
    new.raw_user_meta_data ->> 'nid',
    COALESCE((new.raw_user_meta_data ->> 'nid_verified')::boolean, FALSE)
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(EXCLUDED.full_name, profiles.full_name),
    mobile = COALESCE(EXCLUDED.mobile, profiles.mobile),
    updated_at = timezone('utc', now());
  RETURN new;
END;
$$;

-- Create index for host queries
CREATE INDEX IF NOT EXISTS profiles_is_host_idx ON public.profiles (is_host) WHERE is_host = TRUE;

-- Allow profiles to be read by authenticated users (for looking up other users)
-- This enables the app to display host information on listings
DROP POLICY IF EXISTS "profiles_select_public_info" ON public.profiles;
CREATE POLICY "profiles_select_public_info"
ON public.profiles
FOR SELECT
TO authenticated
USING (TRUE);

-- Comment on new columns
COMMENT ON COLUMN public.profiles.nid IS 'National ID number for identity verification';
COMMENT ON COLUMN public.profiles.nid_verified IS 'Whether the NID has been verified';
COMMENT ON COLUMN public.profiles.phone_verified IS 'Whether the phone number has been verified via OTP';
COMMENT ON COLUMN public.profiles.registration_method IS 'How the user registered: email or phone';
COMMENT ON COLUMN public.profiles.is_host IS 'Whether the user is a property host';
COMMENT ON COLUMN public.profiles.host_since IS 'Date when user became a host';
COMMENT ON COLUMN public.profiles.bio IS 'User bio/description';
COMMENT ON COLUMN public.profiles.response_rate IS 'Host response rate percentage (0-100)';
COMMENT ON COLUMN public.profiles.response_time IS 'Typical response time description';
