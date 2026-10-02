-- LOCAL QA fixtures only; every change rolls back. Run with
-- `sh tool/qa/run_sql_tests.sh 154` after applying 153 and 154 locally.
--
-- Pins 154: search_listings returns a hotel once, as its cheapest room type
-- that passes every filter, with the hotel's name and the number of types
-- that matched; a listing outside a hotel is untouched; paging counts
-- hotels, not room types.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;

\set H  '''11111111-1111-1111-1111-111111111111'''
\set P  '''bbbbbbbb-0000-0000-0000-000000000154'''
\set T1 '''cccccccc-0000-0000-0000-000000000541'''
\set T2 '''cccccccc-0000-0000-0000-000000000542'''
\set T3 '''cccccccc-0000-0000-0000-000000000543'''
\set L  '''cccccccc-0000-0000-0000-000000000544'''

-- A hotel far from every seeded listing, so a box search sees only this.
insert into public.properties (id, owner_id, name, area, city, country, latitude, longitude)
values (:P, :H, 'Hotel Sea Crown', 'Kola Toli', 'QA154 City', 'Bangladesh', 10.5, 10.5);

insert into public.listings (id, owner_id, owner_name, title, description, address, city, country,
       listing_type, daily_rate, max_guests, is_active, property_id)
values (:T1, :H, 'QA Host One', 'Super Deluxe', 'x', 'a', 'b', 'c', 'hotel', 4000, 4, true, :P),
       (:T2, :H, 'QA Host One', 'Deluxe',       'x', 'a', 'b', 'c', 'hotel', 3000, 2, true, :P),
       (:T3, :H, 'QA Host One', 'Sea Front',    'x', 'a', 'b', 'c', 'hotel', 5000, 6, true, :P);

-- A plain listing beside it, not in any hotel.
insert into public.listings (id, owner_id, owner_name, title, description, address, city, country,
       listing_type, daily_rate, max_guests, is_active, latitude, longitude)
values (:L, :H, 'QA Host One', 'Flat next door', 'x', 'a', 'QA154 City', 'c', 'room', 2000, 2, true,
        10.5, 10.5);

create temp table r on commit drop as
  select x from public.search_listings(p_ne_lat => 10.6, p_ne_lng => 10.6,
                                       p_sw_lat => 10.4, p_sw_lng => 10.4,
                                       p_limit => 50) x;

select pg_temp.check_true((select count(*) from r) = 2,
  'three room types and a flat come back as two results');
select pg_temp.check_true(
  (select x->>'id' = :T2 from r where x->>'property_id' = :P),
  'the hotel is shown as its cheapest room type');
select pg_temp.check_true(
  (select x->>'property_name' = 'Hotel Sea Crown' and (x->>'room_types_matching')::int = 3
     from r where x->>'property_id' = :P),
  'the row names the hotel and counts its matching types');
select pg_temp.check_true(
  (select x->'property_name' = 'null'::jsonb and x->'room_types_matching' = 'null'::jsonb
     from r where x->>'id' = :L),
  'a listing outside a hotel carries no hotel keys');

-- Filters apply before the collapse: a party of 4 rules out the cheap
-- Deluxe (2 guests), so the hotel is shown from the next type that fits.
select pg_temp.check_true(
  (select x->>'id' = :T1 and (x->>'room_types_matching')::int = 2
     from public.search_listings(p_guest_count => 4,
                                 p_ne_lat => 10.6, p_ne_lng => 10.6,
                                 p_sw_lat => 10.4, p_sw_lng => 10.4) x
    where x->>'property_id' = :P),
  'the price shown is the cheapest type that fits the party');

-- Paging counts hotels: limit 1 / offset 1 returns the second result, never
-- a second room type of the first hotel.
select pg_temp.check_true(
  (select count(*) from (
     select x->>'id' id from public.search_listings(p_ne_lat => 10.6, p_ne_lng => 10.6,
             p_sw_lat => 10.4, p_sw_lng => 10.4, p_limit => 1, p_offset => 0) x
     union all
     select x->>'id' from public.search_listings(p_ne_lat => 10.6, p_ne_lng => 10.6,
             p_sw_lat => 10.4, p_sw_lng => 10.4, p_limit => 1, p_offset => 1) x
   ) s where s.id in (:T1, :T2, :T3)) = 1,
  'two pages of one never show the same hotel twice');

-- Anon sees the same collapse (the hotel name comes through RLS).
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select pg_temp.check_true(
  (select count(*) = 2 and bool_or(x->>'property_name' = 'Hotel Sea Crown')
     from public.search_listings(p_ne_lat => 10.6, p_ne_lng => 10.6,
                                 p_sw_lat => 10.4, p_sw_lng => 10.4) x),
  'a signed-out guest sees one card per hotel, with its name');
reset role;
select set_config('request.jwt.claims', '{}', true);

rollback;
