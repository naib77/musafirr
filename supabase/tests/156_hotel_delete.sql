-- LOCAL QA fixtures only; every change rolls back. Run with
-- `sh tool/qa/run_sql_tests.sh 156` after applying 153 and 156 locally.
--
-- Pins 156: only the owner can delete a room type or a hotel; anon cannot
-- call either; deleting the type that holds the hotel's trade licence hands
-- the licence to the next-oldest type; a live booking refuses both deletes;
-- a clean hotel delete removes the hotel and every type.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
-- Runs a statement and returns the hint it raised (null if it succeeded),
-- so refusals are measured by hint, never by message text.
create function pg_temp.hint_of(stmt text) returns text language plpgsql as $$
declare h text;
begin
  execute stmt;
  return null;
exception when others then
  get stacked diagnostics h = pg_exception_hint;
  return coalesce(nullif(h, ''), sqlstate);
end $$;

\set H  '''11111111-1111-1111-1111-111111111111'''
\set P  '''bbbbbbbb-0000-0000-0000-000000000156'''
\set T1 '''cccccccc-0000-0000-0000-000000001561'''
\set T2 '''cccccccc-0000-0000-0000-000000001562'''

insert into public.properties (id, owner_id, name, area, city, country, latitude, longitude)
values (:P, :H, 'Hotel QA156', 'Kola Toli', 'QA156 City', 'Bangladesh', 10.5, 10.5);
insert into public.listings (id, owner_id, owner_name, title, description, address, city, country,
       listing_type, daily_rate, max_guests, is_active, property_id, created_at)
values (:T1, :H, 'QA Host One', 'Deluxe', 'x', 'a', 'b', 'c', 'hotel', 3000, 2, true, :P, now() - interval '2 days'),
       (:T2, :H, 'QA Host One', 'Suite',  'x', 'a', 'b', 'c', 'hotel', 5000, 2, true, :P, now() - interval '1 day');
-- The licence sits on the oldest type, as the dashboard files it.
insert into public.listing_trade_licences (listing_id, owner_id, document_path)
values (:T1, :H, 'qa156/licence.pdf');

create temp table fx on commit drop as
  select (select id from public.profiles where id <> :H limit 1) stranger,
         (select id from public.listing_units where listing_id = :T2 limit 1) unit;
grant select on fx to authenticated, anon;
select set_config('qa.stranger', (select stranger::text from fx), true);

-- A stranger.
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('qa.stranger'), 'role', 'authenticated')::text, true);
select pg_temp.check_true(
  pg_temp.hint_of(format('select public.delete_property(%L)', :P)) = 'property_owner_mismatch',
  'a stranger cannot delete the hotel');
select pg_temp.check_true(
  pg_temp.hint_of(format('select public.delete_room_type(%L)', :T1)) = 'not_listing_owner',
  'a stranger cannot delete a room type');
reset role;

set local role anon;
select pg_temp.check_true(
  pg_temp.hint_of(format('select public.delete_property(%L)', :P)) = '42501',
  'anon cannot call delete_property');
reset role;

-- The owner, the way the app does it.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select public.delete_room_type(:T1);
reset role;
select set_config('request.jwt.claims', '', true);

select pg_temp.check_true(
  (select listing_id from public.listing_trade_licences where document_path = 'qa156/licence.pdf') = :T2,
  'the licence moved to the next-oldest type');
select pg_temp.check_true(
  (select count(*) from public.listings where property_id = :P) = 1,
  'one room type left');

-- A confirmed booking on the remaining type.
insert into public.bookings (listing_id, tenant_id, unit_id, starts_at, ends_at, total_price, booking_status)
select :T2, stranger, unit, now() + interval '5 days', now() + interval '6 days', 1000, 'confirmed' from fx;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select pg_temp.check_true(
  pg_temp.hint_of(format('select public.delete_property(%L)', :P)) = 'property_has_bookings',
  'a live booking refuses the hotel delete');
select pg_temp.check_true(
  pg_temp.hint_of(format('select public.delete_room_type(%L)', :T2)) = 'listing_has_bookings',
  'a live booking refuses the room-type delete');
reset role;
select set_config('request.jwt.claims', '', true);

update public.bookings set booking_status = 'cancelled' where listing_id = :T2;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select public.delete_property(:P);
reset role;
select set_config('request.jwt.claims', '', true);

select pg_temp.check_true(
  not exists (select 1 from public.properties where id = :P)
  and not exists (select 1 from public.listings where id in (:T1, :T2)),
  'the owner deleted the hotel and every room type');

rollback;
