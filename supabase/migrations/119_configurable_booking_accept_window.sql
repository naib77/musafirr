-- Migration 119: the host-response window becomes an admin setting.
--
-- A booking request that the host never answers is rejected automatically.
-- That window was 24 hours, written into `expire_stale_bookings()` (018) as an
-- `INTERVAL '24 hours'` plus the same number spelled out in three notification
-- strings, and again in Dart as `BookingRules.expirationDuration`. Changing it
-- meant a migration and an app release.
--
-- It is now `app_settings.booking_accept_window_hours`, edited from the admin
-- portal like every other app-wide knob (see "Nothing user-tunable belongs in
-- Dart" in CLAUDE.md).
--
-- ── Who enforces it ────────────────────────────────────────────────────────
--
-- Only this job. Nothing in the client cancels a booking; the Dart copy of the
-- window exists so the guest's countdown agrees with the server, and it fails
-- open to 24 hours if the settings table cannot be read. That asymmetry is on
-- purpose: a stale client shows a slightly wrong countdown, which is cosmetic,
-- where a client that could expire bookings would be a second enforcer of a
-- rule the database already owns.
--
-- ── Why the cron cadence changes too ───────────────────────────────────────
--
-- The job ran hourly, which was invisible at 24 hours and is not at 2: a
-- 2-hour window enforced by an hourly sweep expires somewhere between 2 and 3
-- hours, so the number an admin types would not be the number that applies.
-- Rescheduled to every 15 minutes. The job is a no-op when nothing is stale —
-- one indexed predicate over `pending` bookings — so the extra runs cost
-- nothing worth counting.
--
-- Even so the window is a floor, not a promise: expiry happens at the first
-- tick AFTER it elapses, so a booking can sit pending for up to 15 minutes
-- past its deadline. The guest's countdown reaches zero first and shows
-- "expired" while the row is still `pending`, which is the honest way round —
-- better than claiming time that has gone.

-- ---------------------------------------------------------------------------
-- 1. Validation, in the established shape: one function per key.
-- ---------------------------------------------------------------------------

create or replace function public.fn_validate_setting_booking_accept_hours(
  p_value text
) returns void
language plpgsql
immutable
set search_path to 'public'
as $$
declare n integer;
begin
  if btrim(coalesce(p_value, '')) !~ '^[0-9]+$' then
    raise exception 'booking_accept_window_hours must be a whole number of hours'
      using errcode = '22023';
  end if;
  n := btrim(p_value)::integer;
  -- Floor of 1: zero would expire a request in the same sweep that created it,
  -- so hosts would be "declining" bookings they were never shown. Ceiling of
  -- 168 (7 days): past that the guest's own dates have usually come and gone,
  -- and the request is dead of old age rather than of the host's silence.
  if n < 1 or n > 168 then
    raise exception 'booking_accept_window_hours: % is outside 1–168 hours (1 hour to 7 days)', n
      using errcode = '22023';
  end if;
end;
$$;

-- The dispatcher, with one arm added. Recreated in full rather than patched:
-- it is a CASE, and every existing key must keep its validator.
create or replace function public.fn_validate_app_setting()
returns trigger
language plpgsql
set search_path to 'public'
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
    else
      null;
  end case;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. One reader, so the guard is written once.
-- ---------------------------------------------------------------------------

-- Mirrors the `fallback_cap` CTE in search_listings: the regex in the WHERE is
-- what makes this safe rather than a cast that could raise. A missing row, a
-- blank, or anything non-numeric all fall through to 24 — the value the job
-- used before it was configurable.
--
-- The validator above means a bad value cannot be written today. This still
-- guards it, because rows predate guards and because a function that can raise
-- inside a cron job is a job that silently stops running.
create or replace function public.booking_accept_window_hours()
returns integer
language sql
stable
set search_path to 'public'
as $$
  select coalesce(
    (select btrim(value)::integer
       from public.app_settings
      where key = 'booking_accept_window_hours'
        and btrim(coalesce(value, '')) ~ '^[0-9]+$'),
    24);
$$;

-- 116's rule: a function in `public` is an unauthenticated PostgREST endpoint
-- from birth, so anything without its own body check gets its default grants
-- taken away. Nothing client-side calls this — the app reads app_settings
-- directly — and expire_stale_bookings is SECURITY DEFINER, so it still can.
revoke execute on function public.booking_accept_window_hours()
  from public, anon, authenticated;

-- How the window is said out loud in a notification.
--
-- Hours below two days, days above: "48 hours" is arithmetic, "2 days" is
-- English. 24 deliberately stays "24 hours" rather than becoming "1 day", so
-- the default configuration keeps the exact wording guests have been reading
-- since 018 and this migration changes no visible text on its own.
create or replace function public.fn_humanise_hours(p_hours integer)
returns text
language sql
immutable
set search_path to 'public'
as $$
  select case
    when p_hours >= 48 and p_hours % 24 = 0
      then (p_hours / 24)::text || ' days'
    when p_hours = 1 then '1 hour'
    else p_hours::text || ' hours'
  end;
$$;

revoke execute on function public.fn_humanise_hours(integer)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Seed the row, so the portal shows the value in force.
-- ---------------------------------------------------------------------------

-- 24, which is what the job has always done. Inserted rather than left absent
-- so an admin opening Settings sees the number that applies instead of an
-- empty box they have to know the default for.
insert into public.app_settings (key, value)
values ('booking_accept_window_hours', '24')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 4. expire_stale_bookings reads the setting.
-- ---------------------------------------------------------------------------

-- 018's body verbatim except that the interval and the three prose strings
-- come from the setting. Signature and return unchanged, so the cron command
-- and admin_expire_bookings() need no edit.
create or replace function public.expire_stale_bookings()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
    expired_count integer;
    booking_record RECORD;
    listing_record RECORD;
    guest_record RECORD;
    v_hours integer;
    v_window text;
begin
    expired_count := 0;
    -- Read ONCE, outside the loop: a mid-sweep edit must not expire the first
    -- half of the batch on one rule and the second half on another.
    v_hours := public.booking_accept_window_hours();
    v_window := public.fn_humanise_hours(v_hours);

    for booking_record in
        select b.*
        from public.bookings b
        where b.booking_status = 'pending'
          and b.created_at < now() - make_interval(hours => v_hours)
    loop
        update public.bookings
        set booking_status = 'rejected',
            rejection_reason = format(
              'Booking request expired after %s without host response', v_window)
        where id = booking_record.id;

        select l.title, l.owner_id into listing_record
        from public.listings l
        where l.id = booking_record.listing_id;

        select p.full_name into guest_record
        from public.profiles p
        where p.id = booking_record.tenant_id;

        insert into public.notifications (
            user_id, type, title, body, priority, action_url, data
        ) values (
            booking_record.tenant_id,
            'booking_rejected'::notification_type,
            'Booking Request Expired',
            format('Your booking request for %s expired. The host did not respond within %s.',
                coalesce(listing_record.title, 'the property'), v_window),
            'normal'::notification_priority,
            '/trips/' || booking_record.id,
            jsonb_build_object(
                'booking_id', booking_record.id,
                'listing_id', booking_record.listing_id,
                'reason', 'expired',
                'window_hours', v_hours,
                'expired_at', now()
            )
        );

        insert into public.notifications (
            user_id, type, title, body, priority, action_url, data
        ) values (
            listing_record.owner_id,
            'booking_cancelled'::notification_type,
            'Booking Request Expired',
            format('A booking request from %s for %s expired because you did not respond within %s.',
                coalesce(guest_record.full_name, 'a guest'),
                coalesce(listing_record.title, 'your property'),
                v_window),
            'normal'::notification_priority,
            '/host/reservations/' || booking_record.id,
            jsonb_build_object(
                'booking_id', booking_record.id,
                'listing_id', booking_record.listing_id,
                'reason', 'expired',
                'window_hours', v_hours,
                'expired_at', now()
            )
        );

        expired_count := expired_count + 1;
    end loop;

    if expired_count > 0 then
        raise notice 'Expired % pending bookings (window: %)', expired_count, v_window;
    end if;

    return expired_count;
end;
$$;

comment on function public.expire_stale_bookings() is
  'Rejects pending bookings older than app_settings.booking_accept_window_hours '
  '(default 24). Scheduled every 15 minutes by the expire-stale-bookings cron job.';

-- 116 revoked this from public/anon/authenticated; recreating the body does
-- not restore grants, but ALTER DEFAULT PRIVILEGES does not apply to CREATE OR
-- REPLACE either. Re-stated so the revoke cannot be lost to a future rewrite.
revoke execute on function public.expire_stale_bookings()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Sweep often enough that the configured number means something.
-- ---------------------------------------------------------------------------

do $$
begin
  -- cron.schedule upserts by job name, so this replaces job 1's schedule
  -- rather than adding a second one. Guarded because pg_cron may be absent on
  -- a local/branch database, where the function is still callable by hand.
  perform cron.schedule(
    'expire-stale-bookings',
    '*/15 * * * *',
    'SELECT public.expire_stale_bookings()'
  );
exception when others then
  raise notice 'pg_cron not available; expire_stale_bookings must be triggered manually';
end $$;
