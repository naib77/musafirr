-- =============================================
-- 126 — reaping device rows that stopped meaning anything
--
-- Completes docs/DEVICE_SESSIONS.md's fifth principle: "a device is not a
-- session — reinstalling must not burn a slot forever". 123-125 gave every row
-- a `last_seen_at` and nothing ever read it for this purpose, so the table grew
-- without bound and a phone sold two years ago stayed in the list forever.
--
-- Two different problems, deliberately given two different windows:
--
--   * A REVOKED row is history. It is kept so the list can say "signed out on
--     12 Mar" rather than letting a device vanish, which reads as data loss —
--     but that sentence stops being useful long before it stops being stored.
--   * An ACTIVE row that has not been seen in a year is not a device anyone
--     still has. It is not evicted the moment it goes quiet, because a phone
--     left in a drawer over a long trip is still the user's phone.
--
-- Neither window is enforcement and neither can lock anyone out: deleting a
-- row only means the next sign-in from that device records a new one.
-- =============================================

create or replace function public.reap_stale_devices()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer;
begin
  with gone as (
    delete from public.user_devices
     where (revoked_at is not null and revoked_at < now() - interval '180 days')
        or (revoked_at is null and last_seen_at < now() - interval '365 days')
    returning 1
  )
  select count(*) into v_deleted from gone;

  return v_deleted;
end;
$$;

-- A SECURITY DEFINER function in `public` is a public endpoint the moment it
-- is created (116), and this one deletes rows while taking no arguments to
-- check. Revoke from PUBLIC *and* anon *and* authenticated: ALTER DEFAULT
-- PRIVILEGES grants the latter two at CREATE time, and dropping only PUBLIC
-- leaves EXECUTE intact through them.
revoke all on function public.reap_stale_devices()
  from public, anon, authenticated;

comment on function public.reap_stale_devices() is
  'Internal, cron-only. Deletes revoked device rows older than 180 days and '
  'active ones unseen for 365. Not granted to any role reachable from '
  'PostgREST.';

-- ---------------------------------------------------------------------------
-- Daily is plenty: both windows are measured in months, so the difference
-- between reaping at 180 days and at 181 is nothing at all. Contrast
-- expire_stale_bookings (119), which runs every 15 minutes because its window
-- is configurable down to one hour.
-- ---------------------------------------------------------------------------
do $$
begin
  -- Upserts by job name, so re-applying replaces the schedule rather than
  -- adding a second job. Guarded because pg_cron may be absent on a local or
  -- branch database, where the function is still callable by hand.
  perform cron.schedule(
    'reap-stale-devices',
    '17 3 * * *',
    'SELECT public.reap_stale_devices()'
  );
exception when others then
  raise notice 'pg_cron not available; reap_stale_devices must be run manually';
end $$;
