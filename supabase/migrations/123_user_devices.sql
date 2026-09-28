-- =============================================
-- 123 — user_devices: which devices an account signs in from
--
-- Phase 0 of docs/DEVICE_SESSIONS.md: RECORDING ONLY. Nothing here restricts a
-- login, and no cap exists yet. Read that file before extending this — in
-- particular why the device list has to ship before any limit does, and why a
-- limit belongs in `verify-otp` rather than in a client-called RPC.
--
-- Why this is not `fcm_tokens` (012): that table is keyed on the FCM token and
-- those rotate, so one phone becomes several rows over time. A token exists to
-- be pushed to; a device row exists to be listed and signed out.
--
-- Why it is not `auth.sessions`: GoTrue's table already carries user_agent, ip
-- and refreshed_at, but it lives in the `auth` schema (PostgREST does not
-- expose it, none of this repo's RLS applies) and it has no stable device
-- identity — one phone produces a fresh row every time storage is cleared.
-- =============================================

create table if not exists public.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,

  -- Client-generated opaque UUID, held in localStorage (web) or
  -- SharedPreferences (Android). Deliberately NOT a hardware identifier:
  -- Android 10+ refuses IMEI and serial to normal apps, iOS's IDFV resets when
  -- the last app from a vendor is uninstalled, and the web has nothing at all.
  device_id text not null,

  platform text not null check (platform in ('web', 'android', 'ios')),

  -- User-editable in Phase 1 ("Naib's Pixel"). Null until then.
  label text,

  model text,
  os_version text,
  app_version text,

  -- The auth.sessions row this device currently holds, read from the JWT
  -- rather than passed in. This is the column that makes a Phase 1 remote
  -- sign-out real: deleting the session is what kills the refresh token, and
  -- it is the only part of a sign-out a client cannot ignore.
  --
  -- Nullable because a GoTrue that does not put `session_id` in the access
  -- token must not stop a device being recorded. Phase 1 cannot ship until it
  -- is confirmed present.
  session_id uuid,

  -- Most recent only, never a history: this is PII, and the row dies with the
  -- account through the cascade above.
  last_ip inet,

  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),

  -- Soft revocation, so Phase 1's list can say "signed out on 12 Sep" instead
  -- of the device silently vanishing, which reads as data loss.
  revoked_at timestamptz,

  unique (user_id, device_id)
);

create index if not exists idx_user_devices_user
  on public.user_devices (user_id, last_seen_at desc);

-- The eviction order a Phase 2 cap would use, and the list Phase 1 renders.
create index if not exists idx_user_devices_active
  on public.user_devices (user_id, last_seen_at)
  where revoked_at is null;

alter table public.user_devices enable row level security;

-- Read your own devices. That is the whole of Phase 1's list.
create policy "user_devices_select_own"
  on public.user_devices for select
  to authenticated
  using (auth.uid() = user_id);

-- Rename your own device, and nothing else. A column-level grant is what stops
-- `last_seen_at`, `revoked_at` or `session_id` being written from the client —
-- the USING clause alone would allow all three.
create policy "user_devices_update_own_label"
  on public.user_devices for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

revoke update on public.user_devices from authenticated;
grant update (label) on public.user_devices to authenticated;

-- There is deliberately NO INSERT policy. Rows are written only by
-- register_device below, the same shape as listing_availability_blocks (110):
-- a client that could insert through PostgREST could insert rows for a device
-- it does not hold, and under a future cap invent slots for itself.
--
-- No DELETE policy either. Phase 1 revokes (soft), it does not delete, or the
-- list loses the very history it exists to show.

comment on table public.user_devices is
  'Devices an account signs in from. Phase 0 of docs/DEVICE_SESSIONS.md: '
  'recording only, nothing is capped.';

-- ---------------------------------------------------------------------------
-- register_device — called once per sign-in, and on app start.
--
-- Takes NO user id. `SECURITY DEFINER` functions in `public` are public,
-- unauthenticated endpoints running as postgres the moment they are created
-- (see CLAUDE.md on 116), so identity is read from the JWT and never accepted
-- from the caller. 012's upsert_fcm_token takes p_user_id and is only safe
-- because a later migration added an auth.uid() guard the repo file still does
-- not show; this one has no such parameter to guard.
-- ---------------------------------------------------------------------------
create or replace function public.register_device(
  p_device_id text,
  p_platform text,
  p_model text default null,
  p_os_version text default null,
  p_app_version text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid := auth.uid();
  v_session uuid;
  v_id uuid;
begin
  if v_user is null then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  -- A device id long enough to be someone else's guess is not useful, and an
  -- unbounded one is a free write-amplification channel into an indexed column.
  if p_device_id is null or length(p_device_id) not between 8 and 128 then
    raise exception 'Invalid device id' using errcode = '22023';
  end if;

  -- Null rather than an error when the claim is absent: a GoTrue without it
  -- must not stop a device being recorded. See the column comment.
  begin
    v_session := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  exception when others then
    v_session := null;
  end;

  insert into public.user_devices as d (
    user_id, device_id, platform, model, os_version, app_version,
    session_id, last_ip
  )
  values (
    v_user, p_device_id, p_platform, p_model, p_os_version, p_app_version,
    v_session, inet_client_addr()
  )
  on conflict (user_id, device_id) do update set
    platform = excluded.platform,
    -- coalesce, not excluded: a client that cannot read its own model must not
    -- erase what an earlier launch already knew.
    model = coalesce(excluded.model, d.model),
    os_version = coalesce(excluded.os_version, d.os_version),
    app_version = coalesce(excluded.app_version, d.app_version),
    session_id = coalesce(excluded.session_id, d.session_id),
    last_ip = coalesce(excluded.last_ip, d.last_ip),
    last_seen_at = now(),
    -- Signing in again un-revokes: under a future cap an evicted device that
    -- the user deliberately returns to is a device they want back.
    revoked_at = null
  returning d.id into v_id;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- touch_device — heartbeat on resume. Returns whether this device has been
-- revoked, which is what a Phase 1 client acts on by signing itself out.
--
-- That client-side sign-out is a courtesy, NOT enforcement: the real one is
-- deleting the auth.sessions row, which Phase 1 does server-side. A client
-- that ignores this answer has already lost its refresh token.
-- ---------------------------------------------------------------------------
create or replace function public.touch_device(p_device_id text)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid := auth.uid();
  v_revoked timestamptz;
  v_found boolean;
begin
  if v_user is null then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  update public.user_devices
     set last_seen_at = now(),
         last_ip = coalesce(inet_client_addr(), last_ip)
   where user_id = v_user
     and device_id = p_device_id
     and revoked_at is null
  returning revoked_at into v_revoked;

  get diagnostics v_found = row_count;

  -- An unknown device id is not "revoked": it is a device that has never
  -- registered, or one whose row was cascaded away with a deleted account.
  -- Answering true would sign out a perfectly good session.
  if not v_found then
    return exists (
      select 1 from public.user_devices
       where user_id = v_user
         and device_id = p_device_id
         and revoked_at is not null
    );
  end if;

  return false;
end;
$$;

-- Revoke from PUBLIC *and* anon *and* authenticated before granting back: the
-- ALTER DEFAULT PRIVILEGES on this schema grants anon and authenticated at
-- CREATE time, and dropping only the PUBLIC pseudo-role leaves EXECUTE intact
-- through the explicit grant. 115's lesson, inverted.
revoke all on function public.register_device(text, text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.touch_device(text) from public, anon, authenticated;

grant execute on function public.register_device(text, text, text, text, text)
  to authenticated;
grant execute on function public.touch_device(text) to authenticated;
