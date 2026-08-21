-- 095_address_verification_by_visit.sql
--
-- Address verification becomes a real, admin-approved credential instead of
-- "a file exists". The flow:
--
--   1. Before publishing a listing, a host uploads a billed copy (utility bill
--      etc. — already stored as profiles.address_proof_path, migration 037)
--      AND declares the full address in writing.
--   2. That submission puts them in the admin queue: address_verification_status
--      = 'pending'. Publishing is NOT blocked — a physical visit takes days and
--      onboarding must not stall on it.
--   3. An admin visits the address in person and approves or rejects it from
--      the Musafir admin panel, recording what they found.
--   4. Only then does the "Address verified" badge appear on the listing page.
--
-- Reuses the existing `verification_status` enum (none|pending|verified|
-- rejected) rather than inventing a parallel one — the identity flow already
-- means exactly these four things by these four words.

-- ---------------------------------------------------------------------------
-- 1. The submission and the verdict
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists address_verification_status
      public.verification_status not null default 'none',
  -- The full address as the HOST declared it, in their own words. This is what
  -- the admin navigates to, so it is deliberately free text: a door a visitor
  -- can actually find beats a tidy set of columns that lost the detail.
  add column if not exists address_line text,
  add column if not exists address_submitted_at timestamptz,
  add column if not exists address_verified_at timestamptz,
  add column if not exists address_verified_by uuid references public.profiles(id),
  -- Shown to the host when they resubmit, so a rejection is actionable.
  add column if not exists address_rejection_reason text,
  -- What the admin actually found at the door. Internal — never exposed to
  -- guests or to the host; `public_profiles` carries only the boolean verdict.
  add column if not exists address_visit_notes text;

comment on column public.profiles.address_verification_status is
  'Admin-approved address credential. verified means a Musafir admin physically visited the declared address (095).';
comment on column public.profiles.address_line is
  'Full address as declared by the host, for the admin''s physical visit.';
comment on column public.profiles.address_visit_notes is
  'Admin-only record of what the visit found. Never exposed to guests or hosts.';

create index if not exists profiles_address_verification_status_idx
  on public.profiles (address_verification_status)
  where address_verification_status <> 'none';

-- Hosts who already uploaded a bill under the old "file is enough" rule have
-- genuinely submitted something, so they belong in the queue rather than being
-- silently dropped. They predate the declared-address field, so the admin sees
-- the document with no address to visit and can reject asking for one — the
-- listing gate will then collect it on their next publish.
update public.profiles
   set address_verification_status = 'pending',
       address_submitted_at = coalesce(address_submitted_at, updated_at, now())
 where address_proof_path is not null
   and address_verification_status = 'none';

-- ---------------------------------------------------------------------------
-- 2. Stop hosts awarding themselves the badge
-- ---------------------------------------------------------------------------
-- The own-row UPDATE policy on `profiles` ("Users can update their own
-- profile") has USING but NO WITH CHECK, so a signed-in user can write any
-- column of their own row through a hand-rolled PostgREST call. For a badge
-- whose entire meaning is "an admin stood at this door", that is fatal: one
-- request would mint it. The app client was narrowed back in the 061-era work,
-- but the database never enforced it. It does now.
--
-- Scope is deliberately the VERDICT columns only. `role`/`is_host` are left
-- alone here: the app legitimately writes them client-side when a tenant
-- becomes a host, and quietly changing that in a feature migration would break
-- hosting signup. That remains a separate, open finding.
create or replace function public.fn_guard_verification_verdicts()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  -- A NULL uid is a trusted server caller: service_role, an Edge Function, or
  -- a pg_cron job running as postgres with no JWT. (Lesson from migration 077:
  -- any auth.uid() guard that a cron job reaches must allow NULL.)
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;

  -- Awarding a verdict is admin-only, in both directions of the flow.
  if new.address_verification_status = 'verified'
     and old.address_verification_status is distinct from 'verified' then
    raise exception 'address verification is granted by an admin visit, not by the host'
      using errcode = '42501';
  end if;

  if new.verification_status = 'verified'
     and old.verification_status is distinct from 'verified' then
    raise exception 'identity verification is granted by an admin, not by the user'
      using errcode = '42501';
  end if;

  if new.nid_verified and not coalesce(old.nid_verified, false) then
    raise exception 'nid_verified is set by an admin, not by the user'
      using errcode = '42501';
  end if;

  -- The paper trail of a visit belongs to whoever made it.
  if new.address_verified_at is distinct from old.address_verified_at
     or new.address_verified_by is distinct from old.address_verified_by
     or new.address_visit_notes is distinct from old.address_visit_notes
     or new.address_rejection_reason is distinct from old.address_rejection_reason then
    raise exception 'address verification audit fields are admin-only'
      using errcode = '42501';
  end if;

  -- Everything else a host may do to their own row is untouched: uploading a
  -- bill, declaring an address, and moving their own submission to 'pending'
  -- (or back to 'none') are all still theirs.
  return new;
end;
$$;

drop trigger if exists trg_guard_verification_verdicts on public.profiles;
create trigger trg_guard_verification_verdicts
  before update on public.profiles
  for each row
  execute function public.fn_guard_verification_verdicts();

-- ---------------------------------------------------------------------------
-- 3. Submitting, and the verdict, as RPCs
-- ---------------------------------------------------------------------------

-- The host's own submission: declare the address, enter the queue. Stamps
-- submitted_at server-side and clears any previous rejection so a resubmission
-- reads clean. Requires the bill to already be on file — the two halves of the
-- submission are meaningless apart.
create or replace function public.submit_address_verification(p_address_line text)
returns void
language plpgsql
security invoker
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if coalesce(btrim(p_address_line), '') = '' then
    raise exception 'a full address is required' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.profiles
     where id = v_uid and address_proof_path is not null
  ) then
    raise exception 'upload a proof-of-address document first'
      using errcode = '22023';
  end if;

  update public.profiles
     set address_line = btrim(p_address_line),
         address_verification_status = 'pending',
         address_submitted_at = now()
   where id = v_uid;
end;
$$;

revoke execute on function public.submit_address_verification(text) from public, anon;
grant execute on function public.submit_address_verification(text) to authenticated;

-- The admin's verdict after the visit. SECURITY DEFINER so it can write the
-- guarded columns, with its own is_admin() gate — the trigger above would
-- otherwise reject the very write this exists to make.
create or replace function public.set_address_verification(
  p_user_id uuid,
  p_status public.verification_status,
  p_visit_notes text default null,
  p_rejection_reason text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_admin uuid := auth.uid();
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  if p_status not in ('pending', 'verified', 'rejected') then
    raise exception 'status must be pending, verified or rejected'
      using errcode = '22023';
  end if;
  if p_status = 'rejected'
     and coalesce(btrim(p_rejection_reason), '') = '' then
    raise exception 'a rejection reason is required' using errcode = '22023';
  end if;

  update public.profiles
     set address_verification_status = p_status,
         -- Stamped only on approval; cleared otherwise, so verified_at can
         -- never outlive the verdict it belongs to.
         address_verified_at = case when p_status = 'verified' then now() end,
         address_verified_by = case when p_status = 'verified' then v_admin end,
         address_visit_notes = coalesce(btrim(p_visit_notes), address_visit_notes),
         address_rejection_reason =
           case when p_status = 'rejected' then btrim(p_rejection_reason) end
   where id = p_user_id;

  if not found then
    raise exception 'no such profile' using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function public.set_address_verification(uuid, public.verification_status, text, text)
  from public, anon;
grant execute on function public.set_address_verification(uuid, public.verification_status, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. The badge now means the visit happened
-- ---------------------------------------------------------------------------
-- Same column list and order as 094 — only the address_verified expression
-- changes, from "a file exists" to "an admin approved it". Every other
-- consumer (search_listings selects pp.avatar_url by name) is unaffected.
create or replace view public.public_profiles as
  select id, full_name, avatar_url, role, is_host, host_since, bio,
         response_rate, response_time, is_available, message_language,
         created_at,
         coalesce(phone_verified, false) as phone_verified,
         (verification_status = 'verified') as identity_verified,
         -- Was `address_proof_path is not null` (094). A document on file is a
         -- claim; a visit is a verification.
         (address_verification_status = 'verified') as address_verified
  from public.profiles;

grant select on public.public_profiles to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Audit the verdict
-- ---------------------------------------------------------------------------
-- A physical visit is a human judgement with no artefact of its own, so the
-- audit row is the only durable record of who approved which door and when.
-- Mirrors trg_audit_owner_documents_upd's 'verification' category (089).
drop trigger if exists trg_audit_profiles_address_verification on public.profiles;
create trigger trg_audit_profiles_address_verification
  after update on public.profiles
  for each row
  when (old.address_verification_status is distinct from new.address_verification_status
        or old.address_verified_by is distinct from new.address_verified_by)
  execute function public.fn_audit('verification');
