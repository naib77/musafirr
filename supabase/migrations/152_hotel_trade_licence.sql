-- 152_hotel_trade_licence.sql
--
-- An OPTIONAL trade licence for a hotel listing. The plan (docs/plans/hotel.md)
-- first had it gate PublishGate; the owner chose optional instead: many small
-- Bangladeshi guest houses trade without one, and a hotel that cannot list is
-- a hotel that lists as a "room" with worse facts. So this is 095's shape, not
-- a gate:
--
--   1. The host uploads a photo/PDF of the licence (private `documents`
--      bucket) and, optionally, its number. The listing is already live or
--      not, independently.
--   2. That puts the listing in the admin queue: status 'pending'.
--   3. An admin approves or rejects it (with a reason the host sees).
--   4. Only then does `listing_licence_verified` answer true and the guest-
--      facing "Licensed hotel" badge appear.
--
-- Per listing, not per profile: the licence names one premises, and a host
-- with two hotels has two. A table of its own, not columns on `listings`,
-- because `listings` is owner-updatable and every verdict column there would
-- need a trigger guard (the lesson of 095/133); here the table has no write
-- policy at all and the only ways in are the three functions below.
--
-- Reuses `verification_status` (none|pending|verified|rejected). A row exists
-- only once something was submitted, so 'none' never appears in it.
--
-- Also (end of file): listing_units narrows to label-only writes, for the
-- room-naming UI that ships with this.

begin;

create table if not exists public.listing_trade_licences (
  listing_id        uuid primary key references public.listings(id) on delete cascade,
  owner_id          uuid not null references public.profiles(id) on delete cascade,
  document_path     text not null,
  licence_number    text,
  status            public.verification_status not null default 'pending',
  submitted_at      timestamptz not null default now(),
  reviewed_at       timestamptz,
  reviewed_by       uuid references public.profiles(id),
  -- Shown to the host so a rejection is actionable; never to guests.
  rejection_reason  text,
  constraint listing_trade_licences_number_len
    check (licence_number is null or char_length(licence_number) between 1 and 60),
  constraint listing_trade_licences_status_submitted
    check (status <> 'none')
);

comment on table public.listing_trade_licences is
  'Optional hotel trade licence, one per listing (152). Never gates publishing; verified only by an admin. Written only through submit_/review_trade_licence.';

create index if not exists listing_trade_licences_pending_idx
  on public.listing_trade_licences (submitted_at) where status = 'pending';

alter table public.listing_trade_licences enable row level security;

-- Reads: the owner sees their own (status + rejection reason), an admin sees
-- the queue. No INSERT/UPDATE/DELETE policy: writes go through the definer
-- functions, so a host cannot write status = 'verified' with a hand-rolled
-- PostgREST call (default privileges grant the DML; RLS is what refuses it).
drop policy if exists listing_trade_licences_owner_select on public.listing_trade_licences;
create policy listing_trade_licences_owner_select on public.listing_trade_licences
  for select to authenticated
  using (owner_id = auth.uid() or public.is_admin());

revoke insert, update, delete on public.listing_trade_licences from anon, authenticated;
revoke all on public.listing_trade_licences from anon;

-- ---------------------------------------------------------------------------
-- Submitting (host)
-- ---------------------------------------------------------------------------
-- Re-submitting replaces the document and goes back to 'pending' — including
-- from 'verified': a new document is a new claim, and the badge must not
-- vouch for a file no admin has seen.
create or replace function public.submit_trade_licence(
  p_listing_id uuid,
  p_document_path text,
  p_licence_number text default null
) returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_listing public.listings;
  v_mime text;
  v_size bigint;
  v_owner uuid;
  v_number text := nullif(btrim(p_licence_number), '');
begin
  if v_uid is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;

  select * into v_listing from public.listings where id = p_listing_id;
  if not found or v_listing.owner_id is distinct from v_uid then
    raise exception 'You can only add a licence to your own listing'
      using errcode = '42501', hint = 'not_listing_owner';
  end if;
  if v_listing.listing_type::text <> 'hotel' then
    raise exception 'A trade licence is for hotel listings'
      using errcode = '22023', hint = 'not_a_hotel';
  end if;
  if v_number is not null and char_length(v_number) > 60 then
    raise exception 'The licence number is too long'
      using errcode = '22023', hint = 'licence_number_invalid';
  end if;

  -- The path is the uploader's own folder AND Storage stamped them as the
  -- owner: the path alone is a string anyone can type (database-security.md).
  if p_document_path is null or p_document_path not like v_uid::text || '/trade_licence/%' then
    raise exception 'Invalid document' using errcode = '42501', hint = 'document_not_owned';
  end if;
  select o.owner, o.metadata->>'mimetype', (o.metadata->>'size')::bigint
    into v_owner, v_mime, v_size
    from storage.objects o
   where o.bucket_id = 'documents' and o.name = p_document_path;
  if found and v_owner is distinct from v_uid then
    raise exception 'Invalid document' using errcode = '42501', hint = 'document_not_owned';
  end if;
  if not found or v_mime is null
     or v_mime not in ('image/jpeg', 'image/png', 'application/pdf')
     or v_size is null or v_size not between 100 and 5242880 then
    raise exception 'Upload a JPG, PNG or PDF of the licence, under 5 MB'
      using errcode = '22023', hint = 'document_invalid';
  end if;

  insert into public.listing_trade_licences
    (listing_id, owner_id, document_path, licence_number, status, submitted_at,
     reviewed_at, reviewed_by, rejection_reason)
  values (p_listing_id, v_uid, p_document_path, v_number, 'pending', now(),
          null, null, null)
  on conflict (listing_id) do update
    set owner_id = excluded.owner_id,
        document_path = excluded.document_path,
        licence_number = excluded.licence_number,
        status = 'pending',
        submitted_at = now(),
        reviewed_at = null,
        reviewed_by = null,
        rejection_reason = null;
end;
$$;

-- ---------------------------------------------------------------------------
-- The verdict (admin)
-- ---------------------------------------------------------------------------
-- p_document_path pins what the admin looked at: if the host re-submitted
-- while the admin had the queue open, the verdict is refused rather than
-- landing on a document nobody reviewed (143's "Submission changed" rule).
create or replace function public.review_trade_licence(
  p_listing_id uuid,
  p_document_path text,
  p_approve boolean,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_row public.listing_trade_licences;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Only an admin can review a licence' using errcode = '42501';
  end if;

  select * into v_row from public.listing_trade_licences
   where listing_id = p_listing_id for update;
  if not found or v_row.status <> 'pending'
     or v_row.document_path is distinct from p_document_path then
    raise exception 'Submission changed. Refresh the review queue'
      using errcode = '40001', hint = 'licence_changed';
  end if;
  if v_row.owner_id = auth.uid() then
    raise exception 'Another admin must review your own listing'
      using errcode = '42501', hint = 'own_listing';
  end if;
  if not p_approve and nullif(btrim(p_reason), '') is null then
    raise exception 'Say why, so the host can fix it'
      using errcode = '22023', hint = 'reason_required';
  end if;

  update public.listing_trade_licences
     set status = case when p_approve then 'verified' else 'rejected' end::public.verification_status,
         reviewed_at = now(),
         reviewed_by = auth.uid(),
         rejection_reason = case when p_approve then null else btrim(p_reason) end
   where listing_id = p_listing_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- The public answer
-- ---------------------------------------------------------------------------
-- A boolean and nothing else: guests never see the document, the number, or a
-- rejection. Still a hotel, still verified, file still there — a host who switches the type
-- away loses the badge without anyone touching the row.
create or replace function public.listing_licence_verified(p_listing_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1
      from public.listing_trade_licences t
      join public.listings l on l.id = t.listing_id
     where t.listing_id = p_listing_id
       and t.status = 'verified'
       and l.listing_type::text = 'hotel'
       -- The host can delete their own documents (documents_owner_delete);
       -- a badge must not vouch for a file that is gone.
       and exists (select 1 from storage.objects o
                    where o.bucket_id = 'documents' and o.name = t.document_path)
  );
$$;

-- Definer functions are public endpoints (database-security.md). The two
-- writers guard on auth.uid() in the body but are still closed to anon; the
-- verdict reader is public on purpose.
revoke all on function public.submit_trade_licence(uuid, text, text) from public, anon;
grant execute on function public.submit_trade_licence(uuid, text, text) to authenticated;
revoke all on function public.review_trade_licence(uuid, text, boolean, text) from public, anon;
grant execute on function public.review_trade_licence(uuid, text, boolean, text) to authenticated;
revoke all on function public.listing_licence_verified(uuid) from public;
grant execute on function public.listing_licence_verified(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Room labels: the one column a host writes on listing_units directly
-- ---------------------------------------------------------------------------
-- 147 granted authenticated full DML, and `listing_units_owner_all` let the
-- owner insert, delete, deactivate or re-point (listing_id) their own units —
-- every capacity rule in set_listing_unit_count (150: the lock, the
-- units_in_use check, the hotel-only count) was one PostgREST call away from
-- not applying. The only writers that need more are the definer functions
-- (fn_listing_default_unit, set_listing_unit_count), which run as postgres.
-- So the host keeps exactly the rename the UI needs; RLS still picks the rows.
revoke insert, update, delete on table public.listing_units from authenticated;
grant update (label) on table public.listing_units to authenticated;

commit;
