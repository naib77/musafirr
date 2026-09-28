-- Two independent admin decisions. Does not enable live face capture.
begin;

create or replace function public.has_approved_face_or_identity(p_user_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  -- Retain the function signature used by booking and publishing callers.
  select exists(select 1 from public.profiles where id=p_user_id
    and verification_status='verified' and nid_verified)
    and coalesce((select status='approved' from public.face_verification_attempts
      where user_id=p_user_id order by created_at desc,id desc limit 1),false);
$$;

create or replace function public.face_verification_status()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare a public.face_verification_attempts;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode='42501'; end if;
  select * into a from public.face_verification_attempts where user_id=auth.uid()
    order by created_at desc,id desc limit 1;
  return jsonb_build_object('status',case when a.status='approved' then 'verified'
    when a.status in ('pending','rejected','retry') then a.status else 'none' end,
    'note',a.review_note,'method',a.method,
    'enabled',coalesce((select value='true' from public.app_settings where key='face_review_enabled'),false));
end;
$$;

create function public.nid_verification_status()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare p public.profiles;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode='42501'; end if;
  select * into strict p from public.profiles where id=auth.uid();
  return jsonb_build_object('status',case when p.verification_status='verified' and not coalesce(p.nid_verified,false)
    then 'none' else p.verification_status::text end,
    'note',(select rejection_reason from public.owner_documents where user_id=p.id
      and document_type in ('nid_front','nid_back') and rejection_reason is not null order by uploaded_at desc limit 1));
end;
$$;

create function public.verification_overview()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare n jsonb; f jsonb; state text;
begin
  n:=public.nid_verification_status(); f:=public.face_verification_status();
  state:=case when n->>'status'='verified' and f->>'status'='verified' then 'verified'
    when n->>'status' in ('pending','verified') and f->>'status' in ('pending','verified') then 'pending'
    else 'none' end;
  return jsonb_build_object('status',state,'nid_status',n->>'status','face_status',f->>'status','face_enabled',f->'enabled');
end;
$$;

-- NID files use a dedicated prefix in the existing private documents bucket.
-- Existing address-proof uploads and historical files keep their policies.
create policy nid_evidence_no_update on storage.objects as restrictive for update to authenticated
  using (not (bucket_id='documents' and split_part(name,'/',2)='nid'))
  with check (not (bucket_id='documents' and split_part(name,'/',2)='nid'));
create policy nid_evidence_no_delete on storage.objects as restrictive for delete to authenticated
  using (not (bucket_id='documents' and split_part(name,'/',2)='nid'));

-- Prevent direct client row writes from changing the evidence under a review.
-- SECURITY INVOKER is intentional: a definer RPC executes as postgres, while
-- direct PostgREST writes execute as authenticated. Never trust client GUCs.
create function public.guard_nid_document_write()
returns trigger language plpgsql set search_path=public as $$
begin
  if current_user not in ('postgres','service_role','supabase_admin') and not public.is_admin()
    and ((tg_op<>'DELETE' and new.document_type in ('nid_front','nid_back'))
      or (tg_op<>'INSERT' and old.document_type in ('nid_front','nid_back'))) then
    raise exception 'Use the NID submission flow' using errcode='42501';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
create trigger guard_nid_document_write before insert or update or delete on public.owner_documents
  for each row execute function public.guard_nid_document_write();

create function public.submit_nid_verification(p_front_path text,p_back_path text)
returns void language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); p public.profiles; path text; mime text;
begin
  if uid is null then raise exception 'Sign in first' using errcode='42501'; end if;
  select * into p from public.profiles where id=uid and suspended_at is null for update;
  if not found then raise exception 'Account unavailable' using errcode='42501'; end if;
  -- Lost-response retries may reuse the same paths without replacing evidence.
  if p.verification_status='pending' and exists(select 1 from public.owner_documents where user_id=uid and document_type='nid_front' and file_path=p_front_path)
    and exists(select 1 from public.owner_documents where user_id=uid and document_type='nid_back' and file_path=p_back_path) then return; end if;
  if p.verification_status in ('pending','verified') then raise exception 'Your NID is already submitted. Refresh status.'; end if;
  if p_front_path is null or p_back_path is null or p_front_path=p_back_path then raise exception 'Both NID sides are required'; end if;
  foreach path in array array[p_front_path,p_back_path] loop
    if path not like uid::text||'/nid/%' then raise exception 'Invalid document owner' using errcode='42501'; end if;
    select metadata->>'mimetype' into mime from storage.objects where bucket_id='documents' and name=path
      and (metadata->>'size')::bigint between 100 and 5242880;
    if not found or mime not in ('image/jpeg','image/png') or mime is null then raise exception 'Upload a JPG or PNG of each side, under 5 MB'; end if;
  end loop;
  insert into public.owner_documents(user_id,document_type,file_path,mime_type,uploaded_at,verified_at,verified_by,rejection_reason)
    select uid,sides.slot,sides.file_path,(select metadata->>'mimetype' from storage.objects where bucket_id='documents' and name=sides.file_path),now(),null,null,null
    from (values ('nid_front',p_front_path),('nid_back',p_back_path)) sides(slot,file_path)
    on conflict(user_id,document_type) do update set file_path=excluded.file_path,mime_type=excluded.mime_type,
      uploaded_at=excluded.uploaded_at,verified_at=null,verified_by=null,rejection_reason=null;
  update public.profiles set verification_status='pending',nid_verified=false,id_document_type='nid' where id=uid;
end;
$$;

-- Approval is atomic and tied to the exact two paths displayed to the admin.
create function public.approve_nid_verification(p_user_id uuid,p_front_path text,p_back_path text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or not public.is_admin() or auth.uid()=p_user_id then
    raise exception 'Another admin must approve this NID' using errcode='42501'; end if;
  perform 1 from public.profiles where id=p_user_id and verification_status='pending' for update;
  if not found then raise exception 'Submission changed. Refresh the review queue'; end if;
  perform 1 from public.owner_documents where user_id=p_user_id and document_type in ('nid_front','nid_back') for update;
  if not exists(select 1 from public.owner_documents where user_id=p_user_id and document_type='nid_front' and file_path=p_front_path)
    or not exists(select 1 from public.owner_documents where user_id=p_user_id and document_type='nid_back' and file_path=p_back_path) then
    raise exception 'Documents changed. Refresh the review queue'; end if;
  if not exists(select 1 from storage.objects where bucket_id='documents' and name=p_front_path)
    or not exists(select 1 from storage.objects where bucket_id='documents' and name=p_back_path) then
    raise exception 'Document evidence is unavailable'; end if;
  update public.owner_documents set verified_at=now(),verified_by=auth.uid(),rejection_reason=null
    where user_id=p_user_id and document_type in ('nid_front','nid_back');
  update public.profiles set verification_status='verified',nid_verified=true where id=p_user_id;
end;
$$;

revoke all on function public.nid_verification_status(),public.verification_overview(),
  public.submit_nid_verification(text,text),public.approve_nid_verification(uuid,text,text) from public,anon;
grant execute on function public.nid_verification_status(),public.verification_overview(),
  public.submit_nid_verification(text,text),public.approve_nid_verification(uuid,text,text) to authenticated;

create or replace function public.start_face_verification(p_method text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.face_verification_attempts; sequence text[];
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode='42501'; end if;
  if not coalesce((select value='true' from public.app_settings where key='face_review_enabled'),false) then
    raise exception 'Face review is not available yet. Please try later'; end if;
  if p_method is null or p_method not in ('guided','manual') then raise exception 'Invalid capture method'; end if;
  -- Serialize starts/submission/review for a user, including simultaneous devices.
  perform 1 from public.profiles where id=auth.uid() and suspended_at is null for update;
  if not found then raise exception 'Account unavailable' using errcode='42501'; end if;
  if (select status='approved' from public.face_verification_attempts where user_id=auth.uid() order by created_at desc,id desc limit 1) then raise exception 'Face already approved'; end if;
  if exists(select 1 from public.face_verification_attempts where user_id=auth.uid() and status='pending') then
    raise exception 'Your submission is already awaiting review'; end if;
  if (select count(*) from public.face_verification_attempts where user_id=auth.uid()
      and created_at > now()-interval '24 hours') >= 5 then
    raise exception 'Daily attempt limit reached. Please try tomorrow'; end if;
  update public.face_verification_attempts set status='superseded' where user_id=auth.uid() and status='draft';
  sequence := case when random() < 0.5 then array['blink','left','right'] else array['blink','right','left'] end;
  if random() < 0.5 then sequence := array[sequence[2],sequence[1],sequence[3]]; end if;
  if p_method='manual' then sequence := '{}'::text[]; end if;
  insert into public.face_verification_attempts(user_id,method,actions)
    values(auth.uid(),p_method,sequence) returning * into a;
  return to_jsonb(a);
end;
$$;


notify pgrst, 'reload schema';
commit;
