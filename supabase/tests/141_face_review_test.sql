-- Run against a LOCAL baseline plus migration 141. All fixtures roll back.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check_true(ok boolean, label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.denied(statement text, label text) returns void language plpgsql as $$
declare refused boolean=false;
begin
  begin execute statement; exception when others then refused=true; end;
  perform pg_temp.check_true(refused,label);
end $$;

-- The local QA seed supplies these users; fail clearly instead of silently
-- skipping if someone points this test at a database without that seed.
select pg_temp.check_true((select count(*)=3 from public.profiles where id in
 ('44444444-4444-4444-4444-444444444444','33333333-3333-3333-3333-333333333333','55555555-5555-5555-5555-555555555555')), 'local QA fixtures available');
delete from public.face_verification_attempts where user_id in ('44444444-4444-4444-4444-444444444444','33333333-3333-3333-3333-333333333333');
update public.profiles set verification_status='none',role='owner',suspended_at=null where id='44444444-4444-4444-4444-444444444444';
update public.app_settings set value='true' where key='face_review_enabled';
create temp table face_test_attempt(data jsonb);
grant all on face_test_attempt to authenticated, service_role;

select set_config('request.jwt.claims','{}',true);
set local role anon;
select pg_temp.denied('select public.start_face_verification(''guided'')','anonymous start denied');
reset role;
select set_config('request.jwt.claims','{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}',true);
set local role authenticated;
insert into face_test_attempt select public.start_face_verification('guided');
select pg_temp.check_true((select jsonb_array_length(data->'actions')=3 from face_test_attempt),'server issues three actions');
select pg_temp.denied('update public.face_verification_attempts set status=''approved''','client cannot set verdict');
select pg_temp.denied('insert into public.face_verification_attempts(user_id,method,actions,status) values(auth.uid(),''manual'',''{}'',''approved'')','client cannot forge attempts');
select pg_temp.denied('select public.review_face_verification((select (data->>''id'')::uuid from face_test_attempt),(select (data->>''evidence_version'')::uuid from face_test_attempt),''approved'','''')','non-admin approval denied');
select pg_temp.denied('select public.submit_face_verification((select (data->>''id'')::uuid from face_test_attempt),gen_random_uuid(),''webm'')','forged nonce denied');
select pg_temp.denied('select public.submit_face_verification((select (data->>''id'')::uuid from face_test_attempt),(select (data->>''nonce'')::uuid from face_test_attempt),''webm'')','missing uploads denied');
insert into storage.objects(bucket_id,name,metadata)
select 'face-evidence',auth.uid()::text||'/'||(data->>'id')||'/selfie.jpg','{"size":1024,"mimetype":"image/jpeg"}'::jsonb from face_test_attempt;
insert into storage.objects(bucket_id,name,metadata)
select 'face-evidence',auth.uid()::text||'/'||(data->>'id')||'/clip.webm','{"size":4096,"mimetype":"video/webm"}'::jsonb from face_test_attempt;
select public.submit_face_verification((select (data->>'id')::uuid from face_test_attempt),(select (data->>'nonce')::uuid from face_test_attempt),'webm');
select public.submit_face_verification((select (data->>'id')::uuid from face_test_attempt),(select (data->>'nonce')::uuid from face_test_attempt),'webm');
select pg_temp.check_true(public.face_verification_status()->>'status'='pending','submission/retry stays pending');
select pg_temp.check_true(not public.can_publish_listings(),'pending capture cannot publish');
do $$
declare hint text;
begin
  begin
    perform public.create_marketplace_booking(null,now()+interval '1 day',now()+interval '2 days','day',1);
    raise exception 'Expected blocked booking';
  exception when sqlstate '42501' then
    get stacked diagnostics hint=pg_exception_hint;
    perform pg_temp.check_true(hint='identity_unverified','pending face cannot book');
  end;
end $$;

select pg_temp.denied('select public.start_face_verification(''guided'')','pending review blocks duplicate attempts');
select pg_temp.denied('insert into storage.objects(bucket_id,name,metadata) select ''face-evidence'',auth.uid()::text||''/''||(data->>''id'')||''/clip.mp4'',''{"size":4096,"mimetype":"video/mp4"}''::jsonb from face_test_attempt','submitted attempt cannot gain new evidence');
update storage.objects set metadata='{"size":999}' where bucket_id='face-evidence';
select pg_temp.check_true(not exists(select 1 from storage.objects where bucket_id='face-evidence' and metadata->>'size'='999'),'evidence cannot be overwritten');
reset role;
select set_config('request.jwt.claims','{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}',true);
set local role authenticated;
select pg_temp.check_true(not exists(select 1 from public.face_verification_attempts where user_id='44444444-4444-4444-4444-444444444444'),'other user cannot read attempt');
select pg_temp.check_true(not exists(select 1 from storage.objects where bucket_id='face-evidence'),'other user cannot read media');
select pg_temp.denied('select public.submit_face_verification((select (data->>''id'')::uuid from face_test_attempt),(select (data->>''nonce'')::uuid from face_test_attempt),''webm'')','cross-user submit denied');
reset role;
select set_config('request.jwt.claims','{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}',true);
set local role authenticated;
select pg_temp.check_true(exists(select 1 from public.face_verification_attempts),'admin can see queue');
select pg_temp.denied('select public.review_face_verification((select (data->>''id'')::uuid from face_test_attempt),gen_random_uuid(),''approved'','''')','stale evidence approval denied');
select public.review_face_verification((select (data->>'id')::uuid from face_test_attempt),(select (data->>'evidence_version')::uuid from face_test_attempt),'approved','Reviewed all movements');
select pg_temp.check_true((select reviewed_by=auth.uid() and reviewed_at is not null from public.face_verification_attempts where id=(select (data->>'id')::uuid from face_test_attempt)),'approval stamps admin and time');
select pg_temp.denied('select public.review_face_verification((select (data->>''id'')::uuid from face_test_attempt),(select (data->>''evidence_version'')::uuid from face_test_attempt),''rejected'',''late decision'')','old review cannot overwrite decision');
reset role;
select set_config('request.jwt.claims','{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}',true);
set local role authenticated;
select pg_temp.check_true(public.can_publish_listings(),'admin face approval enables publishing');
do $$
begin
  begin
    perform public.create_marketplace_booking(null,now()+interval '1 day',now()+interval '2 days','day',1);
    raise exception 'Expected missing listing';
  exception when sqlstate 'P0002' then
    perform pg_temp.check_true(true,'admin-approved face passes booking approval gate');
  end;
end $$;

select pg_temp.check_true(public.face_verification_status()->>'status'='verified','approved user sees approval');
select pg_temp.check_true((select verification_status='none' from public.profiles where id=auth.uid()),'face approval never grants document identity status');
select pg_temp.check_true(not exists(select 1 from public.public_profiles where id=auth.uid() and identity_verified),'no false public identity badge');
select pg_temp.denied('update public.profiles set role=''admin'' where id=auth.uid()','existing role guard preserved');
reset role;
select pg_temp.check_true(not exists(select 1 from pg_trigger where tgname='on_document_verified'),'document stamps no longer auto-approve');
-- A manual attempt requires a recorded exception for approval.
update public.profiles set verification_status='none' where id='33333333-3333-3333-3333-333333333333';
select set_config('request.jwt.claims','{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}',true);
set local role authenticated;
truncate face_test_attempt;
insert into face_test_attempt select public.start_face_verification('manual');
insert into storage.objects(bucket_id,name,metadata)
select 'face-evidence',auth.uid()::text||'/'||(data->>'id')||'/selfie.jpg','{"size":1024,"mimetype":"image/jpeg"}'::jsonb from face_test_attempt;
select public.submit_face_verification((select (data->>'id')::uuid from face_test_attempt),(select (data->>'nonce')::uuid from face_test_attempt));
select pg_temp.denied('select public.record_face_evidence_deleted((select (data->>''id'')::uuid from face_test_attempt))','user cannot mark review media deleted');
reset role;
select set_config('request.jwt.claims','{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}',true);
set local role authenticated;
select pg_temp.denied('select public.review_face_verification((select (data->>''id'')::uuid from face_test_attempt),(select (data->>''evidence_version'')::uuid from face_test_attempt),''approved'','''')','manual approval requires a reason');
select public.review_face_verification((select (data->>'id')::uuid from face_test_attempt),(select (data->>'evidence_version')::uuid from face_test_attempt),'retry','Please capture in brighter light');
reset role;
select set_config('request.jwt.claims','{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}',true);
set local role authenticated;
select pg_temp.check_true(public.face_verification_status()->>'status'='retry','retry request reaches user');
truncate face_test_attempt;
insert into face_test_attempt select public.start_face_verification('guided');
reset role;
update public.face_verification_attempts set expires_at=now()-interval '1 minute' where id=(select (data->>'id')::uuid from face_test_attempt);
set local role authenticated;
select pg_temp.denied('select public.submit_face_verification((select (data->>''id'')::uuid from face_test_attempt),(select (data->>''nonce'')::uuid from face_test_attempt),''webm'')','expired attempt cannot submit');
select pg_temp.denied('insert into storage.objects(bucket_id,name,metadata) select ''face-evidence'',auth.uid()::text||''/''||(data->>''id'')||''/selfie.jpg'',''{"size":1024,"mimetype":"image/jpeg"}''::jsonb from face_test_attempt','expired attempt cannot upload');
reset role;
update public.app_settings set value='false' where key='face_review_enabled';
set local role authenticated;
select pg_temp.denied('select public.start_face_verification(''guided'')','disabled rollout switch blocks start');
select pg_temp.check_true((public.face_verification_status()->>'enabled')::boolean=false,'disabled switch reaches app');
reset role;

select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select public.record_face_evidence_deleted((select id from public.face_verification_attempts where user_id='44444444-4444-4444-4444-444444444444' and status='approved' limit 1));
select pg_temp.check_true((select status='approved' and reviewed_by is not null and media_deleted_at is not null from public.face_verification_attempts where user_id='44444444-4444-4444-4444-444444444444' and status='approved' limit 1),'retention preserves approval and audit metadata');
-- Simulate a pending attempt selected by the retention worker.
update public.face_verification_attempts set status='pending' where id=(select (data->>'id')::uuid from face_test_attempt);
select public.record_face_evidence_deleted((select (data->>'id')::uuid from face_test_attempt));
select pg_temp.check_true((select status='superseded' from public.face_verification_attempts where id=(select (data->>'id')::uuid from face_test_attempt)),'expired pending review can be retried after cleanup');
reset role;

rollback;
