-- LOCAL QA fixtures only; every change rolls back. Run with
-- `sh tool/qa/run_sql_tests.sh 150` -- AFTER 149 is committed (55P04: a
-- 'hotel' fixture cannot share a transaction with the label's creation).
--
-- Pins 150: the hotel-only fields are refused on any other type, the Room
-- Matrix facts are not; the ten amenity names match the Dart catalog; and
-- set_listing_unit_count grows by reactivating first, shrinks only free
-- rooms, all-or-nothing, owner or admin only. Refusals are checked by
-- SQLSTATE and hint, never message text.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
-- Impersonation helpers. Clearing the claims when dropping back matters: a
-- stale sub keeps auth.uid() non-null (see the 132 note in CLAUDE.md).
create function pg_temp.as_user(uid text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims',json_build_object('sub',uid,'role','authenticated')::text,true);
perform set_config('role','authenticated',true); end $$;
create function pg_temp.as_server() returns void language plpgsql as $$
begin perform set_config('role','postgres',true); perform set_config('request.jwt.claims','{}',true); end $$;
-- Run one statement as a user; answer 'OK' or 'REFUSED <sqlstate> <hint>'. A
-- success is KEPT (the whole file rolls back at the end), because the next
-- step usually needs the booking the previous one made. The hint is read from
-- PG_EXCEPTION_DETAIL's sibling, exactly what PostgREST hands the client.
create function pg_temp.try(uid text, statement text) returns text language plpgsql as $$
declare v_hint text; v_state text;
begin
  perform pg_temp.as_user(uid);
  begin
    execute statement;
    perform pg_temp.as_server();
    return 'OK';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_hint = pg_exception_hint;
    perform pg_temp.as_server();
    return 'REFUSED '||v_state||' '||coalesce(v_hint,'');
  end;
end $$;
create function pg_temp.book(uid text, listing uuid, starts timestamptz, ends timestamptz, unit text) returns text language plpgsql as $$
begin
  return pg_temp.try(uid, format($q$select public.create_marketplace_booking(%L,%L,%L,%L,1,'QA')$q$, listing, starts, ends, unit));
end $$;

-- Fixtures. The seed's verified guest has no approved document and the
-- racers none at all; the booking gate is not what this file tests.
update public.app_settings set value='false' where key='face_review_enabled';
update public.profiles set verification_status='verified', nid_verified=true, suspended_at=null
 where id in ('33333333-3333-3333-3333-333333333333','77777777-0000-0000-0000-000000000001',
              '77777777-0000-0000-0000-000000000002','77777777-0000-0000-0000-000000000003');
select pg_temp.check_true(public.has_approved_face_or_identity('33333333-3333-3333-3333-333333333333'),'fixture guest can book');

-- Fixtures. As in 147: the booking gate is not what this file tests.
update public.app_settings set value='false' where key='face_review_enabled';
update public.profiles set verification_status='verified', nid_verified=true, suspended_at=null
 where id in ('33333333-3333-3333-3333-333333333333','77777777-0000-0000-0000-000000000001',
              '77777777-0000-0000-0000-000000000002','77777777-0000-0000-0000-000000000003');

\set H  '''11111111-1111-1111-1111-111111111111'''
\set GV '''33333333-3333-3333-3333-333333333333'''
\set R1 '''77777777-0000-0000-0000-000000000001'''
\set R2 '''77777777-0000-0000-0000-000000000002'''
\set R3 '''77777777-0000-0000-0000-000000000003'''
\set HL '''aaaaaaaa-0000-0000-0000-000000000150'''

----------------------------------------------------------------------------
-- 1. Columns and their guards.
----------------------------------------------------------------------------
insert into public.listings (id, owner_id, owner_name, title, description, address, city, country, listing_type, hourly_rate, max_guests, is_active,
                             hotel_star_rating, hotel_front_desk_24h, hotel_id_required, size_sqft, bathroom_kind, toilet_kind)
values (:HL,:H,'QA Host One','QA 150 hotel','x','Gulshan','Dhaka','Bangladesh','hotel',100,2,true, 3,true,true, 180,'attached','commode');
select pg_temp.check_true((select listing_type::text='hotel' and hotel_star_rating=3 from public.listings where id=:HL),'a hotel stores its star rating');

create function pg_temp.refused(statement text) returns text language plpgsql as $$
begin execute statement; return 'OK';
exception when others then return 'REFUSED '||sqlstate; end $$;
select pg_temp.check_true(pg_temp.refused($q$update public.listings set listing_type='room' where id='aaaaaaaa-0000-0000-0000-000000000150'$q$)='REFUSED 23514',
  'switching a hotel to room while it still carries hotel fields is refused');
select pg_temp.check_true(pg_temp.refused($q$update public.listings set listing_type='room', hotel_star_rating=null, hotel_front_desk_24h=null, hotel_id_required=null where id='aaaaaaaa-0000-0000-0000-000000000150'$q$)='OK',
  'the same switch with the hotel fields cleared is accepted');
select pg_temp.check_true((select size_sqft=180 and toilet_kind='commode' from public.listings where id=:HL),
  'Room Matrix facts survive a type change: they describe any stay');
update public.listings set listing_type='hotel', hotel_star_rating=3 where id=:HL;
select pg_temp.check_true(pg_temp.refused($q$update public.listings set hotel_star_rating=6 where id='aaaaaaaa-0000-0000-0000-000000000150'$q$)='REFUSED 23514','six stars is refused');
select pg_temp.check_true(pg_temp.refused($q$update public.listings set size_sqft=0 where id='aaaaaaaa-0000-0000-0000-000000000150'$q$)='REFUSED 23514','zero square feet is refused');
select pg_temp.check_true(pg_temp.refused($q$update public.listings set toilet_kind='bucket' where id='aaaaaaaa-0000-0000-0000-000000000150'$q$)='REFUSED 23514','an unknown toilet kind is refused');
select pg_temp.check_true(pg_temp.refused($q$update public.listings set bathroom_kind='shared' where id='aaaaaaaa-0000-0000-0000-000000000150'$q$)='REFUSED 23514','an unknown bathroom kind is refused');

----------------------------------------------------------------------------
-- 2. Amenity rows, by the exact names the Dart catalog uses.
----------------------------------------------------------------------------
select pg_temp.check_true((select count(*)=10 from public.facilities where name in
  ('24h Front Desk','Room Service','Restaurant','Breakfast Included','Housekeeping','Gym','Airport Pickup','Luggage Storage','In-room Safe','Keycard Access')),
  'all ten hotel amenities exist');

----------------------------------------------------------------------------
-- 3. set_listing_unit_count: who may call it, and the bounds.
----------------------------------------------------------------------------
select pg_temp.check_true(pg_temp.try(:R1,$q$select public.set_listing_unit_count('aaaaaaaa-0000-0000-0000-000000000150',3)$q$)='REFUSED 42501 not_listing_owner',
  'a stranger cannot resize the host''s listing');
select pg_temp.check_true(pg_temp.try(:H,$q$select public.set_listing_unit_count('aaaaaaaa-0000-0000-0000-000000000150',0)$q$)='REFUSED 22023 unit_count_range','zero units is refused');
select pg_temp.check_true(pg_temp.try(:H,$q$select public.set_listing_unit_count('aaaaaaaa-0000-0000-0000-000000000150',501)$q$)='REFUSED 22023 unit_count_range','501 units is refused');
select pg_temp.check_true(pg_temp.try(:H,$q$select public.set_listing_unit_count('aaaaaaaa-0000-0000-0000-000000000150',5)$q$)='OK','the host grows the hotel to five rooms');
select pg_temp.check_true((select count(*)=5 from public.listing_units where listing_id=:HL and is_active),'five active units');
select pg_temp.check_true(not has_function_privilege('anon','public.set_listing_unit_count(uuid,integer)','execute'),'anon cannot execute set_listing_unit_count');
select pg_temp.check_true(not has_function_privilege('anon','public.listing_unit_count(uuid)','execute'),'anon cannot execute listing_unit_count');
select pg_temp.as_user(:H);
select pg_temp.check_true(public.listing_unit_count(:HL)=5,'the host reads the count');
select pg_temp.as_user(:R1);
select pg_temp.check_true(public.listing_unit_count(:HL)=0,'a stranger reads zero: units are RLS-gated');
select pg_temp.as_server();

----------------------------------------------------------------------------
-- 4. Three guests take three of the five rooms for the same day-use block;
--    the hotel policy (6h floor, slots 6/12) applies to the new type.
----------------------------------------------------------------------------
select pg_temp.check_true(pg_temp.book(:GV,:HL,date_trunc('hour',now())+interval '40 days',date_trunc('hour',now())+interval '40 days 6 hours','hour')='OK','room 1 of 5: a 6h block');
select pg_temp.check_true(pg_temp.book(:R1,:HL,date_trunc('hour',now())+interval '40 days',date_trunc('hour',now())+interval '40 days 6 hours','hour')='OK','room 2 of 5: same block');
select pg_temp.check_true(pg_temp.book(:R2,:HL,date_trunc('hour',now())+interval '40 days',date_trunc('hour',now())+interval '40 days 6 hours','hour')='OK','room 3 of 5: same block');
select pg_temp.check_true(pg_temp.book(:R3,:HL,date_trunc('hour',now())+interval '41 days',date_trunc('hour',now())+interval '41 days 7 hours','hour') like 'REFUSED 22023 hourly_%',
  'a 7h stay on a hotel is refused by the hotel slot rule');
select pg_temp.check_true(public.listing_rooms_left(:HL,date_trunc('hour',now())+interval '40 days',date_trunc('hour',now())+interval '40 days 6 hours')=2,'two rooms left for that block');

----------------------------------------------------------------------------
-- 5. Shrinking only retires free rooms, and is all-or-nothing.
----------------------------------------------------------------------------
select pg_temp.check_true(pg_temp.try(:H,$q$select public.set_listing_unit_count('aaaaaaaa-0000-0000-0000-000000000150',2)$q$)='REFUSED 22023 units_in_use',
  'shrinking below the booked rooms is refused');
select pg_temp.check_true((select count(*)=5 from public.listing_units where listing_id=:HL and is_active),'a refused shrink changes nothing (still five)');
select pg_temp.check_true(pg_temp.try(:H,$q$select public.set_listing_unit_count('aaaaaaaa-0000-0000-0000-000000000150',3)$q$)='OK','shrinking to the booked count is accepted');
select pg_temp.check_true(not exists (select 1 from public.bookings b join public.listing_units u on u.id=b.unit_id where b.listing_id=:HL and not u.is_active),
  'no booking was left on a retired unit');
select pg_temp.check_true((select count(*)=5 from public.listing_units where listing_id=:HL),'retired units are kept, not deleted');
select pg_temp.check_true(public.listing_rooms_left(:HL,date_trunc('hour',now())+interval '40 days',date_trunc('hour',now())+interval '40 days 6 hours')=0,'that block is now full');

----------------------------------------------------------------------------
-- 6. Growing again reuses the retired rows before inserting.
----------------------------------------------------------------------------
select pg_temp.check_true(pg_temp.try(:H,$q$select public.set_listing_unit_count('aaaaaaaa-0000-0000-0000-000000000150',6)$q$)='OK','grow to six');
select pg_temp.check_true((select count(*)=6 from public.listing_units where listing_id=:HL),'two reactivated + one new = six rows, not eight');
select pg_temp.check_true((select count(*)=6 from public.listing_units where listing_id=:HL and is_active),'all six active');
select pg_temp.as_server();

rollback;
