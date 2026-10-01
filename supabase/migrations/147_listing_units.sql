-- 147: bookable units. Phase 1 of docs/plans/hotel.md.
--
-- Today one listing is one bookable thing: `bookings_no_overlap` excludes two
-- live bookings on the same listing_id over overlapping intervals, and
-- `is_booking_available` is "no live booking, no block". A hotel is one
-- listing with twelve identical rooms, so the thing the exclusion constraint
-- keys on has to become the ROOM. This migration introduces that row
-- (`listing_units`) and moves the overlap rule onto it, without changing what
-- a guest or host sees: every existing listing gets exactly one unit, every
-- existing booking is pinned to it, and a single-unit listing behaves exactly
-- as before. The hotel type itself, the hourly policy and the host-facing unit
-- management come in 148–151; this one only has to be right about overlap.
--
-- Who picks the unit: the database, never the guest (plan D4). Booking.com
-- sells a room TYPE and assigns the physical room at check-in; the guest
-- booking "Deluxe Room" does not care which door. So `create_marketplace_booking`
-- selects any free active unit `for update skip locked` and raises the same
-- `listing_overlap` conflict as before when there is none. Two guests racing
-- for the last room: the first locks the unit row, the second skips it, finds
-- nothing and is refused — no wait, no 40P01. If the first then rolls back the
-- second was refused for a room that was in fact free; that is a retry, not a
-- double-booking, and `bookings_no_overlap` on unit_id remains the backstop
-- for anything that bypasses the RPC.
--
-- Nothing here is reversible after a multi-unit listing exists; before that
-- the inverse is "drop unit_id, recreate the constraint on listing_id".
begin;

-- ---------------------------------------------------------------------------
-- 1. The unit row. `label` is the host's name for it ("Room 204"); null for
--    the implicit unit of a listing that IS the unit (a seat, a turf). The
--    unique index lets a hotel reuse nothing, while nulls stay distinct so a
--    dozen unlabelled rooms are fine.
-- ---------------------------------------------------------------------------
create table if not exists public.listing_units (
  id          uuid primary key default gen_random_uuid(),
  listing_id  uuid not null references public.listings(id) on delete cascade,
  label       text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  constraint listing_units_label_len check (label is null or char_length(label) between 1 and 40),
  constraint listing_units_label_unique unique (listing_id, label)
);
create index if not exists listing_units_listing_active_idx
  on public.listing_units (listing_id) where is_active;

-- Every listing that exists today is one bookable thing.
insert into public.listing_units (listing_id)
select l.id from public.listings l
where not exists (select 1 from public.listing_units u where u.listing_id = l.id);

-- And every listing created from now on starts that way too. The app that is
-- deployed today knows nothing about units; a listing it inserts must still be
-- bookable the moment it is published. A hotel host adds rooms on top (150).
create or replace function public.fn_listing_default_unit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.listing_units (listing_id) values (new.id);
  return new;
end $$;
drop trigger if exists trg_listing_default_unit on public.listings;
create trigger trg_listing_default_unit
  after insert on public.listings
  for each row execute function public.fn_listing_default_unit();

-- ---------------------------------------------------------------------------
-- 2. bookings.unit_id. Backfilled to the listing's (only) unit before the
--    not-null lands. ON DELETE is the default NO ACTION: a unit with bookings
--    cannot be removed by a host; a listing delete cascades to both and the
--    check is deferred to statement end, so that path still works.
-- ---------------------------------------------------------------------------
alter table public.bookings
  add column if not exists unit_id uuid references public.listing_units(id);

update public.bookings b
   set unit_id = u.id
  from public.listing_units u
 where u.listing_id = b.listing_id
   and b.unit_id is null;

do $$
declare v_multi int; v_none int; v_unassigned int;
begin
  select count(*) into v_multi from (
    select listing_id from public.listing_units group by listing_id having count(*) <> 1) m;
  select count(*) into v_none from public.listings l
   where not exists (select 1 from public.listing_units u where u.listing_id = l.id);
  select count(*) into v_unassigned from public.bookings where unit_id is null;
  -- The constraint swap below is only equivalent to the old one while each
  -- listing has exactly one unit and every booking sits on it. Refuse to
  -- continue otherwise rather than silently weaken the backstop.
  if v_multi > 0 or v_none > 0 or v_unassigned > 0 then
    raise exception '147: cannot swap the overlap constraint (multi-unit listings=%, unitless listings=%, unassigned bookings=%)',
      v_multi, v_none, v_unassigned;
  end if;
end $$;

alter table public.bookings alter column unit_id set not null;
create index if not exists bookings_unit_idx on public.bookings (unit_id, starts_at);

-- The name is kept on purpose. lib/models/booking_conflict_exception.dart
-- falls back to the constraint name Postgres prints when a 23P01 arrives with
-- no hint, and several comments in lib/ cite `bookings_no_overlap` as "the
-- real backstop". Same role, same name; only the key changed.
alter table public.bookings drop constraint if exists bookings_no_overlap;
alter table public.bookings add constraint bookings_no_overlap
  exclude using gist (unit_id with =, tstzrange(starts_at, ends_at, '[)') with &&)
  where (booking_status in ('pending', 'confirmed', 'active'));

-- unit_id must belong to the booking's listing, and once set it is fixed:
-- moving a guest to another room is an operational act with its own RPC
-- (151, `reassign_booking_unit`, which raises the flag below). A row arriving
-- without a unit — the QA seed, older suites, the legacy direct insert still
-- in the Dart repository — is pinned to the listing's only unit, which is the
-- pre-147 meaning of "a booking on this listing". When there are several, the
-- caller has to choose; defaulting to "the first" would hide a real bug.
create or replace function public.fn_booking_unit_consistent()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_listing uuid; v_n int;
begin
  if tg_op = 'UPDATE' then
    if new.unit_id is distinct from old.unit_id
       and coalesce(current_setting('musafir.unit_reassign', true), '') <> 'on' then
      raise exception 'A booking cannot be moved to another unit here'
        using errcode = '42501', hint = 'booking_columns_protected';
    end if;
    if new.unit_id is not distinct from old.unit_id
       and new.listing_id is not distinct from old.listing_id then
      return new;
    end if;
  end if;

  if new.unit_id is null then
    -- (array_agg)[1], not min(): there is no min(uuid) in core Postgres.
    select count(*), (array_agg(id))[1] into v_n, new.unit_id
      from public.listing_units where listing_id = new.listing_id;
    if v_n <> 1 then
      raise exception 'This listing has % units; a booking must name one', v_n
        using errcode = '22023', hint = 'unit_required';
    end if;
    return new;
  end if;

  select listing_id into v_listing from public.listing_units where id = new.unit_id;
  if v_listing is distinct from new.listing_id then
    raise exception 'The unit does not belong to this listing'
      using errcode = '22023', hint = 'unit_mismatch';
  end if;
  return new;
end $$;
-- `trg_a…` sorts before `trg_enforce_booking_update_rules`, so the unit is
-- resolved before the frozen-column checks read the row. Order is by name.
drop trigger if exists trg_a_booking_unit_consistent on public.bookings;
create trigger trg_a_booking_unit_consistent
  before insert or update on public.bookings
  for each row execute function public.fn_booking_unit_consistent();

-- ---------------------------------------------------------------------------
-- 3. Blocks can be per-unit. null unit_id = the whole listing (every block
--    that exists today). The exclusion keys on the unit too, with a sentinel
--    for "whole listing", so two rooms may be blocked over the same nights
--    while one room still cannot be blocked twice. The host-facing RPC grows
--    its unit parameter in 151; until then only the server writes this column.
-- ---------------------------------------------------------------------------
alter table public.listing_availability_blocks
  add column if not exists unit_id uuid references public.listing_units(id) on delete cascade;

create or replace function public.fn_block_unit_consistent()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.unit_id is not null and not exists (
    select 1 from public.listing_units u where u.id = new.unit_id and u.listing_id = new.listing_id
  ) then
    raise exception 'The unit does not belong to this listing'
      using errcode = '22023', hint = 'unit_mismatch';
  end if;
  return new;
end $$;
drop trigger if exists trg_block_unit_consistent on public.listing_availability_blocks;
create trigger trg_block_unit_consistent
  before insert or update on public.listing_availability_blocks
  for each row execute function public.fn_block_unit_consistent();

alter table public.listing_availability_blocks drop constraint if exists listing_blocks_no_overlap;
alter table public.listing_availability_blocks add constraint listing_blocks_no_overlap
  exclude using gist (
    listing_id with =,
    coalesce(unit_id, '00000000-0000-0000-0000-000000000000'::uuid) with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  );

-- ---------------------------------------------------------------------------
-- 4. Availability: "at least one active unit is free". Same signature, so
--    search_listings (which calls it inside the base CTE) and the detail
--    screen's pre-flight RPC are untouched. A listing-wide block still beats
--    everything; a per-unit block only takes that unit out.
-- ---------------------------------------------------------------------------
create or replace function public.listing_rooms_left(p_listing_id uuid, p_starts_at timestamptz, p_ends_at timestamptz)
returns integer
language sql stable security definer set search_path = public as $$
  select case
    when exists (
      select 1 from public.listing_availability_blocks blk
      where blk.listing_id = p_listing_id and blk.unit_id is null
        and tstzrange(blk.starts_at, blk.ends_at, '[)') && tstzrange(p_starts_at, p_ends_at, '[)'))
    then 0
    else (
      select count(*)::int from public.listing_units u
      where u.listing_id = p_listing_id and u.is_active
        and not exists (
          select 1 from public.bookings b
          where b.unit_id = u.id
            and b.booking_status in ('pending', 'confirmed', 'active')
            and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(p_starts_at, p_ends_at, '[)'))
        and not exists (
          select 1 from public.listing_availability_blocks blk
          where blk.unit_id = u.id
            and tstzrange(blk.starts_at, blk.ends_at, '[)') && tstzrange(p_starts_at, p_ends_at, '[)')))
  end;
$$;

create or replace function public.is_booking_available(p_listing_id uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone)
returns boolean
language sql stable security definer set search_path = public as $$
  select public.listing_rooms_left(p_listing_id, p_starts_at, p_ends_at) > 0;
$$;

-- Same exposure as is_booking_available: the detail page shows "N rooms
-- left" to anyone browsing (public browse, 113). A count leaks nothing a
-- sequence of availability probes would not.
revoke all on function public.listing_rooms_left(uuid, timestamptz, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.listing_rooms_left(uuid, timestamptz, timestamptz) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Unit assignment in the booking RPC. Body identical to 140's except the
--    listing-overlap check, which becomes the unit selection, and the block
--    check, which is split: listing-wide blocks keep their own sentence and
--    run first (otherwise a blocked hotel would read as "fully booked"),
--    per-unit blocks are folded into the selection.
-- ---------------------------------------------------------------------------
create or replace function public.create_marketplace_booking(p_listing_id uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_pricing_unit text, p_guest_count integer, p_tenant_name text DEFAULT NULL::text, p_coupon_code text DEFAULT NULL::text, p_listing_image_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid        uuid := auth.uid();
  v_listing    public.listings%rowtype;
  v_rate       numeric;
  v_qty        int;
  v_min        int;
  v_max        int;
  v_unit_word  text;
  v_gross      numeric;
  v_discount   numeric := 0;
  v_coupon_id  uuid;
  v_total      numeric;
  v_res        jsonb;
  v_booking    public.bookings%rowtype;
  v_unit       uuid;
  v_units      int;
begin
  if v_uid is null then
    raise exception 'You must be signed in to book' using errcode = '42501';
  end if;

  -- Either historical identity approval or explicit current face-review approval.
  -- Keep the stable error hint consumed by the booking client.
  if not public.has_approved_face_or_identity(v_uid) then
    raise exception 'Admin face review is required before booking'
      using errcode = '42501', hint = 'identity_unverified';
  end if;

  -- Reserved interval must be forward-in-time.
  if p_ends_at is null or p_starts_at is null or p_ends_at <= p_starts_at then
    raise exception 'Invalid booking dates' using errcode = '22023';
  end if;

  -- 135: and it must not be in the past. Measured: a stay starting ten days
  -- ago was accepted and returned an id. Past slots are always "free", so the
  -- availability checks below never object, and `expire_stale_bookings` /
  -- the auto-complete sweep then walk the row straight to completed — which
  -- is a review prompt and a ledger entry for a stay nobody had.
  --
  -- The calendar already hides past dates. That is the "the booking form
  -- checks it" pattern this codebase has been bitten by four times: the form
  -- is skippable and the RPC is a public endpoint.
  --
  -- One hour of slack rather than a hard `>= now()`, because a guest booking
  -- a turf for *this* hour is the normal case for hourly listings, the
  -- client's clock is its own, and `now()` here is transaction time. The
  -- guard exists to stop last month, not to police the last minute.
  if p_starts_at < now() - interval '1 hour' then
    raise exception 'Choose a start time in the future'
      using errcode = '22023', hint = 'starts_in_past';
  end if;

  -- Load the listing. Must exist and be active.
  select * into v_listing from public.listings where id = p_listing_id;
  if not found then
    raise exception 'Listing not found' using errcode = 'P0002';
  end if;
  if not coalesce(v_listing.is_active, true) then
    raise exception 'This listing is no longer available' using errcode = '22023';
  end if;

  -- 135: a host must not book their own listing. Nothing checked this, and
  -- live already holds one such booking. Two things go wrong when it is
  -- allowed: the ledger posts the owner an earning against money that only
  -- moved between their own two pockets (or did not move at all, on the cash
  -- path), and a host can black out their own calendar through the booking
  -- path instead of listing_availability_blocks (110), which is the feature
  -- built for exactly that and the only one the host's own UI can undo.
  if v_listing.owner_id = v_uid then
    raise exception 'You cannot book your own listing'
      using errcode = '42501', hint = 'self_booking';
  end if;

  -- 138: a block is a wall, not a filter. `user_blocks` (SAFETY.md) only ever
  -- hid the other party's listings and threads in the CLIENT; measured
  -- 2026-09-19, a guest a host had blocked booked that host's listing and
  -- opened a conversation with them without a hitch. Either direction counts:
  -- a host who blocked a guest does not want their money, and a guest who
  -- blocked a host does not want to stay there.
  -- 140: a suspended account keeps its access token for up to an hour.
  if public.fn_is_suspended(v_uid) then
    raise exception 'This account is suspended'
      using errcode = '42501', hint = 'account_suspended';
  end if;
  -- And a suspended host's listings are hidden, but a deep link or a stale
  -- client can still name one.
  if public.fn_is_suspended(v_listing.owner_id) then
    raise exception 'This listing is no longer available' using errcode = '22023';
  end if;

  if public.fn_users_blocked(v_uid, v_listing.owner_id) then
    raise exception 'You cannot book this listing'
      using errcode = '42501', hint = 'blocked';
  end if;

  -- The host-wide Away switch (038). Only ever a search filter before this, so
  -- a guest who already had the page open could book straight past it.
  if not coalesce(v_listing.host_available, true) then
    raise exception 'This host isn''t accepting new bookings right now'
      using errcode = '22023';
  end if;

  -- Guest count within the listing's capacity.
  if p_guest_count is null or p_guest_count < 1 then
    raise exception 'At least one guest is required' using errcode = '22023';
  end if;
  if v_listing.max_guests is not null and p_guest_count > v_listing.max_guests then
    raise exception 'This place hosts up to % guests', v_listing.max_guests
      using errcode = '22023';
  end if;

  -- Server-side rate + quantity. Quantity is derived from the reserved interval
  -- so the client can't understate it; hour/day are exact epoch multiples,
  -- month is a calendar diff (monthly stays are booked whole-month, same day).
  -- The per-plan duration limits (055) are read here too, so the unit, the
  -- quantity and the bounds they are compared against always come from the same
  -- branch and cannot drift apart.
  case p_pricing_unit
    when 'hour' then
      v_rate := v_listing.hourly_rate;
      v_qty  := round(extract(epoch from (p_ends_at - p_starts_at)) / 3600.0);
      v_min  := v_listing.min_hours;
      v_max  := v_listing.max_hours;
      v_unit_word := 'hour';
    when 'day' then
      v_rate := v_listing.daily_rate;
      v_qty  := round(extract(epoch from (p_ends_at - p_starts_at)) / 86400.0);
      v_min  := v_listing.min_nights;
      v_max  := v_listing.max_nights;
      -- 'night', not 'day' — matches the word the booking form uses, so the
      -- guest doesn't get two different names for one number.
      v_unit_word := 'night';
    when 'month' then
      v_rate := v_listing.monthly_rate;
      v_qty  := (extract(year from p_ends_at) - extract(year from p_starts_at))::int * 12
              + (extract(month from p_ends_at) - extract(month from p_starts_at))::int;
      v_min  := v_listing.min_months;
      v_max  := v_listing.max_months;
      v_unit_word := 'month';
    else
      raise exception 'Unsupported booking type: %', p_pricing_unit using errcode = '22023';
  end case;

  if v_rate is null then
    raise exception 'This listing is not available for % bookings', p_pricing_unit
      using errcode = '22023';
  end if;
  if v_qty is null or v_qty < 1 then
    raise exception 'Booking must be at least one %', p_pricing_unit using errcode = '22023';
  end if;

  -- The host's per-plan minimum/maximum (055). `coalesce(v_min, 1)` mirrors
  -- BookingLimits.minFor's `?? 1` in lib/models/listing.dart — if those two ever
  -- disagree, the form and the server disagree about the floor and the guest
  -- gets refused for something the UI let them pick.
  if v_qty < coalesce(v_min, 1) then
    raise exception 'Minimum booking is % %', coalesce(v_min, 1),
      v_unit_word || case when coalesce(v_min, 1) = 1 then '' else 's' end
      using errcode = '22023';
  end if;
  if v_max is not null and v_qty > v_max then
    raise exception 'Maximum booking is % %', v_max,
      v_unit_word || case when v_max = 1 then '' else 's' end
      using errcode = '22023';
  end if;

  v_gross := round(v_rate * v_qty, 2);

  -- Host-declared blocked dates (110), the listing-wide kind. Checked before
  -- the unit selection so a hotel the host closed for renovation says so,
  -- rather than "fully booked". A block is not a bookings row, so no single
  -- exclusion constraint can cover both tables; a host blocking dates in the
  -- same millisecond a guest commits can lose this check. That window is
  -- accepted deliberately — the cost is one booking the host declines by hand,
  -- and the alternative (storing blocks AS bookings rows under a sentinel
  -- status) would drag them through earnings, commission, payouts and the host
  -- reservations list.
  if exists (
    select 1 from public.listing_availability_blocks blk
    where blk.listing_id = p_listing_id
      and blk.unit_id is null
      and tstzrange(blk.starts_at, blk.ends_at, '[)')
          && tstzrange(p_starts_at, p_ends_at, '[)')
  ) then
    raise exception 'The host has blocked these dates' using errcode = '22023';
  end if;

  -- Same user can't hold two overlapping bookings. Backed by
  -- bookings_no_tenant_overlap, so losing the race here fails at COMMIT rather
  -- than slipping through. Before the unit selection so the guest's own
  -- double-booking is named as such rather than consuming a room first.
  if exists (
    select 1 from public.bookings b
    where b.tenant_id = v_uid
      and b.booking_status in ('pending', 'confirmed', 'active')
      and p_starts_at < b.ends_at
      and b.starts_at < p_ends_at
  ) then
    raise exception 'You already have a booking during this time'
      using errcode = '23P01', hint = 'tenant_overlap';
  end if;

  -- 147: pick a unit. Any active one with no live booking and no per-unit
  -- block over the interval, lowest label first so a hotel fills "101, 102,
  -- …" in order and a single-unit listing has exactly one candidate.
  -- `for update skip locked` is the race rule: a unit another transaction is
  -- in the middle of booking is invisible here, so two guests never pick the
  -- same row, and the loser of the last-room race is refused at once instead
  -- of waiting on a lock it would lose anyway. The `hint` is what the Dart
  -- layer reads to choose the guest-facing sentence (111).
  select u.id into v_unit
    from public.listing_units u
   where u.listing_id = p_listing_id
     and u.is_active
     and not exists (
       select 1 from public.bookings b
       where b.unit_id = u.id
         and b.booking_status in ('pending', 'confirmed', 'active')
         and tstzrange(b.starts_at, b.ends_at, '[)')
             && tstzrange(p_starts_at, p_ends_at, '[)'))
     and not exists (
       select 1 from public.listing_availability_blocks blk
       where blk.unit_id = u.id
         and tstzrange(blk.starts_at, blk.ends_at, '[)')
             && tstzrange(p_starts_at, p_ends_at, '[)'))
   order by u.label nulls last, u.created_at
   for update of u skip locked
   limit 1;

  if v_unit is null then
    select count(*) into v_units from public.listing_units
     where listing_id = p_listing_id and is_active;
    raise exception '%',
      case when v_units > 1 then 'Every room is taken for these dates'
           else 'This time slot is already booked' end
      using errcode = '23P01', hint = 'listing_overlap';
  end if;

  -- Coupon (optional). Reuse the authoritative validator against the SERVER
  -- gross, so the discount can't be inflated against a fake amount either.
  if p_coupon_code is not null and length(trim(p_coupon_code)) > 0 then
    v_res := public.validate_coupon(p_coupon_code, v_gross);
    if (v_res->>'valid')::boolean is not true then
      raise exception '%', coalesce(v_res->>'message', 'Invalid coupon')
        using errcode = '22023';
    end if;
    v_discount  := coalesce((v_res->>'discount_amount')::numeric, 0);
    v_coupon_id := (v_res->>'coupon_id')::uuid;
  end if;

  v_total := greatest(v_gross - v_discount, 0);

  insert into public.bookings (
    listing_id, unit_id, tenant_id, tenant_name,
    starts_at, ends_at, pricing_unit, unit_count,
    total_price, guest_count, booking_status,
    listing_title, listing_image_url, listing_city,
    coupon_code, discount_amount
  ) values (
    p_listing_id, v_unit, v_uid, coalesce(p_tenant_name, ''),
    p_starts_at, p_ends_at, p_pricing_unit::pricing_unit, v_qty,
    v_total, p_guest_count, 'pending',
    v_listing.title, p_listing_image_url, v_listing.city,
    case when v_coupon_id is not null then upper(trim(p_coupon_code)) end,
    case when v_coupon_id is not null then v_discount else 0 end
  ) returning * into v_booking;

  -- Record redemption + bump usage atomically. If limits were exhausted between
  -- validate and here, redeem_coupon raises and the whole booking rolls back.
  if v_coupon_id is not null then
    perform public.redeem_coupon(v_coupon_id, v_booking.id, v_discount);
  end if;

  return to_jsonb(v_booking);
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6. Access. Units are the host's inventory: owner or admin, nothing public.
--    Guests learn about rooms only through listing_rooms_left. Default
--    privileges would have granted anon SELECT at create time (see
--    docs/notes/database-security.md), so the revoke is explicit.
-- ---------------------------------------------------------------------------
alter table public.listing_units enable row level security;

drop policy if exists "listing_units_owner_all" on public.listing_units;
create policy "listing_units_owner_all" on public.listing_units
  as permissive for all to authenticated
  using (exists (select 1 from public.listings l where l.id = listing_units.listing_id and l.owner_id = auth.uid())
         or public.is_admin())
  with check (exists (select 1 from public.listings l where l.id = listing_units.listing_id and l.owner_id = auth.uid())
              or public.is_admin());

revoke all on table public.listing_units from public, anon;
grant select, insert, update, delete on table public.listing_units to authenticated;
grant all on table public.listing_units to service_role;

commit;
