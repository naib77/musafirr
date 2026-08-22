-- 094_public_profile_verification_flags.sql
--
-- The listing page's "Hosted by …" card shows trust badges. Until now those
-- three badges were hard-coded in the Flutter client: every host appeared to
-- have a verified phone, email and identity regardless of what the database
-- said. That is a trust claim we can't back, so the badges have to come from
-- real per-host data.
--
-- The flags live on `public.profiles`, which guests cannot read: migration 061
-- locked the base table down to own-row (+ admin) and pointed cross-user reads
-- at the curated `public_profiles` view. So the view is where these belong.
--
-- What is exposed is three BOOLEANS, and deliberately nothing more — not the
-- NID number, not the document storage paths, not the pending/rejected detail
-- of `verification_status`. A guest learns "this host's identity was checked",
-- never anything about the document that proved it.
--
-- Columns are appended at the END of the select list so `create or replace
-- view` accepts it (Postgres allows added trailing columns, not reordered or
-- retyped ones) and so `search_listings` — which selects `pp.avatar_url` by
-- name, never `to_jsonb(pp)` — keeps working untouched and keeps leaking
-- nothing new into search results.

create or replace view public.public_profiles as
  select id, full_name, avatar_url, role, is_host, host_since, bio,
         response_rate, response_time, is_available, message_language,
         created_at,
         -- Phone OTP at sign-up. Already a plain boolean on the profile.
         coalesce(phone_verified, false) as phone_verified,
         -- Identity: ADMIN-APPROVED only. 'pending' and 'rejected' are both a
         -- no — a submitted document is not a verified one (see 068).
         (verification_status = 'verified') as identity_verified,
         -- Address: the host uploaded a proof-of-address document (utility
         -- bill etc.) into the `documents` bucket (see 037). There is no
         -- separate admin approval step for this one, so presence of the file
         -- is the strongest claim we can make. If an approval flow is added
         -- later, tighten this expression and the badge follows.
         (address_proof_path is not null) as address_verified
  from public.profiles;

grant select on public.public_profiles to anon, authenticated;

comment on view public.public_profiles is
  'Non-sensitive projection of profiles for cross-user reads (061). Carries '
  'the three host trust flags shown on the listing page: phone_verified, '
  'identity_verified (admin-approved identity), address_verified (proof-of-'
  'address on file). Booleans only — no NID, no document paths.';
