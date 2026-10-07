-- 158: storage cutover — the database stops assuming bytes live in Supabase.
--
-- Stage 3+ of docs/plans/aws-s3-storage-migration.md. After 157 an upload can
-- land in S3 (registered in storage_assets) instead of storage.objects. Six
-- functions proved an upload by looking in storage.objects, so every S3
-- upload would be refused as "missing" — face submit, NID submit/approve,
-- trade-licence submit, the hotel licence badge, and the orphan scan. They
-- now ask storage_object_meta(), which answers from the registry first and
-- falls back to storage.objects for objects that never moved. Bodies are the
-- live definitions with only those lookups swapped (CREATE OR REPLACE keeps
-- their grants).
--
-- Also:
--   - admins may upload/replace/delete avatars and listing images through
--     the signer. The admin portal already does exactly that today with the
--     service key after requireAdmin(); doing it under the admin's own JWT
--     (is_admin()) is the same rule with a stronger check and an audit trail.
--   - storage_purge_begin(): the retention job's way to take face evidence
--     out of S3 for good. A user-facing delete leaves a delete marker (the
--     recovery window); evidence past retention must not be recoverable.

-- ============================================================ object facts

-- Owner, type and size of the object at a logical path, wherever it is. The
-- registry wins whenever it has a row for the path at all — including a
-- deleted one, so a legacy Supabase copy left behind by a delete does not
-- resurrect the object (same rule as storage_existing_owner).
create or replace function public.storage_object_meta(p_bucket text, p_path text)
returns table (owner_id uuid, mime_type text, size_bytes bigint)
language sql stable security definer set search_path = '' as $$
  select a.owner_id, a.mime_type, a.size_bytes from public.storage_assets a
   where a.bucket = p_bucket and a.path = p_path and a.state = 'active'
  union all
  select o.owner, o.metadata->>'mimetype', (o.metadata->>'size')::bigint
    from storage.objects o
   where o.bucket_id = p_bucket and o.name = p_path
     and not exists (select 1 from public.storage_assets a
                      where a.bucket = p_bucket and a.path = p_path)
  limit 1;
$$;

-- ============================================================ admin arms

create or replace function public.storage_can_insert(p_bucket text, p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and case p_bucket
    when 'avatars' then public.storage_file_name(p_path) like auth.uid()::text || '.%'
                     or public.is_admin()
    when 'listing-images' then public.can_upload_listing_image() or public.is_admin()
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

create or replace function public.storage_can_replace(p_bucket text, p_path text, p_owner uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and case p_bucket
    when 'avatars' then public.storage_file_name(p_path) like auth.uid()::text || '.%'
                     or public.is_admin()
    when 'listing-images' then p_owner = auth.uid() or public.is_admin()
    when 'documents' then public.storage_first_folder(p_path) = auth.uid()::text
                      and split_part(p_path, '/', 2) <> 'nid'
    else false end;
$$;

create or replace function public.storage_can_delete(p_bucket text, p_path text, p_owner uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and case p_bucket
    when 'avatars' then public.storage_file_name(p_path) like auth.uid()::text || '.%'
                     or public.is_admin()
    when 'listing-images' then p_owner = auth.uid() or public.is_admin()
    when 'chat-attachments' then p_owner = auth.uid() or public.is_admin()
    when 'documents' then public.storage_first_folder(p_path) = auth.uid()::text
                      and split_part(p_path, '/', 2) <> 'nid'
    else false end;
$$;

-- ============================================================ retention

-- Face evidence with no attempt behind it, in either provider.
create or replace function public.orphan_face_evidence()
returns table (name text)
language plpgsql security definer set search_path to 'public' as $$
begin
  perform public.fn_require_service_role();
  return query
  select n.name from (
    select o.name from storage.objects o where o.bucket_id = 'face-evidence'
    union
    select a.path from public.storage_assets a
     where a.bucket = 'face-evidence' and a.state <> 'deleted'
  ) n
  where not exists (select 1 from public.face_verification_attempts a
    where a.id::text = split_part(n.name, '/', 2) and a.user_id::text = split_part(n.name, '/', 1))
  limit 100;
end $$;

-- Hand the retention job the exact S3 versions to destroy, marking them
-- deleting. Paths with no S3 copy are simply absent. Service role only: the
-- job deletes by version (no recovery), which no user action may do.
create or replace function public.storage_purge_begin(p_bucket text, p_paths text[])
returns table (asset_id uuid, path text, s3_bucket text, s3_key text, s3_version text)
language plpgsql volatile security definer set search_path = '' as $$
begin
  return query
  update public.storage_assets a set state = 'deleting', updated_at = now()
   where a.bucket = p_bucket and a.path = any(p_paths) and a.state <> 'deleted'
     and a.s3_key is not null
  returning a.id, a.path, a.s3_bucket, a.s3_key, a.s3_version;
end $$;

-- ============================================================ verifiers

CREATE OR REPLACE FUNCTION public.approve_identity_document(p_user_id uuid, p_document_type text, p_front_path text, p_back_path text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null or not public.is_admin() or auth.uid()=p_user_id then
    raise exception 'Another admin must approve this document' using errcode='42501'; end if;
  perform 1 from public.profiles where id=p_user_id and id_document_type is not distinct from p_document_type and verification_status='pending' for update;
  if not found then raise exception 'Submission changed. Refresh the review queue'; end if;
  if p_document_type='nid' and p_back_path is null then raise exception 'NID requires both sides'; end if;
  perform 1 from public.owner_documents where user_id=p_user_id and document_type in ('nid_front','nid_back') for update;
  if not exists(select 1 from public.owner_documents where user_id=p_user_id and document_type='nid_front' and file_path=p_front_path)
    or (p_back_path is not null and not exists(select 1 from public.owner_documents where user_id=p_user_id and document_type='nid_back' and file_path=p_back_path))
    or (p_back_path is null and exists(select 1 from public.owner_documents where user_id=p_user_id and document_type='nid_back')) then
    raise exception 'Documents changed. Refresh the review queue'; end if;
  if not exists(select 1 from public.storage_object_meta('documents',p_front_path))
    or (p_back_path is not null and not exists(select 1 from public.storage_object_meta('documents',p_back_path))) then
    raise exception 'Document evidence is unavailable'; end if;
  update public.owner_documents set verified_at=now(),verified_by=auth.uid(),rejection_reason=null
    where user_id=p_user_id and document_type in ('nid_front','nid_back');
  update public.profiles set verification_status='verified',nid_verified=true where id=p_user_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.listing_licence_verified(p_listing_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
      from public.listings me
      join public.listings l
        on l.id = me.id or (me.property_id is not null and l.property_id = me.property_id)
      join public.listing_trade_licences t on t.listing_id = l.id
     where me.id = p_listing_id
       and me.listing_type::text = 'hotel'
       and l.listing_type::text = 'hotel'
       and t.status = 'verified'
       and exists (select 1 from public.storage_object_meta('documents', t.document_path))
  );
$function$
;

CREATE OR REPLACE FUNCTION public.submit_face_verification(p_attempt_id uuid, p_nonce uuid, p_clip_extension text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.face_verification_attempts; clip text; selfie text;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode='42501'; end if;
  perform 1 from public.profiles where id=auth.uid() and suspended_at is null for update;
  if not found then raise exception 'Account unavailable' using errcode='42501'; end if;
  select * into a from public.face_verification_attempts where id=p_attempt_id and user_id=auth.uid() for update;
  if not found or a.nonce is distinct from p_nonce then raise exception 'Invalid attempt' using errcode='42501'; end if;
  if a.status='pending' then return; end if;
  if a.status<>'draft' or a.expires_at<=now() then raise exception 'Attempt expired. Start again'; end if;
  selfie := a.user_id::text||'/'||a.id::text||'/selfie.jpg';
  if not exists(select 1 from public.storage_object_meta('face-evidence',selfie) m
    where m.size_bytes between 100 and 524288 and m.mime_type='image/jpeg') then
    raise exception 'Selfie upload is missing or invalid'; end if;
  if a.method='guided' then
    if p_clip_extension is null or p_clip_extension not in ('webm','mp4') then raise exception 'Invalid video format'; end if;
    clip := a.user_id::text||'/'||a.id::text||'/clip.'||p_clip_extension;
    if not exists(select 1 from public.storage_object_meta('face-evidence',clip) m
      where m.size_bytes between 100 and 8388608
      and m.mime_type='video/'||p_clip_extension) then raise exception 'Video upload is missing or invalid'; end if;
  end if;
  -- No client liveness boolean is trusted. The admin must review the media.
  update public.face_verification_attempts set status='pending', submitted_at=now(),
    clip_path=clip, selfie_path=selfie where id=a.id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.submit_identity_document(p_document_type text, p_front_path text, p_back_path text DEFAULT NULL::text, p_document_number text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid:=auth.uid(); p public.profiles; path text; mime text;
begin
  if uid is null then raise exception 'Sign in first' using errcode='42501'; end if;
  select * into p from public.profiles where id=uid and suspended_at is null for update;
  if not found then raise exception 'Account unavailable' using errcode='42501'; end if;
  if p_document_type is null or p_document_type not in ('nid','passport','driving_license','student_id','office_id') then raise exception 'Unsupported document type'; end if;
  if p_document_number is not null and (length(btrim(p_document_number))=0 or length(p_document_number)>100) then raise exception 'Invalid document number'; end if;
  -- Lost-response retries may reuse the same paths without replacing evidence.
  if p.verification_status='pending' and p.id_document_type=p_document_type and p.nid is not distinct from nullif(btrim(p_document_number),'') and exists(select 1 from public.owner_documents where user_id=uid and document_type='nid_front' and file_path=p_front_path)
    and ((p_back_path is null and not exists(select 1 from public.owner_documents where user_id=uid and document_type='nid_back')) or exists(select 1 from public.owner_documents where user_id=uid and document_type='nid_back' and file_path=p_back_path)) then return; end if;
  if p.verification_status in ('pending','verified') then raise exception 'Your document is already submitted. Refresh status.'; end if;
  if p_front_path is null or (p_document_type='nid' and p_back_path is null) or p_front_path=p_back_path then raise exception 'Front image is required; NID also requires the back'; end if;
  foreach path in array array[p_front_path,p_back_path] loop
    if path is null then continue; end if;
    if path not like uid::text||'/nid/%' then raise exception 'Invalid document owner' using errcode='42501'; end if;
    select m.mime_type into mime from public.storage_object_meta('documents',path) m
      where m.size_bytes between 100 and 5242880;
    if not found or mime not in ('image/jpeg','image/png') or mime is null then raise exception 'Upload a JPG or PNG of each side, under 5 MB'; end if;
  end loop;
  -- A replacement with a single-sided document must not inherit an old back.
  -- Stored historical image bytes are preserved; only the current slot changes.
  if p_back_path is null then delete from public.owner_documents where user_id=uid and document_type='nid_back'; end if;
  insert into public.owner_documents(user_id,document_type,file_path,mime_type,uploaded_at,verified_at,verified_by,rejection_reason)
    select uid,sides.slot,sides.file_path,(select m.mime_type from public.storage_object_meta('documents',sides.file_path) m),now(),null,null,null
    from (values ('nid_front',p_front_path),('nid_back',p_back_path)) sides(slot,file_path) where sides.file_path is not null
    on conflict(user_id,document_type) do update set file_path=excluded.file_path,mime_type=excluded.mime_type,
      uploaded_at=excluded.uploaded_at,verified_at=null,verified_by=null,rejection_reason=null;
  update public.profiles set verification_status='pending',nid_verified=false,id_document_type=p_document_type,nid=nullif(btrim(p_document_number),'') where id=uid;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.submit_trade_licence(p_listing_id uuid, p_document_path text, p_licence_number text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_listing public.listings;
  v_mime text;
  v_size bigint;
  v_owner uuid;
  v_number text := nullif(btrim(p_licence_number), '');
begin
  if v_uid is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;

  select * into v_listing from public.listings where id = p_listing_id;
  if not found or v_listing.owner_id is distinct from v_uid then
    raise exception 'You can only add a licence to your own listing'
      using errcode = '42501', hint = 'not_listing_owner';
  end if;
  if v_listing.listing_type::text <> 'hotel' then
    raise exception 'A trade licence is for hotel listings'
      using errcode = '22023', hint = 'not_a_hotel';
  end if;
  if v_number is not null and char_length(v_number) > 60 then
    raise exception 'The licence number is too long'
      using errcode = '22023', hint = 'licence_number_invalid';
  end if;

  -- The path is the uploader's own folder AND the storage layer recorded them
  -- as the owner: the path alone is a string anyone can type (database-security.md).
  if p_document_path is null or p_document_path not like v_uid::text || '/trade_licence/%' then
    raise exception 'Invalid document' using errcode = '42501', hint = 'document_not_owned';
  end if;
  select m.owner_id, m.mime_type, m.size_bytes
    into v_owner, v_mime, v_size
    from public.storage_object_meta('documents', p_document_path) m;
  if found and v_owner is distinct from v_uid then
    raise exception 'Invalid document' using errcode = '42501', hint = 'document_not_owned';
  end if;
  if not found or v_mime is null
     or v_mime not in ('image/jpeg', 'image/png', 'application/pdf')
     or v_size is null or v_size not between 100 and 5242880 then
    raise exception 'Upload a JPG, PNG or PDF of the licence, under 5 MB'
      using errcode = '22023', hint = 'document_invalid';
  end if;

  insert into public.listing_trade_licences
    (listing_id, owner_id, document_path, licence_number, status, submitted_at,
     reviewed_at, reviewed_by, rejection_reason)
  values (p_listing_id, v_uid, p_document_path, v_number, 'pending', now(),
          null, null, null)
  on conflict (listing_id) do update
    set owner_id = excluded.owner_id,
        document_path = excluded.document_path,
        licence_number = excluded.licence_number,
        status = 'pending',
        submitted_at = now(),
        reviewed_at = null,
        reviewed_by = null,
        rejection_reason = null;
end;
$function$
;

-- ============================================================ grants
do $$
declare f text;
begin
  foreach f in array array['storage_object_meta(text,text)', 'storage_purge_begin(text,text[])']
  loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
end $$;
-- orphan_face_evidence was service-role only; CREATE OR REPLACE keeps that.
