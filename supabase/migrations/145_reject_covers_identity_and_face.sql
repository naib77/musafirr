-- 145: one admin Reject always rejects the whole person: the identity document
-- AND the face capture, whatever state each one was in.
--
-- Before this, `admin_reject_verification` (144) only touched what was pending:
--   * identity pending + face already approved: the face stayed approved;
--   * face pending + identity verified: the identity stayed verified;
-- and revoking a verified identity went through a direct table update in the
-- admin console that never touched the face at all. A rejected person could
-- keep an approved face, and the next document they uploaded would pass the
-- face half of the gate without a new capture.
--
-- Now:
--   identity  pending or verified -> rejected (stamps cleared, reason set).
--   face      the pinned pending attempt goes through review_face_verification,
--             so a newer unseen submission is still refused; every approved
--             attempt for the person is rejected with the same reason.
-- An identity that is already rejected and has no face to reject is the only
-- "nothing to do" case.
begin;

create or replace function public.admin_reject_verification(
  p_user_id uuid,
  p_reason text,
  p_face_attempt_id uuid default null,
  p_face_evidence_version uuid default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare p public.profiles; reason text:=btrim(coalesce(p_reason,'')); identity_done boolean:=false;
  face_done boolean:=false; approved_faces int:=0;
begin
  if auth.uid() is null or not public.is_admin() or auth.uid()=p_user_id then
    raise exception 'Another admin must review this verification' using errcode='42501'; end if;
  if reason='' then raise exception 'A rejection reason is required'; end if;
  if length(reason)>500 then raise exception 'Keep the reason under 500 characters'; end if;
  select * into p from public.profiles where id=p_user_id for update;
  if not found then raise exception 'Account not found'; end if;

  if p.verification_status in ('pending','verified') then
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

  update public.face_verification_attempts set status='rejected', reviewed_by=auth.uid(),
    reviewed_at=now(), review_note=reason
    where user_id=p_user_id and status='approved';
  get diagnostics approved_faces = row_count;
  face_done := face_done or approved_faces > 0;

  if not identity_done and not face_done then
    raise exception 'Nothing to reject. Refresh the queue'; end if;
  return jsonb_build_object('identity_rejected',identity_done,'face_rejected',face_done);
end;
$$;

-- Same signature as 144, so its revoke/grant still applies; restated so this
-- file is correct on its own.
revoke all on function public.admin_reject_verification(uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.admin_reject_verification(uuid,text,uuid,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
