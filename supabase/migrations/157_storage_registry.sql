-- 157: S3 storage registry and upload authorization (S3 plan, stage 2).
--
-- Purely additive. Nothing in either app reads these tables yet; the
-- `storage-signer` edge function is the only caller, and it is not deployed.
-- Supabase Storage stays authoritative until stage 4 routes a bucket.
--
-- Two tables, not four (plan §5): an upload *intent* is what a signed POST
-- ticket was issued for; an *asset* is a verified, committed object. Clients
-- can touch neither directly — every write goes through the definer
-- functions below, and the ones that record verified bytes are service-role
-- only, so a caller cannot make an unuploaded file look real by inserting a
-- row.
--
-- Authorization mirrors the nineteen live `storage.objects` policies (plan
-- §3) rather than improving on them: chat stays "any authenticated user may
-- upload", listing images stay `can_upload_listing_image()`, non-NID
-- documents stay owner-replaceable. Each helper names the policy it copies.
-- Tightening any of them is a separate, decided change, not a side effect of
-- moving bytes.
--
-- Every caller-facing check runs under the caller's own JWT (`auth.uid()`),
-- including the recheck at finalize time (`storage_claim_intent`), so the
-- signer never needs a "user id" parameter it would have to be trusted with.

-- ============================================================ tables

create table if not exists public.storage_upload_intents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  bucket text not null references storage.buckets(id),
  path text not null,
  upsert boolean not null,
  mime_type text not null,
  size_bytes bigint not null check (size_bytes > 0),
  idempotency_key text not null check (length(idempotency_key) between 8 and 128),
  -- Derived here, never by the client. The staging key is unique per intent,
  -- so a replayed presigned POST can only ever rewrite its own staging
  -- object; the committed key is unique per intent too, so a promoted
  -- version is never overwritten in place (plan §6).
  staging_key text not null unique,
  committed_key text not null unique,
  state text not null default 'pending'
    check (state in ('pending', 'finalizing', 'finalized', 'rejected')),
  reject_reason text,
  claimed_at timestamptz,
  asset_id uuid,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '15 minutes',
  finalized_at timestamptz,
  unique (user_id, idempotency_key)
);

create table if not exists public.storage_assets (
  id uuid primary key default gen_random_uuid(),
  bucket text not null references storage.buckets(id),
  path text not null,
  -- The logical owner, which drives the owner-or-admin delete/update rules.
  -- A migration copy keeps the Supabase object's owner; it never becomes the
  -- copying service (plan §3).
  owner_id uuid not null,
  generation integer not null default 1,
  mime_type text not null,
  size_bytes bigint not null,
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  business_created_at timestamptz not null default now(),
  retention_deadline timestamptz,
  state text not null default 'active' check (state in ('active', 'deleting', 'deleted')),
  -- Two verified locations are enough for coexistence and rollback (§5).
  supabase_path text,
  s3_bucket text,
  s3_key text,
  s3_version text,
  updated_at timestamptz not null default now(),
  -- One row per logical object. A replacement bumps `generation` and moves
  -- the S3 location; the old version stays in the versioned bucket.
  unique (bucket, path),
  check ((s3_bucket is null) = (s3_key is null))
);

alter table public.storage_upload_intents enable row level security;
alter table public.storage_assets enable row level security;
-- No policies: default privileges grant SELECT/INSERT to anon and
-- authenticated at create time, and RLS with no policy is the gate. Revoke as
-- well so a later permissive policy cannot open them by accident.
revoke all on public.storage_upload_intents from public, anon, authenticated;
revoke all on public.storage_assets from public, anon, authenticated;
grant all on public.storage_upload_intents, public.storage_assets to service_role;

-- ============================================================ helpers

-- `storage.foldername(name)[1]`: the first folder, or null for a bare file
-- name — `avatars/{uid}.webp` has no folder, and the documents policy must
-- not read the file name as one.
create or replace function public.storage_first_folder(p_path text)
returns text language sql immutable set search_path = '' as $$
  select case when position('/' in p_path) > 0 then split_part(p_path, '/', 1) end;
$$;

-- `storage.filename(name)`: the last segment.
create or replace function public.storage_file_name(p_path text)
returns text language sql immutable set search_path = '' as $$
  select regexp_replace(p_path, '^.*/', '');
$$;

-- Keys the backend will accept. Clients name logical paths only; this keeps
-- them to the shapes the apps already produce and out of S3's special cases.
create or replace function public.storage_path_ok(p_path text)
returns boolean language sql immutable set search_path = '' as $$
  select p_path is not null
     and length(p_path) between 1 and 512
     and p_path !~ '(^/|/$|//|\\)'
     and p_path !~ '(^|/)\.\.?(/|$)'
     and p_path ~ '^[A-Za-z0-9._/-]+$';
$$;

-- The existing object at a logical path, from whichever provider holds it.
-- Coexistence means a path can exist in Supabase only; an upload with
-- upsert=false must still be refused there, exactly as Supabase would.
create or replace function public.storage_existing_owner(p_bucket text, p_path text)
returns table (found boolean, owner_id uuid)
language sql stable security definer set search_path = '' as $$
  select true, a.owner_id from public.storage_assets a
   where a.bucket = p_bucket and a.path = p_path and a.state <> 'deleted'
  union all
  select true, o.owner from storage.objects o
   where o.bucket_id = p_bucket and o.name = p_path
     and not exists (select 1 from public.storage_assets a
                      where a.bucket = p_bucket and a.path = p_path)
  limit 1;
$$;

-- INSERT policies: avatars_owner_insert, listing_images_publisher_insert,
-- chat_attachments_authenticated_insert, documents_owner_insert,
-- face_evidence_insert.
create or replace function public.storage_can_insert(p_bucket text, p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and case p_bucket
    when 'avatars' then public.storage_file_name(p_path) like auth.uid()::text || '.%'
    when 'listing-images' then public.can_upload_listing_image()
    when 'chat-attachments' then true
    when 'documents' then public.storage_first_folder(p_path) = auth.uid()::text
    when 'face-evidence' then exists (
      select 1 from public.face_verification_attempts a
       where a.user_id = auth.uid() and a.status = 'draft' and a.expires_at > now()
         and p_path in (a.user_id || '/' || a.id || '/selfie.jpg',
                        a.user_id || '/' || a.id || '/clip.webm',
                        a.user_id || '/' || a.id || '/clip.mp4'))
    else false end;
$$;

-- UPDATE policies, which is what an upsert onto an existing object needs:
-- avatars_owner_update, listing_images_owner_update, documents_owner_update
-- under the restrictive nid_evidence_no_update. chat-attachments and
-- face-evidence have no update policy at all.
create or replace function public.storage_can_replace(p_bucket text, p_path text, p_owner uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and case p_bucket
    when 'avatars' then public.storage_file_name(p_path) like auth.uid()::text || '.%'
    when 'listing-images' then p_owner = auth.uid() or public.is_admin()
    when 'documents' then public.storage_first_folder(p_path) = auth.uid()::text
                      and split_part(p_path, '/', 2) <> 'nid'
    else false end;
$$;

-- DELETE policies: avatars_owner_delete, listing_images_owner_delete,
-- chat_attachments_owner_delete, documents_owner_delete under the restrictive
-- nid_evidence_no_delete. face-evidence is deleted only by the retention job.
create or replace function public.storage_can_delete(p_bucket text, p_path text, p_owner uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and case p_bucket
    when 'avatars' then public.storage_file_name(p_path) like auth.uid()::text || '.%'
    when 'listing-images' then p_owner = auth.uid() or public.is_admin()
    when 'chat-attachments' then p_owner = auth.uid() or public.is_admin()
    when 'documents' then public.storage_first_folder(p_path) = auth.uid()::text
                      and split_part(p_path, '/', 2) <> 'nid'
    else false end;
$$;

-- SELECT policies: the three public buckets read for anyone;
-- documents_owner_or_admin_read, face_evidence_read.
create or replace function public.storage_can_read(p_bucket text, p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select case p_bucket
    when 'avatars' then true
    when 'listing-images' then true
    when 'chat-attachments' then true
    when 'documents' then auth.uid() is not null and (
      public.storage_first_folder(p_path) = auth.uid()::text or public.is_admin())
    when 'face-evidence' then auth.uid() is not null and (
      public.storage_first_folder(p_path) = auth.uid()::text or public.is_admin())
    else false end;
$$;

-- What an upload to this path would be: 'insert', 'replace', or the reason
-- it is refused. Mirrors Supabase: upsert=false onto an existing object is a
-- conflict even for someone allowed to replace it.
create or replace function public.storage_write_mode(p_bucket text, p_path text, p_upsert boolean)
returns text language plpgsql stable security definer set search_path = '' as $$
declare
  v_found boolean;
  v_owner uuid;
begin
  select e.found, e.owner_id into v_found, v_owner
    from public.storage_existing_owner(p_bucket, p_path) e;
  if coalesce(v_found, false) then
    if not p_upsert then return 'exists'; end if;
    return case when public.storage_can_replace(p_bucket, p_path, v_owner)
                then 'replace' else 'denied' end;
  end if;
  return case when public.storage_can_insert(p_bucket, p_path)
              then 'insert' else 'denied' end;
end $$;

-- ============================================================ caller-facing

-- Issue an upload intent. The signer turns the returned keys into a presigned
-- POST bound to exactly this staging key, MIME type and size.
--
-- Idempotent on (caller, idempotency key): a retry after a lost response gets
-- the same intent back rather than a second one, and reusing a key for a
-- different upload is refused.
create or replace function public.storage_begin_upload(
  p_bucket text, p_path text, p_mime_type text, p_size_bytes bigint,
  p_upsert boolean, p_idempotency_key text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_limit bigint;
  v_types text[];
  v_mode text;
  v_intent public.storage_upload_intents;
  v_id uuid := gen_random_uuid();
begin
  if v_uid is null then
    raise exception 'Sign in to upload' using errcode = '42501', hint = 'storage_denied';
  end if;
  select b.file_size_limit, b.allowed_mime_types into v_limit, v_types
    from storage.buckets b where b.id = p_bucket;
  if not found then
    raise exception 'Unknown bucket' using errcode = '22023', hint = 'storage_bucket';
  end if;
  if not public.storage_path_ok(p_path) then
    raise exception 'Invalid path' using errcode = '22023', hint = 'storage_path';
  end if;
  -- The bucket limits are the live ones, read from Supabase's own bucket
  -- config, so the two providers cannot disagree about what fits.
  if p_size_bytes is null or p_size_bytes <= 0
     or (v_limit is not null and p_size_bytes > v_limit) then
    raise exception 'File is too large' using errcode = '22023', hint = 'storage_too_large';
  end if;
  if v_types is not null and not (p_mime_type = any (v_types)) then
    raise exception 'File type not allowed' using errcode = '22023', hint = 'storage_mime';
  end if;

  select * into v_intent from public.storage_upload_intents i
   where i.user_id = v_uid and i.idempotency_key = p_idempotency_key;
  if found then
    if (v_intent.bucket, v_intent.path, v_intent.mime_type, v_intent.size_bytes, v_intent.upsert)
       is distinct from (p_bucket, p_path, p_mime_type, p_size_bytes, p_upsert) then
      raise exception 'Idempotency key reused for a different upload'
        using errcode = '22023', hint = 'storage_idempotency_mismatch';
    end if;
    if v_intent.state = 'pending' and v_intent.expires_at > now() then
      return jsonb_build_object('intent_id', v_intent.id, 'staging_key', v_intent.staging_key,
        'mime_type', v_intent.mime_type, 'size_bytes', v_intent.size_bytes,
        'expires_at', v_intent.expires_at, 'state', v_intent.state);
    end if;
    if v_intent.state in ('finalizing', 'finalized') then
      return jsonb_build_object('intent_id', v_intent.id, 'state', v_intent.state);
    end if;
    raise exception 'Upload expired; start again' using errcode = '22023', hint = 'storage_expired';
  end if;

  v_mode := public.storage_write_mode(p_bucket, p_path, coalesce(p_upsert, false));
  if v_mode = 'exists' then
    raise exception 'The resource already exists' using errcode = '23505', hint = 'storage_exists';
  elsif v_mode = 'denied' then
    raise exception 'Not allowed to upload here' using errcode = '42501', hint = 'storage_denied';
  end if;

  insert into public.storage_upload_intents (id, user_id, bucket, path, upsert, mime_type,
         size_bytes, idempotency_key, staging_key, committed_key)
  values (v_id, v_uid, p_bucket, p_path, coalesce(p_upsert, false), p_mime_type, p_size_bytes,
          p_idempotency_key, 'staging/' || v_id, p_bucket || '/' || p_path || '@' || v_id)
  returning * into v_intent;
  return jsonb_build_object('intent_id', v_intent.id, 'staging_key', v_intent.staging_key,
    'mime_type', v_intent.mime_type, 'size_bytes', v_intent.size_bytes,
    'expires_at', v_intent.expires_at, 'state', v_intent.state);
end $$;

-- Start finalizing: rechecks the caller and their CURRENT authorization (a
-- face attempt may have expired, a listing been handed over) and claims the
-- intent so two concurrent finalizers cannot promote competing versions.
-- A finalized intent answers with its asset, so a retried finalize is a
-- no-op rather than a second submission.
create or replace function public.storage_claim_intent(p_intent_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_i public.storage_upload_intents;
  v_mode text;
begin
  select * into v_i from public.storage_upload_intents
   where id = p_intent_id and user_id = auth.uid()
   for update;
  if not found then
    raise exception 'Upload not found' using errcode = '22023', hint = 'storage_not_found';
  end if;
  if v_i.state = 'finalized' then
    return jsonb_build_object('state', 'finalized', 'asset_id', v_i.asset_id,
      'bucket', v_i.bucket, 'path', v_i.path);
  end if;
  if v_i.state = 'rejected' then
    raise exception 'Upload was rejected' using errcode = '22023', hint = 'storage_rejected';
  end if;
  -- A claim abandoned by a crashed finalizer may be retaken after two
  -- minutes; a live one may not.
  if v_i.state = 'finalizing' and v_i.claimed_at > now() - interval '2 minutes' then
    raise exception 'Upload is already being finalized' using errcode = '55P03', hint = 'storage_busy';
  end if;
  if v_i.state = 'pending' and v_i.expires_at <= now() then
    raise exception 'Upload expired; start again' using errcode = '22023', hint = 'storage_expired';
  end if;
  v_mode := public.storage_write_mode(v_i.bucket, v_i.path, v_i.upsert);
  if v_mode = 'exists' then
    raise exception 'The resource already exists' using errcode = '23505', hint = 'storage_exists';
  elsif v_mode = 'denied' then
    raise exception 'Not allowed to upload here' using errcode = '42501', hint = 'storage_denied';
  end if;
  update public.storage_upload_intents set state = 'finalizing', claimed_at = now()
   where id = v_i.id;
  return jsonb_build_object('state', 'finalizing', 'intent_id', v_i.id,
    'bucket', v_i.bucket, 'path', v_i.path, 'mime_type', v_i.mime_type,
    'size_bytes', v_i.size_bytes, 'staging_key', v_i.staging_key,
    'committed_key', v_i.committed_key);
end $$;

-- The S3 locations a caller may read, for the references they asked about.
-- Anything not readable, not on S3, or unknown is simply absent: the caller
-- falls back to the Supabase URL it already has.
create or replace function public.storage_resolve_reads(p_refs jsonb)
returns table (bucket text, path text, s3_bucket text, s3_key text, s3_version text, generation integer)
language sql stable security definer set search_path = '' as $$
  select a.bucket, a.path, a.s3_bucket, a.s3_key, a.s3_version, a.generation
    from jsonb_to_recordset(coalesce(p_refs, '[]'::jsonb)) as r(bucket text, path text)
    join public.storage_assets a on a.bucket = r.bucket and a.path = r.path
   where a.state = 'active' and a.s3_key is not null
     and public.storage_can_read(a.bucket, a.path)
   limit 100;
$$;

-- Mark an asset for deletion and hand back where its bytes are. A path that
-- does not exist answers null, quietly — Supabase's remove() does the same,
-- and avatar cleanup depends on it.
create or replace function public.storage_begin_delete(p_bucket text, p_path text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_a public.storage_assets;
begin
  select * into v_a from public.storage_assets
   where bucket = p_bucket and path = p_path and state <> 'deleted'
   for update;
  if not found then return null; end if;
  if not public.storage_can_delete(v_a.bucket, v_a.path, v_a.owner_id) then
    raise exception 'Not allowed to delete this' using errcode = '42501', hint = 'storage_denied';
  end if;
  update public.storage_assets set state = 'deleting', updated_at = now() where id = v_a.id;
  return jsonb_build_object('asset_id', v_a.id, 's3_bucket', v_a.s3_bucket,
    's3_key', v_a.s3_key, 's3_version', v_a.s3_version, 'supabase_path', v_a.supabase_path);
end $$;

-- ============================================================ service-only

-- Record the verified object. Called by the signer only after it has read the
-- staged bytes back from S3, checked their size and format, and promoted that
-- exact version to the committed key. The declared size/type must match what
-- the ticket was issued for — the client's Content-Type is a claim, the
-- signer's sniffed type is the evidence.
create or replace function public.storage_commit_upload(
  p_intent_id uuid, p_size_bytes bigint, p_sha256 text, p_mime_type text,
  p_s3_bucket text, p_s3_key text, p_s3_version text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_i public.storage_upload_intents;
  v_a public.storage_assets;
begin
  select * into v_i from public.storage_upload_intents where id = p_intent_id for update;
  if not found then
    raise exception 'Upload not found' using errcode = '22023', hint = 'storage_not_found';
  end if;
  if v_i.state = 'finalized' then
    select * into v_a from public.storage_assets where id = v_i.asset_id;
    return jsonb_build_object('asset_id', v_a.id, 'bucket', v_a.bucket, 'path', v_a.path,
      'generation', v_a.generation);
  end if;
  if v_i.state <> 'finalizing' then
    raise exception 'Upload is not being finalized' using errcode = '22023', hint = 'storage_state';
  end if;
  if p_size_bytes <> v_i.size_bytes or p_mime_type <> v_i.mime_type
     or p_s3_key <> v_i.committed_key then
    raise exception 'Uploaded object does not match its ticket'
      using errcode = '22023', hint = 'storage_mismatch';
  end if;

  insert into public.storage_assets as a (bucket, path, owner_id, mime_type, size_bytes,
         sha256, s3_bucket, s3_key, s3_version)
  values (v_i.bucket, v_i.path, v_i.user_id, v_i.mime_type, p_size_bytes,
          p_sha256, p_s3_bucket, p_s3_key, p_s3_version)
  on conflict (bucket, path) do update set
    generation = a.generation + 1,
    -- A replacement keeps the original owner (an admin fixing a host's
    -- photo does not take it over); a path re-created after deletion
    -- belongs to whoever created it.
    owner_id = case when a.state = 'deleted' then excluded.owner_id else a.owner_id end,
    business_created_at = case when a.state = 'deleted' then now() else a.business_created_at end,
    mime_type = excluded.mime_type, size_bytes = excluded.size_bytes,
    sha256 = excluded.sha256, s3_bucket = excluded.s3_bucket, s3_key = excluded.s3_key,
    s3_version = excluded.s3_version, state = 'active', updated_at = now()
  returning * into v_a;

  update public.storage_upload_intents
     set state = 'finalized', finalized_at = now(), asset_id = v_a.id
   where id = v_i.id;
  return jsonb_build_object('asset_id', v_a.id, 'bucket', v_a.bucket, 'path', v_a.path,
    'generation', v_a.generation);
end $$;

-- Bytes failed verification. Rejected intents never become visible.
create or replace function public.storage_reject_intent(p_intent_id uuid, p_reason text)
returns void language sql volatile security definer set search_path = '' as $$
  update public.storage_upload_intents
     set state = 'rejected', reject_reason = left(p_reason, 200)
   where id = p_intent_id and state in ('pending', 'finalizing');
$$;

-- The signer hit a transient S3 failure after claiming: hand the intent back
-- so the client's retry is not locked out for the two-minute claim window.
create or replace function public.storage_release_intent(p_intent_id uuid)
returns void language sql volatile security definer set search_path = '' as $$
  update public.storage_upload_intents set state = 'pending', claimed_at = null
   where id = p_intent_id and state = 'finalizing';
$$;

-- The S3 delete succeeded (or the bytes were already gone).
create or replace function public.storage_finish_delete(p_asset_id uuid)
returns void language sql volatile security definer set search_path = '' as $$
  update public.storage_assets set state = 'deleted', updated_at = now()
   where id = p_asset_id and state = 'deleting';
$$;

-- ============================================================ grants
-- A SECURITY DEFINER function is a public endpoint: revoke from public, anon
-- and authenticated, then grant only what each one needs.
do $$
declare f text;
begin
  foreach f in array array[
    'storage_first_folder(text)', 'storage_file_name(text)', 'storage_path_ok(text)',
    'storage_existing_owner(text,text)', 'storage_can_insert(text,text)',
    'storage_can_replace(text,text,uuid)', 'storage_can_delete(text,text,uuid)',
    'storage_can_read(text,text)', 'storage_write_mode(text,text,boolean)',
    'storage_begin_upload(text,text,text,bigint,boolean,text)',
    'storage_claim_intent(uuid)', 'storage_resolve_reads(jsonb)',
    'storage_begin_delete(text,text)',
    'storage_commit_upload(uuid,bigint,text,text,text,text,text)',
    'storage_reject_intent(uuid,text)', 'storage_release_intent(uuid)',
    'storage_finish_delete(uuid)']
  loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
end $$;

grant execute on function public.storage_begin_upload(text,text,text,bigint,boolean,text) to authenticated;
grant execute on function public.storage_claim_intent(uuid) to authenticated;
grant execute on function public.storage_begin_delete(text,text) to authenticated;
-- Public buckets are readable without signing in, as today.
grant execute on function public.storage_resolve_reads(jsonb) to anon, authenticated;
