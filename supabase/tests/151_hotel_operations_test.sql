-- LOCAL QA fixtures only; every change rolls back. Run with
-- `sh tool/qa/run_sql_tests.sh 151` after applying 151 locally.
--
-- Pins 151: an instant-book listing's booking is born confirmed and the host
-- is told; an ordinary one still waits. reassign_booking_unit moves a booking
-- only for the host, only onto a free active room of the same listing. A unit
-- block is judged against that room's bookings alone. Refusals are checked by
-- SQLSTATE and hint, never message text.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
-- Same helpers as 150: clear the claims when dropping back, or a stale sub
-- keeps auth.uid() non-null.
create function pg_temp.as_user(uid text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims',json_build_object('sub',uid,'role','authenticated')::text,true);
perform set_config('role','authenticated',true); end $$;
create function pg_temp.as_server() returns void language plpgsql as $$
begin perform set_config('role','postgres',true); perform set_config('request.jwt.claims','{}',true); end $$;
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
create function pg_temp.book(uid text, listing uuid, starts timestamptz, ends timestamptz) returns text language plpgsql as $$
begin
  return pg_temp.try(uid, format($q$select public.create_marketplace_booking(%L,%L,%L,'hour',1,'QA')$q$, listing, starts, ends));
end $$;

-- Fixtures. As in 147/150: the booking gate is not what this file tests.
update public.app_settings set value='false' where key='face_review_enabled';
update public.profiles set verification_status='verified', nid_verified=true, suspended_at=null
 where id in ('33333333-3333-3333-3333-333333333333','77777777-0000-0000-0000-000000000001',
              '77777777-0000-0000-0000-000000000002');

\set H  '''11111111-1111-1111-1111-111111111111'''
\set GV '''33333333-3333-3333-3333-333333333333'''
\set R1 '''77777777-0000-0000-0000-000000000001'''
\set R2 '''77777777-0000-0000-0000-000000000002'''
\set HL '''aaaaaaaa-0000-0000-0000-000000000151'''
\set PL '''aaaaaaaa-0000-0000-0000-000000001510'''

insert into public.listings (id, owner_id, owner_name, title, description, address, city, country, listing_type, hourly_rate, max_guests, is_active, instant_book)
values (:HL,:H,'QA Host One','QA 151 instant hotel','x','Gulshan','Dhaka','Bangladesh','hotel',100,2,true,true),
       (:PL,:H,'QA Host One','QA 151 request hotel','x','Gulshan','Dhaka','Bangladesh','hotel',100,2,true,false);
select pg_temp.as_user(:H);
select public.set_listing_unit_count(:HL, 2);
select pg_temp.as_server();

----------------------------------------------------------------------------
-- 1. instant_book
----------------------------------------------------------------------------
select pg_temp.check_true((select column_default='false' and is_nullable='NO' from information_schema.columns
  where table_schema='public' and table_name='listings' and column_name='instant_book'),'instant_book is not null, default false');

select pg_temp.check_true(pg_temp.book(:GV,:HL,date_trunc('hour',now())+interval '50 days',date_trunc('hour',now())+interval '50 days 6 hours')='OK','instant listing: the guest books');
select pg_temp.check_true((select booking_status::text='confirmed' and confirmed_at is not null from public.bookings where listing_id=:HL and tenant_id=:GV),
  'the instant booking is born confirmed, with confirmed_at');
select pg_temp.check_true((select count(*)=1 from public.notifications n join public.bookings b on (n.data->>'booking_id')::uuid=b.id
  where b.listing_id=:HL and n.user_id=:H and n.title='New Instant Booking'),'the host is notified of the instant booking');

-- R2, not GV: bookings_no_tenant_overlap refuses one guest two stays at once.
select pg_temp.check_true(pg_temp.book(:R2,:PL,date_trunc('hour',now())+interval '50 days',date_trunc('hour',now())+interval '50 days 6 hours')='OK','request listing: the guest books');
select pg_temp.check_true((select booking_status::text='pending' and confirmed_at is null from public.bookings where listing_id=:PL and tenant_id=:R2),
  'an ordinary listing still waits for the host');

----------------------------------------------------------------------------
-- 2. reassign_booking_unit
----------------------------------------------------------------------------
-- R1 takes the other room for the same block: both rooms are now held.
select pg_temp.check_true(pg_temp.book(:R1,:HL,date_trunc('hour',now())+interval '50 days',date_trunc('hour',now())+interval '50 days 6 hours')='OK','room 2 of 2: same block');
create temp table t as
  select (select id from public.bookings where listing_id=:HL and tenant_id=:GV) as b_gv,
         (select unit_id from public.bookings where listing_id=:HL and tenant_id=:GV) as u_gv,
         (select unit_id from public.bookings where listing_id=:HL and tenant_id=:R1) as u_r1,
         (select id from public.listing_units where listing_id=:PL limit 1) as u_other;
grant select on t to authenticated;

select pg_temp.check_true(pg_temp.try(:R1,format($q$select public.reassign_booking_unit(%L,%L)$q$,(select b_gv from t),(select u_r1 from t)))='REFUSED 42501 not_listing_owner',
  'a guest cannot move a booking');
select pg_temp.check_true(pg_temp.try(:H,format($q$select public.reassign_booking_unit(%L,%L)$q$,(select b_gv from t),(select u_r1 from t)))='REFUSED 23P01 unit_taken',
  'moving onto a room already booked for those hours is refused');
select pg_temp.check_true(pg_temp.try(:H,format($q$select public.reassign_booking_unit(%L,%L)$q$,(select b_gv from t),(select u_other from t)))='REFUSED 22023 unit_mismatch',
  'moving onto another listing''s room is refused');
select pg_temp.check_true((select unit_id=(select u_gv from t) from public.bookings where id=(select b_gv from t)),'the refusals left the booking where it was');

-- Free room 2 (R1 cancels), then the move lands.
update public.bookings set booking_status='cancelled', cancelled_by=:R1 where listing_id=:HL and tenant_id=:R1;
select pg_temp.check_true(pg_temp.try(:H,format($q$select public.reassign_booking_unit(%L,%L)$q$,(select b_gv from t),(select u_r1 from t)))='OK',
  'the host moves the guest to the freed room');
select pg_temp.check_true((select unit_id=(select u_r1 from t) from public.bookings where id=(select b_gv from t)),'the booking now sits in room 2');
select pg_temp.check_true(coalesce(current_setting('musafir.unit_reassign',true),'') <> 'on','the reassign permission did not leak out of the call');
select pg_temp.check_true(pg_temp.try(:H,format($q$update public.bookings set unit_id=%L where id=%L$q$,(select u_gv from t),(select b_gv from t)))
  like 'REFUSED %','a direct unit_id write is still refused (147''s guard)');
select pg_temp.check_true(not has_function_privilege('anon','public.reassign_booking_unit(uuid,uuid)','execute'),'anon cannot execute reassign_booking_unit');

----------------------------------------------------------------------------
-- 3. block_listing_dates with a unit
----------------------------------------------------------------------------
select pg_temp.check_true((select count(*)=1 from pg_proc where proname='block_listing_dates' and pronamespace='public'::regnamespace),
  'exactly one block_listing_dates overload (PostgREST picks by keys)');
select pg_temp.check_true(not has_function_privilege('anon','public.block_listing_dates(uuid,timestamptz,timestamptz,text,uuid)','execute'),'anon cannot execute block_listing_dates');

-- Room 1 is free now (the guest moved to room 2): blocking it is accepted;
-- blocking room 2, or the whole listing, over the guest is refused.
select pg_temp.check_true(pg_temp.try(:H,format($q$select public.block_listing_dates(%L,%L,%L,'repairs',%L)$q$,
  'aaaaaaaa-0000-0000-0000-000000000151',date_trunc('hour',now())+interval '50 days',date_trunc('hour',now())+interval '50 days 6 hours',(select u_gv from t)))='OK',
  'blocking a free room while another room is booked is accepted');
select pg_temp.check_true((select unit_id=(select u_gv from t) from public.listing_availability_blocks where listing_id=:HL),'the block names the room');
select pg_temp.check_true(pg_temp.try(:H,format($q$select public.block_listing_dates(%L,%L,%L,null,%L)$q$,
  'aaaaaaaa-0000-0000-0000-000000000151',date_trunc('hour',now())+interval '50 days',date_trunc('hour',now())+interval '50 days 6 hours',(select u_r1 from t)))='REFUSED 23P01 block_over_booking',
  'blocking the booked room is refused');
select pg_temp.check_true(pg_temp.try(:H,format($q$select public.block_listing_dates(%L,%L,%L)$q$,
  'aaaaaaaa-0000-0000-0000-000000000151',date_trunc('hour',now())+interval '50 days',date_trunc('hour',now())+interval '50 days 6 hours'))='REFUSED 23P01 block_over_booking',
  'a listing-wide block over any booking is still refused (the old 3-key call resolves)');
select pg_temp.check_true(pg_temp.try(:H,format($q$select public.block_listing_dates(%L,%L,%L,null,%L)$q$,
  'aaaaaaaa-0000-0000-0000-000000000151',date_trunc('hour',now())+interval '60 days',date_trunc('hour',now())+interval '61 days',(select u_other from t)))='REFUSED 22023 unit_mismatch',
  'blocking another listing''s room is refused');
select pg_temp.check_true(public.listing_rooms_left(:HL,date_trunc('hour',now())+interval '50 days',date_trunc('hour',now())+interval '50 days 6 hours')=0,
  'one room blocked + one booked = none left');

-- And the move onto a blocked room is refused.
select pg_temp.check_true(pg_temp.try(:H,format($q$select public.reassign_booking_unit(%L,%L)$q$,(select b_gv from t),(select u_gv from t)))='REFUSED 23P01 unit_blocked',
  'moving onto a blocked room is refused');
select pg_temp.as_server();

rollback;
