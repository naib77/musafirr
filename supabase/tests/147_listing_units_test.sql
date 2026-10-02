-- LOCAL QA fixtures only; every change rolls back. Run with
-- `sh tool/qa/run_sql_tests.sh 147`.
--
-- Pins 147: the overlap rule now keys on the UNIT. A single-unit listing must
-- behave exactly as before; a multi-unit listing takes as many overlapping
-- bookings as it has free rooms, the database picks the room, and the guest
-- never names one. Every refusal is checked by SQLSTATE and `hint`, never by
-- message text (docs/notes/database-booking-and-search.md).
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

----------------------------------------------------------------------------
-- 1. Backfill and the default unit.
----------------------------------------------------------------------------
select pg_temp.check_true(not exists (select 1 from public.listings l where (select count(*) from public.listing_units u where u.listing_id=l.id) <> 1),
  'every existing listing has exactly one unit');
select pg_temp.check_true(not exists (select 1 from public.bookings b join public.listing_units u on u.id=b.unit_id where u.listing_id<>b.listing_id),
  'every existing booking sits on its own listing''s unit');
select pg_temp.check_true((select attnotnull from pg_attribute where attrelid='public.bookings'::regclass and attname='unit_id'),
  'bookings.unit_id is not null');
insert into public.listings (id, owner_id, owner_name, title, description, address, city, country, listing_type, hourly_rate, max_guests, is_active)
values ('aaaaaaaa-0000-0000-0000-000000000147','11111111-1111-1111-1111-111111111111','QA Host One','QA 147 new','x','Uttara','Dhaka','Bangladesh','seat',10,2,true);
select pg_temp.check_true((select count(*)=1 from public.listing_units where listing_id='aaaaaaaa-0000-0000-0000-000000000147'),
  'a newly inserted listing gets its one unit');

----------------------------------------------------------------------------
-- 2. A single-unit listing behaves as before. L1: HOST1's hourly seat.
----------------------------------------------------------------------------
\set L1 '''aaaaaaaa-0000-0000-0000-000000000001'''
\set L2 '''aaaaaaaa-0000-0000-0000-000000000002'''
\set GV '''33333333-3333-3333-3333-333333333333'''
\set R1 '''77777777-0000-0000-0000-000000000001'''
\set R2 '''77777777-0000-0000-0000-000000000002'''
\set R3 '''77777777-0000-0000-0000-000000000003'''
select pg_temp.check_true(pg_temp.book(:GV,:L1,now()+interval '30 days',now()+interval '30 days 2 hours','hour')='OK','single unit: first booking lands');
select pg_temp.check_true((select unit_id=(select id from public.listing_units where listing_id=:L1) from public.bookings where tenant_id=:GV and starts_at=now()+interval '30 days'),
  'single unit: the booking is pinned to the listing''s unit');
select pg_temp.check_true(pg_temp.book(:R1,:L1,now()+interval '30 days 1 hour',now()+interval '30 days 3 hours','hour')='REFUSED 23P01 listing_overlap',
  'single unit: an overlapping booking is refused as listing_overlap');
select pg_temp.check_true(pg_temp.book(:GV,:L2,now()+interval '30 days',now()+interval '31 days','day')='REFUSED 23P01 tenant_overlap',
  'the guest''s own overlap is still tenant_overlap');
select pg_temp.check_true(not public.is_booking_available(:L1,now()+interval '30 days 1 hour',now()+interval '30 days 3 hours'),'single unit: availability says no');
select pg_temp.check_true(public.is_booking_available(:L1,now()+interval '30 days 2 hours',now()+interval '30 days 3 hours'),'single unit: the adjacent slot is free');
select pg_temp.check_true(public.listing_rooms_left(:L1,now()+interval '30 days 2 hours',now()+interval '30 days 3 hours')=1,'single unit: one room left');

----------------------------------------------------------------------------
-- 3. A multi-unit listing. L2 (HOST1's daily room) becomes a 3-room hotel.
----------------------------------------------------------------------------
insert into public.listing_units (listing_id,label) values (:L2,'102'),(:L2,'103');
update public.listing_units set label='101' where listing_id=:L2 and label is null;
select pg_temp.check_true(public.listing_rooms_left(:L2,now()+interval '40 days',now()+interval '42 days')=3,'three rooms left before anyone books');
select pg_temp.check_true(pg_temp.book(:GV,:L2,now()+interval '40 days',now()+interval '42 days','day')='OK','room 1 of 3');
select pg_temp.check_true(pg_temp.book(:R1,:L2,now()+interval '41 days',now()+interval '43 days','day')='OK','room 2 of 3, overlapping');
select pg_temp.check_true(pg_temp.book(:R2,:L2,now()+interval '41 days',now()+interval '42 days','day')='OK','room 3 of 3, overlapping both');
select pg_temp.check_true((select count(distinct unit_id)=3 from public.bookings where listing_id=:L2 and starts_at>=now()+interval '40 days'),
  'the three bookings sit on three different units');
select pg_temp.check_true((select u.label='101' from public.bookings b join public.listing_units u on u.id=b.unit_id where b.tenant_id=:GV and b.listing_id=:L2 and b.starts_at=now()+interval '40 days'),
  'rooms fill lowest label first');
select pg_temp.check_true(pg_temp.book(:R3,:L2,now()+interval '41 days',now()+interval '42 days','day')='REFUSED 23P01 listing_overlap',
  'the fourth guest is refused as listing_overlap');
select pg_temp.check_true(public.listing_rooms_left(:L2,now()+interval '41 days',now()+interval '42 days')=0,'no rooms left on the full night');
select pg_temp.check_true(not public.is_booking_available(:L2,now()+interval '41 days',now()+interval '42 days'),'availability says no when full');
select pg_temp.check_true(public.listing_rooms_left(:L2,now()+interval '42 days',now()+interval '43 days')=2,'two rooms left where only one booking runs');
select pg_temp.check_true(pg_temp.book(:R3,:L2,now()+interval '42 days',now()+interval '43 days','day')='OK','and that night can be booked');
-- A rejected booking frees its room.
update public.bookings set booking_status='rejected' where tenant_id=:R2 and listing_id=:L2;
select pg_temp.check_true(public.listing_rooms_left(:L2,now()+interval '41 days',now()+interval '42 days')=1,'rejecting a booking frees its room');
-- A deactivated unit is neither counted nor assigned.
update public.listing_units set is_active=false where listing_id=:L2 and label='103';
select pg_temp.check_true(public.listing_rooms_left(:L2,now()+interval '50 days',now()+interval '51 days')=2,'an inactive unit is not counted');
select pg_temp.check_true(pg_temp.book(:GV,:L2,now()+interval '50 days',now()+interval '51 days','day')='OK','booking with one unit inactive');
select pg_temp.check_true(pg_temp.book(:R1,:L2,now()+interval '50 days',now()+interval '51 days','day')='OK','second booking with one unit inactive');
select pg_temp.check_true(pg_temp.book(:R2,:L2,now()+interval '50 days',now()+interval '51 days','day')='REFUSED 23P01 listing_overlap','an inactive unit is never assigned');
update public.listing_units set is_active=true where listing_id=:L2 and label='103';

----------------------------------------------------------------------------
-- 4. The backstop: bookings_no_overlap on unit_id, and the consistency trigger.
----------------------------------------------------------------------------
create function pg_temp.raw_insert(listing uuid, unit uuid, starts timestamptz, ends timestamptz) returns text language plpgsql as $$
declare v_state text; v_hint text; v_msg text;
begin
  insert into public.bookings (listing_id,unit_id,tenant_id,tenant_name,starts_at,ends_at,booking_status,pricing_unit,unit_count,total_price,guest_count)
  values (listing,unit,'44444444-4444-4444-4444-444444444444','QA',starts,ends,'pending','day',1,1,1);
  return 'OK';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_hint = pg_exception_hint, v_msg = message_text;
  return 'REFUSED '||v_state||' '||coalesce(v_hint,'')||' '||v_msg;
end $$;
select pg_temp.check_true(pg_temp.raw_insert(:L2,(select id from public.listing_units where listing_id=:L2 and label='101'),now()+interval '40 days',now()+interval '41 days') like 'REFUSED 23P01 %bookings_no_overlap%',
  'a raw insert on a taken unit hits bookings_no_overlap by name');
select pg_temp.check_true(pg_temp.raw_insert(:L2,(select id from public.listing_units where listing_id=:L2 and label='103'),now()+interval '40 days',now()+interval '41 days')='OK',
  'a raw insert on the free unit of the same listing is allowed');
select pg_temp.check_true(pg_temp.raw_insert(:L2,(select id from public.listing_units where listing_id=:L1),now()+interval '60 days',now()+interval '61 days')='REFUSED 22023 unit_mismatch ' || 'The unit does not belong to this listing',
  'a unit of another listing is refused');
select pg_temp.check_true(pg_temp.raw_insert(:L2,null,now()+interval '60 days',now()+interval '61 days') like 'REFUSED 22023 unit_required%',
  'a unitless insert on a multi-unit listing must name the unit');
select pg_temp.check_true(pg_temp.raw_insert(:L1,null,now()+interval '60 days',now()+interval '61 days')='OK',
  'a unitless insert on a single-unit listing is pinned to its unit (legacy writers)');
select pg_temp.check_true((select unit_id is not null from public.bookings where listing_id=:L1 and starts_at=now()+interval '60 days'),
  '…and really carries the unit');
select pg_temp.check_true(pg_temp.try(:GV, format('update public.bookings set unit_id=%L where tenant_id=%L and listing_id=%L',
    (select id from public.listing_units where listing_id=:L2 and label='103'), :GV, :L2))='REFUSED 42501 booking_columns_protected',
  'a guest cannot move their booking to another room');
do $$ begin
  begin
    update public.bookings set unit_id=(select id from public.listing_units where listing_id='aaaaaaaa-0000-0000-0000-000000000002' and label='103')
     where tenant_id='33333333-3333-3333-3333-333333333333' and listing_id='aaaaaaaa-0000-0000-0000-000000000002' and starts_at=now()+interval '40 days';
    raise exception 'FAIL: postgres moved a booking without the reassign flag';
  exception when sqlstate '42501' then
    raise notice 'PASS: even postgres needs the reassign flag to move a booking';
  end;
end $$;

----------------------------------------------------------------------------
-- 5. Blocks: listing-wide beats everything; per-unit takes one room out.
----------------------------------------------------------------------------
insert into public.listing_availability_blocks (listing_id,starts_at,ends_at,created_by) values (:L2,now()+interval '70 days',now()+interval '71 days','11111111-1111-1111-1111-111111111111');
select pg_temp.check_true(public.listing_rooms_left(:L2,now()+interval '70 days',now()+interval '71 days')=0,'a listing-wide block leaves no rooms');
select pg_temp.check_true(pg_temp.book(:GV,:L2,now()+interval '70 days',now()+interval '71 days','day')='REFUSED 22023 ','a listing-wide block keeps its own refusal (not an overlap)');
insert into public.listing_availability_blocks (listing_id,unit_id,starts_at,ends_at,created_by)
values (:L2,(select id from public.listing_units where listing_id=:L2 and label='101'),now()+interval '80 days',now()+interval '81 days','11111111-1111-1111-1111-111111111111');
select pg_temp.check_true(public.listing_rooms_left(:L2,now()+interval '80 days',now()+interval '81 days')=2,'a per-unit block takes one room out');
select pg_temp.check_true(pg_temp.book(:GV,:L2,now()+interval '80 days',now()+interval '81 days','day')='OK','…and the others still book');
select pg_temp.check_true((select u.label='102' from public.bookings b join public.listing_units u on u.id=b.unit_id where b.tenant_id=:GV and b.starts_at=now()+interval '80 days'),
  '…skipping the blocked room');
-- Two rooms may be blocked over the same nights; one room cannot be blocked twice.
insert into public.listing_availability_blocks (listing_id,unit_id,starts_at,ends_at)
values (:L2,(select id from public.listing_units where listing_id=:L2 and label='102'),now()+interval '80 days',now()+interval '81 days');
select pg_temp.check_true(true,'two different rooms blocked over the same nights');
do $$ begin
  begin
    insert into public.listing_availability_blocks (listing_id,unit_id,starts_at,ends_at)
    values ('aaaaaaaa-0000-0000-0000-000000000002',(select id from public.listing_units where listing_id='aaaaaaaa-0000-0000-0000-000000000002' and label='102'),now()+interval '80 days 6 hours',now()+interval '81 days');
    raise exception 'FAIL: the same room was blocked twice';
  exception when exclusion_violation then
    raise notice 'PASS: the same room cannot be blocked twice';
  end;
  begin
    insert into public.listing_availability_blocks (listing_id,unit_id,starts_at,ends_at)
    values ('aaaaaaaa-0000-0000-0000-000000000002',(select id from public.listing_units where listing_id='aaaaaaaa-0000-0000-0000-000000000001'),now()+interval '90 days',now()+interval '91 days');
    raise exception 'FAIL: a block named a unit of another listing';
  exception when sqlstate '22023' then
    raise notice 'PASS: a block cannot name a unit of another listing';
  end;
end $$;

----------------------------------------------------------------------------
-- 6. Access: units are the host's inventory.
----------------------------------------------------------------------------
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select pg_temp.check_true((select count(*)=0 from public.listing_units),'a guest sees no units');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select pg_temp.check_true((select count(*)=0 from public.listing_units where listing_id=:L2),'another host sees none of HOST1''s units');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select pg_temp.check_true((select count(*)=3 from public.listing_units where listing_id=:L2),'the owner sees their units');
select pg_temp.as_server();
-- 147 let the owner insert and delete units directly; 152 took that away
-- (capacity changes only through set_listing_unit_count, 150) and left the
-- label as the one writable column. Privileges refuse before RLS, so every
-- direct write below is 42501, the admin's too.
select pg_temp.check_true(pg_temp.try('11111111-1111-1111-1111-111111111111', format('insert into public.listing_units (listing_id,label) values (%L,%L)', :L2, '104')) like 'REFUSED 42501%','the owner cannot add a room directly (152)');
select pg_temp.check_true(pg_temp.try('11111111-1111-1111-1111-111111111111', 'insert into public.listing_units (listing_id,label) values (''aaaaaaaa-0000-0000-0000-000000000003'',''x'')') like 'REFUSED 42501%','not on someone else''s listing');
select pg_temp.check_true(pg_temp.try('55555555-5555-5555-5555-555555555555', 'insert into public.listing_units (listing_id,label) values (''aaaaaaaa-0000-0000-0000-000000000003'',''x'')') like 'REFUSED 42501%','nor an admin (152)');
select pg_temp.check_true(pg_temp.try('11111111-1111-1111-1111-111111111111', format('delete from public.listing_units where listing_id=%L and label=%L', :L2, '101')) like 'REFUSED 42501%','a room cannot be deleted directly (152)');
select pg_temp.check_true(pg_temp.try('11111111-1111-1111-1111-111111111111', format('update public.listing_units set label=%L where listing_id=%L and label=%L', '101A', :L2, '101'))='OK','but the owner can rename one');
set local role anon;
do $$ begin
  begin
    perform count(*) from public.listing_units;
    raise exception 'FAIL: anon can read listing_units';
  exception when insufficient_privilege then
    raise notice 'PASS: anon cannot read listing_units';
  end;
end $$;
select pg_temp.check_true(public.listing_rooms_left('aaaaaaaa-0000-0000-0000-000000000002',now()+interval '42 days',now()+interval '43 days')>=1,'anon can ask how many rooms are left');
select pg_temp.as_server();
