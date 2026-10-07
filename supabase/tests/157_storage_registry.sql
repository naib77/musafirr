-- LOCAL QA fixtures only; every change rolls back. Run with
-- `sh tool/qa/run_sql_tests.sh 157` after applying 157 locally.
--
-- Pins 157 against the storage.objects policies it mirrors: who may begin an
-- upload where, upsert=false onto an existing object is a conflict, a
-- replacement keeps the original owner, NID evidence cannot be replaced or
-- deleted, finalize rechecks the caller, commit is service-only and must
-- match its ticket, and reads/deletes follow the same owner/admin rules.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.hint_of(stmt text) returns text language plpgsql as $$
declare h text;
begin
  execute stmt;
  return null;
exception when others then
  get stacked diagnostics h = pg_exception_hint;
  return coalesce(nullif(h, ''), sqlstate);
end $$;
-- SQLSTATE only: a permission error carries Postgres's own "Grant the
-- required privileges" hint, which hint_of would return instead.
create function pg_temp.state_of(stmt text) returns text language plpgsql as $$
begin
  execute stmt;
  return null;
exception when others then
  return sqlstate;
end $$;
-- Acts as a user (or anon when uid is null) for the rest of the transaction.
create function pg_temp.act_as(uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', case when uid is null then
    json_build_object('role', 'anon')::text else
    json_build_object('sub', uid, 'role', 'authenticated')::text end, true);
  execute format('set local role %I', case when uid is null then 'anon' else 'authenticated' end);
end $$;
create function pg_temp.as_service() returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', '', true);
  set local role service_role;
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;

\set H '''11111111-1111-1111-1111-111111111111'''
\set S '''33333333-3333-3333-3333-333333333333'''
\set A '''55555555-5555-5555-5555-555555555555'''
\set SHA '''aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'''

-- Clients cannot see or write the registry at all.
select pg_temp.act_as(:H);
select pg_temp.check_true(
  pg_temp.state_of('select count(*) from public.storage_assets') = '42501',
  'authenticated cannot read storage_assets');
select pg_temp.check_true(
  pg_temp.state_of($q$insert into public.storage_assets (bucket,path,owner_id,mime_type,size_bytes,sha256)
    values ('avatars','x.webp',auth.uid(),'image/webp',1,repeat('a',64))$q$) = '42501',
  'authenticated cannot forge an asset row');
select pg_temp.check_true(
  pg_temp.state_of(format($q$select public.storage_commit_upload(gen_random_uuid(),1,%L,'image/webp','b','k','v')$q$, :SHA)) = '42501',
  'authenticated cannot commit verified metadata');

-- Anonymous: no uploads, public reads only.
select pg_temp.act_as(null);
select pg_temp.check_true(
  pg_temp.state_of($q$select public.storage_begin_upload('chat-attachments','c1/a.pdf','application/pdf',10,false,'anon-key-1')$q$) = '42501',
  'anon cannot begin an upload');

-- Bucket rules come from storage.buckets.
select pg_temp.act_as(:H);
select pg_temp.check_true(
  pg_temp.hint_of(format($q$select public.storage_begin_upload('avatars',%L,'image/webp',3000000,true,'h-big-0001')$q$, :H || '.webp')) = 'storage_too_large',
  'avatar over 2 MiB refused');
select pg_temp.check_true(
  pg_temp.hint_of(format($q$select public.storage_begin_upload('avatars',%L,'image/gif',10,true,'h-gif-0001')$q$, :H || '.gif')) = 'storage_mime',
  'avatar gif refused');
select pg_temp.check_true(
  pg_temp.hint_of($q$select public.storage_begin_upload('documents','../etc/passwd','application/pdf',10,false,'h-path-001')$q$) = 'storage_path',
  'path traversal refused');

-- Avatars: own file name only.
select pg_temp.check_true(
  pg_temp.hint_of(format($q$select public.storage_begin_upload('avatars',%L,'image/webp',10,true,'h-av-other')$q$, :S || '.webp')) = 'storage_denied',
  'cannot upload another user''s avatar');
select pg_temp.check_true(
  pg_temp.hint_of(format($q$select public.storage_begin_upload('avatars',%L,'image/webp',10,true,'h-av-own01')$q$, :H || '.webp')) is null,
  'own avatar upload begins');

-- Documents: own folder only.
select pg_temp.check_true(
  pg_temp.hint_of(format($q$select public.storage_begin_upload('documents',%L,'application/pdf',10,false,'h-doc-othr')$q$, :S || '/address/a.pdf')) = 'storage_denied',
  'cannot upload into another user''s documents folder');

-- Listing images follow can_upload_listing_image(): a host with listings may,
-- a tenant who cannot publish may not.
select pg_temp.check_true(
  pg_temp.hint_of($q$select public.storage_begin_upload('listing-images','draft-1/a.webp','image/webp',10,false,'h-li-00001')$q$) is null,
  'host may upload a listing image before the listing exists');
select pg_temp.act_as(:S);
select pg_temp.check_true(
  pg_temp.hint_of($q$select public.storage_begin_upload('listing-images','draft-2/a.webp','image/webp',10,false,'s-li-00001')$q$)
    is not distinct from case when public.can_upload_listing_image() then null else 'storage_denied' end,
  'tenant listing upload matches can_upload_listing_image()');
-- Chat: any signed-in user, as today.
select pg_temp.check_true(
  pg_temp.hint_of($q$select public.storage_begin_upload('chat-attachments','conv-x/a.pdf','application/pdf',10,false,'s-chat-001')$q$) is null,
  'any signed-in user may begin a chat upload (current policy)');
-- Face evidence needs a live draft attempt for exactly that path.
select pg_temp.check_true(
  pg_temp.hint_of(format($q$select public.storage_begin_upload('face-evidence',%L,'image/jpeg',10,false,'s-face-001')$q$,
    :S || '/00000000-0000-0000-0000-000000000000/selfie.jpg')) = 'storage_denied',
  'face upload without a draft attempt refused');

-- Idempotency: same key and params returns the same intent; other params refuse.
select pg_temp.act_as(:H);
create temp table t_intent on commit drop as
  select public.storage_begin_upload('documents', '11111111-1111-1111-1111-111111111111/address/p.pdf',
    'application/pdf', 1234, false, 'h-doc-0001') j;
grant select on t_intent to authenticated, service_role;
select pg_temp.check_true(
  (public.storage_begin_upload('documents', '11111111-1111-1111-1111-111111111111/address/p.pdf',
    'application/pdf', 1234, false, 'h-doc-0001')->>'intent_id') = (select j->>'intent_id' from t_intent),
  'retry with the same idempotency key returns the same intent');
select pg_temp.check_true(
  pg_temp.hint_of($q$select public.storage_begin_upload('documents','11111111-1111-1111-1111-111111111111/address/q.pdf','application/pdf',1234,false,'h-doc-0001')$q$) = 'storage_idempotency_mismatch',
  'reused idempotency key with a different path refused');
select pg_temp.check_true(
  (select j->>'staging_key' from t_intent) = 'staging/' || (select j->>'intent_id' from t_intent),
  'staging key is derived from the intent id');

-- Another user cannot claim it.
select pg_temp.act_as(:S);
select pg_temp.check_true(
  pg_temp.hint_of(format('select public.storage_claim_intent(%L)', (select j->>'intent_id' from t_intent))) = 'storage_not_found',
  'another user cannot finalize my upload');

-- Owner claims; a second concurrent claim is busy.
select pg_temp.act_as(:H);
create temp table t_claim on commit drop as
  select public.storage_claim_intent((select (j->>'intent_id')::uuid from t_intent)) j;
grant select on t_claim to authenticated, service_role;
select pg_temp.check_true((select j->>'state' from t_claim) = 'finalizing', 'owner claims the intent');
select pg_temp.check_true(
  pg_temp.hint_of(format('select public.storage_claim_intent(%L)', (select j->>'intent_id' from t_intent))) = 'storage_busy',
  'second concurrent finalize is refused');

-- Commit must match the ticket.
select pg_temp.as_service();
select pg_temp.check_true(
  pg_temp.hint_of(format($q$select public.storage_commit_upload(%L, 9999, %L, 'application/pdf', 'phys-docs', %L, 'v1')$q$,
    (select j->>'intent_id' from t_intent), :SHA, (select j->>'committed_key' from t_claim))) = 'storage_mismatch',
  'commit with a different size is refused');
select pg_temp.check_true(
  pg_temp.hint_of(format($q$select public.storage_commit_upload(%L, 1234, %L, 'application/pdf', 'phys-docs', 'documents/other@x', 'v1')$q$,
    (select j->>'intent_id' from t_intent), :SHA)) = 'storage_mismatch',
  'commit to a key other than the ticket''s is refused');
select pg_temp.check_true(
  (public.storage_commit_upload((select (j->>'intent_id')::uuid from t_intent), 1234, :SHA,
    'application/pdf', 'phys-docs', (select j->>'committed_key' from t_claim), 'v1')->>'generation') = '1',
  'service commits the verified object');
select pg_temp.check_true(
  (select owner_id from public.storage_assets where path = '11111111-1111-1111-1111-111111111111/address/p.pdf') = :H::uuid,
  'asset owner is the uploader, not the service');

-- A retried finalize after commit is a no-op that reports the asset.
select pg_temp.act_as(:H);
select pg_temp.check_true(
  public.storage_claim_intent((select (j->>'intent_id')::uuid from t_intent))->>'state' = 'finalized',
  'finalize retry after commit reports finalized');

-- upsert=false onto the now-existing object conflicts; upsert=true replaces
-- (non-NID documents are owner-replaceable today).
select pg_temp.check_true(
  pg_temp.hint_of($q$select public.storage_begin_upload('documents','11111111-1111-1111-1111-111111111111/address/p.pdf','application/pdf',10,false,'h-doc-0002')$q$) = 'storage_exists',
  'upsert=false onto an existing object conflicts');
select pg_temp.check_true(
  pg_temp.hint_of($q$select public.storage_begin_upload('documents','11111111-1111-1111-1111-111111111111/address/p.pdf','application/pdf',10,true,'h-doc-0003')$q$) is null,
  'owner may replace a non-NID document (current behaviour)');

-- Reads: owner and admin see private documents, a stranger and anon do not.
create temp table t_ref on commit drop as
  select '[{"bucket":"documents","path":"11111111-1111-1111-1111-111111111111/address/p.pdf"}]'::jsonb r;
grant select on t_ref to anon, authenticated, service_role;
select pg_temp.check_true((select count(*) from public.storage_resolve_reads((select r from t_ref))) = 1, 'owner resolves own document');
select pg_temp.act_as(:A);
select pg_temp.check_true((select count(*) from public.storage_resolve_reads((select r from t_ref))) = 1, 'admin resolves the document');
select pg_temp.act_as(:S);
select pg_temp.check_true((select count(*) from public.storage_resolve_reads((select r from t_ref))) = 0, 'stranger cannot resolve it');
select pg_temp.act_as(null);
select pg_temp.check_true((select count(*) from public.storage_resolve_reads((select r from t_ref))) = 0, 'anon cannot resolve it');

-- Deletes: stranger refused, missing path quiet, owner allowed.
select pg_temp.act_as(:S);
select pg_temp.check_true(
  pg_temp.hint_of($q$select public.storage_begin_delete('documents','11111111-1111-1111-1111-111111111111/address/p.pdf')$q$) = 'storage_denied',
  'stranger cannot delete my document');
select pg_temp.check_true(public.storage_begin_delete('documents', 'nobody/none.pdf') is null,
  'deleting a missing path is quiet');
select pg_temp.act_as(:H);
select pg_temp.check_true(
  public.storage_begin_delete('documents','11111111-1111-1111-1111-111111111111/address/p.pdf')->>'s3_bucket' = 'phys-docs',
  'owner begins delete and gets the S3 location');

-- NID evidence: never replaceable or deletable by its owner.
select pg_temp.as_service();
insert into public.storage_assets (bucket, path, owner_id, mime_type, size_bytes, sha256, s3_bucket, s3_key, s3_version)
values ('documents', '11111111-1111-1111-1111-111111111111/nid/x/front.jpeg', :H, 'image/jpeg', 10, :SHA, 'phys-docs', 'k-nid', 'v1');
select pg_temp.act_as(:H);
select pg_temp.check_true(
  pg_temp.hint_of($q$select public.storage_begin_upload('documents','11111111-1111-1111-1111-111111111111/nid/x/front.jpeg','image/jpeg',10,true,'h-nid-0001')$q$) = 'storage_denied',
  'NID evidence cannot be replaced');
select pg_temp.check_true(
  pg_temp.hint_of($q$select public.storage_begin_delete('documents','11111111-1111-1111-1111-111111111111/nid/x/front.jpeg')$q$) = 'storage_denied',
  'NID evidence cannot be deleted');

-- Listing image replacement by an admin keeps the host as owner.
select pg_temp.as_service();
insert into public.storage_assets (bucket, path, owner_id, mime_type, size_bytes, sha256, s3_bucket, s3_key, s3_version)
values ('listing-images', 'L1/a.webp', :H, 'image/webp', 10, :SHA, 'phys-pub', 'listing-images/L1/a.webp@0', 'v1');
select pg_temp.act_as(:S);
select pg_temp.check_true(
  pg_temp.hint_of($q$select public.storage_begin_upload('listing-images','L1/a.webp','image/webp',10,true,'s-li-repl1')$q$) = 'storage_denied',
  'stranger cannot replace a host''s listing image');
select pg_temp.act_as(:A);
create temp table t_adm on commit drop as
  select public.storage_begin_upload('listing-images','L1/a.webp','image/webp',20,true,'a-li-repl1') j;
grant select on t_adm to authenticated, service_role;
create temp table t_adm_claim on commit drop as
  select public.storage_claim_intent((select (j->>'intent_id')::uuid from t_adm)) j;
grant select on t_adm_claim to authenticated, service_role;
select pg_temp.as_service();
select public.storage_commit_upload((select (j->>'intent_id')::uuid from t_adm), 20, :SHA, 'image/webp',
  'phys-pub', (select j->>'committed_key' from t_adm_claim), 'v2');
select pg_temp.check_true(
  (select owner_id = :H::uuid and generation = 2 and s3_version = 'v2' from public.storage_assets where path = 'L1/a.webp'),
  'admin replacement bumps generation and keeps the host as owner');

-- Public media resolves for anon.
select pg_temp.act_as(null);
select pg_temp.check_true(
  (select count(*) from public.storage_resolve_reads('[{"bucket":"listing-images","path":"L1/a.webp"}]')) = 1,
  'anon resolves public listing media');
reset role;
rollback;
