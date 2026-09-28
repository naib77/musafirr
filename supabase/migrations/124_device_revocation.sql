-- =============================================
-- 124 — signing a device out, for real
--
-- Phase 1 of docs/DEVICE_SESSIONS.md. Phase 0 (123) recorded devices; this is
-- what lets a user end one.
--
-- **Deleting the auth.sessions row is the only part of a sign-out that means
-- anything.** Setting `revoked_at` is bookkeeping the client could ignore —
-- and a client that has been signed out is exactly the client you cannot
-- assume will cooperate. Removing the session removes the refresh token, so
-- the device's access token dies at its next refresh whatever it does.
--
-- Verified before this was written, because "permitted" is not "works" (115's
-- lesson): auth.sessions is owned by supabase_auth_admin, but `postgres` holds
-- DELETE on it and on auth.refresh_tokens, and a delete inside a rolled-back
-- transaction really did take the count from 39 to 38. A SECURITY DEFINER
-- function owned by postgres can therefore do this; a policy or a grant could
-- not have.
-- =============================================

-- ---------------------------------------------------------------------------
-- The shared half, so Phase 2's eviction and a user's own sign-out cannot
-- drift into two different ideas of what revoking means.
--
-- NOT callable from PostgREST: it takes a row id and does no ownership check,
-- because both callers have already done one. It is revoked from every role
-- below for that reason.
-- ---------------------------------------------------------------------------
create or replace function public.fn_revoke_device_row(p_row_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_session uuid;
  v_user uuid;
  v_killed boolean := false;
begin
  update public.user_devices
     set revoked_at = now()
   where id = p_row_id
     and revoked_at is null
  returning session_id, user_id into v_session, v_user;

  if not found then
    return false;
  end if;

  -- Scoped to the owner as well as the id: a session_id copied onto the wrong
  -- row by some future bug must not become a way to end a stranger's session.
  if v_session is not null then
    delete from auth.sessions
     where id = v_session
       and user_id = v_user;
    v_killed := found;
  end if;

  -- False means the row is marked revoked but no live session was ended —
  -- either it had already expired, or `session_id` was never captured. The
  -- caller says so rather than claiming a sign-out that did not happen.
  return v_killed;
end;
$$;

-- ---------------------------------------------------------------------------
-- What the device list calls.
--
-- Returns whether a live session was actually ended, so the UI can distinguish
-- "signed out" from "marked signed out — it was already expired". Claiming the
-- first when only the second happened is how a security control loses its
-- credibility.
-- ---------------------------------------------------------------------------
create or replace function public.revoke_device(p_device_id text)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid := auth.uid();
  v_row uuid;
begin
  if v_user is null then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  select id into v_row
    from public.user_devices
   where user_id = v_user
     and device_id = p_device_id
     and revoked_at is null;

  if v_row is null then
    -- Already revoked, or never this user's. Both answer the same way on
    -- purpose: telling a caller that a device id belongs to somebody else is
    -- an oracle for device ids.
    return false;
  end if;

  return public.fn_revoke_device_row(v_row);
end;
$$;

-- ---------------------------------------------------------------------------
-- "Sign out everywhere else" — the button that matters after a lost phone.
--
-- Keeps the caller's OWN device, identified by the session in the JWT rather
-- than by a device id from the request body: a caller who could name the
-- device to keep could keep one that is not theirs to keep.
-- ---------------------------------------------------------------------------
create or replace function public.revoke_other_devices()
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid := auth.uid();
  v_session uuid;
  v_row record;
  v_count integer := 0;
begin
  if v_user is null then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  begin
    v_session := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  exception when others then
    v_session := null;
  end;

  for v_row in
    select id from public.user_devices
     where user_id = v_user
       and revoked_at is null
       -- `is distinct from` and not `<>`: with a null session_id on either
       -- side, `<>` is null, the row is skipped, and the button silently signs
       -- nothing out.
       and (v_session is null or session_id is distinct from v_session)
  loop
    if public.fn_revoke_device_row(v_row.id) then
      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end;
$$;

-- fn_revoke_device_row does no ownership check by design — it must never be
-- reachable from PostgREST, which publishes everything in `public` at
-- /rest/v1/rpc/<name>. Revoke from PUBLIC *and* anon *and* authenticated:
-- ALTER DEFAULT PRIVILEGES grants the latter two at CREATE time, and dropping
-- only PUBLIC leaves EXECUTE intact through them (115, inverted).
revoke all on function public.fn_revoke_device_row(uuid)
  from public, anon, authenticated;

revoke all on function public.revoke_device(text) from public, anon, authenticated;
revoke all on function public.revoke_other_devices() from public, anon, authenticated;

grant execute on function public.revoke_device(text) to authenticated;
grant execute on function public.revoke_other_devices() to authenticated;

comment on function public.fn_revoke_device_row(uuid) is
  'Internal. No ownership check — callers must have done one. Not granted to '
  'any role reachable from PostgREST.';
