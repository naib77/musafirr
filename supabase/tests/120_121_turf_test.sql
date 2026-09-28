-- Verification for 120_listing_type_turf.sql + 121_turf_listing_details.sql.
--
-- Mutating (it inserts listings and bookings), so it MUST run inside a
-- transaction you roll back:
--
--   begin;
--   \i supabase/tests/120_121_turf_test.sql
--   rollback;
--
-- ── Read this before running it ───────────────────────────────────────────
--
-- **120 cannot be applied in the same transaction as this file.** Postgres
-- refuses to let a new enum label be used in the transaction that added it:
--
--   55P04: unsafe use of new value "turf" of enum type listing_type
--
-- so the usual "apply and verify in one rolled-back transaction" shape is not
-- available here. The order is: apply 120, COMMIT, apply 121, then run this.
-- That is the whole reason 120 is a file containing one statement.
--
-- Before the migrations this file errors at the first 'turf' cast rather than
-- reporting FAIL -- an unmissable signal, and why row 01 checks the label
-- exists before anything else leans on it.
--
-- The load-bearing rows are 07 (two hourly slots on ONE turf on ONE day both
-- succeed -- the claim that turf needed no new booking machinery, and the
-- thing that would make a turf unusable if it were false) and 05/06 (the
-- check constraint actually refuses the junk it promises to).

create temp table res(name text, value text) on commit drop;

create temp table fixture_owner on commit drop as
  select id from public.profiles order by created_at limit 1;

-- A guest distinct from the owner, for the booking rows below. 111's
-- per-tenant exclusion constraint is per guest, so both bookings can share one.
create temp table fixture_guest on commit drop as
  select id from public.profiles order by created_at desc limit 1;

-- ── 01: the label exists ──────────────────────────────────────────────────
insert into res
select '01_enum_has_turf',
       string_agg(e.enumlabel, ',' order by e.enumsortorder)
from pg_enum e join pg_type t on t.oid = e.enumtypid
where t.typname = 'listing_type';

-- ── 02: the three columns exist ───────────────────────────────────────────
insert into res
select '02_columns_exist',
       coalesce(string_agg(column_name, ',' order by column_name), 'NONE')
from information_schema.columns
where table_schema = 'public' and table_name = 'listings'
  and column_name in ('turf_sport', 'turf_format', 'turf_surface');

-- ── Fixtures: one turf, one room, both otherwise identical ────────────────
create temp table fixture_ids(id uuid, label text) on commit drop;

with ins as (
  insert into public.listings
    (owner_id, title, description, listing_type, city, area, country,
     hourly_rate, is_active, host_available, max_guests,
     bedrooms, beds, bathrooms,
     turf_sport, turf_format, turf_surface)
  select
    (select id from fixture_owner), x.title, 'turf fixture',
    x.ltype::public.listing_type, 'Dhaka', 'Uttara', 'Bangladesh',
    1200, true, true, x.max_guests, x.bedrooms, x.beds, x.bathrooms,
    x.sport, x.fmt, x.surface
  from (values
    -- A fully described turf: every optional column stated.
    ('zz_turf_full', 'turf', 14, 0, 0, 0, 'football', '7-a-side', 'artificial'),
    -- A turf that states nothing beyond being a turf. Legal: all three are
    -- nullable, and a host who skips them has still described a bookable
    -- ground.
    ('zz_turf_bare', 'turf', 10, 0, 0, 0, null, null, null),
    -- An ordinary room, to prove the type filter separates them.
    ('zz_room', 'room', 2, 1, 1, 1, null, null, null)
  ) as x(title, ltype, max_guests, bedrooms, beds, bathrooms,
         sport, fmt, surface)
  returning id, title
)
insert into fixture_ids select id, title from ins;

-- ── 03: a turf round-trips its three columns ──────────────────────────────
insert into res
select '03_turf_roundtrip',
       coalesce(l.turf_sport || '|' || l.turf_format || '|' || l.turf_surface,
                'NULL')
from public.listings l
join fixture_ids f on f.id = l.id
where f.label = 'zz_turf_full';

-- ── 04: a bare turf is legal and stores nulls, not defaults ───────────────
insert into res
select '04_bare_turf_is_null',
       case when l.turf_sport is null and l.turf_format is null
                 and l.turf_surface is null
            then 'ALL NULL' else 'SOMETHING SET' end
from public.listings l
join fixture_ids f on f.id = l.id
where f.label = 'zz_turf_bare';

-- ── 05: a ROOM carrying a turf column is refused ──────────────────────────
-- The constraint that both host save paths depend on. If this stops raising,
-- a room can advertise itself as a football pitch.
do $$
declare v_state text := 'NO ERROR';
begin
  begin
    update public.listings set turf_sport = 'football'
    where id = (select id from fixture_ids where label = 'zz_room');
  exception when check_violation then v_state := 'REFUSED 23514';
  end;
  insert into res values ('05_room_with_turf_sport', v_state);
end $$;

-- ── 06: a turf with a sport outside the vocabulary is refused ─────────────
do $$
declare v_state text := 'NO ERROR';
begin
  begin
    update public.listings set turf_sport = 'kabaddi'
    where id = (select id from fixture_ids where label = 'zz_turf_bare');
  exception when check_violation then v_state := 'REFUSED 23514';
  end;
  insert into res values ('06_unknown_sport', v_state);
end $$;

-- ── 07: TWO hourly slots on one turf, one day, both land ──────────────────
-- The load-bearing claim of the whole feature: a turf needs no new booking
-- machinery because bookings_no_overlap (078) is a RANGE exclusion, so
-- 16:00-17:00 and 18:00-19:00 on the same listing do not collide. If this
-- fails, every turf is a one-booking-per-day listing and the feature is
-- pointless.
do $$
declare
  v_turf uuid := (select id from fixture_ids where label = 'zz_turf_full');
  v_guest uuid := (select id from fixture_guest);
  v_day timestamptz := date_trunc('day', now()) + interval '400 days';
  v_state text := 'BOTH OK';
begin
  begin
    insert into public.bookings
      (listing_id, tenant_id, booking_status, starts_at, ends_at, total_price)
    values
      (v_turf, v_guest, 'confirmed',
       v_day + interval '16 hours', v_day + interval '17 hours', 1200),
      (v_turf, v_guest, 'confirmed',
       v_day + interval '18 hours', v_day + interval '19 hours', 1200);
  exception when exclusion_violation then v_state := 'REFUSED 23P01';
  end;
  insert into res values ('07_two_slots_one_day', v_state);
end $$;

-- ── 08: back-to-back slots do not collide either ─────────────────────────
-- Every range in this schema is half-open '[)', so a slot ending exactly when
-- the next begins is legal -- which is what a turf's hourly grid is made of.
do $$
declare
  v_turf uuid := (select id from fixture_ids where label = 'zz_turf_bare');
  v_guest uuid := (select id from fixture_guest);
  v_day timestamptz := date_trunc('day', now()) + interval '401 days';
  v_state text := 'BOTH OK';
begin
  begin
    insert into public.bookings
      (listing_id, tenant_id, booking_status, starts_at, ends_at, total_price)
    values
      (v_turf, v_guest, 'confirmed',
       v_day + interval '16 hours', v_day + interval '17 hours', 1200),
      (v_turf, v_guest, 'confirmed',
       v_day + interval '17 hours', v_day + interval '18 hours', 1200);
  exception when exclusion_violation then v_state := 'REFUSED 23P01';
  end;
  insert into res values ('08_back_to_back', v_state);
end $$;

-- ── 09: an ACTUAL overlap on a turf is still refused ─────────────────────
-- The control for 07 and 08: if the constraint had simply stopped working,
-- those two would pass for the wrong reason.
do $$
declare
  v_turf uuid := (select id from fixture_ids where label = 'zz_turf_full');
  v_guest uuid := (select id from fixture_guest);
  v_day timestamptz := date_trunc('day', now()) + interval '400 days';
  v_state text := 'NOT REFUSED';
begin
  begin
    insert into public.bookings
      (listing_id, tenant_id, booking_status, starts_at, ends_at, total_price)
    values
      (v_turf, v_guest, 'confirmed',
       v_day + interval '16 hours 30 minutes',
       v_day + interval '17 hours 30 minutes', 1200);
  exception when exclusion_violation then v_state := 'REFUSED 23P01';
  end;
  insert into res values ('09_real_overlap_refused', v_state);
end $$;

-- ── 10: search finds the turfs and only the turfs ────────────────────────
-- p_property_types is text[] and the predicate casts the COLUMN to text, so
-- this needs no enum cast on the input -- the reason a build sending 'turf'
-- to a pre-120 database matched nothing instead of raising 22P02.
insert into res
select '10_search_turf_only',
       coalesce(string_agg(f.label, ',' order by f.label), 'NONE')
from public.search_listings(p_property_types => array['turf'],
                            p_limit => 100) r
join fixture_ids f on f.id = (r->>'id')::uuid;

-- ── 11: searching rooms does not return a turf ───────────────────────────
insert into res
select '11_search_room_only',
       coalesce(string_agg(f.label, ',' order by f.label), 'NONE')
from public.search_listings(p_property_types => array['room'],
                            p_limit => 100) r
join fixture_ids f on f.id = (r->>'id')::uuid;

-- ── 12: an undated, untyped search still sees both ───────────────────────
insert into res
select '12_search_all_types',
       coalesce(string_agg(f.label, ',' order by f.label), 'NONE')
from public.search_listings(p_limit => 200) r
join fixture_ids f on f.id = (r->>'id')::uuid;

-- ── 13: the seven turf amenities exist as rows ───────────────────────────
-- _saveListingFacilities matches BY NAME and silently skips an unknown one,
-- so a missing row here is an amenity a host can tick that never persists.
insert into res
select '13_turf_facilities',
       coalesce(string_agg(name, ',' order by name), 'NONE')
from public.facilities
where name in ('Floodlights', 'Changing Room', 'Showers', 'Washroom',
               'Equipment Rental', 'Covered Turf', 'Spectator Seating');

-- ── Report ───────────────────────────────────────────────────────────────
select
  case
    when name = '01_enum_has_turf'        and value = 'seat,room,fullHouse,turf'  then 'PASS'
    when name = '02_columns_exist'        and value = 'turf_format,turf_sport,turf_surface' then 'PASS'
    when name = '03_turf_roundtrip'       and value = 'football|7-a-side|artificial' then 'PASS'
    when name = '04_bare_turf_is_null'    and value = 'ALL NULL'        then 'PASS'
    when name = '05_room_with_turf_sport' and value = 'REFUSED 23514'   then 'PASS'
    when name = '06_unknown_sport'        and value = 'REFUSED 23514'   then 'PASS'
    when name = '07_two_slots_one_day'    and value = 'BOTH OK'         then 'PASS'
    when name = '08_back_to_back'         and value = 'BOTH OK'         then 'PASS'
    when name = '09_real_overlap_refused' and value = 'REFUSED 23P01'   then 'PASS'
    when name = '10_search_turf_only'     and value = 'zz_turf_bare,zz_turf_full' then 'PASS'
    when name = '11_search_room_only'     and value = 'zz_room'         then 'PASS'
    when name = '12_search_all_types'     and value = 'zz_room,zz_turf_bare,zz_turf_full' then 'PASS'
    when name = '13_turf_facilities'      and value = 'Changing Room,Covered Turf,Equipment Rental,Floodlights,Showers,Spectator Seating,Washroom' then 'PASS'
    else 'FAIL'
  end as result,
  name, value
from res order by name;
