-- Verifies migrations 124 (revocation) and 125 (the cap) against the live
-- database, inside a transaction that is rolled back:
--
--   begin; \i supabase/tests/124_125_device_limit_test.sql rollback;
--
-- One result set, so it runs through the Management API as well as psql.
--
-- The rows that matter most are the ones that would let this feature be
-- security theatre or a lockout:
--
--   03  the auth.sessions row is really deleted, not just flagged
--   06  a user cannot revoke someone else's device
--   11  the device that just signed in is never the one evicted
--   12  web is not counted and not evicted
--   14  a malformed setting falls back to "no limit", never to a lockout
--   16  fn_revoke_device_row is not reachable from PostgREST

create temporary table t_result (seq text primary key, result text)
  on commit drop;
create temporary table t_ids (who text primary key, id uuid) on commit drop;

grant select, insert on t_result to authenticated;
grant select on t_ids to authenticated;

insert into t_ids (who, id)
select 'alice', id from public.profiles order by created_at limit 1;
insert into t_ids (who, id)
select 'bob', id from public.profiles
 where id <> (select id from t_ids where who = 'alice')
 order by created_at limit 1;

-- A real auth.sessions row to delete, so row 03 proves the delete rather than
-- asserting on nothing. Rolled back with everything else.
insert into auth.sessions (id, user_id, created_at, updated_at)
values (
  '22222222-2222-2222-2222-222222222222',
  (select id from t_ids where who = 'alice'),
  now(), now()
);

do $$
declare
  v_alice uuid := (select id from t_ids where who = 'alice');
  v_bob   uuid := (select id from t_ids where who = 'bob');
  v_state text;
  v_bool  boolean;
  v_int   integer;
  v_count integer;
  v_text  text;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object(
    'sub', v_alice, 'role', 'authenticated',
    'session_id', '22222222-2222-2222-2222-222222222222')::text, true);

  -- ── 124: revocation ──────────────────────────────────────────────────────
  perform public.register_device('dev-alice-phone-0001', 'android', 'Pixel 8');

  select session_id::text into v_text from public.user_devices
   where user_id = v_alice and device_id = 'dev-alice-phone-0001';
  insert into t_result values ('01_session_captured_from_jwt',
    case when v_text = '22222222-2222-2222-2222-222222222222'
         then 'PASS' else 'FAIL: ' || coalesce(v_text, 'null') end);

  v_bool := public.revoke_device('dev-alice-phone-0001');
  insert into t_result values ('02_revoke_reports_a_real_signout',
    case when v_bool then 'PASS' else 'FAIL: reported no live session' end);

  -- The whole point. Flagging the row is bookkeeping a signed-out client can
  -- ignore; removing the session removes the refresh token.
  --
  -- Read as postgres: `authenticated` has no SELECT on auth.sessions, which is
  -- itself the reason revocation needs a SECURITY DEFINER function rather than
  -- a policy.
  perform set_config('role', 'none', true);
  select count(*) into v_count from auth.sessions
   where id = '22222222-2222-2222-2222-222222222222';
  perform set_config('role', 'authenticated', true);
  insert into t_result values ('03_auth_session_row_is_gone',
    case when v_count = 0 then 'PASS' else 'FAIL: still there' end);

  select revoked_at is not null into v_bool from public.user_devices
   where user_id = v_alice and device_id = 'dev-alice-phone-0001';
  insert into t_result values ('04_revocation_is_soft',
    case when v_bool then 'PASS' else 'FAIL: row lost its history' end);

  -- Already revoked answers false rather than raising: the list can be tapped
  -- twice, and a second tap is not an error.
  v_bool := public.revoke_device('dev-alice-phone-0001');
  insert into t_result values ('05_second_revoke_is_not_an_error',
    case when v_bool = false then 'PASS' else 'FAIL' end);

  -- Signing in again brings the device back — under a cap, a device the user
  -- deliberately returns to is one they want.
  perform public.register_device('dev-alice-phone-0001', 'android');
  select revoked_at is null into v_bool from public.user_devices
   where user_id = v_alice and device_id = 'dev-alice-phone-0001';
  insert into t_result values ('07_signing_in_again_unrevokes',
    case when v_bool then 'PASS' else 'FAIL' end);

  -- ── cross-user ───────────────────────────────────────────────────────────
  perform set_config('request.jwt.claims', json_build_object(
    'sub', v_bob, 'role', 'authenticated')::text, true);

  v_bool := public.revoke_device('dev-alice-phone-0001');
  insert into t_result values ('06_cannot_revoke_another_users_device',
    case when v_bool = false then 'PASS' else 'FAIL: reported success' end);

  -- ── 125: the cap ─────────────────────────────────────────────────────────
  perform set_config('request.jwt.claims', json_build_object(
    'sub', v_alice, 'role', 'authenticated')::text, true);

  insert into t_result values ('08_seeded_unlimited',
    case when public.max_devices_per_user() = 0
         then 'PASS' else 'FAIL: ' || public.max_devices_per_user() end);

  -- Four phones under no limit: none evicted.
  perform public.register_device('dev-alice-phone-0002', 'android');
  perform public.register_device('dev-alice-phone-0003', 'android');
  perform public.register_device('dev-alice-phone-0004', 'ios');
  select count(*) into v_count from public.user_devices
   where user_id = v_alice and revoked_at is null and platform <> 'web';
  insert into t_result values ('09_no_limit_evicts_nothing',
    case when v_count = 4 then 'PASS' else 'FAIL: ' || v_count end);

  perform set_config('role', 'none', true);
  update public.app_settings set value = '2' where key = 'max_devices_per_user';
  perform set_config('role', 'authenticated', true);

  insert into t_result values ('10_setting_is_read_back',
    case when public.max_devices_per_user() = 2
         then 'PASS' else 'FAIL: ' || public.max_devices_per_user() end);

  -- Registering a fifth device applies the cap, and the device that just
  -- signed in must survive it.
  --
  -- This is the row that earned its keep: every register_device call here runs
  -- in ONE transaction, so `now()` is identical for all of them and the
  -- devices cannot be told apart by last_seen_at. An eviction ordered only by
  -- time evicted the arriving device. It is protected by id now.
  perform public.register_device('dev-alice-phone-0005', 'android');
  select revoked_at is null into v_bool from public.user_devices
   where user_id = v_alice and device_id = 'dev-alice-phone-0005';
  insert into t_result values ('11_the_arriving_device_survives',
    case when v_bool then 'PASS' else 'FAIL: evicted itself' end);

  select count(*) into v_count from public.user_devices
   where user_id = v_alice and revoked_at is null and platform <> 'web';
  insert into t_result values ('11b_count_is_down_to_the_limit',
    case when v_count = 2 then 'PASS' else 'FAIL: ' || v_count end);

  -- Web is exempt: a browser that loses its id on a cleared cache would
  -- otherwise consume the whole allowance by itself.
  perform public.register_device('dev-alice-browser-01', 'web');
  perform public.register_device('dev-alice-browser-02', 'web');
  perform public.register_device('dev-alice-browser-03', 'web');
  select count(*) into v_count from public.user_devices
   where user_id = v_alice and revoked_at is null and platform = 'web';
  insert into t_result values ('12_web_is_neither_counted_nor_evicted',
    case when v_count = 3 then 'PASS' else 'FAIL: ' || v_count end);

  select count(*) into v_count from public.user_devices
   where user_id = v_alice and revoked_at is null and platform <> 'web';
  insert into t_result values ('12b_web_did_not_evict_a_phone',
    case when v_count = 2 then 'PASS' else 'FAIL: ' || v_count end);

  -- ── the validator and the fallback ───────────────────────────────────────
  perform set_config('role', 'none', true);

  v_state := 'no error';
  begin
    update public.app_settings set value = 'lots'
     where key = 'max_devices_per_user';
  exception when others then v_state := sqlstate;
  end;
  insert into t_result values ('13_junk_setting_refused_at_the_source',
    case when v_state = '22023' then 'PASS' else 'FAIL: ' || v_state end);

  -- Past the trigger, the way 119's test does it, to prove the read-side guard
  -- is not decoration. A row that predates a guard must not lock anyone out.
  alter table public.app_settings disable trigger user;
  update public.app_settings set value = 'lots'
   where key = 'max_devices_per_user';
  alter table public.app_settings enable trigger user;

  insert into t_result values ('14_malformed_value_falls_back_to_no_limit',
    case when public.max_devices_per_user() = 0
         then 'PASS' else 'FAIL: ' || public.max_devices_per_user() end);

  v_state := 'no error';
  begin
    update public.app_settings set value = '99'
     where key = 'max_devices_per_user';
  exception when others then v_state := sqlstate;
  end;
  insert into t_result values ('15_absurd_limit_refused',
    case when v_state = '22023' then 'PASS' else 'FAIL: ' || v_state end);

  -- ── the internal functions are not endpoints ─────────────────────────────
  insert into t_result values ('16_internal_fns_not_granted_to_api_roles',
    case when not has_function_privilege('authenticated',
                    'public.fn_revoke_device_row(uuid)', 'EXECUTE')
          and not has_function_privilege('anon',
                    'public.fn_revoke_device_row(uuid)', 'EXECUTE')
          and not has_function_privilege('authenticated',
                    'public.fn_enforce_device_limit(uuid, uuid)', 'EXECUTE')
          and not has_function_privilege('anon',
                    'public.fn_enforce_device_limit(uuid, uuid)', 'EXECUTE')
         then 'PASS' else 'FAIL: reachable from PostgREST' end);

  -- ── sign out everywhere else ─────────────────────────────────────────────
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object(
    'sub', v_alice, 'role', 'authenticated',
    'session_id', '33333333-3333-3333-3333-333333333333')::text, true);
  perform public.register_device('dev-alice-keeper-001', 'android');

  v_int := public.revoke_other_devices();
  select revoked_at is null into v_bool from public.user_devices
   where user_id = v_alice and device_id = 'dev-alice-keeper-001';
  insert into t_result values ('17_revoke_others_keeps_the_caller',
    case when v_bool then 'PASS' else 'FAIL: signed itself out' end);

  select count(*) into v_count from public.user_devices
   where user_id = v_alice and revoked_at is null;
  insert into t_result values ('18_revoke_others_signs_out_the_rest',
    case when v_count = 1 then 'PASS' else 'FAIL: ' || v_count || ' left' end);

  perform set_config('role', 'none', true);
end $$;

select seq, result from t_result order by seq;
