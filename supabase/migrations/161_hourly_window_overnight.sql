-- 161: an hourly window may run past midnight (22:00 -> 02:00).
--
-- 148 held the day-use window to one Asia/Dhaka calendar day: the pair
-- constraint demanded start < end and the check refused any stay whose end
-- fell on the next date (bar exactly 24:00). A host who rents by the hour at
-- night -- 10 pm to 2 am -- could not express it at all; the form said "The
-- hourly window must end after it starts" and the column would have refused
-- it anyway.
--
-- The window is now read as a clock interval that starts at `start` and runs
-- forwards to the next `end`: end > start is the same-day window it always
-- was, end < start wraps past midnight. A stay fits when, measured in
-- minutes from the window's start, it begins at offset `o` and
-- `o + duration <= window length`. That one comparison reproduces every 148
-- case (the 148 suite still passes) and admits a 01:00 start inside a
-- 22:00-02:00 window, which belongs to the previous evening's window.
--
-- start = end stays refused: it is either an empty window or "all day",
-- and "all day" is already spelled "no window". 24:00 stays legal only as an
-- end -- a window cannot start at the end of the day.
--
-- The Dart mirror (HourlyRule.refusalFor, hourlyHostFieldsError in
-- lib/services/booking/hourly_policy.dart) changes in the same commit.
-- hourly_booking_check rewritten from the LIVE definition (pg_get_functiondef,
-- 2026-10-07, identical to 148); signature unchanged, so grants are kept.

begin;

alter table public.listings drop constraint if exists listings_hourly_window_pair;
alter table public.listings add constraint listings_hourly_window_pair check (
  (hourly_window_start is null) = (hourly_window_end is null)
  and (hourly_window_start is null
       or (hourly_window_start <> hourly_window_end
           and hourly_window_start < time '24:00'))
);

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
  v_ws      numeric;
  v_we      numeric;
  v_len     numeric;
  v_off     numeric;
  v_dur     numeric;
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

  -- Day-use window, Asia/Dhaka wall clock, in minutes after midnight. The
  -- window runs forwards from its start to the next occurrence of its end:
  -- 09:00-21:00 is 720 minutes, 22:00-02:00 wraps midnight and is 240.
  -- `time '24:00'` reads as 1440, so 18:00-24:00 is 360 as before. The stay
  -- must start inside the window and finish by its end; an offset taken
  -- mod 1440 makes a start before the window land past its end, and a stay
  -- longer than the window can never fit.
  if v_l.hourly_window_start is not null then
    v_ws  := extract(epoch from v_l.hourly_window_start) / 60;
    v_we  := extract(epoch from v_l.hourly_window_end) / 60;
    v_len := case when v_we > v_ws then v_we - v_ws else 1440 - v_ws + v_we end;
    v_off := mod(extract(epoch from (p_starts_at at time zone 'Asia/Dhaka')::time) / 60
                 - v_ws + 1440, 1440);
    v_dur := extract(epoch from (p_ends_at - p_starts_at)) / 60;
    if v_off + v_dur > v_len then
      raise exception 'Hourly stays here run between % and %',
        to_char(v_l.hourly_window_start, 'HH24:MI'), to_char(v_l.hourly_window_end, 'HH24:MI')
        using errcode = '22023', hint = 'hourly_window';
    end if;
  end if;
end;
$$;

commit;
