-- =============================================
-- 127 — enforcing the device limit where the session is minted, and telling
--       the user when it bites
--
-- Closes the gap docs/DEVICE_SESSIONS.md has carried since 125: registration
-- was a client call, so a client that simply never called `register_device`
-- was never recorded and therefore never evicted. The cap was enforced *for*
-- cooperating clients rather than *against* anything — the same class as "the
-- booking form checks it".
--
-- `verify-otp` is the only place a session is minted and the only one running
-- as service role, so that is where the cap now applies. It cannot use
-- `register_device`: that reads `auth.uid()`, and inside the edge function
-- there is no caller identity — the session does not exist yet. Hence an
-- `admin_` twin, guarded the way every other one in this schema is.
--
-- **It cannot capture `session_id` either**, and that is not a defect. The
-- session is created later, when the client redeems the magic-link token, so
-- at this point there is nothing to record. The client's own
-- `register_device` fills it in moments later and `coalesce` keeps it. What
-- matters is that the *eviction* has already happened, whether or not the
-- client ever calls anything.
-- =============================================

create or replace function public.admin_register_device(
  p_user_id uuid,
  p_device_id text,
  p_platform text
)
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_id uuid;
begin
  -- The guard every admin_* function in this schema carries. Without it this
  -- is a public endpoint that registers a device against any account, which
  -- under a cap is a way to sign other people out.
  if current_setting('request.jwt.claims', true)::jsonb ->> 'role'
     is distinct from 'service_role' then
    raise exception 'Only service_role can execute this function'
      using errcode = '42501';
  end if;

  if p_device_id is null or length(p_device_id) not between 8 and 128 then
    raise exception 'Invalid device id' using errcode = '22023';
  end if;

  insert into public.user_devices as d (user_id, device_id, platform)
  values (p_user_id, p_device_id, p_platform)
  on conflict (user_id, device_id) do update set
    platform = excluded.platform,
    last_seen_at = now(),
    revoked_at = null
  returning d.id into v_id;

  -- Protecting the arriving row by id, exactly as register_device does: a user
  -- must never be signed out by their own login, and `now()` is transaction
  -- time so two rows can share a last_seen_at precisely.
  return public.fn_enforce_device_limit(p_user_id, v_id);
end;
$$;

revoke all on function public.admin_register_device(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.admin_register_device(uuid, text, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- Tell the user when a device was evicted.
--
-- An eviction is the one event here the user did not ask for: a sign-out they
-- performed needs no announcement, but a phone that stops working because they
-- signed in somewhere else does. Without this the only signal is the evicted
-- device quietly landing on the login screen, which reads as a bug.
--
-- A **user-level** notification, not one aimed at the evicted device. That is
-- deliberate: `fcm_tokens` is keyed on the FCM token rather than on a device,
-- so there is no reliable route to one handset — and the evicted phone may
-- never be opened again, while the device in their hand is the one that can
-- act on it. `notifications` already has an `on_notification_send_push`
-- trigger, so an insert here is delivered.
-- ---------------------------------------------------------------------------
create or replace function public.fn_enforce_device_limit(
  p_user_id uuid,
  p_keep uuid default null
)
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_limit integer := public.max_devices_per_user();
  v_row record;
  v_evicted integer := 0;
  v_names text[] := '{}';
begin
  if v_limit <= 0 then
    return 0;
  end if;

  for v_row in
    select id,
           coalesce(nullif(label, ''), nullif(model, ''),
                    case platform
                      when 'android' then 'an Android phone'
                      when 'ios' then 'an iPhone'
                      else 'a device'
                    end) as name
      from (
        select id, label, model, platform,
               row_number() over (
                 order by (id = p_keep) desc nulls last, last_seen_at desc, id desc
               ) as rn
          from public.user_devices
         where user_id = p_user_id
           and revoked_at is null
           and platform <> 'web'
      ) ranked
     where rn > v_limit
  loop
    perform public.fn_revoke_device_row(v_row.id);
    v_evicted := v_evicted + 1;
    v_names := v_names || v_row.name;
  end loop;

  if v_evicted > 0 then
    -- Never allowed to fail the login it is reporting on. A notification that
    -- raises here would turn "you reached your device limit" into "you cannot
    -- sign in", which is the exact outcome the evict-don't-refuse rule exists
    -- to prevent.
    begin
      insert into public.notifications (user_id, type, title, body, data)
      values (
        p_user_id,
        'security_alert',
        'Signed out of another device',
        case when v_evicted = 1
             then 'You reached your device limit, so ' || v_names[1] ||
                  ' was signed out.'
             else 'You reached your device limit, so ' || v_evicted ||
                  ' devices were signed out.'
        end,
        jsonb_build_object('reason', 'device_limit', 'evicted', v_evicted)
      );
    exception when others then
      raise notice 'device-limit notification failed: %', sqlerrm;
    end;
  end if;

  return v_evicted;
end;
$$;

revoke all on function public.fn_enforce_device_limit(uuid, uuid)
  from public, anon, authenticated;

comment on function public.fn_enforce_device_limit(uuid, uuid) is
  'Internal. No ownership check — takes a user id and must never be reachable '
  'from PostgREST.';

-- ---------------------------------------------------------------------------
-- Link a push token to the device that holds it.
--
-- `fcm_tokens` is keyed on the token and those rotate, which is why it was
-- never a device registry — but with the device id recorded alongside, a
-- rotated token can at least be recognised as the same handset, and a revoked
-- device's tokens can be retired with it.
--
-- The old 4-argument function is DROPPED rather than left beside this one.
-- Two overloads where one has a default is ambiguous to PostgREST when the
-- client sends four keys ("Could not choose the best candidate function"); a
-- single function with a default resolves a four-key call cleanly, so a
-- deployed bundle that predates this keeps working.
-- ---------------------------------------------------------------------------
alter table public.fcm_tokens
  add column if not exists device_id text;

create index if not exists idx_fcm_tokens_device
  on public.fcm_tokens (user_id, device_id)
  where device_id is not null;

drop function if exists public.upsert_fcm_token(uuid, text, text, text);

create or replace function public.upsert_fcm_token(
  p_user_id uuid,
  p_token text,
  p_device_type text default 'android',
  p_device_name text default null,
  p_device_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  -- Unchanged from the live definition: 012's repo file shows no guard, but
  -- the deployed body has had one since a later migration, and dropping it
  -- here would reopen push-notification hijacking for every account.
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  insert into public.fcm_tokens (user_id, token, device_type, device_name, device_id)
  values (p_user_id, p_token, p_device_type, p_device_name, p_device_id)
  on conflict (user_id, token)
  do update set
    is_active = true,
    last_used_at = now(),
    updated_at = now(),
    device_type = coalesce(excluded.device_type, fcm_tokens.device_type),
    device_name = coalesce(excluded.device_name, fcm_tokens.device_name),
    device_id = coalesce(excluded.device_id, fcm_tokens.device_id)
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.upsert_fcm_token(uuid, text, text, text, text)
  from public, anon;
grant execute on function public.upsert_fcm_token(uuid, text, text, text, text)
  to authenticated;

-- A signed-out device must stop receiving pushes for that account. Without
-- this a lost phone keeps showing message and booking notifications after it
-- has been signed out, which is most of what the user was trying to stop.
create or replace function public.fn_deactivate_device_tokens()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.revoked_at is not null and old.revoked_at is null
     and new.device_id is not null then
    update public.fcm_tokens
       set is_active = false, updated_at = now()
     where user_id = new.user_id
       and device_id = new.device_id;
  end if;
  return new;
end;
$$;

drop trigger if exists user_devices_revoked_tokens on public.user_devices;
create trigger user_devices_revoked_tokens
  after update on public.user_devices
  for each row
  execute function public.fn_deactivate_device_tokens();
