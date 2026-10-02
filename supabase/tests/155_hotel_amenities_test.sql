-- LOCAL QA fixtures only; every change rolls back. Run with
-- `sh tool/qa/run_sql_tests.sh 155` after applying 153 and 155 locally.
--
-- Pins 155: a hotel's amenities are copied onto every room type, survive the
-- app's delete-all-then-insert save, follow the hotel when it removes one,
-- reach a room type added later, and only the hotel's owner can set them.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;

\set H  '''11111111-1111-1111-1111-111111111111'''
\set P  '''bbbbbbbb-0000-0000-0000-000000000155'''
\set T1 '''cccccccc-0000-0000-0000-000000000551'''
\set T2 '''cccccccc-0000-0000-0000-000000000552'''
\set T3 '''cccccccc-0000-0000-0000-000000000553'''

create temp table fx on commit drop as
  select (select id from public.facilities where name = 'Gym') gym,
         (select id from public.facilities where name = 'Restaurant') rest,
         (select id from public.facilities where name = 'Wi-Fi') wifi,
         (select id from public.facilities where name = 'Kettle') kettle;
grant select on fx to authenticated;

select pg_temp.check_true(
  (select count(*) from public.facilities where name in
     ('Kettle','Toiletries','Slippers','Hairdryer','Iron','Minibar','Telephone',
      'Bathtub','Tour Desk','Wheelchair Accessible','Event Hall',
      'Family Friendly','Beach Access')) = 13,
  'the thirteen new amenities exist');

insert into public.properties (id, owner_id, name, area, city, country, latitude, longitude)
values (:P, :H, 'Hotel Sea Crown', 'Kola Toli', 'QA155 City', 'Bangladesh', 10.5, 10.5);
insert into public.listings (id, owner_id, owner_name, title, description, address, city, country,
       listing_type, daily_rate, max_guests, is_active, property_id)
values (:T1, :H, 'QA Host One', 'Deluxe',       'x', 'a', 'b', 'c', 'hotel', 3000, 2, true, :P),
       (:T2, :H, 'QA Host One', 'Super Deluxe', 'x', 'a', 'b', 'c', 'hotel', 4000, 4, true, :P);
insert into public.listing_facilities (listing_id, facility_id)
select :T1::uuid, wifi from fx;

-- As the host, the way the app does it.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

insert into public.property_facilities (property_id, facility_id)
select :P::uuid, gym from fx union all select :P::uuid, rest from fx;

select pg_temp.check_true(
  (select count(*) from public.listing_facilities lf, fx
    where lf.listing_id in (:T1, :T2) and lf.facility_id in (fx.gym, fx.rest)) = 4,
  'the hotel''s amenities reach every room type');

-- _saveListingFacilities: delete all, insert the ticked ones. The room-type
-- form shows only in-room amenities, so it re-sends Wi-Fi and a Kettle.
delete from public.listing_facilities where listing_id = :T1;
insert into public.listing_facilities (listing_id, facility_id)
select :T1::uuid, wifi from fx union all select :T1::uuid, kettle from fx;

select pg_temp.check_true(
  (select array_agg(f.name order by f.name) from public.listing_facilities lf
     join public.facilities f on f.id = lf.facility_id where lf.listing_id = :T1)
  = array['Gym','Kettle','Restaurant','Wi-Fi'],
  'a room-type save keeps the hotel''s amenities and its own');

-- An older bundle re-sends the hotel's amenities too: skipped, not 23505.
delete from public.listing_facilities where listing_id = :T2;
insert into public.listing_facilities (listing_id, facility_id)
select :T2::uuid, gym from fx union all select :T2::uuid, rest from fx;
select pg_temp.check_true(
  (select count(*) from public.listing_facilities where listing_id = :T2) = 2,
  're-sending a hotel amenity is skipped, not refused');

-- The hotel drops the restaurant: gone from every room type.
delete from public.property_facilities pf using fx
 where pf.property_id = :P and pf.facility_id = fx.rest;
select pg_temp.check_true(
  (select count(*) from public.listing_facilities lf, fx
    where lf.listing_id in (:T1, :T2) and lf.facility_id = fx.rest) = 0,
  'removing an amenity from the hotel removes it from its room types');

-- A room type added later starts with the hotel's amenities. (Inserted as
-- postgres: the listings insert policy wants a verified host, which the
-- fixture host is not; the trigger does not care who inserts.)
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into public.listings (id, owner_id, owner_name, title, description, address, city, country,
       listing_type, daily_rate, max_guests, is_active, property_id)
values (:T3, :H, 'QA Host One', 'Sea Front', 'x', 'a', 'b', 'c', 'hotel', 5000, 6, true, :P);
select pg_temp.check_true(
  (select count(*) from public.listing_facilities lf, fx
    where lf.listing_id = :T3 and lf.facility_id = fx.gym) = 1,
  'a new room type gets the hotel''s amenities');
set local role authenticated;

-- Another host cannot add to or strip this hotel.
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
delete from public.property_facilities where property_id = :P;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select pg_temp.check_true(
  (select count(*) from public.property_facilities where property_id = :P) = 1,
  'another host''s delete changes nothing');
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
do $$ begin
  insert into public.property_facilities (property_id, facility_id)
  select 'bbbbbbbb-0000-0000-0000-000000000155'::uuid, wifi from fx;
  raise exception 'FAIL: another host added an amenity';
exception when insufficient_privilege then
  raise notice 'PASS: another host cannot add an amenity';
end $$;

-- A guest sees the hotel's amenities (the hotel has live room types).
reset role;
select set_config('request.jwt.claims', '{}', true);
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select pg_temp.check_true(
  (select count(*) from public.property_facilities where property_id = :P) = 1,
  'a signed-out guest sees the hotel''s amenities');
reset role;
select set_config('request.jwt.claims', '{}', true);

-- Deleting a room type still deletes its amenities (the guard lets a
-- cascade through: the listing is already gone).
delete from public.listings where id = :T3;
select pg_temp.check_true(
  (select count(*) from public.listing_facilities where listing_id = :T3) = 0,
  'deleting a room type deletes its amenity rows');

rollback;
