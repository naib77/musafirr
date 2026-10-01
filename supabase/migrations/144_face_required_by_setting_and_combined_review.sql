-- 144: face review is required only while the admin switch says so, and one
-- admin decision covers both the identity document and the face capture.
--
-- Before this, `face_review_enabled` only allowed captures to START, while 142
-- required an approved face for every booking and every publish regardless.
-- With the switch off (its seeded value, and live's value on apply) nobody
-- could capture a face and nobody could satisfy the gate: every account with
-- an approved document was locked out of booking and hosting.
--
-- Now the one switch means one thing: "face verification is mandatory".
--   off: an approved identity document is enough; no new captures start.
--   on:  an approved document AND an approved latest face attempt.
-- Turning it on later re-blocks document-only accounts until their face is
-- approved. That is the point of the switch, not a side effect.
--
-- The admin console reviewed the two halves on two pages with two buttons.
-- `admin_approve_verification` and `admin_reject_verification` decide both in
-- one transaction, so an approval can never land on one half and fail on the
-- other. The per-half RPCs (approve_identity_document,
-- review_face_verification) are left in place and are what these call.
begin;

create or replace function public.face_review_required()
returns boolean language sql stable security definer set search_path=public as $$
  -- Exact 'true' check, the same one start_face_verification makes, so the
  -- switch can never read as "required" while captures are refused.
  select coalesce((select value='true' from public.app_settings where key='face_review_enabled'),false);
$$;

create or replace function public.has_approved_face_or_identity(p_user_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  -- Signature kept: create_marketplace_booking and can_publish_listings call it.
  select exists(select 1 from public.profiles where id=p_user_id
    and verification_status='verified' and nid_verified)
    and (not public.face_review_required()
      or coalesce((select status='approved' from public.face_verification_attempts
        where user_id=p_user_id order by created_at desc,id desc limit 1),false));
$$;

create or replace function public.verification_overview()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare n jsonb; f jsonb; state text; required boolean:=public.face_review_required();
begin
  n:=public.nid_verification_status(); f:=public.face_verification_status();
  if not required then
    state:=case when n->>'status'='verified' then 'verified'
      when n->>'status'='pending' then 'pending' else 'none' end;
  else
    state:=case when n->>'status'='verified' and f->>'status'='verified' then 'verified'
      when n->>'status' in ('pending','verified') and f->>'status' in ('pending','verified') then 'pending'
      else 'none' end;
  end if;
  -- face_enabled is kept for builds that predate face_required.
  return jsonb_build_object('status',state,'nid_status',n->>'status','face_status',f->>'status',
    'face_enabled',required,'face_required',required);
end;
$$;

-- One Approve for both halves. Each half is approved only if it is waiting:
--   * identity pending              -> approved against the exact paths shown;
--   * identity already verified     -> left alone (a face-only resubmission);
--   * face attempt given            -> approved against the evidence version shown;
--   * face required, none given     -> refused, unless the latest attempt is
--                                      already approved.
-- Everything runs as the calling admin, so the inner RPCs' own admin and
-- not-yourself checks still apply.
create or replace function public.admin_approve_verification(
  p_user_id uuid,
  p_document_type text,
  p_front_path text,
  p_back_path text default null,
  p_face_attempt_id uuid default null,
  p_face_evidence_version uuid default null,
  p_note text default ''
) returns jsonb language plpgsql security definer set search_path=public as $$
declare p public.profiles; identity_done boolean:=false; face_done boolean:=false;
begin
  if auth.uid() is null or not public.is_admin() or auth.uid()=p_user_id then
    raise exception 'Another admin must approve this verification' using errcode='42501'; end if;
  select * into p from public.profiles where id=p_user_id for update;
  if not found then raise exception 'Account not found'; end if;

  if p.verification_status='pending' then
    perform public.approve_identity_document(p_user_id,p_document_type,p_front_path,p_back_path);
    identity_done:=true;
  elsif not (p.verification_status='verified' and coalesce(p.nid_verified,false)) then
    raise exception 'No identity document is waiting for review. Refresh the queue';
  end if;

  if p_face_attempt_id is not null then
    if (select user_id from public.face_verification_attempts where id=p_face_attempt_id) is distinct from p_user_id then
      raise exception 'Face submission belongs to another account' using errcode='42501'; end if;
    perform public.review_face_verification(p_face_attempt_id,p_face_evidence_version,'approved',coalesce(p_note,''));
    face_done:=true;
  elsif public.face_review_required() and not coalesce((select status='approved'
      from public.face_verification_attempts where user_id=p_user_id
      order by created_at desc,id desc limit 1),false) then
    raise exception 'Face verification is required and this person has not submitted one yet';
  end if;

  if not identity_done and not face_done then
    raise exception 'Nothing is waiting for review. Refresh the queue'; end if;
  return jsonb_build_object('identity_approved',identity_done,'face_approved',face_done);
end;
$$;

-- One Reject. A pending identity is rejected with the reason; a pending face
-- attempt is rejected with the same reason, which lets the person capture
-- again (start_face_verification only refuses while approved or pending).
-- An already-verified identity is NOT revoked by rejecting a face-only
-- resubmission: the admin is judging the face, and revoking the document
-- would make the person redo a step nobody objected to.
create or replace function public.admin_reject_verification(
  p_user_id uuid,
  p_reason text,
  p_face_attempt_id uuid default null,
  p_face_evidence_version uuid default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare p public.profiles; reason text:=btrim(coalesce(p_reason,'')); identity_done boolean:=false; face_done boolean:=false;
begin
  if auth.uid() is null or not public.is_admin() or auth.uid()=p_user_id then
    raise exception 'Another admin must review this verification' using errcode='42501'; end if;
  if reason='' then raise exception 'A rejection reason is required'; end if;
  if length(reason)>500 then raise exception 'Keep the reason under 500 characters'; end if;
  select * into p from public.profiles where id=p_user_id for update;
  if not found then raise exception 'Account not found'; end if;

  if p.verification_status='pending' then
    update public.owner_documents set verified_at=null,verified_by=null,rejection_reason=reason
      where user_id=p_user_id and document_type in ('nid_front','nid_back');
    update public.profiles set verification_status='rejected',nid_verified=false where id=p_user_id;
    identity_done:=true;
  end if;

  if p_face_attempt_id is not null then
    if (select user_id from public.face_verification_attempts where id=p_face_attempt_id) is distinct from p_user_id then
      raise exception 'Face submission belongs to another account' using errcode='42501'; end if;
    perform public.review_face_verification(p_face_attempt_id,p_face_evidence_version,'rejected',reason);
    face_done:=true;
  end if;

  if not identity_done and not face_done then
    raise exception 'Nothing is waiting for review. Refresh the queue'; end if;
  return jsonb_build_object('identity_rejected',identity_done,'face_rejected',face_done);
end;
$$;

-- 116: a definer function in public is a public endpoint. Admin-only by body;
-- the grant is authenticated because the console calls with the admin's JWT.
revoke all on function public.face_review_required(),
  public.admin_approve_verification(uuid,text,text,text,uuid,uuid,text),
  public.admin_reject_verification(uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.face_review_required(),
  public.admin_approve_verification(uuid,text,text,text,uuid,uuid,text),
  public.admin_reject_verification(uuid,text,uuid,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
