-- =============================================
-- 130 — the edge-invoke key. Run inside begin; … rollback; against live.
--
-- Safe to run rolled back: `net.http_post` IS transactional (verified twice on
-- live — a request enqueued in a rolled-back transaction is never sent, at top
-- level and from inside a DO block). What is NOT safe is committing a STARTED
-- sms campaign, because the every-minute cron sweep will send it; nothing here
-- does that.
-- =============================================

create temp table t_result (n int, name text, ok boolean, detail text) on commit drop;
grant select, insert on t_result to authenticated, service_role;

do $$
declare
  v_user   uuid;
  v_before int;
  v_after  int;
  v_hdr    jsonb;
  v_auth   text;
  v_def    text;
begin
  select id into v_user from public.profiles order by created_at limit 1;
  select value into v_auth from public.app_secrets where key = 'edge_invoke_key';

  insert into t_result values (1, 'edge_invoke_key exists and is non-empty',
    coalesce(v_auth,'') <> '', 'length=' || coalesce(length(v_auth),0)::text);

  -- The literal is what went stale. Its absence is the fix.
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='send_push_on_notification_insert';
  insert into t_result values (2, 'no JWT is hardcoded in the push trigger any more',
    v_def not like '%Bearer eyJ%', 'literal absent');

  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='sweep_sms_campaigns';
  insert into t_result values (3, 'the SMS sweep reads the same one key',
    v_def like '%edge_invoke_key%' and v_def not like '%sms_worker_auth%',
    'one key, no second copy');

  insert into t_result values (4, 'the superseded key name is gone',
    not exists (select 1 from public.app_secrets where key = 'sms_worker_auth'),
    'sms_worker_auth removed');

  -- ---- on the wire: the header the gateway actually receives ---------------
  select count(*) into v_before from net.http_request_queue;
  insert into public.notifications (user_id, type, title, body)
  values (v_user, 'system_alert', '130 wiring check', 'rolled back');
  select count(*) into v_after from net.http_request_queue;
  select headers into v_hdr from net.http_request_queue order by id desc limit 1;

  insert into t_result values (5, 'an ordinary notification still enqueues a push',
    v_after = v_before + 1, v_before::text || ' -> ' || v_after::text);

  insert into t_result values (6, 'the push now carries the CURRENT key, not the stale literal',
    (v_hdr ->> 'Authorization') = 'Bearer ' || v_auth,
    'bearer matches edge_invoke_key');

  insert into t_result values (7, 'the push secret is still sent alongside it',
    coalesce(length(v_hdr ->> 'x-push-secret'),0) > 0,
    'x-push-secret present');

  -- 129's guard must survive the rewrite.
  select count(*) into v_before from net.http_request_queue;
  insert into public.notifications (user_id, type, title, body, data)
  values (v_user, 'promotion_available', '130 quiet', 'rolled back',
          jsonb_build_object('suppress_push', true));
  select count(*) into v_after from net.http_request_queue;
  insert into t_result values (8, '129 suppress_push still holds after the rewrite',
    v_after = v_before, 'queue unchanged');
end $$;

-- ---- 9  a missing key must warn, not break the inbox ----------------------
do $$
declare v_user uuid; v_before int; v_after int; v_notifs int;
begin
  select id into v_user from public.profiles order by created_at limit 1;
  delete from public.app_secrets where key = 'edge_invoke_key';

  select count(*) into v_before from net.http_request_queue;
  insert into public.notifications (user_id, type, title, body)
  values (v_user, 'system_alert', '130 no key', 'rolled back');
  select count(*) into v_after from net.http_request_queue;
  select count(*) into v_notifs from public.notifications where title = '130 no key';

  -- The notification MUST still be created. A delivery-layer problem that ate
  -- the user's in-app inbox would be worse than the outage it came from.
  insert into t_result values (9,
    'with no key: no push attempted, but the notification is still created',
    v_after = v_before and v_notifs = 1,
    'queue unchanged, row created');
end $$;

select n, case when ok then 'PASS' else 'FAIL' end as result, name, detail
  from t_result order by n;
