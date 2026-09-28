-- Restore all previous identity-document choices without rewriting saved records.
-- Historical nid_front/nid_back slot names and nid_verified flag represent the
-- selected identity document, as they did before the face-review work.
begin;
create function public.submit_identity_document(p_document_type text,p_front_path text,p_back_path text default null,p_document_number text default null)
returns void language plpgsql security definer set search_path=public as $$
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
    select metadata->>'mimetype' into mime from storage.objects where bucket_id='documents' and name=path
      and (metadata->>'size')::bigint between 100 and 5242880;
    if not found or mime not in ('image/jpeg','image/png') or mime is null then raise exception 'Upload a JPG or PNG of each side, under 5 MB'; end if;
  end loop;
  -- A replacement with a single-sided document must not inherit an old back.
  -- Stored historical image bytes are preserved; only the current slot changes.
  if p_back_path is null then delete from public.owner_documents where user_id=uid and document_type='nid_back'; end if;
  insert into public.owner_documents(user_id,document_type,file_path,mime_type,uploaded_at,verified_at,verified_by,rejection_reason)
    select uid,sides.slot,sides.file_path,(select metadata->>'mimetype' from storage.objects where bucket_id='documents' and name=sides.file_path),now(),null,null,null
    from (values ('nid_front',p_front_path),('nid_back',p_back_path)) sides(slot,file_path) where sides.file_path is not null
    on conflict(user_id,document_type) do update set file_path=excluded.file_path,mime_type=excluded.mime_type,
      uploaded_at=excluded.uploaded_at,verified_at=null,verified_by=null,rejection_reason=null;
  update public.profiles set verification_status='pending',nid_verified=false,id_document_type=p_document_type,nid=nullif(btrim(p_document_number),'') where id=uid;
end;
$$;

create function public.approve_identity_document(p_user_id uuid,p_document_type text,p_front_path text,p_back_path text default null)
returns void language plpgsql security definer set search_path=public as $$
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
  if not exists(select 1 from storage.objects where bucket_id='documents' and name=p_front_path)
    or (p_back_path is not null and not exists(select 1 from storage.objects where bucket_id='documents' and name=p_back_path)) then
    raise exception 'Document evidence is unavailable'; end if;
  update public.owner_documents set verified_at=now(),verified_by=auth.uid(),rejection_reason=null
    where user_id=p_user_id and document_type in ('nid_front','nid_back');
  update public.profiles set verification_status='verified',nid_verified=true where id=p_user_id;
end;
$$;

create or replace function public.nid_verification_status()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare p public.profiles;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode='42501'; end if;
  select * into strict p from public.profiles where id=auth.uid();
  return jsonb_build_object('status',case when p.verification_status='verified' and not coalesce(p.nid_verified,false)
    then 'none' else p.verification_status::text end,
    'document_type',p.id_document_type,
    'note',(select rejection_reason from public.owner_documents where user_id=p.id
      and document_type in ('nid_front','nid_back') and rejection_reason is not null order by uploaded_at desc limit 1));
end;
$$;


-- Preserve the deployed NID endpoint signatures for older clients.
create or replace function public.submit_nid_verification(p_front_path text,p_back_path text)
returns void language sql security definer set search_path=public as $$
  select public.submit_identity_document('nid',p_front_path,p_back_path,null);
$$;
create or replace function public.approve_nid_verification(p_user_id uuid,p_front_path text,p_back_path text)
returns void language sql security definer set search_path=public as $$
  select public.approve_identity_document(p_user_id,'nid',p_front_path,p_back_path);
$$;
revoke all on function public.submit_identity_document(text,text,text,text),public.approve_identity_document(uuid,text,text,text) from public,anon;
grant execute on function public.submit_identity_document(text,text,text,text),public.approve_identity_document(uuid,text,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
