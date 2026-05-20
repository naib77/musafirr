-- Migration: Fix missing INSERT policy on profiles table
-- This fixes the RLS error: "new row violates row-level security policy for table profiles"
--
-- The issue: completePhoneSignup does an upsert to profiles, but there was no INSERT policy.
-- The handle_new_user trigger creates the profile via SECURITY DEFINER, but the subsequent
-- client-side upsert needs INSERT permission for the "ON CONFLICT DO UPDATE" to work.

-- Add INSERT policy for profiles - users can only insert their own profile
CREATE POLICY "profiles_insert_self"
ON public.profiles
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

-- Also ensure the upsert can work by allowing users to insert even if they're creating
-- their own profile for the first time (this handles edge cases where trigger fails)
COMMENT ON POLICY "profiles_insert_self" ON public.profiles IS
  'Allows authenticated users to insert their own profile row (id must match auth.uid())';
