-- Migration 110: let a host block a date range without hiding the listing.
--
-- PROBLEM: a host had exactly four availability controls, all of them
-- all-or-nothing across every future date — the host-wide Available/Away switch
-- (038), the per-listing is_active hide/show, the per-plan rate toggles, and the
-- min/max duration numbers (055). None of them expresses "I'm away 2-9
-- September". The only workaround was to hide the whole listing and remember to
-- un-hide it, which silently costs the host every booking in between.
--
-- FIX: a table of half-open blocked ranges per listing. Migration 111 teaches
-- create_marketplace_booking and is_booking_available to respect it; this
-- migration only adds the data and the write path, so it is inert on its own and
-- safe to apply first.
--
-- Bounds are '[)' everywhere, matching bookings_no_overlap (078): a block ending
-- at the same instant a stay begins does NOT collide. Getting this wrong would
-- make a checkout-day block eat the next check-in.

create table if not exists public.listing_availability_blocks (
  id          uuid primary key default gen_random_uuid(),
  listing_id  uuid not null references public.listings (id) on delete cascade,
  starts_at   timestamptz not null,
  ends_at     timestamptz not null,
  -- Host-private reason ("Family visit"). Never shown to a guest — see the
  -- listing_blocked_ranges reader below, which is why the SELECT policy is
  -- owner-only rather than open to every authenticated user.
  note        text,
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default timezone('utc', now()),
  constraint block_time_check check (ends_at > starts_at),
  constraint block_note_len  check (note is null or char_length(note) <= 200)
);

create index if not exists listing_availability_blocks_listing_idx
  on public.listing_availability_blocks (listing_id, starts_at);

-- Two blocks on one listing may not overlap. Not a correctness requirement —
-- overlapping blocks would still block — but it keeps the host's own list
-- readable and makes "remove this block" mean one unambiguous thing.
alter table public.listing_availability_blocks
  drop constraint if exists listing_blocks_no_overlap;
alter table public.listing_availability_blocks
  add constraint listing_blocks_no_overlap
  exclude using gist (
    listing_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  );

comment on table public.listing_availability_blocks is
  'Host-declared unavailable date ranges for a listing. Enforced at booking time '
  'by create_marketplace_booking and surfaced to guests by is_booking_available '
  '(both migration 111).';

-- ---------------------------------------------------------------------------
-- RLS: SELECT-only policy, every write through a SECURITY DEFINER RPC. Same
-- shape migration 100 used for payout_methods.
-- ---------------------------------------------------------------------------

alter table public.listing_availability_blocks enable row level security;

-- Owner (and admin) only, because rows carry the host's private `note`. Guests
-- get the dates — and nothing else — from listing_blocked_ranges() below.
drop policy if exists listing_availability_blocks_select
  on public.listing_availability_blocks;
create policy listing_availability_blocks_select
  on public.listing_availability_blocks
  for select to authenticated
  using (
    exists (
      select 1 from public.listings l
      where l.id = listing_id and l.owner_id = auth.uid()
    )
    or public.is_admin()
  );

-- No INSERT / UPDATE / DELETE policies, by design: the RPCs below are the only
-- write path, so the "does this range already hold a booking?" check cannot be
-- routed around by a direct PostgREST write.

-- ---------------------------------------------------------------------------
-- Write path
-- ---------------------------------------------------------------------------

create or replace function public.block_listing_dates(
  p_listing_id uuid,
  p_starts_at  timestamptz,
  p_ends_at    timestamptz,
  p_note       text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid   uuid := auth.uid();
  v_block public.listing_availability_blocks%rowtype;
begin
  if v_uid is null then
    raise exception 'You must be signed in' using errcode = '42501';
  end if;

  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then
    raise exception 'Invalid dates' using errcode = '22023';
  end if;

  -- Ownership. SECURITY DEFINER means RLS is not doing this for us.
  if not exists (
    select 1 from public.listings l
    where l.id = p_listing_id
      and (l.owner_id = v_uid or public.is_admin())
  ) then
    raise exception 'You can only block dates on your own listing'
      using errcode = '42501';
  end if;

  -- Refuse to block over a live booking. Silently swallowing this would leave
  -- the host believing they are free on a date a guest is already holding, and
  -- the guest with a booking the host has mentally cancelled. Make them decline
  -- it explicitly instead.
  if exists (
    select 1 from public.bookings b
    where b.listing_id = p_listing_id
      and b.booking_status in ('pending', 'confirmed', 'active')
      and tstzrange(b.starts_at, b.ends_at, '[)')
          && tstzrange(p_starts_at, p_ends_at, '[)')
  ) then
    raise exception 'You already have a booking in these dates. Decline or cancel it first.'
      using errcode = '23P01', hint = 'block_over_booking';
  end if;

  -- The handler is scoped to the INSERT alone, deliberately. 23P01 *is*
  -- exclusion_violation, so a function-level `when exclusion_violation` would
  -- also catch the booking-overlap raise above and relabel it as a block
  -- collision — the wrong sentence for the wrong problem.
  begin
    insert into public.listing_availability_blocks
      (listing_id, starts_at, ends_at, note, created_by)
    values
      (p_listing_id, p_starts_at, p_ends_at, nullif(trim(coalesce(p_note, '')), ''), v_uid)
    returning * into v_block;
  exception
    -- listing_blocks_no_overlap. Reachable by a double-tap or two devices, and
    -- "conflicting key value violates exclusion constraint" is not a sentence
    -- to show a host.
    when exclusion_violation then
      raise exception 'These dates overlap a block you already have.'
        using errcode = '23P01', hint = 'block_overlaps_block';
  end;

  return to_jsonb(v_block);
end;
$$;

create or replace function public.unblock_listing_dates(p_block_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'You must be signed in' using errcode = '42501';
  end if;

  delete from public.listing_availability_blocks blk
  using public.listings l
  where blk.id = p_block_id
    and l.id = blk.listing_id
    and (l.owner_id = v_uid or public.is_admin());

  if not found then
    raise exception 'Block not found' using errcode = 'P0002';
  end if;
end;
$$;

-- Guest-safe reader: the two timestamps and nothing else. The host's `note` and
-- created_by stay behind the owner-only SELECT policy. Guests need this to be
-- told *why* a date is unavailable rather than just being refused at checkout.
create or replace function public.listing_blocked_ranges(p_listing_id uuid)
returns table (starts_at timestamptz, ends_at timestamptz)
language sql
stable
security definer
set search_path to 'public'
as $$
  select blk.starts_at, blk.ends_at
  from public.listing_availability_blocks blk
  where blk.listing_id = p_listing_id
    and blk.ends_at > timezone('utc', now())
  order by blk.starts_at;
$$;

revoke all on function public.block_listing_dates(uuid, timestamptz, timestamptz, text) from public;
revoke all on function public.unblock_listing_dates(uuid) from public;
revoke all on function public.listing_blocked_ranges(uuid) from public;

grant execute on function public.block_listing_dates(uuid, timestamptz, timestamptz, text) to authenticated;
grant execute on function public.unblock_listing_dates(uuid) to authenticated;
grant execute on function public.listing_blocked_ranges(uuid) to authenticated;
