-- Local synthetic QA profiles only; no production data or real documents.
\set ON_ERROR_STOP on
begin;
do $test$
declare kind text; front_path text; back_path text; refused boolean;
  u uuid:='44444444-4444-4444-4444-444444444444';
  admin_id uuid:='55555555-5555-5555-5555-555555555555';
begin
  if not exists(select 1 from public.profiles where id=u) then raise exception 'Missing local QA fixture'; end if;
  foreach kind in array array['nid','passport','driving_license','student_id','office_id'] loop
    perform set_config('role','postgres',true); perform set_config('request.jwt.claims','{}',true);
    update public.profiles set verification_status='rejected',nid_verified=false,suspended_at=null where id=u;
    front_path:=u::text||'/nid/'||kind||'/front.png';
    back_path:=case when kind='nid' then u::text||'/nid/'||kind||'/back.png' else null end;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
    perform set_config('role','authenticated',true);
    insert into storage.objects(bucket_id,name,metadata) values('documents',front_path,'{"size":1024,"mimetype":"image/png"}');
    if back_path is not null then
      insert into storage.objects(bucket_id,name,metadata) values('documents',back_path,'{"size":1024,"mimetype":"image/png"}');
      refused:=false;
      begin perform public.submit_identity_document(kind,front_path,null,'TEST-ID'); exception when others then refused:=true; end;
      if not refused then raise exception 'NID without back accepted'; end if;
      raise notice 'PASS: NID requires back';
    end if;
    perform public.submit_identity_document(kind,front_path,back_path,'TEST-ID');
    perform public.submit_identity_document(kind,front_path,back_path,'TEST-ID');
    if public.nid_verification_status()->>'status'<>'pending' or public.nid_verification_status()->>'document_type'<>kind then raise exception 'Incorrect status/type: %',kind; end if;
    if back_path is null and exists(select 1 from public.owner_documents where user_id=u and document_type='nid_back') then raise exception 'Old back leaked into new document'; end if;
    raise notice 'PASS: % submission, retry, type and side requirements',kind;
    refused:=false;
    begin perform public.approve_identity_document(u,kind,front_path,back_path); exception when insufficient_privilege then refused:=true; end;
    if not refused then raise exception 'Self approval allowed'; end if;
    perform set_config('role','postgres',true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated')::text,true);
    perform set_config('role','authenticated',true);
    refused:=false;
    begin perform public.approve_identity_document(u,'changed-type',front_path,back_path); exception when others then refused:=true; end;
    if not refused then raise exception 'Stale type approval accepted'; end if;
    perform public.approve_identity_document(u,kind,front_path,back_path);
    if not exists(select 1 from public.profiles where id=u and verification_status='verified' and id_document_type=kind and nid='TEST-ID') then raise exception 'Approval lost type or number'; end if;
    raise notice 'PASS: % admin-only approval, stale type denied, metadata preserved',kind;
  end loop;
  perform set_config('role','postgres',true); perform set_config('request.jwt.claims','{}',true);
  update public.profiles set verification_status='rejected',nid_verified=false where id=u;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  perform set_config('role','authenticated',true);
  refused:=false;
  begin perform public.submit_identity_document('fake',front_path,null,'123'); exception when others then refused:=true; end;
  if not refused then raise exception 'Unsupported type accepted'; end if;
  raise notice 'PASS: unsupported document type denied';
end $test$;
rollback;
