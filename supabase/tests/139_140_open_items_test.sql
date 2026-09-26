-- =============================================
-- 139/140 — refund policy, no-show, suspension, rate limits (2026-09-19)
--
-- One rolled-back transaction against the LOCAL mirror, impersonating the
-- seeded accounts through `request.jwt.claims` the way PostgREST does.
-- **Local only**: leans on supabase/baseline/qa_seed.sql and suspends a seeded
-- host (rolled back with everything else).
--
-- Same two rules as 138's test: measure the EFFECT, not the exception, and
-- clear `request.jwt.claims` whenever the role drops back to postgres.
--
-- Negative controls: with 140 reverted, rows 1-5, 7-9, 11-16, 18-24, 26-27,
-- 29-31, 33-45, 47-49 go red (most as "function does not exist"). Rows 6, 10,
-- 17, 25, 28, 32, 46 pin behaviour that must NOT have changed.
--
-- Run: sh tool/qa/run_sql_tests.sh 139_140
-- =============================================

begin;

create temp table t_result(n int, name text, expected text, actual text, ok boolean);

create or replace function pg_temp.effect(p_uid uuid, p_sql text, p_probe text,
                                          p_role text default 'authenticated')
returns text language plpgsql as $$
declare v_before text; v_after text; res text;
begin
  execute p_probe into v_before;
  begin
    perform set_config('request.jwt.claims',
      json_build_object('sub', p_uid, 'role', p_role)::text, true);
    perform set_config('role', p_role, true);
    execute p_sql;
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', '', true);
    execute p_probe into v_after;
    res := case when v_after is distinct from v_before
                then 'CHANGED ' || coalesce(v_before,'null') || '->' || coalesce(v_after,'null')
                else 'NO-OP' end;
    raise exception using errcode = 'ZZ999', message = 'undo';
  exception when others then
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', '', true);
    if sqlstate <> 'ZZ999' then res := 'REFUSED ' || sqlstate; end if;
  end;
  return res;
end $$;

-- Like act() in 138's test, but reports the HINT too, because 140 tells its
-- refusals apart by hint (no_show_too_early vs booking_transition_forbidden,
-- account_suspended vs blocked).
create or replace function pg_temp.hint(p_uid uuid, p_sql text, p_role text default 'authenticated')
returns text language plpgsql as $$
declare res text; v_hint text;
begin
  begin
    perform set_config('request.jwt.claims',
      json_build_object('sub', p_uid, 'role', p_role)::text, true);
    perform set_config('role', p_role, true);
    execute p_sql;
    res := 'OK';
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', '', true);
    raise exception using errcode = 'ZZ999', message = 'undo';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', '', true);
    if sqlstate <> 'ZZ999' then
      res := 'REFUSED ' || sqlstate || case when coalesce(v_hint, '') <> '' then ' ' || v_hint else '' end;
    end if;
  end;
  return res;
end $$;

-- KEEPS the write (a later row needs to see it). Returns 'OK' or the refusal.
create or replace function pg_temp.keep(p_uid uuid, p_sql text, p_role text default 'authenticated')
returns text language plpgsql as $$
declare res text := 'OK';
begin
  begin
    perform set_config('request.jwt.claims',
      json_build_object('sub', p_uid, 'role', p_role)::text, true);
    perform set_config('role', p_role, true);
    execute p_sql;
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', '', true);
  exception when others then
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', '', true);
    res := 'REFUSED ' || sqlstate;
  end;
  return res;
end $$;

-- Evaluate a scalar as a role and KEEP any side effect (rate-limit counters).
create or replace function pg_temp.query(p_uid uuid, p_sql text, p_role text default 'authenticated')
returns text language plpgsql as $$
declare res text;
begin
  begin
    perform set_config('request.jwt.claims',
      json_build_object('sub', p_uid, 'role', p_role)::text, true);
    perform set_config('role', p_role, true);
    execute p_sql into res;
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', '', true);
  exception when others then
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', '', true);
    res := 'REFUSED ' || sqlstate;
  end;
  return res;
end $$;

-- An RPC answer as jsonb, or the refusal wrapped so a missing function (the
-- negative control) reads as a red row instead of aborting the whole file.
create or replace function pg_temp.j(p_txt text) returns jsonb language sql as $$
  select case when p_txt like '{%' then p_txt::jsonb
              else jsonb_build_object('error', p_txt) end;
$$;

create or replace function pg_temp.check(n int, name text, expected text, actual text)
returns void language sql as $$
  insert into t_result values (n, name, expected, actual,
    actual is not distinct from expected or actual like expected || '%');
$$;

do $$
declare
  HOST1  uuid := '11111111-1111-1111-1111-111111111111';
  HOST2  uuid := '22222222-2222-2222-2222-222222222222';
  GUESTV uuid := '33333333-3333-3333-3333-333333333333';
  GUESTU uuid := '44444444-4444-4444-4444-444444444444';
  ADMIN  uuid := '55555555-5555-5555-5555-555555555555';
  L1     uuid := 'aaaaaaaa-0000-0000-0000-000000000001'; -- HOST1, hourly seat
  L2     uuid := 'aaaaaaaa-0000-0000-0000-000000000002'; -- HOST1, daily room
  L3     uuid := 'aaaaaaaa-0000-0000-0000-000000000003'; -- HOST2, active turf
  L4     uuid := 'aaaaaaaa-0000-0000-0000-000000000004'; -- HOST2, already hidden
  B3     uuid := 'bbbbbbbb-0000-0000-0000-000000000003'; -- GUESTV on L1, confirmed, unpaid
  BF     uuid;  -- GUESTV on L2, +10d, confirmed, PAID 1000 — early cancel
  BL     uuid;  -- GUESTV on L2, +30h, confirmed, PAID 1000 — late cancel
  BH     uuid;  -- GUESTU on L2, +20d, confirmed, PAID 600  — host cancels
  BN     uuid;  -- GUESTU on L2, started 2h ago, confirmed, PAID 800 — no-show
  BE     uuid;  -- GUESTU on L1, +3d, confirmed — a no-show reported too early
  BQ     uuid;  -- GUESTV pending on L3 (HOST2's) — declined by suspension
  BQ2    uuid;  -- GUESTU pending on L3, made AFTER suspension
  CONV   uuid;  -- HOST2 <-> GUESTU thread
  SESS   uuid := gen_random_uuid();
  v_txt  text;
  v_n    int;
  v_admins int;
  v_earn numeric;
  v_res  jsonb;
begin
  -- ── fixtures ─────────────────────────────────────────────────────────────
  insert into public.bookings (id, listing_id, tenant_id, tenant_name, starts_at, ends_at,
    booking_status, pricing_unit, unit_count, total_price, guest_count, listing_title, payment_status)
  values (gen_random_uuid(), L2, GUESTV, 'QA Guest Verified',
          now() + interval '10 days', now() + interval '12 days',
          'confirmed', 'day', 2, 1000, 1, 'QA daily room', 'paid')
  returning id into BF;
  insert into public.bookings (id, listing_id, tenant_id, tenant_name, starts_at, ends_at,
    booking_status, pricing_unit, unit_count, total_price, guest_count, listing_title, payment_status)
  values (gen_random_uuid(), L2, GUESTV, 'QA Guest Verified',
          now() + interval '30 hours', now() + interval '54 hours',
          'confirmed', 'day', 1, 1000, 1, 'QA daily room', 'paid')
  returning id into BL;
  insert into public.bookings (id, listing_id, tenant_id, tenant_name, starts_at, ends_at,
    booking_status, pricing_unit, unit_count, total_price, guest_count, listing_title, payment_status)
  values (gen_random_uuid(), L2, GUESTU, 'QA Guest Unverified',
          now() + interval '20 days', now() + interval '21 days',
          'confirmed', 'day', 1, 600, 1, 'QA daily room', 'paid')
  returning id into BH;
  insert into public.bookings (id, listing_id, tenant_id, tenant_name, starts_at, ends_at,
    booking_status, pricing_unit, unit_count, total_price, guest_count, listing_title, payment_status)
  values (gen_random_uuid(), L2, GUESTU, 'QA Guest Unverified',
          now() - interval '2 hours', now() + interval '22 hours',
          'confirmed', 'day', 1, 800, 1, 'QA daily room', 'paid')
  returning id into BN;
  insert into public.bookings (id, listing_id, tenant_id, tenant_name, starts_at, ends_at,
    booking_status, pricing_unit, unit_count, total_price, guest_count, listing_title)
  values (gen_random_uuid(), L3, GUESTV, 'QA Guest Verified',
          now() + interval '40 days', now() + interval '40 days 2 hours',
          'pending', 'hour', 2, 400, 4, 'QA turf ground')
  returning id into BQ;

  select id into CONV from public.conversations
   where least(participant_one_id, participant_two_id) = least(HOST2, GUESTU)
     and greatest(participant_one_id, participant_two_id) = greatest(HOST2, GUESTU);
  if CONV is null then
    insert into public.conversations (participant_one_id, participant_two_id, status)
    values (HOST2, GUESTU, 'active') returning id into CONV;
  end if;

  insert into auth.sessions (id, user_id, created_at, updated_at)
  values (SESS, HOST2, now(), now());

  select count(*) into v_admins from public.profiles where role = 'admin';

  -- ══ 1. refund policy, the pure function ══════════════════════════════════
  perform pg_temp.check(1, 'host cancels a paid booking -> 100%', '100',
    public.fn_refund_policy_pct('cancelled', HOST1, GUESTV, now() + interval '30 hours')::text);
  perform pg_temp.check(2, 'guest cancels 72h before check-in (window 48h) -> 100%', '100',
    public.fn_refund_policy_pct('cancelled', GUESTV, GUESTV, now() + interval '72 hours')::text);
  perform pg_temp.check(3, 'guest cancels 30h before -> late pct (50)', '50',
    public.fn_refund_policy_pct('cancelled', GUESTV, GUESTV, now() + interval '30 hours')::text);
  perform pg_temp.check(4, 'guest cancels after check-in time -> 0%', '0',
    public.fn_refund_policy_pct('cancelled', GUESTV, GUESTV, now() - interval '1 hour')::text);
  perform pg_temp.check(5, 'no-show -> 0%', '0',
    public.fn_refund_policy_pct('no_show', null, GUESTV, now() - interval '2 hours')::text);
  perform pg_temp.check(6, 'an open booking has no refund answer', 'null',
    coalesce(public.fn_refund_policy_pct('confirmed', null, GUESTV, now())::text, 'null'));

  -- The settings move the answer, and bad settings are refused at the source.
  begin
    update public.app_settings set value = '150' where key = 'refund_late_pct';
    v_txt := 'ACCEPTED';
  exception when others then v_txt := 'REFUSED ' || sqlstate; end;
  perform pg_temp.check(7, 'refund_late_pct 150 is refused', 'REFUSED 22023', v_txt);
  begin
    update public.app_settings set value = 'abc' where key = 'refund_full_window_hours';
    v_txt := 'ACCEPTED';
  exception when others then v_txt := 'REFUSED ' || sqlstate; end;
  perform pg_temp.check(8, 'refund_full_window_hours abc is refused', 'REFUSED 22023', v_txt);
  update public.app_settings set value = '25' where key = 'refund_late_pct';
  perform pg_temp.check(9, 'refund_late_pct 25 changes the late answer', '25',
    public.fn_refund_policy_pct('cancelled', GUESTV, GUESTV, now() + interval '30 hours')::text);
  update public.app_settings set value = '50' where key = 'refund_late_pct';
  update public.app_settings set value = '0' where key = 'refund_full_window_hours';
  perform pg_temp.check(10, 'window 0 = full refund right up to check-in', '100',
    public.fn_refund_policy_pct('cancelled', GUESTV, GUESTV, now() + interval '1 minute')::text);
  update public.app_settings set value = '48' where key = 'refund_full_window_hours';

  -- ══ 2. the stamp and the alerts ═════════════════════════════════════════
  perform pg_temp.check(11, 'guest cannot write refund_pct on own booking',
    'REFUSED 42501 booking_columns_protected',
    pg_temp.hint(GUESTV, format('update public.bookings set refund_pct = 100 where id = %L', BF)));

  v_txt := pg_temp.keep(GUESTV,
    format('update public.bookings set booking_status = ''cancelled'' where id = %L', BF));
  select refund_pct || ' / ' || refund_amount into v_txt
    from public.bookings where id = BF;
  perform pg_temp.check(12, 'early guest cancel of a paid 1000 stamps 100 / 1000', '100 / 1000.00', v_txt);

  select count(*) into v_n from public.notifications
   where title = 'Refund due: ৳1000.00' and data->>'booking_id' = BF::text;
  perform pg_temp.check(13, 'every admin is told the refund amount', v_admins::text, v_n::text);
  select body into v_txt from public.notifications
   where user_id = GUESTV and data->>'booking_id' = BF::text and title = 'Your refund is being arranged';
  perform pg_temp.check(14, 'guest is told 1000 back (full refund)',
    'Your booking at QA daily room was cancelled after you paid ৳1000.00. Under the cancellation policy you get ৳1000.00 back (full refund)', v_txt);

  v_txt := pg_temp.keep(GUESTV,
    format('update public.bookings set booking_status = ''cancelled'' where id = %L', BL));
  select refund_pct || ' / ' || refund_amount into v_txt from public.bookings where id = BL;
  perform pg_temp.check(15, 'late guest cancel of a paid 1000 stamps 50 / 500', '50 / 500.00', v_txt);

  v_txt := pg_temp.keep(HOST1,
    format('update public.bookings set booking_status = ''cancelled'' where id = %L', BH));
  select refund_pct || ' / ' || refund_amount into v_txt from public.bookings where id = BH;
  perform pg_temp.check(16, 'host cancel of a paid 600 stamps 100 / 600', '100 / 600.00', v_txt);

  v_txt := pg_temp.effect(GUESTV,
    format('update public.bookings set booking_status = ''cancelled'' where id = %L', B3),
    format('select coalesce(refund_pct::text, ''null'') from public.bookings where id = %L', B3));
  perform pg_temp.check(17, 'cancelling an UNPAID booking stamps nothing', 'NO-OP', v_txt);

  -- ══ 3. the ledger follows the policy ════════════════════════════════════
  select amount into v_earn from public.host_ledger_entries
   where booking_id = BL and entry_type = 'booking_online';
  v_txt := pg_temp.keep(ADMIN,
    format('update public.bookings set payment_status = ''refunded'' where id = %L', BL));
  select amount::text into v_txt from public.host_ledger_entries
   where booking_id = BL and entry_type = 'booking_refund_reversal';
  perform pg_temp.check(18, 'marking a 50% refund refunded reverses half the earning',
    (-round(v_earn * 0.5, 2))::text, v_txt);

  select amount into v_earn from public.host_ledger_entries
   where booking_id = BF and entry_type = 'booking_online';
  v_txt := pg_temp.keep(ADMIN,
    format('update public.bookings set payment_status = ''refunded'' where id = %L', BF));
  select amount::text into v_txt from public.host_ledger_entries
   where booking_id = BF and entry_type = 'booking_refund_reversal';
  perform pg_temp.check(19, 'a 100% refund still reverses the whole earning',
    (-v_earn)::text, v_txt);

  -- ══ 4. no-show ══════════════════════════════════════════════════════════
  -- A confirmed booking whose check-in is still ahead (BH was cancelled in
  -- row 16, so it needs its own fixture).
  insert into public.bookings (id, listing_id, tenant_id, tenant_name, starts_at, ends_at,
    booking_status, pricing_unit, unit_count, total_price, guest_count, listing_title)
  values (gen_random_uuid(), L1, GUESTU, 'QA Guest Unverified',
          now() + interval '3 days', now() + interval '3 days 1 hour',
          'confirmed', 'hour', 1, 10, 1, 'QA cheap hourly seat')
  returning id into BE;
  perform pg_temp.check(20, 'host cannot report a no-show before check-in time',
    'REFUSED 42501 no_show_too_early',
    pg_temp.hint(HOST1, format('update public.bookings set booking_status = ''no_show'' where id = %L', BE)));
  perform pg_temp.check(21, 'guest cannot mark own booking a no-show',
    'REFUSED 42501 booking_transition_forbidden',
    pg_temp.hint(GUESTU, format('update public.bookings set booking_status = ''no_show'' where id = %L', BN)));

  perform pg_temp.check(22, 'slot is taken while BN is confirmed', 'false',
    public.is_booking_available(L2, now() - interval '1 hour', now() + interval '1 hour')::text);

  v_txt := pg_temp.keep(HOST1,
    format('update public.bookings set booking_status = ''no_show'' where id = %L', BN));
  select booking_status || ' / ' || coalesce(refund_pct::text, 'null') || ' / ' || coalesce(refund_amount::text, 'null')
    into v_txt from public.bookings where id = BN;
  perform pg_temp.check(23, 'host reports a no-show after check-in time; paid -> 0 / 0.00',
    'no_show / 0 / 0.00', v_txt);
  select count(*) into v_n from public.notifications
   where user_id = GUESTU and data->>'booking_id' = BN::text and title = 'Marked as a no-show';
  perform pg_temp.check(24, 'the guest is told about the no-show', '1', v_n::text);
  select count(*) into v_n from public.notifications
   where user_id = GUESTU and data->>'booking_id' = BN::text and title = 'No refund for this booking';
  perform pg_temp.check(25, 'and told there is no refund', '1', v_n::text);
  select count(*) into v_n from public.notifications
   where title like 'Refund due%' and data->>'booking_id' = BN::text;
  perform pg_temp.check(26, 'admins are NOT alerted when nothing is owed', '0', v_n::text);
  perform pg_temp.check(27, 'a no-show frees the slot', 'true',
    public.is_booking_available(L2, now() - interval '1 hour', now() + interval '1 hour')::text);
  perform pg_temp.check(28, 'no_show is terminal',
    'REFUSED 42501 booking_transition_forbidden',
    pg_temp.hint(HOST1, format('update public.bookings set booking_status = ''confirmed'' where id = %L', BN)));
  perform pg_temp.check(29, 'nobody reviews a no-show', 'REFUSED 42501',
    pg_temp.hint(GUESTU, format($q$insert into public.reviews (booking_id, listing_id, reviewer_id, reviewer_name,
      reviewee_id, review_type, overall_rating) values (%L, %L, %L, 'QA Guest Unverified', %L, 'guest_to_host', 1)$q$,
      BN, L2, GUESTU, HOST1)));
  perform public.auto_complete_elapsed_bookings();
  select booking_status::text into v_txt from public.bookings where id = BN;
  perform pg_temp.check(30, 'the auto-complete sweep leaves a no-show alone', 'no_show', v_txt);

  -- ══ 5. suspension ═══════════════════════════════════════════════════════
  perform pg_temp.check(31, 'fn_is_suspended is not a client function', 'REFUSED 42501',
    pg_temp.query(GUESTV, format('select public.fn_is_suspended(%L)::text', GUESTV)));
  perform pg_temp.check(32, 'an admin''s own JWT cannot suspend anyone', 'REFUSED 42501',
    pg_temp.hint(ADMIN, format('select public.admin_suspend_user(%L, ''fraud'')', HOST2)));
  perform pg_temp.check(33, 'an admin account cannot be suspended', 'REFUSED 42501',
    pg_temp.hint(null, format('select public.admin_suspend_user(%L, ''oops'')', ADMIN), 'service_role'));
  perform pg_temp.check(34, 'a reason is required', 'REFUSED 22023',
    pg_temp.hint(null, format('select public.admin_suspend_user(%L, ''  '')', HOST2), 'service_role'));

  v_txt := pg_temp.query(null,
    format('select public.admin_suspend_user(%L, ''Fake listing photos, three reports'', %L)::text', HOST2, ADMIN),
    'service_role');
  v_res := pg_temp.j(v_txt);
  perform pg_temp.check(35, 'suspending HOST2 ends 1 session, hides 1 listing, declines 1 request',
    '1 / 1 / 1',
    (v_res->>'sessions_ended') || ' / ' || (v_res->>'listings_hidden') || ' / ' || (v_res->>'requests_declined'));
  select count(*) into v_n from auth.sessions where user_id = HOST2;
  perform pg_temp.check(36, 'the auth session row is gone (the enforcement)', '0', v_n::text);
  select is_active::text || ' / ' || suspended_hidden::text into v_txt from public.listings where id = L3;
  perform pg_temp.check(37, 'L3 is hidden and remembered', 'false / true', v_txt);
  select booking_status::text || ' / ' || coalesce(rejection_reason, '') into v_txt from public.bookings where id = BQ;
  perform pg_temp.check(38, 'the pending request on L3 is declined with a reason',
    'rejected / The host''s account is no longer active', v_txt);
  v_txt := pg_temp.query(null, format('select public.admin_suspend_user(%L, ''again'')::text', HOST2), 'service_role');
  perform pg_temp.check(39, 'suspending twice is a no-op that says so', 'true', (pg_temp.j(v_txt)->>'already_suspended'));

  -- What HOST2 can still do with the access token they hold: nothing.
  perform pg_temp.check(40, 'suspended host cannot send a message', 'REFUSED 42501 account_suspended',
    pg_temp.hint(HOST2, format($q$insert into public.messages (conversation_id, sender_id, content, content_type)
      values (%L, %L, 'hello', 'text')$q$, CONV, HOST2)));
  perform pg_temp.check(41, 'suspended host cannot edit a listing', 'REFUSED 42501 account_suspended',
    pg_temp.hint(HOST2, format('update public.listings set title = ''x'' where id = %L', L3)));
  insert into public.bookings (id, listing_id, tenant_id, tenant_name, starts_at, ends_at,
    booking_status, pricing_unit, unit_count, total_price, guest_count, listing_title)
  values (gen_random_uuid(), L3, GUESTU, 'QA Guest Unverified',
          now() + interval '50 days', now() + interval '50 days 1 hour',
          'pending', 'hour', 1, 200, 2, 'QA turf ground')
  returning id into BQ2;
  perform pg_temp.check(42, 'suspended host cannot accept a booking', 'REFUSED 42501 account_suspended',
    pg_temp.hint(HOST2, format('update public.bookings set booking_status = ''confirmed'' where id = %L', BQ2)));
  perform pg_temp.check(43, 'suspended host cannot open a thread', 'REFUSED 42501 account_suspended',
    pg_temp.hint(HOST2, format('select public.get_or_create_conversation(%L, %L)', HOST2, GUESTV)));
  perform pg_temp.check(44, 'nobody can open a thread TO a suspended account', 'REFUSED 42501 account_suspended',
    pg_temp.hint(GUESTV, format('select public.get_or_create_conversation(%L, %L)', GUESTV, HOST2)));
  perform pg_temp.check(45, 'touch_device tells a suspended device it is revoked', 'true',
    pg_temp.query(HOST2, 'select public.touch_device(''qa-device-that-never-registered'')::text'));
  perform pg_temp.check(46, 'a suspended account cannot un-suspend itself', 'REFUSED 42501 suspension_columns_protected',
    pg_temp.hint(HOST2, format('update public.profiles set suspended_at = null where id = %L', HOST2)));
  perform pg_temp.check(47, 'a verified guest cannot book a suspended host''s listing', 'REFUSED 22023',
    pg_temp.hint(GUESTV, format($q$select public.create_marketplace_booking(%L, now() + interval '60 days',
      now() + interval '60 days 1 hour', 'hour', 2)$q$, L3)));

  -- A suspended GUEST cannot book, even a live listing.
  perform pg_temp.query(null, format('select public.admin_suspend_user(%L, ''chargebacks'')::text', GUESTV), 'service_role');
  perform pg_temp.check(48, 'a suspended guest cannot book', 'REFUSED 42501 account_suspended',
    pg_temp.hint(GUESTV, format($q$select public.create_marketplace_booking(%L, now() + interval '61 days',
      now() + interval '61 days 1 hour', 'hour', 1)$q$, L1)));
  perform pg_temp.query(null, format('select public.admin_unsuspend_user(%L)::text', GUESTV), 'service_role');

  -- Lifting it puts back exactly what it took down.
  v_txt := pg_temp.query(null, format('select public.admin_unsuspend_user(%L)::text', HOST2), 'service_role');
  select (pg_temp.j(v_txt)->>'listings_restored') || ' / ' ||
         (select is_active::text from public.listings where id = L3) || ' / ' ||
         (select is_active::text from public.listings where id = L4)
    into v_txt;
  perform pg_temp.check(49, 'unsuspend restores L3 and leaves the always-hidden L4 alone', '1 / true / false', v_txt);
  perform pg_temp.check(50, 'and the host can message again', 'OK',
    pg_temp.hint(HOST2, format($q$insert into public.messages (conversation_id, sender_id, content, content_type)
      values (%L, %L, 'hello again', 'text')$q$, CONV, HOST2)));

  -- ══ 6. rate limits ══════════════════════════════════════════════════════
  perform pg_temp.check(51, 'fn_rate_limit_hit is service-role only', 'REFUSED 42501',
    pg_temp.query(GUESTV, 'select public.fn_rate_limit_hit(''geocode:x'', 3, 60)::text'));
  perform pg_temp.check(52, 'edge_rate_limits is unreadable by clients', 'REFUSED 42501',
    pg_temp.query(GUESTV, 'select count(*)::text from public.edge_rate_limits'));
  v_txt := '';
  for v_n in 1..4 loop
    v_txt := v_txt || (pg_temp.query(null,
      'select (public.fn_rate_limit_hit(''qa:geocode:1.2.3.4'', 3, 60)->>''allowed'')', 'service_role'));
    if v_n < 4 then v_txt := v_txt || ','; end if;
  end loop;
  perform pg_temp.check(53, 'three hits pass a limit of 3, the fourth is refused', 'true,true,true,false', v_txt);
  perform pg_temp.check(54, 'a different key is a different bucket', 'true',
    pg_temp.query(null, 'select (public.fn_rate_limit_hit(''qa:geocode:5.6.7.8'', 3, 60)->>''allowed'')', 'service_role'));
  perform pg_temp.check(55, 'the refused answer carries a retry-after within the window', 'true',
    pg_temp.query(null, $q$select ((public.fn_rate_limit_hit('qa:geocode:1.2.3.4', 3, 60)->>'retry_after_seconds')::int between 1 and 60)::text$q$, 'service_role'));
  insert into public.edge_rate_limits (bucket, window_start, hits) values ('qa:old', now() - interval '2 days', 9);
  perform pg_temp.check(56, 'the daily reap removes yesterday''s windows and keeps today''s', '1',
    public.reap_edge_rate_limits()::text);
  select count(*) into v_n from public.edge_rate_limits where bucket like 'qa:%';
  perform pg_temp.check(57, 'today''s buckets survive the reap', '2', v_n::text);
end $$;

select n, name, expected, actual, case when ok then 'PASS' else 'FAIL' end as result
from t_result order by n;
select count(*) filter (where ok) as pass, count(*) filter (where not ok) as fail from t_result;

rollback;
