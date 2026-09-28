-- Verifies migration 127 against live, rolled back. One result set.
--
-- The rows that matter: 01 and 02 are the enforcement gap actually closing —
-- a device is evicted by the login itself, with no cooperating client — and 03
-- is the guard that stops that same function being a way to sign strangers out.

create temporary table t_result (seq text primary key, result text)
  on commit drop;

do $$
declare
  v_alice uuid := (select id from public.profiles order by created_at limit 1);
  v_state text;
  v_evicted integer;
  v_count integer;
begin
  perform set_config('request.jwt.claims',
    json_build_object('role', 'service_role')::text, true);

  update public.app_settings set value = '2' where key = 'max_devices_per_user';

  perform public.admin_register_device(v_alice, 'login-phone-0001', 'android');
  perform public.admin_register_device(v_alice, 'login-phone-0002', 'android');
  v_evicted := public.admin_register_device(v_alice, 'login-phone-0003', 'android');

  -- The whole point of 127: nothing in the client was involved.
  insert into t_result values ('01_login_alone_enforces_the_cap',
    case when v_evicted = 1 then 'PASS' else 'FAIL: evicted ' || v_evicted end);

  insert into t_result values ('02_the_arriving_device_survives',
    case when exists (select 1 from public.user_devices
                       where user_id = v_alice
                         and device_id = 'login-phone-0003'
                         and revoked_at is null)
         then 'PASS' else 'FAIL: evicted itself' end);

  -- An eviction is the one event the user did not ask for, so it is announced.
  select count(*) into v_count from public.notifications
   where user_id = v_alice and type = 'security_alert'
     and data ->> 'reason' = 'device_limit';
  insert into t_result values ('04_the_user_is_told',
    case when v_count = 1 then 'PASS' else 'FAIL: ' || v_count end);

  -- A revoked device must stop receiving pushes, or a lost phone keeps showing
  -- messages after being signed out — most of what the user wanted stopped.
  insert into public.fcm_tokens (user_id, token, device_id, is_active)
  values (v_alice, 'tok-for-0001', 'login-phone-0001', true);
  update public.user_devices set revoked_at = null
   where user_id = v_alice and device_id = 'login-phone-0001';
  update public.user_devices set revoked_at = now()
   where user_id = v_alice and device_id = 'login-phone-0001';
  insert into t_result values ('05_revoking_deactivates_its_push_tokens',
    case when exists (select 1 from public.fcm_tokens
                       where token = 'tok-for-0001' and is_active = false)
         then 'PASS' else 'FAIL: still pushing' end);

  -- ── as a signed-in user ──────────────────────────────────────────────────
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_alice, 'role', 'authenticated')::text, true);

  -- A four-key call from a bundle that predates 127 must still resolve against
  -- the five-parameter function, or every deployed client stops registering
  -- for push the moment this migration lands.
  perform public.upsert_fcm_token(v_alice, 'tok-legacy-4key', 'android', 'Pixel');
  insert into t_result values ('06_legacy_four_arg_call_still_works',
    case when exists (select 1 from public.fcm_tokens
                       where token = 'tok-legacy-4key')
         then 'PASS' else 'FAIL' end);

  v_state := 'no error';
  begin
    perform public.admin_register_device(v_alice, 'login-sneaky-001', 'android');
  exception when others then v_state := sqlstate;
  end;
  insert into t_result values ('03_not_callable_by_a_signed_in_user',
    case when v_state = '42501' then 'PASS' else 'FAIL: ' || v_state end);

  insert into t_result values ('07_not_granted_to_api_roles',
    case when not has_function_privilege('authenticated',
                    'public.admin_register_device(uuid, text, text)', 'EXECUTE')
          and not has_function_privilege('anon',
                    'public.admin_register_device(uuid, text, text)', 'EXECUTE')
         then 'PASS' else 'FAIL: reachable' end);
end $$;

select seq, result from t_result order by seq;
