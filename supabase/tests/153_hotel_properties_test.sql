-- LOCAL QA fixtures only; every change rolls back. Run with
-- `sh tool/qa/run_sql_tests.sh 153` after applying 153 locally.
--
-- Pins 153: a hotel (property) owns its facts and copies them onto its room
-- types; only its host writes it; guests see it once a type is live; room
-- names are unique across the hotel; the named-room functions refuse other
-- hosts, upcoming bookings and the last room; a move keeps history with the
-- old type; one verified licence badges every type.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.as_user(uid text) returns void language plpgsql as $$
begin
  if uid is null then
    perform set_config('request.jwt.claims','{"role":"anon"}',true);
    perform set_config('role','anon',true);
  else
    perform set_config('request.jwt.claims',json_build_object('sub',uid,'role','authenticated')::text,true);
    perform set_config('role','authenticated',true);
  end if;
end $$;
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
-- Measure the effect, never the exception: an RLS-refused write raises
-- nothing, so this returns the row count a statement actually changed.
create function pg_temp.rows(uid text, statement text) returns int language plpgsql as $$
declare n int;
begin
  perform pg_temp.as_user(uid);
  begin execute statement; get diagnostics n = row_count;
  exception when others then n := -1; end;
  perform pg_temp.as_server();
  return n;
end $$;
-- Listings are inserted as the server: the local seed's hosts do not pass
-- can_publish_listings(), and the insert policy is not what 153 is about.
create function pg_temp.try_srv(statement text) returns text language plpgsql as $$
declare v_hint text; v_state text;
begin
  execute statement;
  return 'OK';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_hint = pg_exception_hint;
  return 'REFUSED '||v_state||' '||coalesce(v_hint,'');
end $$;
create function pg_temp.active_labels(listing uuid) returns text language sql as $$
  select coalesce(string_agg(coalesce(label,'∅'), ',' order by label nulls first), '')
    from public.listing_units where listing_id = listing and is_active $$;

\set H  '''11111111-1111-1111-1111-111111111111'''
\set H2 '''22222222-2222-2222-2222-222222222222'''
\set GV '''33333333-3333-3333-3333-333333333333'''
\set P  '''bbbbbbbb-0000-0000-0000-000000000153'''
\set P2 '''bbbbbbbb-0000-0000-0000-000000001532'''
\set T1 '''cccccccc-0000-0000-0000-000000000001'''
\set T2 '''cccccccc-0000-0000-0000-000000000002'''
\set DOC '''11111111-1111-1111-1111-111111111111/trade_licence/p153.jpg'''

-- ---------------------------------------------------------------- 1. writing a hotel
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$insert into public.properties (id, owner_id, name, area, city, country, latitude, longitude,
       check_in_time, check_out_time, hotel_star_rating, hotel_front_desk_24h)
     values (%L, %L, '  Hotel Sea Crown ', 'Kola Toli', 'Cox''s Bazar', 'Bangladesh',
             21.4194712, 91.9735511, '14:00', '11:00', 3, true)$q$, :P, :H)) = 'OK',
  'the host creates their hotel');
select pg_temp.check_true((select name from public.properties where id = :P) = 'Hotel Sea Crown',
  'the name is trimmed');
select pg_temp.check_true((select latitude from public.properties where id = :P)
                          = public.snap_coordinate(21.4194712),
  'coordinates are snapped like a listing''s');
select pg_temp.check_true(pg_temp.try(:GV, format(
  $q$insert into public.properties (owner_id, name) values (%L, 'Planted')$q$, :H)) like 'REFUSED 42501%',
  'nobody creates a hotel in another host''s name');
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$update public.properties set owner_id = %L where id = %L$q$, :H2, :P))
  = 'REFUSED 42501 property_owner_fixed', 'a hotel cannot be handed to another owner');
select pg_temp.check_true(pg_temp.rows(:GV, format(
  $q$update public.properties set name = 'Hijacked' where id = %L$q$, :P)) = 0,
  'another user''s update changes nothing');
select pg_temp.check_true(pg_temp.try(null, format(
  $q$insert into public.properties (owner_id, name) values (%L, 'Anon')$q$, :H)) like 'REFUSED 42501%',
  'anon cannot create a hotel');

-- Another host's hotel, for the cross-hotel checks.
insert into public.properties (id, owner_id, name) values (:P2, :H2, 'Other Hotel');

-- ---------------------------------------------------------------- 2. room types inherit
select pg_temp.check_true(pg_temp.try_srv(format(
  $q$insert into public.listings (id, owner_id, owner_name, title, description, address, city, country,
       listing_type, daily_rate, max_guests, is_active, property_id, area, hotel_star_rating)
     values (%L, %L, 'QA Host One', 'Super Deluxe Room', 'x', 'typed', 'Typed City', 'X',
             'hotel', 3285, 4, false, %L, 'Typed Area', 5)$q$, :T1, :H, :P)) = 'OK',
  'the host adds a room type to their hotel');
select pg_temp.check_true(
  (select area = 'Kola Toli' and city = 'Cox''s Bazar' and hotel_star_rating = 3
          and check_in_time = '14:00' and hotel_front_desk_24h
          and latitude = public.snap_coordinate(21.4194712) and geog is not null
     from public.listings where id = :T1),
  'the type carries the hotel''s location and facts, not what was typed');
select pg_temp.check_true(pg_temp.try_srv(format(
  $q$insert into public.listings (owner_id, owner_name, title, description, address, city, country,
       listing_type, daily_rate, max_guests, property_id)
     values (%L, 'QA Host One', 'Room in hotel', 'x', 'a', 'b', 'c', 'room', 1, 2, %L)$q$, :H, :P))
  = 'REFUSED 22023 property_child_type', 'only hotel listings can be a hotel''s room type');
select pg_temp.check_true(pg_temp.try_srv(format(
  $q$insert into public.listings (owner_id, owner_name, title, description, address, city, country,
       listing_type, daily_rate, max_guests, property_id)
     values (%L, 'QA Host One', 'Squat', 'x', 'a', 'b', 'c', 'hotel', 1, 2, %L)$q$, :H, :P2))
  = 'REFUSED 42501 property_owner_mismatch', 'a host cannot add a type to someone else''s hotel');

insert into public.listings (id, owner_id, owner_name, title, description, address, city, country,
       listing_type, daily_rate, max_guests, is_active, property_id)
values (:T2, :H, 'QA Host One', 'Sea Front Deluxe', 'x', 'a', 'b', 'c', 'hotel', 4296, 4, false, :P);

select pg_temp.check_true(pg_temp.try(:H, format(
  $q$update public.properties set hotel_star_rating = 4, area = 'Marine Drive' where id = %L$q$, :P)) = 'OK',
  'the host edits the hotel');
select pg_temp.check_true(
  (select bool_and(hotel_star_rating = 4 and area = 'Marine Drive') from public.listings where property_id = :P),
  'the edit reaches every room type at once');
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$update public.listings set hotel_star_rating = 1, title = 'Super Deluxe' where id = %L$q$, :T1)) = 'OK', 'a type''s own save keeps its title but cannot change the hotel''s facts (call)');
select pg_temp.check_true((select hotel_star_rating = 4 and title = 'Super Deluxe' from public.listings where id = :T1),
  'a type''s own save keeps its title but cannot change the hotel''s facts');
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$update public.listings set property_id = null where id = %L$q$, :T1))
  = 'REFUSED 42501 property_fixed', 'a room type cannot leave its hotel');
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$update public.listings set listing_type = 'room' where id = %L$q$, :T1))
  = 'REFUSED 22023 property_child_type', 'a room type cannot stop being a hotel listing');

-- ---------------------------------------------------------------- 3. who sees a hotel
select pg_temp.check_true(pg_temp.rows(null, format(
  $q$select 1 from public.properties where id = %L$q$, :P)) = 0,
  'a hotel with no live type is a draft guests cannot see');
select pg_temp.check_true(pg_temp.rows(:H, format(
  $q$select 1 from public.properties where id = %L$q$, :P)) = 1, 'the host sees their draft');
update public.listings set is_active = true where id = :T1;
select pg_temp.check_true(pg_temp.rows(null, format(
  $q$select 1 from public.properties where id = %L$q$, :P)) = 1,
  'once a type is live, guests see the hotel');
select pg_temp.check_true(pg_temp.rows(null, format(
  $q$update public.properties set name = 'x' where id = %L$q$, :P)) = -1,
  'anon cannot edit a hotel');
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$delete from public.properties where id = %L$q$, :P)) like 'REFUSED 23503%',
  'a hotel with room types cannot be deleted');

-- ---------------------------------------------------------------- 4. named rooms
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$select public.add_listing_units(%L, array['101',' 102 ','103'], true)$q$, :T1)) = 'OK', 'naming rooms on a new type names its implicit room first: 3 rooms, not 4 (call)');
select pg_temp.check_true(pg_temp.active_labels(:T1) = '101,102,103',
  'naming rooms on a new type names its implicit room first: 3 rooms, not 4');
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$select public.add_listing_units(%L, array['301','302'])$q$, :T2)) = 'OK', 'without the flag the unnamed room stays (call)');
select pg_temp.check_true(pg_temp.active_labels(:T2) = '∅,301,302',
  'without the flag the unnamed room stays');
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$select public.add_listing_units(%L, array['101'])$q$, :T2))
  = 'REFUSED 23505 room_label_taken', 'room 101 cannot exist twice in one hotel, across types');
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$select public.add_listing_units(%L, array['  ROOM a', 'room A'])$q$, :T2))
  = 'REFUSED 22023 room_label_duplicate', 'the same name twice in one add is refused');
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$select public.add_listing_units(%L, array[repeat('x', 41)])$q$, :T2))
  = 'REFUSED 22023 room_label_invalid', 'a name over 40 characters is refused');
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$select public.add_listing_units(%L, array[' ', ''])$q$, :T2))
  = 'REFUSED 22023 unit_count_range', 'blank names add nothing and are refused');
select pg_temp.check_true(pg_temp.try(:H2, format(
  $q$select public.add_listing_units(%L, array['999'])$q$, :T1))
  = 'REFUSED 42501 not_listing_owner', 'another host cannot add rooms');
select pg_temp.check_true(pg_temp.try(null, format(
  $q$select public.add_listing_units(%L, array['999'])$q$, :T1)) like 'REFUSED 42501%',
  'anon cannot add rooms');
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$update public.listing_units set label = '301' where listing_id = %L and label = '103'$q$, :T1))
  = 'REFUSED 23505 room_label_taken', 'a rename cannot take another type''s room name either');

-- An upcoming booking on 102.
insert into public.bookings (listing_id,unit_id,tenant_id,tenant_name,starts_at,ends_at,booking_status,pricing_unit,unit_count,total_price,guest_count)
select :T1, id, '44444444-4444-4444-4444-444444444444', 'QA', now() + interval '3 days', now() + interval '5 days',
       'pending', 'day', 1, 1, 1
  from public.listing_units where listing_id = :T1 and label = '102';

select pg_temp.check_true(pg_temp.try(:H, format(
  $q$select public.deactivate_listing_unit((select id from public.listing_units where listing_id = %L and label = '102'))$q$, :T1))
  = 'REFUSED 22023 units_in_use', 'a room with an upcoming booking cannot be removed');
-- The id is resolved here, as the server: under H2's RLS the lookup itself
-- would come back empty and the call would only prove "not found".
select id as u103 from public.listing_units where listing_id = :T1 and label = '103' \gset
select pg_temp.check_true(pg_temp.try(:H2, format(
  $q$select public.deactivate_listing_unit(%L)$q$, :'u103'))
  = 'REFUSED 42501 not_listing_owner', 'another host cannot remove a room');
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$select public.deactivate_listing_unit((select id from public.listing_units where listing_id = %L and label = '103'))$q$, :T1)) = 'OK', 'a free room is retired, not deleted (call)');
select pg_temp.check_true(pg_temp.active_labels(:T1) = '101,102'
  and exists (select 1 from public.listing_units where listing_id = :T1 and label = '103' and not is_active),
  'a free room is retired, not deleted');
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$select public.add_listing_units(%L, array['103'])$q$, :T1)) = 'OK', 're-adding a retired name brings the same room back (call)');
select pg_temp.check_true(pg_temp.active_labels(:T1) = '101,102,103'
  and (select count(*) from public.listing_units where listing_id = :T1 and label = '103') = 1,
  're-adding a retired name brings the same room back');

-- ---------------------------------------------------------------- 5. moving a room between types
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$select public.move_listing_unit((select id from public.listing_units where listing_id = %L and label = '102'), %L)$q$, :T1, :T2))
  = 'REFUSED 22023 units_in_use', 'a booked room cannot be re-classified');
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$select public.move_listing_unit((select id from public.listing_units where listing_id = %L and label = '103'), %L)$q$, :T1, :T2)) = 'OK', 'room 103 moves to the other type under the same name (call)');
select pg_temp.check_true(pg_temp.active_labels(:T1) = '101,102'
  and pg_temp.active_labels(:T2) = '∅,103,301,302',
  'room 103 moves to the other type under the same name');
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$select public.move_listing_unit((select id from public.listing_units where listing_id = %L and label = '103'), %L)$q$, :T2, :T1)) = 'OK', 'and back, reusing its old row (call)');
select pg_temp.check_true(pg_temp.active_labels(:T1) = '101,102,103'
  and (select count(*) from public.listing_units where listing_id = :T1 and label = '103') = 1,
  'and back, reusing its old row');

insert into public.listings (id, owner_id, owner_name, title, description, address, city, country, listing_type, daily_rate, max_guests)
values ('cccccccc-0000-0000-0000-000000000009', :H, 'QA Host One', 'Loose hotel', 'x', 'a', 'b', 'c', 'hotel', 1, 2);
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$select public.move_listing_unit((select id from public.listing_units where listing_id = %L and label = '101'), 'cccccccc-0000-0000-0000-000000000009')$q$, :T1))
  = 'REFUSED 22023 unit_move_other_property', 'a room moves only within its hotel');
select pg_temp.check_true(pg_temp.try(:H,
  $q$select public.deactivate_listing_unit((select id from public.listing_units where listing_id = 'cccccccc-0000-0000-0000-000000000009'))$q$)
  = 'REFUSED 22023 unit_count_range', 'a listing keeps at least one room');
select pg_temp.check_true(pg_temp.try(:H, format(
  $q$update public.listings set property_id = %L where id = 'cccccccc-0000-0000-0000-000000000009'$q$, :P)) = 'OK',
  'an existing hotel listing can join its host''s hotel');
select pg_temp.check_true(pg_temp.rows(:H, format(
  $q$insert into public.listing_units (listing_id, label) values (%L, '999')$q$, :T1)) = -1,
  'direct unit inserts stay refused (152)');

-- ---------------------------------------------------------------- 6. licence badges the hotel
insert into storage.objects (bucket_id, name, owner, metadata)
values ('documents', '11111111-1111-1111-1111-111111111111/trade_licence/p153.jpg', :H, '{"mimetype":"image/jpeg","size":2048}');
insert into public.listing_trade_licences (listing_id, owner_id, document_path, status)
values (:T1, :H, :DOC, 'pending');
select pg_temp.check_true(not public.listing_licence_verified(:T2), 'a pending licence badges nothing');
update public.listing_trade_licences set status = 'verified' where listing_id = :T1;
select pg_temp.check_true(public.listing_licence_verified(:T1) and public.listing_licence_verified(:T2),
  'one verified licence badges every room type of the hotel');
select pg_temp.check_true(not public.listing_licence_verified('cccccccc-0000-0000-0000-000000000099'),
  'an unknown listing is not licensed');

rollback;
