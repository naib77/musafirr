-- Migration 151: hotel operations -- instant booking, moving a booking to
-- another room, and blocking one room. Decisions D2/D4 in docs/plans/hotel.md.
--
--   1. listings.instant_book (D2). Default false, so every existing listing
--      keeps the accept window; any type may switch it on. The booking RPC
--      inserts such a booking as `confirmed` (with confirmed_at), and the
--      lifecycle trigger gains the INSERT-confirmed arm that tells the host.
--
--      Known gap, deliberately not decided here: a confirmed booking that is
--      never paid holds its room until the stay, exactly as a host-confirmed
--      one does today. Instant book only removes the host's tap from that
--      path. expire_stale_bookings still touches pending only.
--
--   2. reassign_booking_unit (D4: the database assigns, the host may move).
--      The only writer of musafir.unit_reassign, 147's guard on unit_id.
--
--   3. block_listing_dates gains p_unit_id. The old 4-argument function is
--      DROPPED and recreated with the new argument defaulted: two overloads
--      that both accept the old four keys would make PostgREST's pick
--      ambiguous (it chooses by the keys present), so every existing caller
--      keeps resolving to exactly one function.
--
-- create_marketplace_booking, notify_on_booking_lifecycle and
-- block_listing_dates are recreated IN FULL from the live definitions; diff
-- against supabase/baseline/live_baseline.sql to see only the 151 lines.

begin;

-- ---------------------------------------------------------------------------
-- 1. instant_book
-- ---------------------------------------------------------------------------
alter table public.listings
  add column if not exists instant_book boolean not null default false;

comment on column public.listings.instant_book is
  'Bookings are created confirmed, skipping the host accept window (151).';

-- Only the insert's status and confirmed_at change.
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

  -- The hourly policy (148): the platform floor per listing type, the offered
  -- slot durations and the host's day-use window. One function holds the rule
  -- for the server and HourlyPolicy.resolve mirrors it in Dart; it is checked
  -- here, before the generic min/max, because its floor can be HIGHER than
  -- the host's own min_hours and its message says which.
  if p_pricing_unit = 'hour' then
    perform public.hourly_booking_check(p_listing_id, p_starts_at, p_ends_at);
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
    total_price, guest_count, booking_status, confirmed_at,
    listing_title, listing_image_url, listing_city,
    coupon_code, discount_amount
  ) values (
    p_listing_id, v_unit, v_uid, coalesce(p_tenant_name, ''),
    p_starts_at, p_ends_at, p_pricing_unit::pricing_unit, v_qty,
    v_total, p_guest_count,
    -- 151: an instant-book listing skips the accept window. Inserted as
    -- confirmed rather than inserted pending and then updated, because that
    -- update would run enforce_booking_update_rules as the GUEST, who may
    -- not confirm anything -- and a bypass for it is a hole every other
    -- update could reach.
    (case when v_listing.instant_book then 'confirmed' else 'pending' end)
      ::public.booking_status,
    case when v_listing.instant_book then now() end,
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

-- One new arm: INSERT + confirmed.
CREATE OR REPLACE FUNCTION public.notify_on_booking_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    listing_record RECORD;
    guest_record RECORD;
    notification_title text;
    notification_body text;
    notification_type text;
    notification_priority text;
    target_user_id uuid;
    action_url text;
BEGIN
    SELECT l.title, l.owner_id INTO listing_record
    FROM public.listings l
    WHERE l.id = NEW.listing_id;

    SELECT p.full_name INTO guest_record
    FROM public.profiles p
    WHERE p.id = NEW.tenant_id;

    CASE
        WHEN TG_OP = 'INSERT' AND NEW.booking_status = 'pending' THEN
            notification_title := 'New Booking Request';
            notification_body := format('%s wants to book %s',
                COALESCE(guest_record.full_name, 'A guest'),
                COALESCE(listing_record.title, 'your property'));
            notification_type := 'booking_request';
            notification_priority := 'high';
            target_user_id := listing_record.owner_id;
            action_url := '/host/reservations/' || NEW.id;

        -- 151: an instant booking is born confirmed. Without this arm it fell
        -- through to ELSE and the host heard nothing about a guest arriving.
        WHEN TG_OP = 'INSERT' AND NEW.booking_status = 'confirmed' THEN
            notification_title := 'New Instant Booking';
            notification_body := format('%s booked %s',
                COALESCE(guest_record.full_name, 'A guest'),
                COALESCE(listing_record.title, 'your property'));
            notification_type := 'booking_confirmed';
            notification_priority := 'high';
            target_user_id := listing_record.owner_id;
            action_url := '/host/reservations/' || NEW.id;

        WHEN TG_OP = 'UPDATE' AND OLD.booking_status = 'pending' AND NEW.booking_status = 'confirmed' THEN
            notification_title := 'Booking Confirmed!';
            notification_body := format('Your booking at %s has been confirmed',
                COALESCE(listing_record.title, 'the property'));
            notification_type := 'booking_confirmed';
            notification_priority := 'high';
            target_user_id := NEW.tenant_id;
            action_url := '/trips/' || NEW.id;

        WHEN TG_OP = 'UPDATE' AND OLD.booking_status = 'pending' AND NEW.booking_status = 'rejected' THEN
            notification_title := 'Booking Declined';
            notification_body := CASE
                WHEN NEW.rejection_reason IS NOT NULL THEN
                    format('Your booking was declined: %s', NEW.rejection_reason)
                ELSE
                    format('Your booking at %s was declined', COALESCE(listing_record.title, 'the property'))
            END;
            notification_type := 'booking_rejected';
            notification_priority := 'normal';
            target_user_id := NEW.tenant_id;
            action_url := '/trips/' || NEW.id;

        WHEN TG_OP = 'UPDATE' AND OLD.booking_status = 'confirmed' AND NEW.booking_status = 'active' THEN
            notification_title := 'Enjoy Your Stay!';
            notification_body := format('You are now checked in at %s',
                COALESCE(listing_record.title, 'the property'));
            notification_type := 'checked_in';
            notification_priority := 'normal';
            target_user_id := NEW.tenant_id;
            action_url := '/trips/' || NEW.id;

        WHEN TG_OP = 'UPDATE' AND OLD.booking_status = 'active' AND NEW.booking_status = 'completed' THEN
            notification_title := 'How Was Your Stay?';
            notification_body := format('Your stay at %s is complete. Leave a review!',
                COALESCE(listing_record.title, 'the property'));
            notification_type := 'review_prompt';
            notification_priority := 'normal';
            target_user_id := NEW.tenant_id;
            action_url := '/review/' || NEW.id || '/guest';

            INSERT INTO public.notifications (
                user_id, type, title, body, priority, action_url, data
            ) VALUES (
                target_user_id,
                notification_type::notification_type,
                notification_title,
                notification_body,
                notification_priority::notification_priority,
                action_url,
                jsonb_build_object(
                    'booking_id', NEW.id,
                    'listing_id', NEW.listing_id,
                    'listing_title', listing_record.title
                )
            );

            notification_title := 'Leave a Guest Review';
            notification_body := format('Your guest %s has checked out. Leave a review!',
                COALESCE(guest_record.full_name, 'your guest'));
            target_user_id := listing_record.owner_id;
            action_url := '/review/' || NEW.id || '/host';

        -- 140: the host reported that the guest never arrived. The guest is
        -- told in plain words; there is no review window and (see the refund
        -- policy) nothing comes back, which fn_alert_paid_cancellation says
        -- separately when the booking was paid.
        WHEN TG_OP = 'UPDATE' AND OLD.booking_status = 'confirmed' AND NEW.booking_status = 'no_show' THEN
            notification_title := 'Marked as a no-show';
            notification_body := format('The host reported that you did not arrive for your booking at %s. If that is wrong, reply to the host from Messages.',
                COALESCE(listing_record.title, 'the property'));
            notification_type := 'booking_cancelled';
            notification_priority := 'high';
            target_user_id := NEW.tenant_id;
            action_url := '/trips/' || NEW.id;

        WHEN TG_OP = 'UPDATE' AND NEW.booking_status = 'cancelled' AND NEW.cancelled_by = NEW.tenant_id THEN
            notification_title := 'Booking Cancelled';
            notification_body := format('%s cancelled their booking at %s',
                COALESCE(guest_record.full_name, 'A guest'),
                COALESCE(listing_record.title, 'your property'));
            notification_type := 'booking_cancelled';
            notification_priority := 'high';
            target_user_id := listing_record.owner_id;
            action_url := '/host/reservations/' || NEW.id;

        WHEN TG_OP = 'UPDATE' AND NEW.booking_status = 'cancelled' AND NEW.cancelled_by != NEW.tenant_id THEN
            notification_title := 'Booking Cancelled by Host';
            notification_body := format('Your booking at %s was cancelled by the host',
                COALESCE(listing_record.title, 'the property'));
            notification_type := 'booking_cancelled';
            notification_priority := 'high';
            target_user_id := NEW.tenant_id;
            action_url := '/trips/' || NEW.id;

        ELSE
            RETURN NEW;
    END CASE;

    INSERT INTO public.notifications (
        user_id, type, title, body, priority, action_url, data
    ) VALUES (
        target_user_id,
        notification_type::notification_type,
        notification_title,
        notification_body,
        notification_priority::notification_priority,
        action_url,
        jsonb_build_object(
            'booking_id', NEW.id,
            'listing_id', NEW.listing_id,
            'tenant_id', NEW.tenant_id,
            'listing_title', listing_record.title,
            'guest_name', guest_record.full_name,
            'check_in', NEW.starts_at,
            'check_out', NEW.ends_at,
            'total_price', NEW.total_price
        )
    );

    RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 2. reassign_booking_unit(booking, unit) -> the booking row.
--
--    Host (or admin) only, live bookings only (pending/confirmed/active --
--    moving a checked-in guest whose AC broke is the real case). The target
--    must be an active unit of the same listing with no unit block over the
--    stay. The target is locked `for update` (waiting) first, so a guest
--    booking that room right now either finished first or skips it (148's
--    `skip locked`). bookings_no_overlap is the backstop for a live booking
--    already on the room; its 23P01 is relabelled with hint `unit_taken`.
--
--    Definer: the overlap must be judged against other guests' bookings. The
--    body does its own owner/admin check, so it is granted to authenticated.
-- ---------------------------------------------------------------------------
create or replace function public.reassign_booking_unit(p_booking_id uuid, p_unit_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_booking public.bookings%rowtype;
  v_owner   uuid;
begin
  select * into v_booking from public.bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Booking not found' using errcode = 'P0002', hint = 'booking_not_found';
  end if;

  select owner_id into v_owner from public.listings where id = v_booking.listing_id;
  if v_owner is distinct from auth.uid() and not public.is_admin() then
    raise exception 'Only the host can move a booking to another room'
      using errcode = '42501', hint = 'not_listing_owner';
  end if;

  if v_booking.booking_status not in ('pending', 'confirmed', 'active') then
    raise exception 'A % booking cannot be moved', v_booking.booking_status
      using errcode = '22023', hint = 'booking_not_live';
  end if;
  if v_booking.unit_id = p_unit_id then
    return to_jsonb(v_booking);
  end if;

  perform 1 from public.listing_units u
   where u.id = p_unit_id and u.listing_id = v_booking.listing_id and u.is_active
   for update;
  if not found then
    raise exception 'That room is not an active room of this listing'
      using errcode = '22023', hint = 'unit_mismatch';
  end if;

  -- Listing-wide blocks need no check: the booking already sits inside them
  -- or not, whichever room it is in.
  if exists (
    select 1 from public.listing_availability_blocks blk
    where blk.unit_id = p_unit_id
      and tstzrange(blk.starts_at, blk.ends_at, '[)')
          && tstzrange(v_booking.starts_at, v_booking.ends_at, '[)')
  ) then
    raise exception 'That room is blocked for these dates'
      using errcode = '23P01', hint = 'unit_blocked';
  end if;

  perform set_config('musafir.unit_reassign', 'on', true);
  begin
    update public.bookings set unit_id = p_unit_id
     where id = p_booking_id
     returning * into v_booking;
  exception when exclusion_violation then
    raise exception 'That room already has a booking in these dates'
      using errcode = '23P01', hint = 'unit_taken';
  end;
  -- Transaction-local already; cleared so nothing later in the same
  -- transaction inherits the permission.
  perform set_config('musafir.unit_reassign', '', true);

  return to_jsonb(v_booking);
end $$;

revoke all on function public.reassign_booking_unit(uuid, uuid) from public, anon, authenticated;
grant execute on function public.reassign_booking_unit(uuid, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. block_listing_dates(..., p_unit_id). Null = the whole listing, as before.
-- ---------------------------------------------------------------------------
drop function if exists public.block_listing_dates(uuid, timestamptz, timestamptz, text);

CREATE OR REPLACE FUNCTION public.block_listing_dates(p_listing_id uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_note text DEFAULT NULL::text, p_unit_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  -- 151: a unit block names one room. It must be this listing's (the
  -- trigger checks too; this says it in a sentence), and only that room's
  -- bookings stand in its way -- blocking 104 for repairs must not be
  -- refused because 101 is occupied.
  if p_unit_id is not null and not exists (
    select 1 from public.listing_units u
    where u.id = p_unit_id and u.listing_id = p_listing_id
  ) then
    raise exception 'That room is not part of this listing'
      using errcode = '22023', hint = 'unit_mismatch';
  end if;

  if exists (
    select 1 from public.bookings b
    where b.listing_id = p_listing_id
      and (p_unit_id is null or b.unit_id = p_unit_id)
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
      (listing_id, unit_id, starts_at, ends_at, note, created_by)
    values
      (p_listing_id, p_unit_id, p_starts_at, p_ends_at,
       nullif(trim(coalesce(p_note, '')), ''), v_uid)
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
$function$;


-- The old function carried the create-time default grants (anon included).
-- The body refuses a null auth.uid(), but a definer endpoint is revoked anyway.
revoke all on function public.block_listing_dates(uuid, timestamptz, timestamptz, text, uuid) from public, anon, authenticated;
grant execute on function public.block_listing_dates(uuid, timestamptz, timestamptz, text, uuid) to authenticated, service_role;

commit;
