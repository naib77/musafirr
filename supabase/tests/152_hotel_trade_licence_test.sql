-- LOCAL QA fixtures only; every change rolls back. Run with
-- `sh tool/qa/run_sql_tests.sh 152` after applying 152 locally.
--
-- Pins 152: the licence is optional (a hotel without one is still live), only
-- the owner can submit, only for a hotel, only a file they uploaded; a host
-- cannot write the verdict; only another admin can, against the document they
-- saw; and the public answer is a boolean that needs verified + hotel + file.
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

\set H  '''11111111-1111-1111-1111-111111111111'''
\set GV '''33333333-3333-3333-3333-333333333333'''
\set AD '''55555555-5555-5555-5555-555555555555'''
\set HL '''aaaaaaaa-0000-0000-0000-000000000152'''
\set RL '''aaaaaaaa-0000-0000-0000-000000001520'''
\set DOC '''11111111-1111-1111-1111-111111111111/trade_licence/hl_1.jpg'''
\set DOC2 '''11111111-1111-1111-1111-111111111111/trade_licence/hl_2.pdf'''

insert into public.listings (id, owner_id, owner_name, title, description, address, city, country, listing_type, hourly_rate, max_guests, is_active)
values (:HL,:H,'QA Host One','QA 152 hotel','x','Gulshan','Dhaka','Bangladesh','hotel',100,2,true),
       (:RL,:H,'QA Host One','QA 152 room','x','Gulshan','Dhaka','Bangladesh','room',100,2,true);
-- Storage stamps owner on upload; fixtures stamp it by hand.
insert into storage.objects (bucket_id, name, owner, metadata) values
  ('documents', '11111111-1111-1111-1111-111111111111/trade_licence/hl_1.jpg', :H, '{"mimetype":"image/jpeg","size":2048}'),
  ('documents', '11111111-1111-1111-1111-111111111111/trade_licence/hl_2.pdf', :H, '{"mimetype":"application/pdf","size":4096}'),
  ('documents', '11111111-1111-1111-1111-111111111111/trade_licence/big.jpg', :H, '{"mimetype":"image/jpeg","size":9000000}'),
  -- Right folder name, wrong uploader: the path alone proves nothing.
  ('documents', '11111111-1111-1111-1111-111111111111/trade_licence/planted.jpg', :GV, '{"mimetype":"image/jpeg","size":2048}');

----------------------------------------------------------------------------
-- 1. Optional
----------------------------------------------------------------------------
select pg_temp.check_true((select is_active from public.listings where id=:HL),'a hotel with no licence is live (152 gates nothing)');
select pg_temp.check_true(public.listing_licence_verified(:HL) = false,'no licence: not verified');

----------------------------------------------------------------------------
-- 2. Submitting
----------------------------------------------------------------------------
select pg_temp.check_true(pg_temp.try(:GV,format($q$select public.submit_trade_licence(%L,%L)$q$,:HL,:DOC))='REFUSED 42501 not_listing_owner','a guest cannot submit for the host''s hotel');
select pg_temp.check_true(pg_temp.try(:H,format($q$select public.submit_trade_licence(%L,%L)$q$,:RL,:DOC))='REFUSED 22023 not_a_hotel','a room listing cannot carry a licence');
select pg_temp.check_true(pg_temp.try(:H,format($q$select public.submit_trade_licence(%L,%L)$q$,:HL,'11111111-1111-1111-1111-111111111111/trade_licence/planted.jpg'))='REFUSED 42501 document_not_owned','a file someone else uploaded into the host''s folder is refused');
select pg_temp.check_true(pg_temp.try(:H,format($q$select public.submit_trade_licence(%L,%L)$q$,:HL,'11111111-1111-1111-1111-111111111111/nid/front.jpg'))='REFUSED 42501 document_not_owned','a path outside trade_licence/ is refused');
select pg_temp.check_true(pg_temp.try(:H,format($q$select public.submit_trade_licence(%L,%L)$q$,:HL,'11111111-1111-1111-1111-111111111111/trade_licence/big.jpg'))='REFUSED 22023 document_invalid','a file over 5 MB is refused');
select pg_temp.check_true(pg_temp.try(:H,format($q$select public.submit_trade_licence(%L,%L,%L)$q$,:HL,:DOC,'  TL-123  '))='OK','the host submits');
select pg_temp.check_true((select status::text='pending' and licence_number='TL-123' and owner_id=:H from public.listing_trade_licences where listing_id=:HL),'pending, number trimmed');

-- The host cannot write the verdict around the RPC.
select pg_temp.check_true(pg_temp.rows(:H,format($q$update public.listing_trade_licences set status='verified' where listing_id=%L$q$,:HL)) <= 0,'a direct status write changes nothing');
select pg_temp.check_true(pg_temp.rows(:H,format($q$insert into public.listing_trade_licences(listing_id,owner_id,document_path,status) values (%L,%L,%L,'verified') on conflict do nothing$q$,:RL,:H,:DOC)) <= 0,'a direct insert is refused');
select pg_temp.check_true((select status::text='pending' from public.listing_trade_licences where listing_id=:HL),'still pending');
select pg_temp.check_true(pg_temp.rows(:GV,format($q$select 1 from public.listing_trade_licences where listing_id=%L$q$,:HL))=0,'another user cannot read the row');

----------------------------------------------------------------------------
-- 3. The verdict
----------------------------------------------------------------------------
select pg_temp.check_true(pg_temp.try(:H,format($q$select public.review_trade_licence(%L,%L,true)$q$,:HL,:DOC)) like 'REFUSED 42501%','the host cannot approve their own');
select pg_temp.check_true(pg_temp.try(:AD,format($q$select public.review_trade_licence(%L,%L,false)$q$,:HL,:DOC))='REFUSED 22023 reason_required','a rejection needs a reason');
select pg_temp.check_true(pg_temp.try(:AD,format($q$select public.review_trade_licence(%L,%L,true)$q$,:HL,:DOC2))='REFUSED 40001 licence_changed','a verdict on a document the admin did not see is refused');
select pg_temp.check_true(pg_temp.try(:AD,format($q$select public.review_trade_licence(%L,%L,false,'Blurry, please retake')$q$,:HL,:DOC))='OK','the admin rejects with a reason');
select pg_temp.check_true(pg_temp.rows(:H,format($q$select 1 from public.listing_trade_licences where listing_id=%L and status='rejected' and rejection_reason='Blurry, please retake'$q$,:HL))=1,'the host reads the rejection reason');
select pg_temp.check_true(public.listing_licence_verified(:HL) = false,'rejected: not verified');

select pg_temp.check_true(pg_temp.try(:H,format($q$select public.submit_trade_licence(%L,%L)$q$,:HL,:DOC2))='OK','the host resubmits a PDF');
select pg_temp.check_true((select status::text='pending' and rejection_reason is null and licence_number is null from public.listing_trade_licences where listing_id=:HL),'resubmission reads clean');
select pg_temp.check_true(pg_temp.try(:AD,format($q$select public.review_trade_licence(%L,%L,true)$q$,:HL,:DOC2))='OK','the admin approves');
select pg_temp.check_true((select reviewed_by=:AD and reviewed_at is not null from public.listing_trade_licences where listing_id=:HL),'the verdict is signed');

----------------------------------------------------------------------------
-- 4. The public answer
----------------------------------------------------------------------------
set local role anon;
select pg_temp.check_true(public.listing_licence_verified('aaaaaaaa-0000-0000-0000-000000000152'),'anon sees the badge');
select pg_temp.check_true(not has_function_privilege('anon','public.submit_trade_licence(uuid,text,text)','execute'),'anon cannot submit');
select pg_temp.check_true(not has_function_privilege('anon','public.review_trade_licence(uuid,text,boolean,text)','execute'),'anon cannot review');
reset role;
select pg_temp.as_server();

update public.listings set listing_type='room' where id=:HL;
select pg_temp.check_true(public.listing_licence_verified(:HL) = false,'no longer a hotel: no badge');
update public.listings set listing_type='hotel' where id=:HL;
-- Storage refuses direct deletes unless asked; the host's real path is the
-- Storage API, which ends in the same row going away.
set local storage.allow_delete_query = 'true';
delete from storage.objects where bucket_id='documents' and name='11111111-1111-1111-1111-111111111111/trade_licence/hl_2.pdf';
select pg_temp.check_true(public.listing_licence_verified(:HL) = false,'document deleted: no badge');

-- A new submission after approval takes the badge away until re-reviewed.
select pg_temp.check_true(pg_temp.try(:H,format($q$select public.submit_trade_licence(%L,%L)$q$,:HL,:DOC))='OK','resubmit after approval');
select pg_temp.check_true((select status::text='pending' and reviewed_by is null from public.listing_trade_licences where listing_id=:HL),'back to pending, verdict cleared');

----------------------------------------------------------------------------
-- 5. Room labels: the host renames, and nothing else
----------------------------------------------------------------------------
select pg_temp.as_user(:H);
select public.set_listing_unit_count(:HL, 2);
select pg_temp.as_server();
create temp table u as
  select (select id from public.listing_units where listing_id=:HL order by created_at, id limit 1) as u1,
         (select id from public.listing_units where listing_id=:HL order by created_at, id offset 1 limit 1) as u2;
grant select on u to authenticated;

select pg_temp.check_true(pg_temp.rows(:H,format($q$update public.listing_units set label='Deluxe 101' where id=%L$q$,(select u1 from u)))=1,'the host names a room');
select pg_temp.check_true(pg_temp.try(:H,format($q$update public.listing_units set label='Deluxe 101' where id=%L$q$,(select u2 from u))) like 'REFUSED 23505%','two rooms cannot share a name');
select pg_temp.check_true(pg_temp.rows(:GV,format($q$update public.listing_units set label='Mine' where id=%L$q$,(select u2 from u)))<=0,'another user cannot rename the host''s room');
select pg_temp.check_true(pg_temp.rows(:H,format($q$update public.listing_units set label=null where id=%L$q$,(select u1 from u)))=1,'clearing a name falls back to Room N');

select pg_temp.check_true(pg_temp.try(:H,format($q$update public.listing_units set is_active=false where id=%L$q$,(select u2 from u))) like 'REFUSED 42501%','a direct deactivate is refused (set_listing_unit_count owns that)');
select pg_temp.check_true(pg_temp.try(:H,format($q$update public.listing_units set listing_id=%L where id=%L$q$,:RL,(select u2 from u))) like 'REFUSED 42501%','a unit cannot be moved to another listing');
select pg_temp.check_true(pg_temp.try(:H,format($q$insert into public.listing_units(listing_id) values (%L)$q$,:RL)) like 'REFUSED 42501%','a direct insert cannot add capacity');
select pg_temp.check_true(pg_temp.try(:H,format($q$delete from public.listing_units where id=%L$q$,(select u2 from u))) like 'REFUSED 42501%','a direct delete is refused');
select pg_temp.check_true((select count(*)=2 from public.listing_units where listing_id=:HL and is_active),'both rooms still active');
select pg_temp.as_user(:H);
select public.set_listing_unit_count(:HL, 1);
select pg_temp.as_server();
select pg_temp.check_true((select count(*)=1 from public.listing_units where listing_id=:HL and is_active),'the RPC still changes the count');

rollback;
