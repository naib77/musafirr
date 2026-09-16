-- Verifies migration 126 against live, inside a transaction that is rolled
-- back. One result set, so it runs through the Management API as well as psql.
--
-- The rows that matter: 02 and 04 are what stop the reaper deleting a device
-- someone still uses, which would silently un-name their phone and, under a
-- cap, hand them back a slot they had not asked for.

create temporary table t_result (seq text primary key, result text)
  on commit drop;

do $$
declare
  v_alice uuid := (select id from public.profiles order by created_at limit 1);
  v_deleted integer;
begin
  insert into public.user_devices
    (user_id, device_id, platform, last_seen_at, revoked_at)
  values
    -- Revoked long ago: history nobody reads any more.
    (v_alice, 'reap-old-revoked-01', 'android',
     now() - interval '400 days', now() - interval '200 days'),
    -- Revoked recently: the list still says "signed out on ...", which is the
    -- sentence someone hunting a login they did not make comes here for.
    (v_alice, 'reap-new-revoked-02', 'android',
     now() - interval '40 days', now() - interval '10 days'),
    -- Active but ancient: not a device anyone still holds.
    (v_alice, 'reap-old-active-03', 'android',
     now() - interval '400 days', null),
    -- Active and quiet for months. NOT stale: a phone left in a drawer over a
    -- long trip is still the user's phone.
    (v_alice, 'reap-quiet-active-04', 'android',
     now() - interval '100 days', null);

  v_deleted := public.reap_stale_devices();

  insert into t_result values ('01_old_revoked_is_reaped',
    case when not exists (select 1 from public.user_devices
                           where device_id = 'reap-old-revoked-01')
         then 'PASS' else 'FAIL' end);

  insert into t_result values ('02_recent_revoked_is_kept',
    case when exists (select 1 from public.user_devices
                       where device_id = 'reap-new-revoked-02')
         then 'PASS' else 'FAIL: lost the sign-out history' end);

  insert into t_result values ('03_year_old_active_is_reaped',
    case when not exists (select 1 from public.user_devices
                           where device_id = 'reap-old-active-03')
         then 'PASS' else 'FAIL' end);

  insert into t_result values ('04_merely_quiet_device_is_kept',
    case when exists (select 1 from public.user_devices
                       where device_id = 'reap-quiet-active-04')
         then 'PASS' else 'FAIL: reaped a device still in use' end);

  insert into t_result values ('05_reports_what_it_deleted',
    case when v_deleted = 2 then 'PASS' else 'FAIL: ' || v_deleted end);

  insert into t_result values ('06_not_reachable_from_postgrest',
    case when not has_function_privilege('authenticated',
                    'public.reap_stale_devices()', 'EXECUTE')
          and not has_function_privilege('anon',
                    'public.reap_stale_devices()', 'EXECUTE')
         then 'PASS' else 'FAIL: reachable' end);
end $$;

select seq, result from t_result order by seq;
