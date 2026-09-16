-- =============================================
-- 128 — bulk SMS. Run inside begin; … rollback; against live.
--
-- The negative controls are the point. Nearly every row here would still pass
-- if the feature quietly sent duplicates, so each one is paired with the thing
-- that must NOT happen: the same number added twice, a claimed row claimed
-- again, a retry reviving a row that may already have gone out, a suppressed
-- number reached by a promotional campaign, an over-cap campaign truncated
-- instead of refused.
-- =============================================

create temp table t_result (
  n      int,
  name   text,
  ok     boolean,
  detail text
) on commit drop;
-- The impersonated role does not own the temp table, so without this every
-- insert below dies with "permission denied for table t_result".
grant select, insert on t_result to authenticated, service_role;

do $$
declare
  v_campaign  uuid;
  v_promo     uuid;
  v_trans     uuid;
  v_user      uuid;
  v_res       jsonb;
  v_ids       uuid[];
  v_ids2      uuid[];
  v_n         integer;
  v_txt       text;
  v_ok        boolean;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

  -- ---- 01  the phone gate refuses what profiles.mobile actually contains ----
  insert into t_result values (1, 'placeholder string is refused',
    public.fn_canonical_bd_phone('pending_382e2a8a-1199-415e-a974-9e1da6ca0647') is null,
    coalesce(public.fn_canonical_bd_phone('pending_382e2a8a-1199-415e-a974-9e1da6ca0647'), 'NULL'));

  insert into t_result values (2, 'unassigned prefix 123 is refused',
    public.fn_canonical_bd_phone('+880 1233293542') is null,
    coalesce(public.fn_canonical_bd_phone('+880 1233293542'), 'NULL'));

  -- NEGATIVE CONTROL for 01/02: a real number must still pass, or the gate
  -- could be refusing everything and both rows above would be meaningless.
  insert into t_result values (3, 'a real number still passes',
    public.fn_canonical_bd_phone('+880 1711314754') = '01711314754',
    coalesce(public.fn_canonical_bd_phone('+880 1711314754'), 'NULL'));

  insert into t_result values (4, 'bare 10-digit regains its zero',
    public.fn_canonical_bd_phone('1711314754') = '01711314754',
    coalesce(public.fn_canonical_bd_phone('1711314754'), 'NULL'));

  insert into t_result values (5, 'all four spellings agree',
    (select count(distinct p) = 1 from unnest(array[
        public.fn_canonical_bd_phone('+8801711314754'),
        public.fn_canonical_bd_phone('8801711314754'),
        public.fn_canonical_bd_phone('01711314754'),
        public.fn_canonical_bd_phone('+880 1711-314754')
     ]) p),
    'four spellings -> one canonical');

  -- ---- 06  segment counting, where the money is -----------------------------
  insert into t_result values (6, 'English 160 chars is one segment',
    public.fn_sms_segments(repeat('a', 160)) = 1,
    public.fn_sms_segments(repeat('a', 160))::text);

  insert into t_result values (7, 'English 161 chars is two (153 not 160)',
    public.fn_sms_segments(repeat('a', 161)) = 2,
    public.fn_sms_segments(repeat('a', 161))::text);

  insert into t_result values (8, 'Bangla is UCS-2 at 70 per segment',
    public.fn_sms_encoding('আপনার বুকিং') = 'ucs2'
      and public.fn_sms_segments(repeat('আ', 70)) = 1
      and public.fn_sms_segments(repeat('আ', 71)) = 2,
    public.fn_sms_encoding('আপনার বুকিং') || ' / ' ||
      public.fn_sms_segments(repeat('আ', 71))::text);

  -- ---- 09  merge fields ------------------------------------------------------
  insert into t_result values (9, 'merge fields render, unknown one is left visible',
    public.fn_render_sms_body('Hi {{first_name}}, {{nmae}}', 'Rahim Uddin')
      = 'Hi Rahim, {{nmae}}',
    public.fn_render_sms_body('Hi {{first_name}}, {{nmae}}', 'Rahim Uddin'));

  insert into t_result values (10, 'a nameless recipient gets a readable fallback',
    public.fn_render_sms_body('Hi {{name}}', null) = 'Hi there',
    public.fn_render_sms_body('Hi {{name}}', null));

  -- ---- 11  the queue: dedupe is enforced, not requested ----------------------
  v_campaign := public.admin_create_sms_campaign(
    'Test campaign', 'Hi {{first_name}}, welcome.', 'promotional', '{}'::jsonb, null);

  v_res := public.admin_add_sms_recipients(v_campaign, jsonb_build_array(
    jsonb_build_object('phone', '+880 1711314754', 'name', 'Rahim Uddin'),
    -- the same human, three more ways
    jsonb_build_object('phone', '01711314754',     'name', 'Rahim'),
    jsonb_build_object('phone', '1711314754',      'name', 'R'),
    jsonb_build_object('phone', '8801711314754',   'name', 'RU'),
    -- and two that must be dropped
    jsonb_build_object('phone', 'pending_382e2a8a-1199-415e-a974-9e1da6ca0647'),
    jsonb_build_object('phone', '+880 1233293542')
  ));

  insert into t_result values (11, 'one human added once from four spellings',
    (v_res ->> 'added')::int = 1 and (v_res ->> 'duplicate')::int = 3
      and (v_res ->> 'invalid')::int = 2 and (v_res ->> 'total')::int = 1,
    v_res::text);

  -- ---- 12  suppression --------------------------------------------------------
  perform public.admin_set_sms_suppression('01711314754', true, 'test', null);

  v_promo := public.admin_create_sms_campaign('Promo', 'x', 'promotional', '{}'::jsonb, null);
  v_res := public.admin_add_sms_recipients(v_promo, jsonb_build_array(
    jsonb_build_object('phone', '01711314754', 'name', 'Rahim')));

  insert into t_result values (12, 'promotional campaign skips a suppressed number',
    (v_res ->> 'added')::int = 0 and (v_res ->> 'suppressed')::int = 1,
    v_res::text);

  -- NEGATIVE CONTROL for 12: if suppression applied to everything, row 12 would
  -- pass for the wrong reason. A transactional campaign must still reach them.
  v_trans := public.admin_create_sms_campaign('Service notice', 'x', 'transactional', '{}'::jsonb, null);
  v_res := public.admin_add_sms_recipients(v_trans, jsonb_build_array(
    jsonb_build_object('phone', '01711314754', 'name', 'Rahim')));

  insert into t_result values (13, 'transactional campaign still reaches them',
    (v_res ->> 'added')::int = 1 and (v_res ->> 'suppressed')::int = 0,
    v_res::text);

  perform public.admin_set_sms_suppression('01711314754', false, null, null);

  -- ---- 14  the cap refuses, it does not truncate -----------------------------
  update public.app_settings set value = '1' where key = 'sms_bulk_max_recipients';

  v_campaign := public.admin_create_sms_campaign('Too big', 'x', 'promotional', '{}'::jsonb, null);
  perform public.admin_add_sms_recipients(v_campaign, jsonb_build_array(
    jsonb_build_object('phone', '01711314754'),
    jsonb_build_object('phone', '01839290436')));

  begin
    perform public.admin_start_sms_campaign(v_campaign);
    v_ok := false;   -- reached = it did not refuse
  exception when others then
    v_ok := true;
  end;
  insert into t_result values (14, 'a campaign over the cap is refused',
    v_ok and (select count(*) from public.sms_recipients
               where campaign_id = v_campaign and status = 'pending') = 2,
    'both recipients still pending, nothing truncated');

  -- 0 means disabled here, NOT unlimited — the inversion from max_devices_per_user
  update public.app_settings set value = '0' where key = 'sms_bulk_max_recipients';
  begin
    perform public.admin_start_sms_campaign(v_campaign);
    v_ok := false;
  exception when others then
    v_ok := true;
  end;
  insert into t_result values (15, 'zero disables bulk SMS rather than unlimiting it',
    v_ok, 'start refused at sms_bulk_max_recipients = 0');

  update public.app_settings set value = '500' where key = 'sms_bulk_max_recipients';

  -- ---- 16  claim-before-send: a row is handed out exactly once ---------------
  perform public.admin_start_sms_campaign(v_campaign);

  select array_agg(id) into v_ids  from public.admin_claim_sms_batch(v_campaign, 10);
  select array_agg(id) into v_ids2 from public.admin_claim_sms_batch(v_campaign, 10);

  -- 131: an IN(subquery) claim silently over-claimed, so assert the SIZE of the
  -- batch and not merely that something came back. This is the row that caught
  -- it, intermittently, as claimed=2 against a limit of 1.
  insert into t_result values (16, 'first claim takes both, second claim takes none',
    array_length(v_ids, 1) = 2 and v_ids2 is null,
    coalesce(array_length(v_ids, 1), 0)::text || ' then ' ||
      coalesce(array_length(v_ids2, 1), 0)::text);

  insert into t_result values (17, 'claimed rows are marked sending before any send',
    (select count(*) from public.sms_recipients
      where campaign_id = v_campaign and status = 'sending') = 2,
    'both sending');

  -- ---- 18  results roll up ---------------------------------------------------
  perform public.admin_mark_sms_result(v_ids[1], true,  'SUCCESS', 'ref-1', null);
  perform public.admin_mark_sms_result(v_ids[2], false, 'FAILED',  null, 'rejected by provider');

  select status into v_txt from public.sms_campaigns where id = v_campaign;
  select sent_count from public.sms_campaigns where id = v_campaign into v_n;

  insert into t_result values (18, 'campaign closes with 1 sent, 1 failed',
    v_txt = 'sent' and v_n = 1
      and (select failed_count from public.sms_campaigns where id = v_campaign) = 1,
    v_txt || ' sent=' || v_n::text);

  -- ---- 19  retry revives the refused row, NEVER the in-flight one ------------
  -- This is the single most important row in the file. A retry that re-queued a
  -- 'sending' row would text somebody a second time, which is the one thing
  -- this design exists to make impossible.
  update public.sms_recipients set status = 'sending'
   where id = v_ids[1];     -- pretend the worker died after handing it to GenNet

  v_n := public.admin_retry_sms_failures(v_campaign);

  insert into t_result values (19, 'retry re-queues only the failed row',
    v_n = 1
      and (select status from public.sms_recipients where id = v_ids[1]) = 'sending'
      and (select status from public.sms_recipients where id = v_ids[2]) = 'pending',
    'retried=' || v_n::text || ', in-flight row untouched');

  -- ---- 20  cancel stops the unsent and lies about nothing --------------------
  v_campaign := public.admin_create_sms_campaign('Cancel me', 'x', 'promotional', '{}'::jsonb, null);
  perform public.admin_add_sms_recipients(v_campaign, jsonb_build_array(
    jsonb_build_object('phone', '01711314754'),
    jsonb_build_object('phone', '01839290436')));
  perform public.admin_start_sms_campaign(v_campaign);
  select array_agg(id) into v_ids from public.admin_claim_sms_batch(v_campaign, 1);
  perform public.admin_mark_sms_result(v_ids[1], true, 'SUCCESS', 'ref', null);
  perform public.admin_cancel_sms_campaign(v_campaign);

  insert into t_result values (20, 'cancel skips the unsent and keeps the sent',
    (select count(*) from public.sms_recipients
      where campaign_id = v_campaign and status = 'sent') = 1
    and (select count(*) from public.sms_recipients
          where campaign_id = v_campaign and status = 'skipped') = 1,
    'sent=' || (select count(*) from public.sms_recipients
                 where campaign_id = v_campaign and status = 'sent')::text ||
    ' skipped=' || (select count(*) from public.sms_recipients
                     where campaign_id = v_campaign and status = 'skipped')::text ||
    ' statuses=' || (select coalesce(string_agg(status, ',' order by status), 'none')
                       from public.sms_recipients where campaign_id = v_campaign) ||
    ' claimed=' || coalesce(array_length(v_ids,1),0)::text);

  -- ---- 21  the audience dedupes the real data --------------------------------
  select count(*) into v_n from public.admin_sms_audience('{}'::jsonb);
  insert into t_result values (21, 'audience is smaller than the profile count',
    v_n < (select count(*) from public.profiles) and v_n > 0,
    v_n::text || ' reachable of ' ||
      (select count(*) from public.profiles)::text || ' profiles');

  select count(*) into v_n from public.admin_sms_audience('{"role":"admin"}'::jsonb);
  insert into t_result values (22, 'audience honours a role filter',
    v_n < (select count(*) from public.admin_sms_audience('{}'::jsonb)),
    v_n::text || ' admins');

  -- 23  "select some users" — the compose screen's individual-tick path, which
  -- reaches the RPC as a user_ids array rather than as a filter. Untested, this
  -- silently degrades to "everyone" and an admin who ticked three people texts
  -- the whole database.
  select array_agg(user_id) into v_ids
    from (select user_id from public.admin_sms_audience('{}'::jsonb) limit 2) t;
  select count(*) into v_n
    from public.admin_sms_audience(jsonb_build_object('user_ids', to_jsonb(v_ids)));
  insert into t_result values (23, 'an explicit user_ids list narrows to exactly those',
    v_n = 2
      and (select count(*) from public.admin_sms_audience(
             jsonb_build_object('user_ids', jsonb_build_array(v_ids[1])))) = 1
      and v_n < (select count(*) from public.admin_sms_audience('{}'::jsonb)),
    'two ids -> ' || v_n::text || ' rows');
end $$;

-- ---- 24-31  reachability: none of this may be driven from the internet ------
do $$
declare
  fn text;
  n  int := 23;
begin
  perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  foreach fn in array array[
    'admin_create_sms_campaign', 'admin_add_sms_recipients',
    'admin_start_sms_campaign', 'admin_claim_sms_batch',
    'admin_mark_sms_result', 'admin_sms_audience',
    'admin_set_sms_suppression', 'fn_require_service_role'
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

select n,
       case when ok then 'PASS' else 'FAIL' end as result,
       name,
       detail
  from t_result
 order by n;
