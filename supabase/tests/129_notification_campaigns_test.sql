-- =============================================
-- 129 — bulk notifications. Run inside begin; … rollback; against live.
--
-- The rows that matter most are the ones about `notification_preferences`:
-- only ONE of 44 accounts has a row, so almost every mistake here has the same
-- signature — a campaign that quietly reaches one person, or one that quietly
-- reaches everybody regardless of what they asked for.
-- =============================================

create temp table t_result (n int, name text, ok boolean, detail text) on commit drop;
grant select, insert on t_result to authenticated, service_role;

do $$
declare
  v_user   uuid;
  v_other  uuid;
  v_res    jsonb;
  v_n      integer;
  v_all    integer;
  v_ok     boolean;
  v_row    record;
  v_queued integer;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

  select id into v_user  from public.profiles order by created_at limit 1;
  select id into v_other from public.profiles order by created_at offset 1 limit 1;

  -- ---- 01  every enum label must map, or preferences are silently ignored ---
  -- This is the drift catcher. The Dart enum already lacks three labels the
  -- database has; the next one added must fail here rather than quietly opt its
  -- recipients out of their own settings.
  select count(*) into v_n
    from unnest(enum_range(null::public.notification_type)) t
   where public.fn_notification_category(t) is null;
  insert into t_result values (1, 'every notification_type maps to a category',
    v_n = 0,
    v_n::text || ' unmapped of ' ||
      (select count(*) from unnest(enum_range(null::public.notification_type)))::text);

  insert into t_result values (2, 'categories match the Dart mapping',
    public.fn_notification_category('booking_confirmed') = 'booking'
      and public.fn_notification_category('promotion_available') = 'promotion'
      and public.fn_notification_category('new_message') = 'message'
      and public.fn_notification_category('security_alert') = 'system'
      and public.fn_notification_category('payment_failed') = 'payment'
      and public.fn_notification_category('review_received') = 'review',
    'six representative types');

  -- The three the Dart enum does not have at all.
  insert into t_result values (3, 'the labels Dart has never seen still map',
    public.fn_notification_category('booking_rejected') = 'booking'
      and public.fn_notification_category('checked_in') = 'booking'
      and public.fn_notification_category('review_prompt') = 'review',
    'booking_rejected, checked_in, review_prompt');

  -- ---- 04  the LEFT JOIN. An inner join reaches exactly one person. --------
  select count(*) into v_all from public.admin_notify_audience('{}'::jsonb, 'system_alert');
  insert into t_result values (4, 'audience covers everyone, not just those with a prefs row',
    v_all = (select count(*) from public.profiles)
      and v_all > (select count(*) from public.notification_preferences),
    v_all::text || ' reachable, ' ||
      (select count(*) from public.notification_preferences)::text || ' prefs rows exist');

  -- Unlike SMS, nobody is excluded for lacking a phone.
  insert into t_result values (5, 'notification reach exceeds SMS reach',
    v_all > (select count(*) from public.admin_sms_audience('{}'::jsonb)),
    v_all::text || ' notifiable vs ' ||
      (select count(*) from public.admin_sms_audience('{}'::jsonb))::text || ' textable');

  -- ---- 06  global_enabled = false means nothing at all --------------------
  insert into public.notification_preferences (user_id, global_enabled)
  values (v_user, false)
  on conflict (user_id) do update set global_enabled = false;

  select delivers, push_allowed into v_row
    from public.admin_notify_audience(
      jsonb_build_object('user_ids', jsonb_build_array(v_user)), 'system_alert');
  insert into t_result values (6, 'global_enabled=false stops delivery entirely',
    v_row.delivers = false and v_row.push_allowed = false,
    'delivers=' || v_row.delivers::text || ' push_allowed=' || v_row.push_allowed::text);

  update public.notification_preferences set global_enabled = true where user_id = v_user;

  -- ---- 07  a disabled CATEGORY stops that category only -------------------
  update public.notification_preferences
     set category_preferences = '{"promotion": {"enabled": false}}'::jsonb
   where user_id = v_user;

  select delivers into v_ok from public.admin_notify_audience(
    jsonb_build_object('user_ids', jsonb_build_array(v_user)), 'promotion_available');
  insert into t_result values (7, 'a disabled category blocks that category',
    v_ok = false, 'promotion delivers=' || v_ok::text);

  -- NEGATIVE CONTROL: without this, row 07 would pass even if the code blocked
  -- everything for anyone holding a prefs row.
  select delivers into v_ok from public.admin_notify_audience(
    jsonb_build_object('user_ids', jsonb_build_array(v_user)), 'system_alert');
  insert into t_result values (8, 'other categories are unaffected',
    v_ok = true, 'system_alert delivers=' || v_ok::text);

  -- ---- 09  in-app only: delivered, but no push ----------------------------
  update public.notification_preferences
     set category_preferences = '{"promotion": {"enabled": true, "channels": ["inApp"]}}'::jsonb
   where user_id = v_user;

  select delivers, push_allowed into v_row from public.admin_notify_audience(
    jsonb_build_object('user_ids', jsonb_build_array(v_user)), 'promotion_available');
  insert into t_result values (9, 'channels without push still deliver in-app',
    v_row.delivers = true and v_row.push_allowed = false,
    'delivers=' || v_row.delivers::text || ' push_allowed=' || v_row.push_allowed::text);

  -- NEGATIVE CONTROL: with push in the channel list it must come back true
  -- (provided they have a device), or row 09 proves nothing.
  update public.notification_preferences
     set category_preferences =
       '{"promotion": {"enabled": true, "channels": ["inApp","push"]}}'::jsonb
   where user_id = v_user;
  select push_allowed, has_token into v_row from public.admin_notify_audience(
    jsonb_build_object('user_ids', jsonb_build_array(v_user)), 'promotion_available');
  insert into t_result values (10, 'push channel restored means push again (if they have a device)',
    v_row.push_allowed = v_row.has_token,
    'push_allowed=' || v_row.push_allowed::text || ' has_token=' || v_row.has_token::text);

  -- ---- 11  quiet hours that CROSS MIDNIGHT --------------------------------
  -- The default window is 22:00–07:00. A plain BETWEEN is false for the whole
  -- of it, so this is the case the naive implementation gets exactly backwards.
  -- start AFTER end, so the window runs [start, midnight) + [midnight, end] and
  -- genuinely contains "now" only via the wrap. `x between 23:30 and 22:30` is
  -- empty, so the naive implementation reports "not in quiet hours" and pushes
  -- at 3am — the exact thing the feature exists to prevent. Holds at any hour
  -- of the day, including just after midnight.
  update public.notification_preferences
     set category_preferences = '{}'::jsonb,
         quiet_hours_enabled = true,
         quiet_hours_allow_urgent = true,
         quiet_hours_start = ((now() at time zone 'Asia/Dhaka')::time - interval '1 hour')::time,
         quiet_hours_end   = ((now() at time zone 'Asia/Dhaka')::time - interval '2 hours')::time
   where user_id = v_user;

  select delivers, push_allowed into v_row from public.admin_notify_audience(
    jsonb_build_object('user_ids', jsonb_build_array(v_user)), 'promotion_available', 'normal');
  insert into t_result values (11,
    'a quiet window CROSSING MIDNIGHT suppresses the push',
    v_row.delivers = true and v_row.push_allowed = false,
    'delivers=' || v_row.delivers::text || ' push_allowed=' || v_row.push_allowed::text);

  -- NEGATIVE CONTROL for 11: a same-day window must behave too, or 11 would
  -- pass under an implementation that simply called everyone quiet.
  update public.notification_preferences
     set quiet_hours_start = ((now() at time zone 'Asia/Dhaka')::time - interval '1 hour')::time,
         quiet_hours_end   = ((now() at time zone 'Asia/Dhaka')::time + interval '1 hour')::time
   where user_id = v_user;
  select push_allowed into v_ok from public.admin_notify_audience(
    jsonb_build_object('user_ids', jsonb_build_array(v_user)), 'promotion_available', 'normal');
  insert into t_result values (12,
    'a same-day quiet window suppresses it as well',
    v_ok = false, 'push_allowed=' || v_ok::text);

  -- ...and OUTSIDE any quiet window the push must come back, or both of the
  -- above prove only that quiet hours are permanently on.
  update public.notification_preferences
     set quiet_hours_start = ((now() at time zone 'Asia/Dhaka')::time + interval '2 hours')::time,
         quiet_hours_end   = ((now() at time zone 'Asia/Dhaka')::time + interval '3 hours')::time
   where user_id = v_user;
  select push_allowed, has_token into v_row from public.admin_notify_audience(
    jsonb_build_object('user_ids', jsonb_build_array(v_user)), 'promotion_available', 'normal');
  insert into t_result values (13,
    'outside the quiet window the push is allowed again',
    v_row.push_allowed = v_row.has_token,
    'push_allowed=' || v_row.push_allowed::text);

  -- Back to a window containing "now" for the urgent-override rows below.
  update public.notification_preferences
     set quiet_hours_start = ((now() at time zone 'Asia/Dhaka')::time - interval '1 hour')::time,
         quiet_hours_end   = ((now() at time zone 'Asia/Dhaka')::time + interval '1 hour')::time
   where user_id = v_user;

  -- ---- 12  urgent overrides quiet hours when they allow it ----------------
  select push_allowed, has_token into v_row from public.admin_notify_audience(
    jsonb_build_object('user_ids', jsonb_build_array(v_user)), 'security_alert', 'urgent');
  insert into t_result values (14, 'urgent still pushes when quiet hours allow it',
    v_row.push_allowed = v_row.has_token,
    'push_allowed=' || v_row.push_allowed::text);

  -- ...and does not when they do not.
  update public.notification_preferences
     set quiet_hours_allow_urgent = false where user_id = v_user;
  select push_allowed into v_ok from public.admin_notify_audience(
    jsonb_build_object('user_ids', jsonb_build_array(v_user)), 'security_alert', 'urgent');
  insert into t_result values (15, 'urgent is held back when quiet hours forbid it',
    v_ok = false, 'push_allowed=' || v_ok::text);

  delete from public.notification_preferences where user_id = v_user;

  -- ---- 14  sending ---------------------------------------------------------
  v_res := public.admin_send_bulk_notification(
    'Test blast', 'Hello {{unused}}', 'system_alert', 'normal', null,
    jsonb_build_object('user_ids', jsonb_build_array(v_user, v_other)), null);

  insert into t_result values (16, 'a send creates one notification per recipient',
    (v_res ->> 'total')::int = 2
      and (select count(*) from public.notifications
            where campaign_id = (v_res ->> 'campaign_id')::uuid) = 2,
    v_res::text);

  insert into t_result values (17, 'the campaign records what it did',
    (select total_recipients from public.notification_campaigns
      where id = (v_res ->> 'campaign_id')::uuid) = 2,
    'total_recipients=2');

  -- ---- 16  suppress_push is per recipient ---------------------------------
  update public.notification_preferences set user_id = user_id where false; -- no-op
  insert into public.notification_preferences (user_id, global_enabled, category_preferences)
  values (v_other, true, '{"system": {"enabled": true, "channels": ["inApp"]}}'::jsonb)
  on conflict (user_id) do update
    set category_preferences = '{"system": {"enabled": true, "channels": ["inApp"]}}'::jsonb;

  v_res := public.admin_send_bulk_notification(
    'Mixed blast', 'body', 'system_alert', 'normal', null,
    jsonb_build_object('user_ids', jsonb_build_array(v_user, v_other)), null);

  insert into t_result values (18, 'the in-app-only recipient gets suppress_push, the other does not',
    (select data ->> 'suppress_push' from public.notifications
      where campaign_id = (v_res ->> 'campaign_id')::uuid and user_id = v_other) = 'true'
    and (select count(*) from public.notifications
          where campaign_id = (v_res ->> 'campaign_id')::uuid) = 2,
    'per-recipient flag');

  delete from public.notification_preferences where user_id = v_other;

  -- ---- 17  the cap refuses, it does not truncate --------------------------
  update public.app_settings set value = '1' where key = 'notification_bulk_max_recipients';
  begin
    perform public.admin_send_bulk_notification(
      'Too big', 'body', 'system_alert', 'normal', null, '{}'::jsonb, null);
    v_ok := false;
  exception when others then
    v_ok := true;
  end;
  insert into t_result values (19, 'a campaign over the cap is refused', v_ok, 'refused');

  update public.app_settings set value = '0' where key = 'notification_bulk_max_recipients';
  begin
    perform public.admin_send_bulk_notification(
      'Disabled', 'body', 'system_alert', 'normal', null,
      jsonb_build_object('user_ids', jsonb_build_array(v_user)), null);
    v_ok := false;
  exception when others then
    v_ok := true;
  end;
  insert into t_result values (20, 'zero disables bulk notifications, it does not unlimit them',
    v_ok, 'refused at 0');

  update public.app_settings set value = '2000' where key = 'notification_bulk_max_recipients';

  -- Proves the temp table is not left behind by the two refusals above — a
  -- second successful call in the SAME transaction would otherwise die with
  -- "relation t_audience already exists".
  v_res := public.admin_send_bulk_notification(
    'After refusals', 'body', 'system_alert', 'normal', null,
    jsonb_build_object('user_ids', jsonb_build_array(v_user)), null);
  insert into t_result values (21, 'a send still works after refusals in the same transaction',
    (v_res ->> 'total')::int = 1, 'temp table was not left behind');
end $$;

-- ---- 20-21  the trigger change, proven on the wire ------------------------
-- pg_net queues into an ordinary table, so inside this rolled-back transaction
-- the request is built and then discarded unsent. This is the only way to show
-- the push really is suppressed, and really is NOT suppressed by default.
do $$
declare
  v_user uuid;
  v_before integer;
  v_after_plain integer;
  v_after_suppressed integer;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  select id into v_user from public.profiles order by created_at limit 1;

  select count(*) into v_before from net.http_request_queue;

  insert into public.notifications (user_id, type, title, body)
  values (v_user, 'system_alert', 'plain', 'no flag');
  select count(*) into v_after_plain from net.http_request_queue;

  insert into public.notifications (user_id, type, title, body, data)
  values (v_user, 'system_alert', 'quiet', 'flagged',
          jsonb_build_object('suppress_push', true));
  select count(*) into v_after_suppressed from net.http_request_queue;

  insert into t_result values (22,
    'an ordinary notification still fires a push (018 behaviour unchanged)',
    v_after_plain = v_before + 1,
    'queue ' || v_before::text || ' -> ' || v_after_plain::text);

  insert into t_result values (23,
    'suppress_push stops the push and nothing else',
    v_after_suppressed = v_after_plain
      and (select count(*) from public.notifications
            where user_id = v_user and title = 'quiet') = 1,
    'queue unchanged at ' || v_after_suppressed::text || ', row still created');
end $$;

-- ---- 22+  reachability -----------------------------------------------------
do $$
declare fn text; n int := 23;
begin
  perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  foreach fn in array array[
    'admin_notify_audience', 'admin_send_bulk_notification'
  ] loop
    n := n + 1;
    insert into t_result
    select n,
           fn || ' is not executable by anon or authenticated',
           not has_function_privilege('authenticated', p.oid, 'execute')
             and not has_function_privilege('anon', p.oid, 'execute'),
           'anon=' || has_function_privilege('anon', p.oid, 'execute')::text ||
           ' authenticated=' || has_function_privilege('authenticated', p.oid, 'execute')::text
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public' and p.proname = fn
     limit 1;
  end loop;
end $$;

select n, case when ok then 'PASS' else 'FAIL' end as result, name, detail
  from t_result order by n;
