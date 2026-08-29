-- Migration 111: enforce, in the database, every availability rule a host can
-- already set — plus the two remaining booking-race gaps.
--
-- Migration 070 exists because "the client no longer decides" the price. These
-- are the rules it left behind, each of which lived ONLY in Flutter:
--
--   1. host_available (038). Its own migration comment claims it is "enforced at
--      the Reserve step". It is not. create_marketplace_booking checked
--      is_active but never host_available, and listing_detail_screen.dart has no
--      host-away guard at all — it was purely a search/browse filter (062, 082,
--      085, 092, 097). A guest with the listing already open, deep-linked, or
--      reached from wishlist/trips booked an away host successfully.
--
--   2. min/max duration (055). Enforced in the booking form only. The price was
--      still recomputed server-side so the guest was charged correctly, but they
--      could book below the host's stated minimum.
--
--   3. Availability blocks (110). New, so this is the first enforcement.
--
--   4. is_booking_available was SECURITY INVOKER. bookings has RLS on and its
--      SELECT policies are own-booking / own-listing / admin, so the function
--      the client calls "server-authoritative, sees ALL bookings" saw only the
--      caller's own rows and returned TRUE for a slot another guest already
--      held. The data stayed correct — bookings_no_overlap (078) caught it at
--      COMMIT — but the guest was told the dates were free, filled in the whole
--      sheet, and only then got refused. This is the user-visible one.
--
--   5. The same-user overlap guard was a bare check-then-insert with no
--      constraint behind it — the exact TOCTOU hole 078 closed for listings,
--      still open for tenants. Two concurrent bookings by one guest on
--      DIFFERENT listings could both land.
--
--   6. Which of the two conflict sentences the guest saw was decided by the Dart
--      layer sniffing English prose out of the SQL message. Both raises now
--      carry a stable `hint`, so rewording a message can no longer silently
--      show the guest the wrong one.
--
-- Applying this is safe in either order relative to app deploys: every new
-- refusal uses an SQLSTATE the shipped client already understands (22023 →
-- BookingRejectedException, 23P01 → BookingConflictException), and the `hint`
-- is additive — an older client ignores it and falls back to the prose it
-- already sniffs for.

-- ---------------------------------------------------------------------------
-- 1. Tenant overlap constraint — the race-safe backstop for the guard that
--    create_marketplace_booking has always had but never had teeth behind.
-- ---------------------------------------------------------------------------

-- btree_gist is already installed (001, re-asserted by 078) for `uuid WITH =`
-- inside a GiST index.
--
-- Verified before writing: zero existing same-tenant overlaps on live, so the
-- index builds. If this ALTER fails, do NOT weaken the constraint — find the
-- overlapping pairs first:
--
--   select a.id, b.id, a.tenant_id
--     from public.bookings a join public.bookings b
--       on a.tenant_id = b.tenant_id and a.id < b.id
--    where a.booking_status in ('pending','confirmed','active')
--      and b.booking_status in ('pending','confirmed','active')
--      and tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(b.starts_at,b.ends_at,'[)');
--
-- Note bookings.tenant_id is NULLABLE on live, despite 001 declaring it NOT
-- NULL — pre-existing schema drift. Harmless here: NULL is never `=` NULL, so
-- an orphaned row simply never conflicts with anything.
alter table public.bookings
  drop constraint if exists bookings_no_tenant_overlap;
alter table public.bookings
  add constraint bookings_no_tenant_overlap
  exclude using gist (
    tenant_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  )
  where (booking_status in ('pending', 'confirmed', 'active'));

comment on constraint bookings_no_tenant_overlap on public.bookings is
  'One guest cannot hold two overlapping active bookings, on the same listing or '
  'different ones. Race-safe backstop for create_marketplace_booking''s '
  'pre-insert same-user check, mirroring what bookings_no_overlap does per listing.';

-- ---------------------------------------------------------------------------
-- 2. is_booking_available — make it actually authoritative, and blocks-aware.
-- ---------------------------------------------------------------------------

-- SECURITY DEFINER is the fix for gap 4. It returns a single boolean about a
-- listing the caller is already looking at, so it leaks nothing a booking
-- calendar would not; as SECURITY INVOKER it was simply answering the wrong
-- question. Kept STABLE and pinned to a search_path, as a definer function must
-- be.
create or replace function public.is_booking_available(
    p_listing_id uuid, p_starts_at timestamptz, p_ends_at timestamptz)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select not exists (
    select 1
    from public.bookings b
    where b.listing_id = p_listing_id
      and b.booking_status in ('pending', 'confirmed', 'active')
      and tstzrange(b.starts_at, b.ends_at, '[)')
          && tstzrange(p_starts_at, p_ends_at, '[)')
  )
  and not exists (
    select 1
    from public.listing_availability_blocks blk
    where blk.listing_id = p_listing_id
      and tstzrange(blk.starts_at, blk.ends_at, '[)')
          && tstzrange(p_starts_at, p_ends_at, '[)')
  );
$function$;

revoke all on function public.is_booking_available(uuid, timestamptz, timestamptz) from public;
grant execute on function public.is_booking_available(uuid, timestamptz, timestamptz) to authenticated;

comment on function public.is_booking_available is
  'Pre-flight availability for one listing over one interval: no active booking '
  'and no host block. SECURITY DEFINER because bookings RLS hides other guests'' '
  'rows from the caller, which made the INVOKER version report free slots that '
  'were taken.';

-- ---------------------------------------------------------------------------
-- 3. create_marketplace_booking — same signature (so 071's direct-insert lock
--    and the existing grants stand), four new refusals, two tagged conflicts.
-- ---------------------------------------------------------------------------

create or replace function public.create_marketplace_booking(
  p_listing_id   uuid,
  p_starts_at    timestamptz,
  p_ends_at      timestamptz,
  p_pricing_unit text,
  p_guest_count  int,
  p_tenant_name  text default null,
  p_coupon_code  text default null,
  p_listing_image_url text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
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
begin
  if v_uid is null then
    raise exception 'You must be signed in to book' using errcode = '42501';
  end if;

  -- Reserved interval must be forward-in-time.
  if p_ends_at is null or p_starts_at is null or p_ends_at <= p_starts_at then
    raise exception 'Invalid booking dates' using errcode = '22023';
  end if;

  -- Load the listing. Must exist and be active.
  select * into v_listing from public.listings where id = p_listing_id;
  if not found then
    raise exception 'Listing not found' using errcode = 'P0002';
  end if;
  if not coalesce(v_listing.is_active, true) then
    raise exception 'This listing is no longer available' using errcode = '22023';
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

  -- Conflict checks (authoritative backstop for the client's pre-flight checks;
  -- also catches races). Blocking statuses match BookingStatus.isActive. The
  -- `hint` is what the Dart layer reads to choose between the two guest-facing
  -- sentences; it used to grep this message for the words 'already have a
  -- booking', which meant rewording the line below silently changed the UI.
  if exists (
    select 1 from public.bookings b
    where b.listing_id = p_listing_id
      and b.booking_status in ('pending', 'confirmed', 'active')
      and p_starts_at < b.ends_at
      and b.starts_at < p_ends_at
  ) then
    raise exception 'This time slot is already booked'
      using errcode = '23P01', hint = 'listing_overlap';
  end if;

  -- Same user can't hold two overlapping bookings. Now backed by
  -- bookings_no_tenant_overlap, so losing the race here fails at COMMIT rather
  -- than slipping through.
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

  -- Host-declared blocked dates (110). A block is not a bookings row, so no
  -- single exclusion constraint can cover both tables; a host blocking dates in
  -- the same millisecond a guest commits can lose this check. That window is
  -- accepted deliberately — the cost is one booking the host declines by hand,
  -- and the alternative (storing blocks AS bookings rows under a sentinel
  -- status) would drag them through earnings, commission, payouts and the host
  -- reservations list.
  if exists (
    select 1 from public.listing_availability_blocks blk
    where blk.listing_id = p_listing_id
      and tstzrange(blk.starts_at, blk.ends_at, '[)')
          && tstzrange(p_starts_at, p_ends_at, '[)')
  ) then
    raise exception 'The host has blocked these dates' using errcode = '22023';
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
    listing_id, tenant_id, tenant_name,
    starts_at, ends_at, pricing_unit, unit_count,
    total_price, guest_count, booking_status,
    listing_title, listing_image_url, listing_city,
    coupon_code, discount_amount
  ) values (
    p_listing_id, v_uid, coalesce(p_tenant_name, ''),
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
$$;

-- Re-assert the grants from 070. CREATE OR REPLACE keeps them, but stating them
-- makes this file safe to run against a database where the function was ever
-- dropped and recreated by hand.
revoke all on function public.create_marketplace_booking(uuid, timestamptz, timestamptz, text, int, text, text, text) from public;
grant execute on function public.create_marketplace_booking(uuid, timestamptz, timestamptz, text, int, text, text, text) to authenticated;
