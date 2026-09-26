-- =============================================
-- QA — one reservation from request to review, and what each party is told.
-- Run inside begin; … rollback; against the LOCAL mirror (uses qa_seed.sql).
--
-- Every step records the booking's two statuses AND the notifications raised
-- by that step alone, because "the state machine works" and "the other party
-- finds out" are different claims and only the first has tests today.
-- =============================================

create temp table t_step (n int, actor text, step text, statuses text, notified text, ok boolean) on commit drop;
create temp table t_seen (id uuid primary key) on commit drop;
grant select, insert on t_step to anon, authenticated, service_role;
grant select, insert on t_seen to anon, authenticated, service_role;

-- Which notifications appeared since the previous call, named by recipient.
-- It cannot be done by timestamp: `created_at default now()` is TRANSACTION
-- time, identical for every row in this test, so a clock_timestamp() watermark
-- matches nothing and every step reads as "NOBODY" — which is exactly how an
-- earlier draft of this file reported a working notification as missing.
create or replace function pg_temp.new_notes() returns text language plpgsql as $$
declare v text;
begin
  select coalesce(string_agg(p.full_name || ': ' || n.title, '; ' order by n.title), 'NOBODY')
    into v
    from public.notifications n
    join public.profiles p on p.id = n.user_id
   where n.id not in (select id from t_seen);
  insert into t_seen select id from public.notifications
   where id not in (select id from t_seen);
  return v;
end $$;

do $$
declare
  HOST1  uuid := '11111111-1111-1111-1111-111111111111';
  GUESTV uuid := '33333333-3333-3333-3333-333333333333';
  L1     uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  v_b    uuid;
  v_st   text;
  v_note text;
  v_res  jsonb;
begin
  perform pg_temp.new_notes();   -- ignore anything already in the table

  -- 1. the guest asks -------------------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', GUESTV, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  v_res := public.create_marketplace_booking(
    L1, now() + interval '400 days', now() + interval '400 days 2 hours', 'hour', 1, 'QA Guest Verified');
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  v_b := (v_res ->> 'id')::uuid;

  select booking_status || ' / ' || payment_status into v_st from public.bookings where id = v_b;
  v_note := pg_temp.new_notes();
  insert into t_step values (1, 'guest', 'request a 2-hour stay', v_st, v_note,
    v_st = 'pending / unpaid' and v_note like '%QA Host One%');

  -- 2. the host accepts -----------------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', HOST1, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  update public.bookings set booking_status = 'confirmed' where id = v_b;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);

  select booking_status || ' / ' || payment_status into v_st from public.bookings where id = v_b;
  v_note := pg_temp.new_notes();
  insert into t_step values (2, 'host', 'accept the request', v_st, v_note,
    v_st = 'confirmed / unpaid' and v_note like '%QA Guest Verified%');

  -- 3. the guest chooses cash, the host confirms receipt ---------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', GUESTV, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.set_booking_payment_method(v_b, 'cash');
  perform set_config('request.jwt.claims',
    json_build_object('sub', HOST1, 'role', 'authenticated')::text, true);
  perform public.mark_cash_payment(v_b);
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);

  select booking_status || ' / ' || payment_status into v_st from public.bookings where id = v_b;
  v_note := pg_temp.new_notes();
  insert into t_step values (3, 'host', 'confirm cash received', v_st, v_note,
    v_st = 'confirmed / paid' and v_note like '%QA Guest Verified%');

  -- 4. the host checks the guest in -----------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', HOST1, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  update public.bookings set booking_status = 'active' where id = v_b;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);

  select booking_status || ' / ' || payment_status into v_st from public.bookings where id = v_b;
  v_note := pg_temp.new_notes();
  insert into t_step values (4, 'host', 'check the guest in', v_st, v_note, v_st = 'active / paid');

  -- 5. the host completes the service ---------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', HOST1, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  update public.bookings set booking_status = 'completed' where id = v_b;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);

  select booking_status || ' / ' || payment_status into v_st from public.bookings where id = v_b;
  v_note := pg_temp.new_notes();
  insert into t_step values (5, 'host', 'mark the service complete', v_st, v_note, v_st = 'completed / paid');

  -- 6. the money lands on the host's ledger ---------------------------------
  select coalesce(count(*)::text || ' ledger row(s), ' || coalesce(sum(amount)::text, '0'), 'none')
    into v_st from public.host_ledger_entries where booking_id = v_b;
  insert into t_step values (6, 'system', 'host earning posted', v_st, '-',
    v_st like '1 ledger row%');

  -- 7. both sides review ----------------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', GUESTV, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  insert into public.reviews (booking_id, listing_id, reviewer_id, reviewer_name, reviewee_id,
      review_type, overall_rating, cleanliness_rating, accuracy_rating,
      communication_rating, location_rating, value_rating, comment)
    values (v_b, L1, GUESTV, 'QA Guest Verified', HOST1, 'guest_to_host', 5, 5, 5, 5, 5, 5, 'QA guest review');
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);

  -- 8. what a stranger sees while only ONE side has written ------------------
  -- The guest's review is in and the host's is not: double-blind means a
  -- stranger sees nothing yet. (This step used to run after BOTH reviews and
  -- still expected 0 — which only passed because the reveal was broken; see
  -- 138. Measure the blind window where it actually is.)
  perform set_config('request.jwt.claims',
    json_build_object('sub', '44444444-4444-4444-4444-444444444444', 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*)::text into v_st from public.reviews where booking_id = v_b;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  insert into t_step values (8, 'stranger', 'read the review while only the guest has written',
    v_st || ' visible', '-', v_st = '0');

  perform set_config('request.jwt.claims',
    json_build_object('sub', HOST1, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  insert into public.reviews (booking_id, listing_id, reviewer_id, reviewer_name, reviewee_id,
      review_type, overall_rating, comment)
    values (v_b, L1, HOST1, 'QA Host One', GUESTV, 'host_to_guest', 5, 'QA host review');
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);

  -- 7. both in → both revealed at once (138 made this true; it was not) ------
  select count(*)::text || ' review(s), revealed: ' || count(*) filter (where is_revealed)::text
    into v_st from public.reviews where booking_id = v_b;
  insert into t_step values (7, 'both', 'leave reviews (double-blind until both are in)',
    v_st, '-', v_st = '2 review(s), revealed: 2');

  -- 9. and now a stranger sees both --------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', '44444444-4444-4444-4444-444444444444', 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*)::text into v_st from public.reviews where booking_id = v_b;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  insert into t_step values (9, 'stranger', 'read both reviews once both are in',
    v_st || ' visible', '-', v_st = '2');
end $$;

select n, actor, step, statuses, notified, case when ok then 'PASS' else 'FAIL' end as verdict
  from t_step order by n;
