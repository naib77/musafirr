-- 067 — Server-side phone OTP auth support (CRITICAL auth-bypass fix)
--
-- Background: sign-in used a password derived deterministically from the phone
-- number (_phoneToPassword), so anyone who knew a phone number could sign in
-- without an OTP. OTP generation + verification are moving fully server-side
-- into the send-otp / verify-otp Edge Functions, which mint the session via
-- Supabase's admin generateLink (a single-use magic-link token_hash the client
-- exchanges for a real session). No guessable credential remains.
--
-- This migration adds the two pieces the Edge Functions need:
--   1. profiles.signup_completed — an explicit "finished the profile step" flag,
--      so verify-otp can tell a returning user from a brand-new one. (The
--      on_auth_user_created trigger always inserts a bare profile, so mere
--      profile existence can't distinguish them.)
--   2. get_auth_user_id_by_email() — lets the service-role function resolve
--      whether an auth user already exists for a phone-derived email, without
--      exposing the auth schema.

alter table public.profiles
  add column if not exists signup_completed boolean not null default false;

-- Backfill: anyone who already has a real name has finished signup, so they are
-- not bounced back through profile completion after this change ships.
update public.profiles
  set signup_completed = true
  where full_name is not null
    and full_name <> 'New User';

comment on column public.profiles.signup_completed is
  'True once the user finished the phone-signup profile step (verify-otp uses '
  'this to route returning vs new users). Bare trigger-created rows stay false.';

-- Resolve an auth user id by email (email is our internal phone-derived id:
-- phone.<normalized>@musafir.app). SECURITY DEFINER so the service-role Edge
-- Function can check existence without touching the auth schema directly.
create or replace function public.get_auth_user_id_by_email(p_email text)
returns uuid
language sql
security definer
set search_path = public
as $$
  select id from auth.users where email = p_email limit 1;
$$;

-- Only the backend (service_role / postgres) may call this; never clients.
revoke execute on function public.get_auth_user_id_by_email(text)
  from public, anon, authenticated;
grant execute on function public.get_auth_user_id_by_email(text) to service_role;
