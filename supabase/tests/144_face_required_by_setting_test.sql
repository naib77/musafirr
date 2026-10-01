-- LOCAL QA fixtures only; every change rolls back. Run with
-- `sh tool/qa/run_sql_tests.sh 144`.
--
-- Pins the two halves of 144: face_review_enabled decides whether a face is
-- required at all, and admin_approve_verification / admin_reject_verification
-- decide identity and face in one transaction.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.denied(statement text,label text) returns void language plpgsql as $$
declare refused boolean=false;
begin begin execute statement; exception when others then refused=true; end;
perform pg_temp.check_true(refused,label); end $$;
-- Impersonation helpers. Clearing the claims when dropping back matters: a
-- stale sub keeps auth.uid() non-null (see the 132 note in CLAUDE.md).
create function pg_temp.as_user(uid text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims',json_build_object('sub',uid,'role','authenticated')::text,true);
perform set_config('role','authenticated',true); end $$;
create function pg_temp.as_server() returns void language plpgsql as $$
begin perform set_config('role','postgres',true); perform set_config('request.jwt.claims','{}',true); end $$;
-- Every attempt in one transaction shares now(), so "latest attempt" would tie
-- and fall to the random id tiebreak. Age earlier attempts before a new one.
create function pg_temp.age_attempts() returns void language plpgsql as $$
begin perform pg_temp.as_server();
update public.face_verification_attempts set created_at=created_at-interval '1 hour'
  where user_id='44444444-4444-4444-4444-444444444444'; end $$;

select pg_temp.check_true((select count(*)=3 from public.profiles where id in ('44444444-4444-4444-4444-444444444444','33333333-3333-3333-3333-333333333333','55555555-5555-5555-5555-555555555555')),'local fixtures present');
select pg_temp.check_true((select role='admin' from public.profiles where id='55555555-5555-5555-5555-555555555555'),'fixture 5555 is an admin');
update public.profiles set verification_status='none',nid_verified=false,suspended_at=null,role='owner' where id='44444444-4444-4444-4444-444444444444';
delete from public.face_verification_attempts where user_id='44444444-4444-4444-4444-444444444444';
delete from public.owner_documents where user_id='44444444-4444-4444-4444-444444444444';
create temp table t_face(data jsonb);
grant all on t_face to authenticated;

-- Evidence the subject can submit: two document sides, then a face capture.
create function pg_temp.submit_identity(tag text) returns void language plpgsql as $$
begin
  insert into storage.objects(bucket_id,name,metadata) values
   ('documents',auth.uid()::text||'/nid/'||tag||'/front.png','{"size":1024,"mimetype":"image/png"}'),
   ('documents',auth.uid()::text||'/nid/'||tag||'/back.png','{"size":1024,"mimetype":"image/png"}');
  perform public.submit_identity_document('nid',auth.uid()::text||'/nid/'||tag||'/front.png',auth.uid()::text||'/nid/'||tag||'/back.png','1234567890');
end $$;
create function pg_temp.submit_face() returns void language plpgsql as $$
declare d jsonb;
begin
  d:=public.start_face_verification('guided');
  delete from t_face; insert into t_face values(d);
  insert into storage.objects(bucket_id,name,metadata) values
   ('face-evidence',auth.uid()::text||'/'||(d->>'id')||'/selfie.jpg','{"size":1024,"mimetype":"image/jpeg"}'),
   ('face-evidence',auth.uid()::text||'/'||(d->>'id')||'/clip.webm','{"size":4096,"mimetype":"video/webm"}');
  perform public.submit_face_verification((d->>'id')::uuid,(d->>'nonce')::uuid,'webm');
  -- evidence_version is what the admin saw; re-read it after submission.
  update t_face set data=(select to_jsonb(a) from public.face_verification_attempts a where a.id=(d->>'id')::uuid);
end $$;

----------------------------------------------------------------------------
-- 1. Switch OFF: an approved identity document is the whole requirement.
----------------------------------------------------------------------------
update public.app_settings set value='false' where key='face_review_enabled';
select pg_temp.check_true(not public.face_review_required(),'off: face not required');
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select pg_temp.submit_identity('off');
select pg_temp.check_true(public.verification_overview()->>'status'='pending','off: pending document reads pending, not none');
select pg_temp.check_true((public.verification_overview()->>'face_required')::boolean=false,'off: overview says face not required');
select pg_temp.denied('select public.start_face_verification(''guided'')','off: no capture can start');
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select pg_temp.check_true((public.admin_approve_verification('44444444-4444-4444-4444-444444444444','nid',
  '44444444-4444-4444-4444-444444444444/nid/off/front.png','44444444-4444-4444-4444-444444444444/nid/off/back.png')->>'identity_approved')::boolean,
  'off: one approve with no face verifies identity');
select pg_temp.check_true(public.has_approved_face_or_identity('44444444-4444-4444-4444-444444444444'),'off: identity alone satisfies the booking gate');
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select pg_temp.check_true(public.verification_overview()->>'status'='verified','off: overview verified');
select pg_temp.check_true(public.can_publish_listings(),'off: identity alone can publish');
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select pg_temp.denied('select public.admin_approve_verification(''44444444-4444-4444-4444-444444444444'',''nid'',''x'',''y'')','off: approving again with nothing waiting is refused');

----------------------------------------------------------------------------
-- 2. Switch ON: the same document-only account is blocked again.
----------------------------------------------------------------------------
select pg_temp.as_server();
update public.app_settings set value='true' where key='face_review_enabled';
select pg_temp.check_true(public.face_review_required(),'on: face required');
select pg_temp.check_true(not public.has_approved_face_or_identity('44444444-4444-4444-4444-444444444444'),'on: verified identity without face is blocked');
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select pg_temp.check_true(not public.can_publish_listings(),'on: cannot publish without face');
select pg_temp.check_true(public.verification_overview()->>'status'='none','on: overview asks for the face step');

-- Face-only resubmission: identity already verified, one pending face.
select pg_temp.submit_face();
select pg_temp.check_true(public.verification_overview()->>'status'='pending','on: verified identity + pending face reads pending');
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select pg_temp.denied('select public.admin_approve_verification(''44444444-4444-4444-4444-444444444444'',null,null,null,(select (data->>''id'')::uuid from t_face),gen_random_uuid())','on: stale face evidence version refused');
select pg_temp.check_true((select status='pending' from public.face_verification_attempts where id=(select (data->>'id')::uuid from t_face)),'on: refused approve left the face pending');

-- Face-only reject keeps the verified identity.
select pg_temp.check_true((public.admin_reject_verification('44444444-4444-4444-4444-444444444444','Face not visible',
  (select (data->>'id')::uuid from t_face),(select (data->>'evidence_version')::uuid from t_face))->>'face_rejected')::boolean,'on: face-only reject accepted');
select pg_temp.check_true((select verification_status='verified' and nid_verified from public.profiles where id='44444444-4444-4444-4444-444444444444'),'on: face reject does not revoke the verified identity');
select pg_temp.check_true((select status='rejected' and review_note='Face not visible' from public.face_verification_attempts where id=(select (data->>'id')::uuid from t_face)),'on: face rejected with the reason');

-- A rejected face may capture again; approving it unlocks the account.
select pg_temp.age_attempts();
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select pg_temp.submit_face();
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select pg_temp.check_true((select r->>'face_approved'='true' and r->>'identity_approved'='false'
  from (select public.admin_approve_verification('44444444-4444-4444-4444-444444444444',null,null,null,
    (select (data->>'id')::uuid from t_face),(select (data->>'evidence_version')::uuid from t_face)) r) s),'on: face-only approve after retry');
select pg_temp.check_true(public.has_approved_face_or_identity('44444444-4444-4444-4444-444444444444'),'on: identity + face unlocks booking gate');

----------------------------------------------------------------------------
-- 3. Switch ON, both halves waiting: one approve decides both, atomically.
----------------------------------------------------------------------------
select pg_temp.as_server();
update public.profiles set verification_status='rejected',nid_verified=false where id='44444444-4444-4444-4444-444444444444';
delete from public.face_verification_attempts where user_id='44444444-4444-4444-4444-444444444444';
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select pg_temp.submit_identity('both');
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select pg_temp.denied('select public.admin_approve_verification(''44444444-4444-4444-4444-444444444444'',''nid'',''44444444-4444-4444-4444-444444444444/nid/both/front.png'',''44444444-4444-4444-4444-444444444444/nid/both/back.png'')','on: identity approve refused while no face submitted');
select pg_temp.check_true((select verification_status='pending' from public.profiles where id='44444444-4444-4444-4444-444444444444'),'on: refused approve left identity pending');
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select pg_temp.submit_face();
select pg_temp.check_true(public.verification_overview()->>'status'='pending','on: both pending reads pending');

-- Self-approval and anon are refused, whatever the role.
select pg_temp.denied('select public.admin_approve_verification(auth.uid(),''nid'',''x'',''y'')','subject cannot approve themselves');
select pg_temp.as_server();
set local role anon;
select pg_temp.denied('select public.admin_approve_verification(''44444444-4444-4444-4444-444444444444'',''nid'',''x'',''y'')','anon cannot call combined approve');
select pg_temp.denied('select public.admin_reject_verification(''44444444-4444-4444-4444-444444444444'',''no'')','anon cannot call combined reject');
reset role;
-- Another signed-in non-admin.
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select pg_temp.denied('select public.admin_approve_verification(''44444444-4444-4444-4444-444444444444'',''nid'',''x'',''y'')','non-admin cannot approve');

-- Atomicity: stale document paths with a good face must approve neither.
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select pg_temp.denied('select public.admin_approve_verification(''44444444-4444-4444-4444-444444444444'',''nid'',''stale'',''stale'',(select (data->>''id'')::uuid from t_face),(select (data->>''evidence_version'')::uuid from t_face))','on: stale document paths refused');
select pg_temp.check_true((select status='pending' from public.face_verification_attempts where id=(select (data->>'id')::uuid from t_face)),'on: stale document left the face pending too');
-- Face belonging to another account is refused.
select pg_temp.denied('select public.admin_approve_verification(''33333333-3333-3333-3333-333333333333'',''nid'',''x'',''y'',(select (data->>''id'')::uuid from t_face),(select (data->>''evidence_version'')::uuid from t_face))','face of another account refused');

-- Combined reject rejects both halves with one reason.
select pg_temp.denied('select public.admin_reject_verification(''44444444-4444-4444-4444-444444444444'','''')','reject needs a reason');
select pg_temp.check_true((select r->>'identity_rejected'='true' and r->>'face_rejected'='true'
  from (select public.admin_reject_verification('44444444-4444-4444-4444-444444444444','Photos are blurry',
    (select (data->>'id')::uuid from t_face),(select (data->>'evidence_version')::uuid from t_face)) r) s),'on: combined reject decides both');
select pg_temp.check_true((select verification_status='rejected' and not nid_verified from public.profiles where id='44444444-4444-4444-4444-444444444444'),'on: identity rejected');
select pg_temp.check_true((select bool_and(rejection_reason='Photos are blurry' and verified_at is null) from public.owner_documents where user_id='44444444-4444-4444-4444-444444444444'),'on: document rows carry the reason');

-- Resubmit both and approve both with one call.
select pg_temp.age_attempts();
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select pg_temp.submit_identity('again');
select pg_temp.submit_face();
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select pg_temp.check_true((select r->>'identity_approved'='true' and r->>'face_approved'='true'
  from (select public.admin_approve_verification('44444444-4444-4444-4444-444444444444','nid',
    '44444444-4444-4444-4444-444444444444/nid/again/front.png','44444444-4444-4444-4444-444444444444/nid/again/back.png',
    (select (data->>'id')::uuid from t_face),(select (data->>'evidence_version')::uuid from t_face)) r) s),'on: one approve verifies identity and face');
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select pg_temp.check_true(public.verification_overview()->>'status'='verified','on: overview verified after combined approve');
select pg_temp.check_true(public.can_publish_listings(),'on: can publish after combined approve');

select pg_temp.as_server();
select pg_temp.check_true(not exists(select 1 from pg_proc, unnest(proacl) a
  where proname in ('admin_approve_verification','admin_reject_verification','face_review_required')
    and (a::text like 'anon=%' or a::text like '=%')),
  'no anon or PUBLIC execute on the combined RPCs');
rollback;
