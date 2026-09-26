-- =============================================
-- 133 — a client cannot award itself a role. Run inside begin; … rollback;
-- against live, after (or in the same transaction as) 133.
--
-- Rows 1 and 2 are the hole and go red without the migration (verified on
-- live: role went owner -> admin and the admin count 1 -> 2). Rows 3 to 7 are
-- the paths that must keep working — becoming a host, ordinary profile edits,
-- an admin doing admin things, and the service role — because the cheap fix
-- ("non-admins may never touch role") breaks the first of them.
--
-- Fixtures are real live rows, read not written: the oldest non-admin account
-- and the admin. Every change is undone by the enclosing rollback.
-- =============================================

create temp table t_result (n int, name text, ok boolean, detail text) on commit drop;
grant select, insert on t_result to anon, authenticated, service_role;

do $$
declare
  v_user  uuid;
  v_admin uuid;
  v_tenant uuid;
  v_role  text;
  v_msg   text;
  v_hint  text;
  v_name  text;
begin
  select id into v_user  from public.profiles where role <> 'admin' order by created_at limit 1;
  select id into v_admin from public.profiles where role  = 'admin' limit 1;
  select id into v_tenant from public.profiles where role = 'tenant' order by created_at limit 1;

  -- ---- 1  the escalation itself -------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    update public.profiles set role = 'admin' where id = v_user;
    select role::text into v_role from public.profiles where id = v_user;
    insert into t_result values (1, 'a signed-in user cannot make themselves admin',
      false, 'update accepted, role is now ' || v_role);
  exception when others then
    get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
    insert into t_result values (1, 'a signed-in user cannot make themselves admin',
      v_hint = 'role_change_forbidden', v_msg);
  end;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);

  -- ---- 2  and cannot reach it in two steps either --------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    update public.profiles set role = 'tenant' where id = v_user;
    update public.profiles set role = 'admin'  where id = v_user;
    select role::text into v_role from public.profiles where id = v_user;
    insert into t_result values (2, 'demote-then-promote is refused as well',
      v_role <> 'admin', 'role ended as ' || v_role);
  exception when others then
    get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
    insert into t_result values (2, 'demote-then-promote is refused as well',
      v_hint = 'role_change_forbidden', v_msg);
  end;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);

  -- ---- 3  becomeHost() still works ----------------------------------------
  -- SupabaseAuthService.becomeHost writes is_host + host_since + role='owner'
  -- in one client-side update. This row is why the guard is not a blanket ban.
  update public.profiles set role = 'tenant' where id = v_tenant;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_tenant, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    update public.profiles
       set is_host = true, host_since = now(), role = 'owner'
     where id = v_tenant;
    select role::text into v_role from public.profiles where id = v_tenant;
    insert into t_result values (3, 'a tenant can still become a host (tenant -> owner)',
      v_role = 'owner', 'role is now ' || v_role);
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into t_result values (3, 'a tenant can still become a host (tenant -> owner)', false, v_msg);
  end;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);

  -- ---- 4  ordinary profile edits are untouched ----------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    update public.profiles set full_name = '133 guard test', bio = 'still editable'
     where id = v_user;
    select full_name into v_name from public.profiles where id = v_user;
    insert into t_result values (4, 'name and bio are still self-service',
      v_name = '133 guard test', 'full_name = ' || v_name);
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into t_result values (4, 'name and bio are still self-service', false, v_msg);
  end;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);

  -- ---- 5  an admin can still grant a role ---------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  begin
    update public.profiles set role = 'admin' where id = v_user;
    select role::text into v_role from public.profiles where id = v_user;
    insert into t_result values (5, 'an admin can still grant the admin role',
      v_role = 'admin', 'role is now ' || v_role);
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into t_result values (5, 'an admin can still grant the admin role', false, v_msg);
  end;
  perform set_config('request.jwt.claims', '', true);

  -- ---- 6  the service role (no auth context) is untouched ------------------
  update public.profiles set role = 'tenant' where id = v_user;
  perform set_config('role', 'service_role', true);
  begin
    update public.profiles set role = 'owner' where id = v_user;
    select role::text into v_role from public.profiles where id = v_user;
    insert into t_result values (6, 'service_role (edge functions, cron) still writes roles',
      v_role = 'owner', 'role is now ' || v_role);
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into t_result values (6, 'service_role (edge functions, cron) still writes roles', false, v_msg);
  end;
  perform set_config('role', 'postgres', true);

  -- ---- 7  negative control: the older guards still fire --------------------
  -- The guard only fires on a TRANSITION to 'verified', so the fixture has to
  -- start unverified; the oldest live account is already verified and an
  -- earlier draft of this row passed for that reason alone.
  update public.profiles set verification_status = 'none' where id = v_user;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    update public.profiles set verification_status = 'verified' where id = v_user;
    insert into t_result values (7, 'self-approving identity verification is still refused',
      false, 'update accepted');
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into t_result values (7, 'self-approving identity verification is still refused',
      v_msg like '%granted by an admin%', v_msg);
  end;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

select n, case when ok then 'PASS' else 'FAIL' end as outcome, name, detail
  from t_result order by n;
