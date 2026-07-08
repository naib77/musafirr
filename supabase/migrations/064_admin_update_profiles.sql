-- 064 — Allow admins to update any profile (verification review flow)
--
-- Migration 061 tightened profiles so users can only update their OWN row. But
-- the admin verification screen sets other users' verification_status (approve/
-- reject), which that own-row policy blocks. Add an admin-only UPDATE policy so
-- the verification flow works. Regular users remain restricted to their own row
-- (permissive policies are OR'd). Uses the SECURITY DEFINER is_admin() helper
-- from 061 to avoid RLS recursion on profiles.

drop policy if exists "admins_update_any_profile" on public.profiles;

create policy "admins_update_any_profile"
on public.profiles
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());
