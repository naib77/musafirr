-- =============================================
-- 125 — a limit on how many devices an account may hold
--
-- Phase 2 of docs/DEVICE_SESSIONS.md. Read that first: the shape of this is
-- decided by two facts about THIS app rather than by what other apps do.
--
--   1. The only way back into Musafir is a real SMS. Every hard lockout costs
--      money and support, and the master OTP is an unthrottled allowlist entry
--      kept live for the Play reviewer — a device cap must never be the thing
--      that locks that account out mid-review. So the limit EVICTS, it does
--      not refuse.
--   2. Web is the primary target and has no durable device id. A localStorage
--      UUID dies with clear-site-data and never exists in a private window, so
--      a browser can burn a slot per visit. Web is therefore exempt from the
--      count, not merely given a bigger one.
--
-- Seeded at 0 = unlimited, so applying this migration changes nothing until an
-- admin types a number.
-- =============================================

-- `is_public` because the device list shows "2 of 3 devices", and every other
-- setting the app reads at startup is public too. The value is a policy, not a
-- secret.
insert into public.app_settings (key, value, is_public)
values ('max_devices_per_user', '0', true)
on conflict (key) do nothing;

comment on column public.app_settings.value is
  'Validated on write by fn_validate_app_setting. max_devices_per_user: how '
  'many non-web devices one account may hold at once, 0 = no limit. Over it, '
  'the least recently seen is signed out — logins are never refused, because '
  'the only way back in is an SMS.';

-- ---------------------------------------------------------------------------
-- The validator arm. `fn_validate_app_setting` is a CASE, so it has to be
-- recreated IN FULL — a patch that drops an arm silently stops validating that
-- key, which is the trap CLAUDE.md warns about under app_settings.
-- ---------------------------------------------------------------------------
create or replace function public.fn_validate_setting_max_devices(p_value text)
returns void
language plpgsql
as $$
begin
  if p_value !~ '^[0-9]+$' then
    raise exception 'max_devices_per_user must be a whole number'
      using errcode = '22023';
  end if;

  -- The ceiling is not arbitrary: it is high enough that no honest user meets
  -- it and low enough that a typo cannot make the setting meaningless.
  if p_value::int > 20 then
    raise exception 'max_devices_per_user must be 20 or fewer'
      using errcode = '22023';
  end if;
end;
$$;

create or replace function public.fn_validate_app_setting()
returns trigger
language plpgsql
as $$
begin
  case new.key
    when 'search_radius_tiers_m' then
      perform public.fn_validate_setting_search_radius_tiers(new.value);
    when 'search_landmark_radius_m', 'search_nearest_fallback_limit' then
      perform public.fn_validate_setting_search_scalar(new.key, new.value);
    when 'payout_channels_enabled' then
      perform public.fn_validate_setting_payout_channels(new.value);
    when 'address_disclosure_grace_days' then
      perform public.fn_validate_setting_address_grace(new.value);
    when 'platform_commission_pct' then
      perform public.fn_validate_setting_commission_pct(new.value);
    when 'active_theme' then
      perform public.fn_validate_setting_active_theme(new.value);
    when 'booking_accept_window_hours' then
      perform public.fn_validate_setting_booking_accept_hours(new.value);
    when 'android_min_version_code' then
      perform public.fn_validate_setting_android_min_version_code(new.value);
    when 'max_devices_per_user' then
      perform public.fn_validate_setting_max_devices(new.value);
    else
      null;
  end case;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Re-guards the value on read, and falls back to 0.
--
-- Not redundant with the validator: rows predate guards, and a function that
-- can raise inside a login is a login that stops working for everyone. Same
-- reasoning as booking_accept_window_hours() (119), and the same reasoning as
-- android_min_version_code (122) for why the fallback is the value that
-- restricts nobody — this is a setting that can take the app away from a user,
-- so failing open has to mean *don't*.
-- ---------------------------------------------------------------------------
create or replace function public.max_devices_per_user()
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_raw text;
begin
  select value into v_raw from public.app_settings
   where key = 'max_devices_per_user';

  if v_raw is null or v_raw !~ '^[0-9]+$' then
    return 0;
  end if;

  if v_raw::int > 20 then
    return 0;
  end if;

  return v_raw::int;
end;
$$;

-- ---------------------------------------------------------------------------
-- Enforcement. Called after a device registers.
--
-- Returns how many devices it signed out, so the caller can tell the user
-- which of their devices just lost its session rather than leaving them to
-- discover it.
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
begin
  if v_limit <= 0 then
    return 0;
  end if;

  -- `p_keep` is the device that just registered, and it is protected
  -- **explicitly** rather than by having the newest `last_seen_at`.
  --
  -- That distinction is not pedantry. `now()` is transaction time, so two
  -- registrations inside one transaction share a timestamp exactly, and the
  -- tiebreaker then decides which device survives — the test caught this by
  -- evicting the device that had just signed in. Ordering by time alone is
  -- also at the mercy of a clock that went backwards. A user must never be
  -- signed out by their own login, so that cannot rest on a comparison.
  --
  -- Web is excluded from the count AND from eviction: a browser that cannot
  -- keep an identifier through a cleared cache would consume the whole
  -- allowance by itself, and evicting one is pointless because the next visit
  -- arrives as a different device anyway.
  for v_row in
    select id from (
      select id,
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
    -- Counted whether or not a live session was ended: the row is marked
    -- revoked either way, so the slot is reclaimed either way. Only counting
    -- real sign-outs would report 0 for a user whose old sessions had all
    -- expired, which reads as "nothing happened".
    perform public.fn_revoke_device_row(v_row.id);
    v_evicted := v_evicted + 1;
  end loop;

  return v_evicted;
end;
$$;

-- ---------------------------------------------------------------------------
-- register_device gains the enforcement step.
--
-- Replaced in full rather than patched, because that is the only way to see
-- what it now does. Everything above the marked block is 123 unchanged.
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

  if p_device_id is null or length(p_device_id) not between 8 and 128 then
    raise exception 'Invalid device id' using errcode = '22023';
  end if;

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
    model = coalesce(excluded.model, d.model),
    os_version = coalesce(excluded.os_version, d.os_version),
    app_version = coalesce(excluded.app_version, d.app_version),
    session_id = coalesce(excluded.session_id, d.session_id),
    last_ip = coalesce(excluded.last_ip, d.last_ip),
    last_seen_at = now(),
    revoked_at = null
  returning d.id into v_id;

  -- ── Phase 2 (125) ────────────────────────────────────────────────────────
  -- After the upsert, and passing the row that just registered so it is
  -- protected by identity rather than by timestamp. A user must never be
  -- signed out by their own login.
  perform public.fn_enforce_device_limit(v_user, v_id);

  return v_id;
end;
$$;

revoke all on function public.fn_enforce_device_limit(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.max_devices_per_user() from public, anon;
revoke all on function public.register_device(text, text, text, text, text)
  from public, anon, authenticated;

grant execute on function public.register_device(text, text, text, text, text)
  to authenticated;
-- The client shows the limit in the device list ("2 of 3 devices"), so it has
-- to be readable. It exposes nothing: app_settings is already public.
grant execute on function public.max_devices_per_user() to authenticated, anon;

comment on function public.fn_enforce_device_limit(uuid, uuid) is
  'Internal. No ownership check — takes a user id and must never be reachable '
  'from PostgREST.';
