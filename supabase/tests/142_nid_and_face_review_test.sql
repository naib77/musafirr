-- LOCAL QA fixtures only; every change rolls back.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.denied(statement text,label text) returns void language plpgsql as $$
declare refused boolean=false;
begin begin execute statement; exception when others then refused=true; end;
perform pg_temp.check_true(refused,label); end $$;
select pg_temp.check_true((select count(*)=3 from public.profiles where id in ('44444444-4444-4444-4444-444444444444','33333333-3333-3333-3333-333333333333','55555555-5555-5555-5555-555555555555')),'local fixtures present');
update public.profiles set verification_status='rejected',nid_verified=false,suspended_at=null,role='owner' where id='44444444-4444-4444-4444-444444444444';
delete from public.face_verification_attempts where user_id='44444444-4444-4444-4444-444444444444';
delete from public.owner_documents where user_id='44444444-4444-4444-4444-444444444444';
update public.app_settings set value='true' where key='face_review_enabled';
select set_config('request.jwt.claims','{}',true);
set local role anon;
select pg_temp.denied('select public.verification_overview()','anonymous denied');
reset role;
select set_config('request.jwt.claims','{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}',true);
set local role authenticated;
select pg_temp.check_true(public.nid_verification_status()->>'status'='rejected','revoked NID can resubmit');
select pg_temp.denied('select public.submit_nid_verification(null,null)','missing sides denied');
insert into storage.objects(bucket_id,name,metadata) values
 ('documents',auth.uid()::text||'/nid/test/front.png','{"size":1024,"mimetype":"image/png"}'),
 ('documents',auth.uid()::text||'/nid/test/back.png','{"size":1024,"mimetype":"image/png"}');
select pg_temp.denied('select public.submit_nid_verification(''33333333-3333-3333-3333-333333333333/nid/test/front.png'',''44444444-4444-4444-4444-444444444444/nid/test/back.png'')','cross-user evidence denied');
select public.submit_nid_verification(auth.uid()::text||'/nid/test/front.png',auth.uid()::text||'/nid/test/back.png');
select public.submit_nid_verification(auth.uid()::text||'/nid/test/front.png',auth.uid()::text||'/nid/test/back.png');
select pg_temp.check_true(public.nid_verification_status()->>'status'='pending','durable submission and retry pending');
select pg_temp.check_true((select count(*)=2 from public.owner_documents where user_id=auth.uid()),'both sides linked');
select pg_temp.check_true(public.verification_overview()->>'status'='none','pending NID does not hide missing face step');
select pg_temp.denied('update public.owner_documents set file_path=''changed'' where user_id=auth.uid()','client cannot replace reviewed rows');
update storage.objects set metadata='{"size":400}' where bucket_id='documents' and name=auth.uid()::text||'/nid/test/front.png';
select pg_temp.denied('delete from storage.objects where bucket_id=''documents'' and name=auth.uid()::text||''/nid/test/front.png''','direct evidence deletion denied');
select pg_temp.check_true(exists(select 1 from storage.objects where bucket_id='documents' and name=auth.uid()::text||'/nid/test/front.png' and metadata->>'size'='1024'),'evidence immutable');
select pg_temp.denied('select public.approve_nid_verification(auth.uid(),auth.uid()::text||''/nid/test/front.png'',auth.uid()::text||''/nid/test/back.png'')','user cannot approve NID');
reset role;
select set_config('request.jwt.claims','{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}',true);
set local role authenticated;
select pg_temp.denied('select public.approve_nid_verification(''44444444-4444-4444-4444-444444444444'',''stale'',''stale'')','stale admin evidence denied');
select public.approve_nid_verification('44444444-4444-4444-4444-444444444444','44444444-4444-4444-4444-444444444444/nid/test/front.png','44444444-4444-4444-4444-444444444444/nid/test/back.png');
select pg_temp.check_true((select bool_and(verified_by=auth.uid() and verified_at is not null) from public.owner_documents where user_id='44444444-4444-4444-4444-444444444444'),'NID admin audit stamps');
reset role;
select set_config('request.jwt.claims','{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}',true);
set local role authenticated;
select pg_temp.check_true(public.face_verification_status()->>'status'='none','NID approval does not approve face');
select pg_temp.check_true(not public.can_publish_listings(),'NID alone cannot publish');
create temp table a as select public.start_face_verification('guided') data;
select pg_temp.check_true((select data->>'method'='guided' from a),'NID approved account can start live face check');
reset role;
select set_config('request.jwt.claims','{}',true);
-- Seed a reviewed face verdict as the server to isolate the combined predicate.
update public.face_verification_attempts set status='approved',submitted_at=now(),reviewed_at=now(),reviewed_by='55555555-5555-5555-5555-555555555555'
where id=(select (data->>'id')::uuid from a);
select set_config('request.jwt.claims','{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}',true);
set local role authenticated;
select pg_temp.check_true(public.verification_overview()->>'status'='verified','both approvals unlock account');
select pg_temp.check_true(public.can_publish_listings(),'both approvals allow publishing');
select pg_temp.denied('select public.start_face_verification(''guided'')','approved face cannot create replacement');
reset role;
select set_config('request.jwt.claims','{}',true);
update public.profiles set verification_status='rejected',nid_verified=false where id='44444444-4444-4444-4444-444444444444';
select pg_temp.check_true(not public.has_approved_face_or_identity('44444444-4444-4444-4444-444444444444'),'NID revocation blocks existing face approval');
select set_config('request.jwt.claims','{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}',true);
set local role authenticated;
select pg_temp.check_true(public.face_verification_status()->>'status'='verified','NID revocation preserves separate face verdict');
select pg_temp.denied('select public.create_marketplace_booking(null,now()+interval ''1 day'',now()+interval ''2 days'',''day'',1)','face alone cannot book after NID revocation');
insert into storage.objects(bucket_id,name,metadata) values
 ('documents',auth.uid()::text||'/nid/retry/front.png','{"size":1024,"mimetype":"image/png"}'),
 ('documents',auth.uid()::text||'/nid/retry/back.png','{"size":1024,"mimetype":"image/png"}');
select public.submit_nid_verification(auth.uid()::text||'/nid/retry/front.png',auth.uid()::text||'/nid/retry/back.png');
select pg_temp.check_true(public.nid_verification_status()->>'status'='pending','revoked NID resubmission is pending');
select pg_temp.check_true((select bool_and(verified_at is null and verified_by is null) from public.owner_documents where user_id=auth.uid()),'resubmission clears old NID approval stamps');
select pg_temp.check_true(public.verification_overview()->>'status'='pending','face approval plus pending NID still awaits admin');
rollback;
