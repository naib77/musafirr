-- 148: the hourly booking policy (docs/plans/hotel.md §3.2).
--
-- Hourly stays had one rule: the host's min_hours/max_hours, enforced by the
-- RPC since 135. A hotel needs more than that -- a day-use room is sold in
-- 6- and 12-hour blocks, never 7 -- and the platform needs a floor the host
-- cannot undercut (a full house for one hour is a party, not a stay). Two
-- layers, both enforced by `hourly_booking_check`, which the booking RPC
-- calls for every `hour` booking:
--
--   platform  app_settings.hourly_policy  JSON, one object per listing type:
--             {"enabled", "min_hours", "slots"}. Read at booking time from
--             the table, so a stale client bundle cannot book below the floor.
--   host      listings.hourly_slots, hourly_window_start/end. The host may
--             narrow the platform's offer, never widen it.
--
-- Effective rule, mirrored exactly by HourlyPolicy.resolve in Dart
-- (lib/services/booking/hourly_policy.dart; the two share fixtures in their
-- tests):
--
--   allowed  = policy.enabled and listing.hourly_rate is not null
--   floor    = greatest(policy.min_hours, coalesce(listing.min_hours, 1))
--   slots    = coalesce(listing.hourly_slots, policy.slots)   -- null = free
--   ok       = hours >= floor and (max_hours is null or hours <= max_hours)
--              and (slots is null or hours = any(slots))
--   window   = both null, or the stay sits inside [start, end] on one
--              Asia/Dhaka calendar day
--
-- Pricing is unchanged: hourly_rate x hours (decision D1). The `hotel` key is
-- stored and validated ahead of the enum value (149) so the policy row needs
-- no second edit when the type lands.
begin;

-- ---------------------------------------------------------------------------
-- 1. The compiled defaults. One place, used by the validator (to know the
--    shape), by hourly_policy_for (when the row is absent or a type is
--    missing from it) and copied verbatim into HourlyPolicy.defaults.
-- ---------------------------------------------------------------------------
create or replace function public.hourly_policy_defaults()
returns jsonb
language sql
immutable
as $$
  select '{
    "seat":      {"enabled": true, "min_hours": 1, "slots": null},
    "room":      {"enabled": true, "min_hours": 1, "slots": null},
    "fullHouse": {"enabled": true, "min_hours": 3, "slots": null},
    "turf":      {"enabled": true, "min_hours": 1, "slots": null},
    "hotel":     {"enabled": true, "min_hours": 6, "slots": [6, 12]}
  }'::jsonb
$$;

-- ---------------------------------------------------------------------------
-- 2. Validator arm. Same contract as every other setting (097): raise 22023
--    with a sentence that names the offending value, so the admin console can
--    show it verbatim. A type missing from the object is allowed -- it falls
--    back to the default above -- but a key that is not a listing type is
--    refused, because it is almost certainly a typo of one.
-- ---------------------------------------------------------------------------
create or replace function public.fn_validate_setting_hourly_policy(p_value text)
returns void
language plpgsql
immutable
set search_path to 'public'
as $$
declare
  v_doc    jsonb;
  v_key    text;
  v_entry  jsonb;
  v_min    integer;
  v_slot   jsonb;
  v_prev   integer;
  v_n      integer;
begin
  begin
    v_doc := p_value::jsonb;
  exception when others then
    raise exception 'hourly_policy must be a JSON object' using errcode = '22023';
  end;
  if jsonb_typeof(v_doc) <> 'object' then
    raise exception 'hourly_policy must be a JSON object' using errcode = '22023';
  end if;

  for v_key, v_entry in select * from jsonb_each(v_doc) loop
    -- The enum plus 'hotel', which 149 adds; until then the literal keeps the
    -- default row storable. IMMUTABLE forbids enum_range here, so the list is
    -- spelled out -- a new listing type must be added to it.
    if v_key not in ('seat', 'room', 'fullHouse', 'turf', 'hotel') then
      raise exception 'hourly_policy: "%" is not a listing type', v_key
        using errcode = '22023';
    end if;
    if jsonb_typeof(v_entry) <> 'object' then
      raise exception 'hourly_policy: % must be an object', v_key using errcode = '22023';
    end if;
    if jsonb_typeof(v_entry -> 'enabled') is distinct from 'boolean' then
      raise exception 'hourly_policy: %.enabled must be true or false', v_key
        using errcode = '22023';
    end if;
    if jsonb_typeof(v_entry -> 'min_hours') is distinct from 'number'
       or (v_entry ->> 'min_hours') !~ '^[0-9]+$' then
      raise exception 'hourly_policy: %.min_hours must be a whole number of hours', v_key
        using errcode = '22023';
    end if;
    v_min := (v_entry ->> 'min_hours')::integer;
    if v_min < 1 or v_min > 168 then
      raise exception 'hourly_policy: %.min_hours is % — must be 1 to 168', v_key, v_min
        using errcode = '22023';
    end if;
    if v_entry ? 'slots' and jsonb_typeof(v_entry -> 'slots') <> 'null' then
      if jsonb_typeof(v_entry -> 'slots') <> 'array'
         or jsonb_array_length(v_entry -> 'slots') = 0 then
        raise exception 'hourly_policy: %.slots must be null or a list of hours', v_key
          using errcode = '22023';
      end if;
      v_prev := null;
      for v_slot in select * from jsonb_array_elements(v_entry -> 'slots') loop
        if jsonb_typeof(v_slot) <> 'number' or (v_slot #>> '{}') !~ '^[0-9]+$' then
          raise exception 'hourly_policy: %.slots holds "%", not a whole number of hours',
            v_key, v_slot #>> '{}' using errcode = '22023';
        end if;
        v_n := (v_slot #>> '{}')::integer;
        -- A slot below the floor could never be booked; one above a week is a
        -- nightly stay wearing the wrong hat.
        if v_n < v_min or v_n > 168 then
          raise exception 'hourly_policy: %.slots: % h is outside %–168 h', v_key, v_n, v_min
            using errcode = '22023';
        end if;
        -- Ascending and distinct, so the guest's chips read in order and no
        -- duration is offered twice.
        if v_prev is not null and v_n <= v_prev then
          raise exception 'hourly_policy: %.slots must ascend (% came after %)', v_key, v_n, v_prev
            using errcode = '22023';
        end if;
        v_prev := v_n;
      end loop;
    end if;
  end loop;
end;
$$;

-- Recreated in full: a CASE arm cannot be added in place
-- (docs/notes/app-settings-and-theme.md).
create or replace function public.fn_validate_app_setting()
returns trigger
language plpgsql
as $$
begin
  case new.key
    when 'search_radius_tiers_m' then
      perform public.fn_validate_setting_search_radius_tiers(new.value);
    when 'search_landmark_radius_m', 'search_nearest_fallback_limit' then
      perform public.fn_validate_setting_search_scalar(new.key, new.value);
    when 'payout_channels_enabled' then
      perform public.fn_validate_setting_payout_channels(new.value);
    when 'address_disclosure_grace_days' then
      perform public.fn_validate_setting_address_grace(new.value);
    when 'platform_commission_pct' then
      perform public.fn_validate_setting_commission_pct(new.value);
    when 'active_theme' then
      perform public.fn_validate_setting_active_theme(new.value);
    when 'booking_accept_window_hours' then
      perform public.fn_validate_setting_booking_accept_hours(new.value);
    when 'android_min_version_code' then
      perform public.fn_validate_setting_android_min_version_code(new.value);
    when 'max_devices_per_user' then
      perform public.fn_validate_setting_max_devices(new.value);
    when 'sms_bulk_max_recipients' then
      perform public.fn_validate_setting_sms_max_recipients(new.value);
    when 'notification_bulk_max_recipients' then
      perform public.fn_validate_setting_notification_max_recipients(new.value);
    when 'refund_full_window_hours' then
      perform public.fn_validate_setting_refund_window_hours(new.value);
    when 'refund_late_pct' then
      perform public.fn_validate_setting_refund_late_pct(new.value);
    when 'hourly_policy' then
      perform public.fn_validate_setting_hourly_policy(new.value);
    else
      null;
  end case;
  return new;
end;
$$;

-- The row itself, so the admin console shows a value rather than a blank and
-- an edit is an UPDATE the audit log can diff. Absent is equivalent (see
-- hourly_policy_for), so an existing row is left alone.
insert into public.app_settings (key, value)
values ('hourly_policy', public.hourly_policy_defaults()::text)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 3. The host layer. `hourly_slots` null = inherit the platform's slots (or
--    free hours); a window with one end set is meaningless, so the pair is
--    constrained together. Times are wall-clock Asia/Dhaka, like the
--    check_in_time / check_out_time text columns, but typed so the check
--    below cannot be fed "9am".
-- ---------------------------------------------------------------------------
alter table public.listings
  add column if not exists hourly_slots        integer[],
  add column if not exists hourly_window_start time,
  add column if not exists hourly_window_end   time;

alter table public.listings drop constraint if exists listings_hourly_slots_sane;
alter table public.listings add constraint listings_hourly_slots_sane check (
  hourly_slots is null
  or (cardinality(hourly_slots) between 1 and 12
      and 1 <= all(hourly_slots) and 168 >= all(hourly_slots))
);
alter table public.listings drop constraint if exists listings_hourly_window_pair;
alter table public.listings add constraint listings_hourly_window_pair check (
  (hourly_window_start is null) = (hourly_window_end is null)
  and (hourly_window_start is null or hourly_window_start < hourly_window_end)
);

-- ---------------------------------------------------------------------------
-- 4. Resolution. hourly_policy_for returns the effective platform entry for a
--    type: the stored row's object for that key, else the default. A stored
--    row that the validator would refuse today (written before 148, or by
--    hand) is treated as absent rather than trusted -- the RPC must never
--    raise a parse error at a guest.
-- ---------------------------------------------------------------------------
create or replace function public.hourly_policy_for(p_type text)
returns jsonb
language plpgsql
stable
set search_path to 'public'
as $$
declare
  v_raw   text;
  v_doc   jsonb;
  v_entry jsonb;
begin
  select value into v_raw from public.app_settings where key = 'hourly_policy';
  if v_raw is not null then
    begin
      v_doc := v_raw::jsonb;
    exception when others then
      v_doc := null;
    end;
  end if;
  v_entry := case when jsonb_typeof(v_doc) = 'object' then v_doc -> p_type end;
  if v_entry is null or jsonb_typeof(v_entry) <> 'object' then
    v_entry := public.hourly_policy_defaults() -> p_type;
  end if;
  -- An unknown type (should not happen -- listing_type is an enum) gets the
  -- loosest sane policy rather than an error.
  return coalesce(v_entry, '{"enabled": true, "min_hours": 1, "slots": null}'::jsonb);
end;
$$;

-- The rule. STABLE because it reads two tables and raises; the RPC calls it
-- with PERFORM. Every refusal is 22023 with a `hint` the client can switch on
-- (hourly_disabled / hourly_min / hourly_max / hourly_slot / hourly_window),
-- and a message written to be shown to the guest verbatim.
create or replace function public.hourly_booking_check(
  p_listing_id uuid, p_starts_at timestamptz, p_ends_at timestamptz)
returns void
language plpgsql
stable
set search_path to 'public'
as $$
declare
  v_l       public.listings%rowtype;
  v_policy  jsonb;
  v_hours   integer;
  v_floor   integer;
  v_slots   integer[];
  v_start_l timestamp;
  v_end_l   timestamp;
  v_end_t   time;
begin
  select * into v_l from public.listings where id = p_listing_id;
  if not found then
    raise exception 'Listing not found' using errcode = 'P0002';
  end if;
  v_policy := public.hourly_policy_for(v_l.listing_type::text);

  if not coalesce((v_policy ->> 'enabled')::boolean, true) then
    raise exception 'Hourly bookings are not offered for this kind of listing'
      using errcode = '22023', hint = 'hourly_disabled';
  end if;

  -- Same derivation as the RPC: whole hours from the interval, rounded, so a
  -- client cannot send 5h59m and call it 5.
  v_hours := round(extract(epoch from (p_ends_at - p_starts_at)) / 3600.0);

  v_floor := greatest(coalesce((v_policy ->> 'min_hours')::integer, 1),
                      coalesce(v_l.min_hours, 1));
  if v_hours < v_floor then
    raise exception 'Minimum booking is % hour%', v_floor, case when v_floor = 1 then '' else 's' end
      using errcode = '22023', hint = 'hourly_min';
  end if;
  if v_l.max_hours is not null and v_hours > v_l.max_hours then
    raise exception 'Maximum booking is % hour%', v_l.max_hours, case when v_l.max_hours = 1 then '' else 's' end
      using errcode = '22023', hint = 'hourly_max';
  end if;

  -- The host's list wins outright when set; otherwise the platform's. Not
  -- intersected: a host narrowing [6,12] to [6] is the common case and an
  -- intersection would make a host offering [4] on a slotted type silently
  -- offer nothing.
  if v_l.hourly_slots is not null then
    v_slots := v_l.hourly_slots;
  elsif jsonb_typeof(v_policy -> 'slots') = 'array' then
    select array_agg(x::integer order by x::integer) into v_slots
      from jsonb_array_elements_text(v_policy -> 'slots') as x;
  end if;
  if v_slots is not null and not (v_hours = any(v_slots)) then
    raise exception 'Choose one of the offered durations: % hours',
      array_to_string(v_slots, ', ')
      using errcode = '22023', hint = 'hourly_slot';
  end if;

  -- Day-use window, on one Asia/Dhaka calendar day. A stay ending exactly at
  -- midnight is "24:00" of the day it started, which `time` can hold.
  if v_l.hourly_window_start is not null then
    v_start_l := p_starts_at at time zone 'Asia/Dhaka';
    v_end_l   := p_ends_at   at time zone 'Asia/Dhaka';
    v_end_t   := case when v_end_l::time = time '00:00' and v_end_l::date = v_start_l::date + 1
                      then time '24:00' else v_end_l::time end;
    if (v_end_l::date <> v_start_l::date and v_end_t <> time '24:00')
       or v_start_l::time < v_l.hourly_window_start
       or v_end_t > v_l.hourly_window_end then
      raise exception 'Hourly stays here run between % and %',
        to_char(v_l.hourly_window_start, 'HH24:MI'), to_char(v_l.hourly_window_end, 'HH24:MI')
        using errcode = '22023', hint = 'hourly_window';
    end if;
  end if;
end;
$$;

-- Readable by everyone: the policy is public configuration (the app reads
-- the row directly) and the check only ever reads listings a guest can see.
-- The RPC is a definer so it does not need these, but a client may call the
-- check before submitting to pre-validate a selection.
grant execute on function public.hourly_policy_defaults() to anon, authenticated, service_role;
grant execute on function public.hourly_policy_for(text) to anon, authenticated, service_role;
grant execute on function public.hourly_booking_check(uuid, timestamptz, timestamptz) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. The booking RPC, 147's body plus the one call. Still the only writer.
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
commit;
