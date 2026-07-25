-- 070: Server-authoritative booking creation.
--
-- Problem this closes: the app currently inserts bookings directly and sends
-- `total_price` from the client. Any authenticated user could POST a booking
-- with a tampered price (e.g. total_price = 1). RLS only checked
-- `auth.uid() = tenant_id`, never the money.
--
-- Fix: `create_marketplace_booking` recomputes the price on the server from the
-- listing's own stored rates and the reserved interval, validates + applies the
-- coupon, checks conflicts, inserts the row, and records the coupon redemption
-- — all in one transaction. The client no longer decides the price.
--
-- This migration is ADDITIVE and safe to apply anytime: it only adds a function.
-- The direct-insert policy is tightened separately in migration 071, which must
-- only be applied AFTER every shipped app build calls this RPC (see that file).

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
  case p_pricing_unit
    when 'hour' then
      v_rate := v_listing.hourly_rate;
      v_qty  := round(extract(epoch from (p_ends_at - p_starts_at)) / 3600.0);
    when 'day' then
      v_rate := v_listing.daily_rate;
      v_qty  := round(extract(epoch from (p_ends_at - p_starts_at)) / 86400.0);
    when 'month' then
      v_rate := v_listing.monthly_rate;
      v_qty  := (extract(year from p_ends_at) - extract(year from p_starts_at))::int * 12
              + (extract(month from p_ends_at) - extract(month from p_starts_at))::int;
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

  v_gross := round(v_rate * v_qty, 2);

  -- Conflict checks (authoritative backstop for the client's pre-flight checks;
  -- also catches races). Blocking statuses match BookingStatus.isActive.
  if exists (
    select 1 from public.bookings b
    where b.listing_id = p_listing_id
      and b.booking_status in ('pending', 'confirmed', 'active')
      and p_starts_at < b.ends_at
      and b.starts_at < p_ends_at
  ) then
    raise exception 'This time slot is already booked' using errcode = '23P01';
  end if;

  -- Same user can't hold two overlapping bookings.
  if exists (
    select 1 from public.bookings b
    where b.tenant_id = v_uid
      and b.booking_status in ('pending', 'confirmed', 'active')
      and p_starts_at < b.ends_at
      and b.starts_at < p_ends_at
  ) then
    raise exception 'You already have a booking during this time' using errcode = '23P01';
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

revoke all on function public.create_marketplace_booking(uuid, timestamptz, timestamptz, text, int, text, text, text) from public;
grant execute on function public.create_marketplace_booking(uuid, timestamptz, timestamptz, text, int, text, text, text) to authenticated;

comment on function public.create_marketplace_booking is
  'Server-authoritative booking creation: recomputes price from the listing rate x reserved interval, applies coupon, checks conflicts, inserts and redeems in one transaction. Clients must use this instead of a direct bookings insert.';
