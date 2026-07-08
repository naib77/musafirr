-- 061 — Stop leaking profile PII to every authenticated user (HIGH severity)
--
-- The live policy `profiles_select_public_info` was `to authenticated USING
-- (true)`, so any logged-in user could `select *` from profiles and harvest
-- every user's email, mobile, nid (national ID) and address_proof_path.
--
-- Fix:
--   * Base `profiles` table SELECT is restricted to the row owner (+ admins).
--   * A curated `public_profiles` VIEW exposes only non-sensitive, display
--     columns for all users. A view runs with its owner's privileges and so
--     bypasses the base-table RLS for exactly the columns it selects.
--   * App reads of OTHER users' profiles go through public_profiles; reads of
--     the caller's own full row and admin flows stay on `profiles`.

-- ---- admin check (SECURITY DEFINER avoids RLS recursion on profiles) --------
create or replace function public.is_admin(p_uid uuid default auth.uid())
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles where id = p_uid and role = 'admin'
  );
$$;
revoke execute on function public.is_admin(uuid) from public;
grant execute on function public.is_admin(uuid) to anon, authenticated;

-- ---- curated, non-sensitive projection of every profile --------------------
create or replace view public.public_profiles as
  select id, full_name, avatar_url, role, is_host, host_since, bio,
         response_rate, response_time, is_available, message_language,
         created_at
  from public.profiles;

grant select on public.public_profiles to anon, authenticated;

-- ---- lock the base table down to own-row (+ admin) -------------------------
drop policy if exists "profiles_select_public_info" on public.profiles;

alter policy "Users can view their own profile" on public.profiles
  using (auth.uid() = id or public.is_admin());
