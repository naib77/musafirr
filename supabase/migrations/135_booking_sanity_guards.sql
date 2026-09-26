-- =============================================
-- 135 — a booking could be made by the listing's own host, or in the past
--
-- Two findings from the full QA round of 2026-09-18, both measured against
-- the local mirror and both confirmed as accepted-with-an-id:
--
--   N4  HOST1 booked HOST1's own listing.
--   N5  a stay from ten days ago was created.
--
-- `create_marketplace_booking` is the only way a booking row can be written
-- (071 locked direct INSERT), so the RPC is the whole of the enforcement,
-- and it checked neither. Recreated IN FULL from the live definition with
-- two blocks added — the same rule as 132 and 133: this function is a chain
-- of guards, and a patch that quietly dropped one would stop enforcing it
-- with nothing to show for it.
--
-- Live already holds one self-booking; it is left alone. This is an
-- INSERT-time rule, the same choice 114 made for identity.
-- =============================================

CREATE OR REPLACE FUNCTION public.create_marketplace_booking(p_listing_id uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_pricing_unit text, p_guest_count integer, p_tenant_name text DEFAULT NULL::text, p_coupon_code text DEFAULT NULL::text, p_listing_image_url text DEFAULT NULL::text)
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
begin
  if v_uid is null then
    raise exception 'You must be signed in to book' using errcode = '42501';
  end if;

  -- Identity verification (114). Until now this lived ONLY in the Flutter
  -- client -- IdentityGate.ensure, called from the Reserve button -- and this
  -- function never looked at it. Live has 8 bookings from guests whose
  -- verification_status is 'none', so that gate demonstrably leaked even
  -- before Explore went public; a public browse page makes the RPC reachable
  -- by anyone holding the publishable anon key.
  --
  -- Reads the column directly rather than trusting a client claim. 095's
  -- trg_guard_verification_verdicts already stops a non-admin awarding
  -- themselves 'verified', so this check cannot be defeated by a PostgREST
  -- write to one's own profile -- the two halves only work together.
  --
  -- The hint is how the client tells this apart from an availability
  -- conflict. Never match on the message prose: that is the mistake
  -- bookingConflictTypeFrom was rewritten to stop making.
  if (select verification_status from public.profiles where id = v_uid)
     is distinct from 'verified' then
    raise exception 'Your identity must be verified before you can book'
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
$function$;
