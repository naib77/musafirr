-- LOCAL QA fixtures only; every change rolls back. Run with
-- `sh tool/qa/run_sql_tests.sh 158` after applying 157 and 158 locally.
--
-- Pins 158: an object registered in storage_assets (an S3 upload) satisfies
-- every verifier that used to look in storage.objects, with the same size and
-- type limits; a deleted asset does not; admins may write avatars and listing
-- images; the purge hook is service-only and hands back exact versions.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.err_of(stmt text) returns text language plpgsql as $$
begin
  execute stmt;
  return null;
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;
create function pg_temp.act_as(uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', case when uid is null then
    json_build_object('role', 'anon')::text else
    json_build_object('sub', uid, 'role', 'authenticated')::text end, true);
  execute format('set local role %I', case when uid is null then 'anon' else 'authenticated' end);
end $$;
create function pg_temp.as_postgres() returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', '', true);
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;

\set H '''11111111-1111-1111-1111-111111111111'''
\set S '''33333333-3333-3333-3333-333333333333'''
\set A '''55555555-5555-5555-5555-555555555555'''
\set SHA '''aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'''

-- Registers an S3 object the way storage_commit_upload would.
create function pg_temp.s3_asset(b text, p text, owner uuid, mime text, size bigint) returns void
language sql as $$
  insert into public.storage_assets (bucket, path, owner_id, mime_type, size_bytes, sha256,
         s3_bucket, s3_key, s3_version)
  values (b, p, owner, mime, size, repeat('a', 64), 'phys', b || '/' || p || '@x', 'v1');
$$;

-- ---------------------------------------------------------------- face
insert into public.face_verification_attempts (id, user_id, method, actions)
values ('f0000000-0000-0000-0000-000000000001', :S, 'manual', '{}');
select pg_temp.act_as(:S);
select pg_temp.check_true(
  pg_temp.err_of($q$select public.submit_face_verification('f0000000-0000-0000-0000-000000000001',
    (select nonce from public.face_verification_attempts where id='f0000000-0000-0000-0000-000000000001'))$q$)
    like '%Selfie upload is missing%',
  'face submit with nothing uploaded is refused');
select pg_temp.as_postgres();
select pg_temp.s3_asset('face-evidence', :S || '/f0000000-0000-0000-0000-000000000001/selfie.jpg',
  :S, 'image/jpeg', 50);
select pg_temp.act_as(:S);
select pg_temp.check_true(
  pg_temp.err_of($q$select public.submit_face_verification('f0000000-0000-0000-0000-000000000001',
    (select nonce from public.face_verification_attempts where id='f0000000-0000-0000-0000-000000000001'))$q$)
    like '%Selfie upload is missing%',
  'an S3 selfie under the size floor is still refused');
select pg_temp.as_postgres();
update public.storage_assets set size_bytes = 4000
 where bucket = 'face-evidence' and path like :S || '/f0000000%';
select pg_temp.act_as(:S);
select pg_temp.check_true(
  pg_temp.err_of($q$select public.submit_face_verification('f0000000-0000-0000-0000-000000000001',
    (select nonce from public.face_verification_attempts where id='f0000000-0000-0000-0000-000000000001'))$q$)
    is null,
  'face submit accepts a selfie that is only in S3');
select pg_temp.as_postgres();
select pg_temp.check_true(
  (select status from public.face_verification_attempts where id='f0000000-0000-0000-0000-000000000001') = 'pending',
  'attempt moved to pending');

-- ---------------------------------------------------------------- NID
update public.profiles set verification_status = 'none', id_document_type = null where id = :S;
select pg_temp.s3_asset('documents', :S || '/nid/front.jpg', :S, 'image/jpeg', 2000);
select pg_temp.s3_asset('documents', :S || '/nid/back.jpg', :S, 'image/jpeg', 2000);
select pg_temp.s3_asset('documents', :S || '/nid/fake.jpg', :S, 'image/gif', 2000);
select pg_temp.act_as(:S);
select pg_temp.check_true(
  pg_temp.err_of(format($q$select public.submit_identity_document('nid', %L, %L)$q$,
    :S || '/nid/fake.jpg', :S || '/nid/back.jpg')) like '%JPG or PNG%',
  'NID submit still enforces the type, from the registry');
select pg_temp.check_true(
  pg_temp.err_of(format($q$select public.submit_identity_document('nid', %L, %L)$q$,
    :S || '/nid/front.jpg', :S || '/nid/back.jpg')) is null,
  'NID submit accepts S3 sides');
select pg_temp.as_postgres();
select pg_temp.check_true(
  (select mime_type from public.owner_documents where user_id = :S and document_type = 'nid_front') = 'image/jpeg',
  'owner_documents.mime_type comes from the registry');
select pg_temp.act_as(:A);
select pg_temp.check_true(
  pg_temp.err_of(format($q$select public.approve_identity_document(%L, 'nid', %L, %L)$q$,
    :S, :S || '/nid/front.jpg', :S || '/nid/back.jpg')) is null,
  'admin approval finds S3 evidence');

-- A deleted asset is gone, even if a stale legacy copy existed.
select pg_temp.as_postgres();
update public.storage_assets set state = 'deleted' where bucket = 'documents' and path = :S || '/nid/front.jpg';
select pg_temp.check_true(
  not exists (select 1 from public.storage_object_meta('documents', :S || '/nid/front.jpg')),
  'deleted asset has no meta');

-- ---------------------------------------------------------------- trade licence
update public.listings set listing_type = 'hotel' where id = 'aaaaaaaa-0000-0000-0000-000000000002';
select pg_temp.s3_asset('documents', :H || '/trade_licence/l.pdf', :H, 'application/pdf', 3000);
select pg_temp.s3_asset('documents', :H || '/trade_licence/stolen.pdf', :S, 'application/pdf', 3000);
select pg_temp.act_as(:H);
select pg_temp.check_true(
  pg_temp.err_of(format($q$select public.submit_trade_licence('aaaaaaaa-0000-0000-0000-000000000002', %L)$q$,
    :H || '/trade_licence/stolen.pdf')) like '42501%',
  'licence uploaded by someone else is refused (registry owner)');
select pg_temp.check_true(
  pg_temp.err_of(format($q$select public.submit_trade_licence('aaaaaaaa-0000-0000-0000-000000000002', %L)$q$,
    :H || '/trade_licence/l.pdf')) is null,
  'licence submit accepts an S3 document');
select pg_temp.as_postgres();
update public.listing_trade_licences set status = 'verified' where listing_id = 'aaaaaaaa-0000-0000-0000-000000000002';
select pg_temp.check_true(public.listing_licence_verified('aaaaaaaa-0000-0000-0000-000000000002'),
  'licence badge sees the S3 document');

-- ---------------------------------------------------------------- admin arms
-- The can_* helpers are not executable by users; evaluate them as postgres
-- with the caller's claims, which is how the definer RPCs run them.
select pg_temp.as_postgres();
select set_config('request.jwt.claims', json_build_object('sub', :A, 'role', 'authenticated')::text, true);
select pg_temp.check_true(public.storage_can_insert('avatars', :H || '.webp'), 'admin may set a user avatar');
select pg_temp.check_true(public.storage_can_insert('listing-images', 'aaaaaaaa-0000-0000-0000-000000000002/x.jpg'),
  'admin may add a listing image');
select pg_temp.check_true(public.storage_can_delete('avatars', :H || '.png', :H), 'admin may remove an avatar');
select pg_temp.check_true(not public.storage_can_replace('documents', :H || '/nid/a.jpg', :H),
  'admin still cannot replace NID evidence');
select set_config('request.jwt.claims', json_build_object('sub', :S, 'role', 'authenticated')::text, true);
select pg_temp.check_true(not public.storage_can_insert('avatars', :H || '.webp'), 'stranger still cannot set an avatar');

-- ---------------------------------------------------------------- retention
select pg_temp.as_postgres();
select pg_temp.s3_asset('face-evidence', :S || '/f0000000-0000-0000-0000-00000000dead/selfie.jpg', :S, 'image/jpeg', 4000);
select set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
set local role service_role;
select pg_temp.check_true(
  exists (select 1 from public.orphan_face_evidence() where name like '%0000dead/selfie.jpg'),
  'orphan scan includes S3-only evidence');
select pg_temp.check_true(
  (select s3_version from public.storage_purge_begin('face-evidence',
     array[:S || '/f0000000-0000-0000-0000-00000000dead/selfie.jpg'])) = 'v1',
  'purge hands back the exact version');
select pg_temp.check_true(
  (select state from public.storage_assets where path like '%0000dead/selfie.jpg') = 'deleting',
  'purged asset is marked deleting');
select pg_temp.act_as(:S);
select pg_temp.check_true(
  pg_temp.err_of($q$select * from public.storage_purge_begin('face-evidence', array['x'])$q$) like '42501%',
  'users cannot purge');
select pg_temp.check_true(
  pg_temp.err_of($q$select * from public.storage_object_meta('documents', 'x')$q$) like '42501%',
  'users cannot probe object meta');

rollback;
