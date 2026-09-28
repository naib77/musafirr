-- Verifies migration 123 against the live database, inside a transaction that
-- is rolled back:
--
--   begin; \i supabase/tests/123_user_devices_test.sql rollback;
--
-- Results come back as ONE result set rather than as notices, so the same file
-- runs through the Management API (which returns only the last statement's
-- rows) as well as through psql.
--
-- The negative controls matter more than the positive ones: rows 05-07, 09, 10
-- and 13 are what go red if the RLS or the SECURITY DEFINER guards are
-- loosened later. `auth.uid()` reads a request-local GUC, so impersonation is
-- `set_config('request.jwt.claims', …, true)` — the same shape as
-- 113_114_public_browse_and_identity_test.sql.

create temporary table t_result (seq text primary key, result text)
  on commit drop;
create temporary table t_ids (who text primary key, id uuid) on commit drop;

-- The block below runs as `authenticated` in order to be governed by RLS, and
-- that role owns neither temp table. Without these grants the first write to
-- t_result fails with 42501 and looks exactly like a policy refusal.
grant select, insert on t_result to authenticated;
grant select on t_ids to authenticated;

insert into t_ids (who, id)
select 'alice', id from public.profiles order by created_at limit 1;
insert into t_ids (who, id)
select 'bob', id from public.profiles
 where id <> (select id from t_ids where who = 'alice')
 order by created_at limit 1;

do $$
declare
  v_alice uuid := (select id from t_ids where who = 'alice');
  v_bob   uuid := (select id from t_ids where who = 'bob');
  v_state text;
  v_bool  boolean;
  v_text  text;
  v_uuid  uuid;
  v_count int;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_alice, 'role', 'authenticated',
      'session_id', '11111111-1111-1111-1111-111111111111'
    )::text, true);

  -- ── recording ────────────────────────────────────────────────────────────
  v_uuid := public.register_device(
    'dev-aaaaaaaa-0001', 'android', 'Pixel 8', '14', '1.0.0');
  insert into t_result values ('01_register_returns_a_row',
    case when v_uuid is not null then 'PASS' else 'FAIL' end);

  -- Read from the JWT, never accepted from the caller.
  select session_id::text into v_text from public.user_devices
   where user_id = v_alice and device_id = 'dev-aaaaaaaa-0001';
  insert into t_result values ('02_session_id_read_from_jwt',
    case when v_text = '11111111-1111-1111-1111-111111111111'
         then 'PASS' else 'FAIL: ' || coalesce(v_text, 'null') end);

  -- A device signing in twice must not consume two slots under a future cap.
  perform public.register_device('dev-aaaaaaaa-0001', 'android');
  select count(*) into v_count from public.user_devices
   where user_id = v_alice and device_id = 'dev-aaaaaaaa-0001';
  insert into t_result values ('03_register_is_idempotent',
    case when v_count = 1 then 'PASS' else 'FAIL: ' || v_count end);

  -- A client that cannot read its own model must not erase what an earlier
  -- launch already knew.
  select model into v_text from public.user_devices
   where user_id = v_alice and device_id = 'dev-aaaaaaaa-0001';
  insert into t_result values ('04_nulls_do_not_erase_known_fields',
    case when v_text = 'Pixel 8' then 'PASS' else 'FAIL: ' || coalesce(v_text,'null') end);

  -- ── the guards ───────────────────────────────────────────────────────────
  v_state := 'no error';
  begin
    perform public.register_device('short', 'web');
  exception when others then v_state := sqlstate;
  end;
  insert into t_result values ('05_short_device_id_refused',
    case when v_state = '22023' then 'PASS' else 'FAIL: ' || v_state end);

  -- No INSERT policy, deliberately: a client that could write rows through
  -- PostgREST could invent slots for itself under a cap.
  v_state := 'no error';
  begin
    insert into public.user_devices (user_id, device_id, platform)
    values (v_alice, 'dev-direct-insert', 'web');
  exception when others then v_state := sqlstate;
  end;
  insert into t_result values ('06_direct_insert_refused',
    case when v_state = '42501' then 'PASS' else 'FAIL: ' || v_state end);

  -- Only `label` is writable from the client; revoked_at, last_seen_at and
  -- session_id are what a cap would depend on.
  v_state := 'no error';
  begin
    update public.user_devices set revoked_at = now()
     where user_id = v_alice and device_id = 'dev-aaaaaaaa-0001';
  exception when others then v_state := sqlstate;
  end;
  insert into t_result values ('07_revoked_at_not_client_writable',
    case when v_state = '42501' then 'PASS' else 'FAIL: ' || v_state end);

  v_state := 'ok';
  begin
    update public.user_devices set label = 'Naib''s Pixel'
     where user_id = v_alice and device_id = 'dev-aaaaaaaa-0001';
  exception when others then v_state := sqlstate;
  end;
  insert into t_result values ('08_label_is_client_writable',
    case when v_state = 'ok' then 'PASS' else 'FAIL: ' || v_state end);

  -- ── a GoTrue with no session_id claim still records the device ───────────
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_alice, 'role', 'authenticated')::text, true);
  v_uuid := public.register_device('dev-bbbbbbbb-0002', 'web');
  select session_id::text into v_text from public.user_devices
   where user_id = v_alice and device_id = 'dev-bbbbbbbb-0002';
  insert into t_result values ('11_registers_without_session_claim',
    case when v_uuid is not null then 'PASS' else 'FAIL' end);
  insert into t_result values ('12_session_id_null_when_claim_absent',
    case when v_text is null then 'PASS' else 'FAIL: ' || v_text end);

  -- ── as bob ───────────────────────────────────────────────────────────────
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_bob, 'role', 'authenticated')::text, true);

  select count(*) into v_count from public.user_devices
   where device_id = 'dev-aaaaaaaa-0001';
  insert into t_result values ('09_cannot_see_another_users_devices',
    case when v_count = 0 then 'PASS' else 'FAIL: ' || v_count end);

  -- Must not answer "revoked" for a device bob does not own: a true here
  -- would sign alice out.
  v_bool := public.touch_device('dev-aaaaaaaa-0001');
  insert into t_result values ('10_touching_anothers_device_is_not_revoked',
    case when v_bool = false then 'PASS' else 'FAIL' end);

  -- ── signed out ───────────────────────────────────────────────────────────
  perform set_config('request.jwt.claims', '', true);
  v_state := 'no error';
  begin
    perform public.register_device('dev-cccccccc-0003', 'web');
  exception when others then v_state := sqlstate;
  end;
  insert into t_result values ('13_anon_cannot_register',
    case when v_state = '42501' then 'PASS' else 'FAIL: ' || v_state end);

  perform set_config('role', 'none', true);
end $$;

select seq, result from t_result order by seq;
