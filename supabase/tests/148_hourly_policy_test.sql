-- LOCAL QA fixtures only; every change rolls back. Run with
-- `sh tool/qa/run_sql_tests.sh 148`.
--
-- Pins 148: the hourly policy. The platform floor beats the host's min_hours,
-- a slotted type takes only its slots, the host may narrow but not widen,
-- the day-use window is Asia/Dhaka wall clock (161: it may wrap midnight), and a disabled type is refused
-- even with a rate set. Refusals are checked by SQLSTATE and `hint`, never
-- by message text. The fixture table in section 3 is the same one
-- test/services/hourly_policy_test.dart feeds HourlyPolicy.resolve.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
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
-- Same, as postgres: for settings writes, which RLS keeps from any user.
create function pg_temp.try_server(statement text) returns text language plpgsql as $$
declare v_state text; v_msg text;
begin
  begin
    execute statement;
    return 'OK';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return 'REFUSED '||v_state||' '||v_msg;
  end;
end $$;
create function pg_temp.book(uid text, listing uuid, starts timestamptz, hours int) returns text language plpgsql as $$
begin
  return pg_temp.try(uid, format($q$select public.create_marketplace_booking(%L,%L,%L,'hour',1,'QA')$q$, listing, starts, starts + make_interval(hours => hours)));
end $$;
create function pg_temp.set_policy(doc text) returns text language plpgsql as $$
begin
  return pg_temp.try_server(format('update public.app_settings set value=%L where key=%L', doc, 'hourly_policy'));
end $$;
-- A Dhaka wall-clock instant on a fixed future day: the window rule is
-- about local time, so the fixtures must not depend on the server's zone.
create function pg_temp.dhaka(day date, t time) returns timestamptz language sql immutable as $$
  select (day + t) at time zone 'Asia/Dhaka' $$;

update public.app_settings set value='false' where key='face_review_enabled';
update public.profiles set verification_status='verified', nid_verified=true, suspended_at=null
 where id in ('33333333-3333-3333-3333-333333333333','77777777-0000-0000-0000-000000000001',
              '77777777-0000-0000-0000-000000000002','77777777-0000-0000-0000-000000000003');
\set L1 '''aaaaaaaa-0000-0000-0000-000000000001'''
\set L2 '''aaaaaaaa-0000-0000-0000-000000000002'''
\set L3 '''aaaaaaaa-0000-0000-0000-000000000003'''
\set GV '''33333333-3333-3333-3333-333333333333'''
\set R1 '''77777777-0000-0000-0000-000000000001'''
\set R2 '''77777777-0000-0000-0000-000000000002'''
-- L1: HOST1 seat, hourly 10, min 1 max 12. L2: HOST1 room, hourly 150, no
-- limits. L3: HOST2 turf, hourly 2000, min 1 max 3. L5 (new): HOST1 full
-- house with an hourly rate and no host limits -- the platform floor alone.
insert into public.listings (id, owner_id, owner_name, title, description, address, city, country, listing_type, hourly_rate, daily_rate, max_guests, is_active)
values ('aaaaaaaa-0000-0000-0000-000000000148','11111111-1111-1111-1111-111111111111','QA Host One','QA 148 house','x','Uttara','Dhaka','Bangladesh','fullHouse',500,5000,6,true);
\set L5 '''aaaaaaaa-0000-0000-0000-000000000148'''

----------------------------------------------------------------------------
-- 1. Defaults and resolution.
----------------------------------------------------------------------------
select pg_temp.check_true((select value::jsonb = public.hourly_policy_defaults() from public.app_settings where key='hourly_policy'),
  'the hourly_policy row is seeded with the defaults');
select pg_temp.check_true(public.hourly_policy_for('hotel') = '{"enabled":true,"min_hours":6,"slots":[6,12]}'::jsonb,'hotel resolves to 6h floor, slots 6/12');
select pg_temp.check_true(public.hourly_policy_for('fullHouse') ->> 'min_hours' = '3','full house floor is 3h');
select pg_temp.check_true(public.hourly_policy_for('seat') = '{"enabled":true,"min_hours":1,"slots":null}'::jsonb,'seat is free hours from 1');
-- A type missing from the stored row falls back to its default, not to null.
select pg_temp.check_true(pg_temp.set_policy('{"seat":{"enabled":true,"min_hours":2,"slots":null}}')='OK','a partial policy is storable');
select pg_temp.check_true(public.hourly_policy_for('seat') ->> 'min_hours' = '2' and public.hourly_policy_for('hotel') ->> 'min_hours' = '6',
  'stored types override, missing types fall back to defaults');
-- A corrupt row (written past the validator) is treated as absent.
alter table public.app_settings disable trigger user;
update public.app_settings set value='not json' where key='hourly_policy';
alter table public.app_settings enable trigger user;
select pg_temp.check_true(public.hourly_policy_for('seat') ->> 'min_hours' = '1','a corrupt policy row reads as the defaults');
update public.app_settings set value=public.hourly_policy_defaults()::text where key='hourly_policy';

----------------------------------------------------------------------------
-- 2. The validator refuses what the RPC could not read.
----------------------------------------------------------------------------
select pg_temp.check_true(pg_temp.set_policy('garbage') like 'REFUSED 22023%','not JSON is refused');
select pg_temp.check_true(pg_temp.set_policy('[1,2]') like 'REFUSED 22023%','a JSON array is refused');
select pg_temp.check_true(pg_temp.set_policy('{"flat":{"enabled":true,"min_hours":1}}') like 'REFUSED 22023%flat%','an unknown type is named in the refusal');
select pg_temp.check_true(pg_temp.set_policy('{"seat":{"enabled":"yes","min_hours":1}}') like 'REFUSED 22023%','enabled must be boolean');
select pg_temp.check_true(pg_temp.set_policy('{"seat":{"enabled":true,"min_hours":0}}') like 'REFUSED 22023%','min_hours 0 is refused');
select pg_temp.check_true(pg_temp.set_policy('{"seat":{"enabled":true,"min_hours":2.5}}') like 'REFUSED 22023%','a fractional floor is refused');
select pg_temp.check_true(pg_temp.set_policy('{"seat":{"enabled":true,"min_hours":200}}') like 'REFUSED 22023%','a floor over a week is refused');
select pg_temp.check_true(pg_temp.set_policy('{"hotel":{"enabled":true,"min_hours":6,"slots":[3,6]}}') like 'REFUSED 22023%','a slot below the floor is refused');
select pg_temp.check_true(pg_temp.set_policy('{"hotel":{"enabled":true,"min_hours":6,"slots":[12,6]}}') like 'REFUSED 22023%','slots must ascend');
select pg_temp.check_true(pg_temp.set_policy('{"hotel":{"enabled":true,"min_hours":6,"slots":[6,6]}}') like 'REFUSED 22023%','a repeated slot is refused');
select pg_temp.check_true(pg_temp.set_policy('{"hotel":{"enabled":true,"min_hours":6,"slots":[]}}') like 'REFUSED 22023%','an empty slot list is refused (use null)');
select pg_temp.check_true(pg_temp.set_policy('{"hotel":{"enabled":true,"min_hours":6,"slots":["6"]}}') like 'REFUSED 22023%','a string slot is refused');
select pg_temp.check_true(pg_temp.set_policy('{"hotel":{"enabled":false,"min_hours":6,"slots":null}}')='OK','a valid narrowing is accepted');
select pg_temp.check_true(pg_temp.set_policy(public.hourly_policy_defaults()::text)='OK','the defaults themselves validate');

----------------------------------------------------------------------------
-- 3. The rule, through the RPC. One row per fixture line in the Dart test.
----------------------------------------------------------------------------
-- seat L1, host 1..12, platform floor 1, free hours
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-01','10:00'),1)='OK','seat: 1h within host 1..12 is fine');
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-02','08:00'),13)='REFUSED 22023 hourly_max','seat: 13h over the host max');
-- platform floor above the host min: the host's 1 is clamped up to 2
select pg_temp.check_true(pg_temp.set_policy('{"seat":{"enabled":true,"min_hours":2,"slots":null}}')='OK','raise the seat floor to 2h');
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-03','10:00'),1)='REFUSED 22023 hourly_min','seat: 1h under the platform floor although the host allows it');
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-03','10:00'),2)='OK','seat: 2h meets the raised floor');
-- a host min above the platform floor is honoured
update public.listings set min_hours=4 where id=:L1;
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-04','10:00'),3)='REFUSED 22023 hourly_min','seat: host min 4 beats platform floor 2');
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-04','10:00'),4)='OK','seat: 4h meets the host min');
update public.listings set min_hours=1 where id=:L1;
select pg_temp.set_policy(public.hourly_policy_defaults()::text);
-- full house L5: no host limits, platform floor 3
select pg_temp.check_true(pg_temp.book(:GV,:L5,pg_temp.dhaka('2026-12-05','10:00'),2)='REFUSED 22023 hourly_min','full house: 2h under the 3h floor with no host limits');
select pg_temp.check_true(pg_temp.book(:GV,:L5,pg_temp.dhaka('2026-12-05','10:00'),3)='OK','full house: 3h is the floor');
-- disabled type: a rate is not an offer
select pg_temp.check_true(pg_temp.set_policy('{"turf":{"enabled":false,"min_hours":1,"slots":null}}')='OK','switch turf hourly off');
select pg_temp.check_true(pg_temp.book(:GV,:L3,pg_temp.dhaka('2026-12-06','10:00'),2)='REFUSED 22023 hourly_disabled','turf: refused while disabled although hourly_rate is set');
select pg_temp.set_policy(public.hourly_policy_defaults()::text);
select pg_temp.check_true(pg_temp.book(:GV,:L3,pg_temp.dhaka('2026-12-06','10:00'),2)='OK','turf: bookable again once enabled');
-- platform slots: room gets [6,12]
select pg_temp.check_true(pg_temp.set_policy('{"room":{"enabled":true,"min_hours":6,"slots":[6,12]}}')='OK','slot the room type');
select pg_temp.check_true(pg_temp.book(:GV,:L2,pg_temp.dhaka('2026-12-07','08:00'),7)='REFUSED 22023 hourly_slot','room: 7h is not a slot');
select pg_temp.check_true(pg_temp.book(:GV,:L2,pg_temp.dhaka('2026-12-07','08:00'),6)='OK','room: 6h is a slot');
select pg_temp.check_true(pg_temp.book(:GV,:L2,pg_temp.dhaka('2026-12-08','08:00'),12)='OK','room: 12h is a slot');
-- host narrows the slots: [6] only
update public.listings set hourly_slots='{6}' where id=:L2;
select pg_temp.check_true(pg_temp.book(:GV,:L2,pg_temp.dhaka('2026-12-09','08:00'),12)='REFUSED 22023 hourly_slot','room: host dropped the 12h slot');
select pg_temp.check_true(pg_temp.book(:GV,:L2,pg_temp.dhaka('2026-12-09','08:00'),6)='OK','room: the kept slot still books');
-- host slots on a free-hours type
update public.listings set hourly_slots='{2,4}' where id=:L1;
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-10','10:00'),3)='REFUSED 22023 hourly_slot','seat: host slots [2,4] refuse 3h');
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-10','10:00'),4)='OK','seat: host slot 4h books');
-- the host max still applies on top of slots (3 of L3 host max) -- a slot
-- above the max is dead, which the host form warns about
update public.listings set hourly_slots='{2,4}' where id=:L3;
select pg_temp.check_true(pg_temp.book(:GV,:L3,pg_temp.dhaka('2026-12-11','10:00'),4)='REFUSED 22023 hourly_max','turf: a host slot above the host max is refused as max');
update public.listings set hourly_slots=null where id in (:L1,:L2,:L3);
select pg_temp.set_policy(public.hourly_policy_defaults()::text);
-- the day-use window, Dhaka wall clock
update public.listings set hourly_window_start='09:00', hourly_window_end='21:00' where id=:L1;
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-12','08:00'),2)='REFUSED 22023 hourly_window','window: starts before 09:00');
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-12','20:00'),2)='REFUSED 22023 hourly_window','window: ends after 21:00');
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-12','09:00'),12)='OK','window: 09:00-21:00 exactly fills it');
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-13','23:00'),2)='REFUSED 22023 hourly_window','window: a stay crossing midnight is refused');
update public.listings set hourly_window_start='18:00', hourly_window_end='24:00' where id=:L1;
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-14','22:00'),2)='OK','window: ending at midnight counts as 24:00 of the same day');
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-15','23:00'),2)='REFUSED 22023 hourly_window','window: past midnight is the next day');
-- 161: a window may wrap past midnight; 22:00-02:00 is one 4-hour window
update public.listings set hourly_window_start='22:00', hourly_window_end='02:00' where id=:L1;
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-17','22:00'),4)='OK','161: 22:00-02:00 exactly fills an overnight window');
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-19','01:00'),1)='OK','161: a start after midnight belongs to the window');
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-23','21:00'),2)='REFUSED 22023 hourly_window','161: starting before an overnight window');
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-24','01:00'),2)='REFUSED 22023 hourly_window','161: running past an overnight window''s end');
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-25','12:00'),2)='REFUSED 22023 hourly_window','161: midday is outside an overnight window');
update public.listings set hourly_window_start=null, hourly_window_end=null where id=:L1;
-- windows are checked AFTER the floor, so a short stay gets the floor's message
update public.listings set hourly_window_start='09:00', hourly_window_end='21:00', min_hours=3 where id=:L1;
select pg_temp.check_true(pg_temp.book(:GV,:L1,pg_temp.dhaka('2026-12-16','07:00'),1)='REFUSED 22023 hourly_min','order: floor before window');
update public.listings set hourly_window_start=null, hourly_window_end=null, min_hours=1 where id=:L1;
-- nightly bookings are untouched by any of this
select pg_temp.check_true(pg_temp.set_policy('{"room":{"enabled":false,"min_hours":6,"slots":[6]}}')='OK','room hourly off');
select pg_temp.check_true(pg_temp.try(:R1, format($q$select public.create_marketplace_booking(%L,%L,%L,'day',1,'QA')$q$, :L2, pg_temp.dhaka('2026-12-20','14:00'), pg_temp.dhaka('2026-12-21','11:00')))='OK',
  'a nightly stay ignores the hourly policy');
select pg_temp.set_policy(public.hourly_policy_defaults()::text);

----------------------------------------------------------------------------
-- 4. Column constraints on the host layer.
----------------------------------------------------------------------------
select pg_temp.check_true(pg_temp.try_server(format('update public.listings set hourly_slots=%L where id=%L','{}',:L1)) like 'REFUSED 23514%','an empty slot array is refused (null means inherit)');
select pg_temp.check_true(pg_temp.try_server(format('update public.listings set hourly_slots=%L where id=%L','{0,6}',:L1)) like 'REFUSED 23514%','a zero-hour slot is refused');
select pg_temp.check_true(pg_temp.try_server(format('update public.listings set hourly_window_start=%L where id=%L','09:00',:L1)) like 'REFUSED 23514%','a window needs both ends');
select pg_temp.check_true(pg_temp.try_server(format('update public.listings set hourly_window_start=%L, hourly_window_end=%L where id=%L','21:00','09:00',:L1))='OK','161: an end before the start is an overnight window');
select pg_temp.check_true(pg_temp.try_server(format('update public.listings set hourly_window_start=%L, hourly_window_end=%L where id=%L','09:00','09:00',:L1)) like 'REFUSED 23514%','161: an empty window is refused');
select pg_temp.check_true(pg_temp.try_server(format('update public.listings set hourly_window_start=%L, hourly_window_end=%L where id=%L','24:00','02:00',:L1)) like 'REFUSED 23514%','161: a window cannot start at 24:00');
select pg_temp.check_true(pg_temp.try_server(format('update public.listings set hourly_window_start=%L, hourly_window_end=%L where id=%L','09:00','24:00',:L1))='OK','24:00 is a valid window end');
update public.listings set hourly_window_start=null, hourly_window_end=null where id=:L1;
-- the host can set these through RLS as themselves
select pg_temp.check_true(pg_temp.try('11111111-1111-1111-1111-111111111111', format('update public.listings set hourly_slots=%L, hourly_window_start=%L, hourly_window_end=%L where id=%L','{6,12}','09:00','21:00',:L1))='OK','the owner can set slots and a window');
select pg_temp.check_true((select hourly_slots='{6,12}' and hourly_window_start=time '09:00' from public.listings where id=:L1),'and they landed');

----------------------------------------------------------------------------
-- 5. Access: the check and the policy are callable by anyone, so a client
--    can pre-validate; the policy row is public configuration.
----------------------------------------------------------------------------
do $$
begin
  perform set_config('role','anon',true);
  perform public.hourly_policy_for('hotel');
  perform public.hourly_booking_check('aaaaaaaa-0000-0000-0000-000000000002', pg_temp.dhaka('2026-12-22','08:00'), pg_temp.dhaka('2026-12-22','14:00'));
  perform set_config('role','postgres',true);
  raise notice 'PASS: anon can resolve the policy and pre-check a selection';
end $$;
select pg_temp.check_true((select value is not null from public.app_settings where key='hourly_policy'),'hourly_policy row survives the suite');
select pg_temp.as_server();
