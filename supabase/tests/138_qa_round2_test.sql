-- =============================================
-- 138 — the second QA round's database fixes (2026-09-19)
--
-- One rolled-back transaction against the LOCAL mirror, impersonating the
-- seeded accounts through `request.jwt.claims` the way PostgREST does.
-- **Local only**: it leans on supabase/baseline/qa_seed.sql and several rows
-- deliberately attempt writes that must never be attempted against
-- production data.
--
-- Two rules, both learned the hard way in the round before this one:
--
--   * **Measure the effect, not the exception.** An UPDATE whose rows RLS
--     filters out matches nothing and raises NOTHING. Every write row probes a
--     value before and after and reports CHANGED / NO-OP / REFUSED <sqlstate>.
--   * **Clear `request.jwt.claims` when you drop back to postgres.** A stale
--     `sub` leaves `auth.uid()` non-null and the guards correctly refuse even
--     postgres, which reads as the fix being broken.
--
-- Negative controls: with 138 reverted, rows 1-3, 9-14, 17-18, 20-22, 26, 28,
-- 30-33, 36, 38-42, 44-48 go red. Rows 4-8, 15, 19, 23-25, 27, 29, 34-35, 37,
-- 43, 49-52 pin behaviour that must NOT have changed.
--
-- Run: psql "$DB" -f supabase/tests/138_qa_round2_test.sql
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

create or replace function pg_temp.act(p_uid uuid, p_sql text, p_role text default 'authenticated')
returns text language plpgsql as $$
declare res text;
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
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', '', true);
    if sqlstate <> 'ZZ999' then res := 'REFUSED ' || sqlstate; end if;
  end;
  return res;
end $$;

-- Like act(), but KEEPS the write. For the few rows where the next step needs
-- the previous user's write to be visible (the double-blind reveal).
create or replace function pg_temp.keep(p_uid uuid, p_sql text)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  execute p_sql;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

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
  RACER1 uuid := '77777777-0000-0000-0000-000000000001';
  L1     uuid := 'aaaaaaaa-0000-0000-0000-000000000001'; -- HOST1, hourly seat
  L2     uuid := 'aaaaaaaa-0000-0000-0000-000000000002'; -- HOST1, daily room
  B1     uuid := 'bbbbbbbb-0000-0000-0000-000000000001'; -- GUESTV on L2, completed, paid
  B2     uuid := 'bbbbbbbb-0000-0000-0000-000000000002'; -- GUESTV on L2, completed, paid
  B3     uuid := 'bbbbbbbb-0000-0000-0000-000000000003'; -- GUESTV on L1, confirmed, unpaid
  B4     uuid := 'bbbbbbbb-0000-0000-0000-000000000004'; -- GUESTV on L1, rejected
  B6     uuid := 'bbbbbbbb-0000-0000-0000-000000000006'; -- GUESTV on L2, cancelled
  BP     uuid;   -- a fresh pending request, GUESTV on L1
  BC     uuid;   -- a booking carrying coupon QA10
  CONV   uuid;   -- the GUESTV <-> HOST1 thread
  COUP   uuid := 'dddddddd-0000-0000-0000-000000000001';
  v_txt  text;
  v_n    int;
  v_ok   boolean;
  v_new_listing uuid;
  v_expected text;
begin
  -- ── fixtures ─────────────────────────────────────────────────────────────
  insert into public.bookings (id, listing_id, tenant_id, tenant_name, starts_at, ends_at,
    booking_status, pricing_unit, unit_count, total_price, guest_count, listing_title)
  values (gen_random_uuid(), L1, GUESTV, 'QA Guest Verified',
          now() + interval '20 days', now() + interval '20 days 2 hours',
          'pending', 'hour', 2, 20, 1, 'QA cheap hourly seat')
  returning id into BP;

  insert into public.coupons (id, code, discount_type, discount_value, min_booking_amount,
    usage_limit, per_user_limit, is_active)
  values (COUP, 'QA10', 'flat', 1, 0, 1, 1, true);

  insert into public.bookings (id, listing_id, tenant_id, tenant_name, starts_at, ends_at,
    booking_status, pricing_unit, unit_count, total_price, guest_count, listing_title,
    coupon_code, discount_amount)
  values (gen_random_uuid(), L1, GUESTV, 'QA Guest Verified',
          now() + interval '25 days', now() + interval '25 days 1 hour',
          'pending', 'hour', 1, 9, 1, 'QA cheap hourly seat', 'QA10', 1)
  returning id into BC;

  select id into CONV from public.conversations
   where least(participant_one_id, participant_two_id) = least(GUESTV, HOST1)
     and greatest(participant_one_id, participant_two_id) = greatest(GUESTV, HOST1);
  if CONV is null then
    insert into public.conversations (participant_one_id, participant_two_id)
    values (GUESTV, HOST1) returning id into CONV;
  end if;

  -- ============================================ host state machine
  perform pg_temp.check(1, 'host cannot resurrect a cancelled booking', 'REFUSED 42501',
    pg_temp.effect(HOST1,
      format('update public.bookings set booking_status = ''confirmed'' where id = %L', B6),
      format('select booking_status::text from public.bookings where id = %L', B6)));

  perform pg_temp.check(2, 'host cannot cancel a completed booking', 'REFUSED 42501',
    pg_temp.effect(HOST1,
      format('update public.bookings set booking_status = ''cancelled'' where id = %L', B1),
      format('select booking_status::text from public.bookings where id = %L', B1)));

  perform pg_temp.check(3, 'host cannot un-reject a booking', 'REFUSED 42501',
    pg_temp.effect(HOST1,
      format('update public.bookings set booking_status = ''confirmed'' where id = %L', B4),
      format('select booking_status::text from public.bookings where id = %L', B4)));

  perform pg_temp.check(4, 'host CAN accept a pending request', 'CHANGED pending->confirmed',
    pg_temp.effect(HOST1,
      format('update public.bookings set booking_status = ''confirmed'', confirmed_at = now(), host_message = ''Welcome'' where id = %L', BP),
      format('select booking_status::text from public.bookings where id = %L', BP)));

  perform pg_temp.check(5, 'host CAN reject a pending request', 'CHANGED pending->rejected',
    pg_temp.effect(HOST1,
      format('update public.bookings set booking_status = ''rejected'', rejection_reason = ''Full'' where id = %L', BP),
      format('select booking_status::text from public.bookings where id = %L', BP)));

  perform pg_temp.check(6, 'host CAN check a confirmed guest in', 'CHANGED confirmed->active',
    pg_temp.effect(HOST1,
      format('update public.bookings set booking_status = ''active'', actual_check_in = now() where id = %L', B3),
      format('select booking_status::text from public.bookings where id = %L', B3)));

  update public.bookings set booking_status = 'active', actual_check_in = now() where id = B3;
  perform pg_temp.check(7, 'host CAN complete an active stay', 'CHANGED active->completed',
    pg_temp.effect(HOST1,
      format('update public.bookings set booking_status = ''completed'', completed_at = now() where id = %L', B3),
      format('select booking_status::text from public.bookings where id = %L', B3)));
  update public.bookings set booking_status = 'confirmed', actual_check_in = null where id = B3;

  perform pg_temp.check(8, 'host cancel is stamped with the host', 'CHANGED null->' || HOST1::text,
    pg_temp.effect(HOST1,
      format('update public.bookings set booking_status = ''cancelled'' where id = %L', B3),
      format('select cancelled_by::text from public.bookings where id = %L', B3)));

  -- ============================================ guest side
  perform pg_temp.check(9, 'a plain guest cancel is stamped with the guest', 'CHANGED null->' || GUESTV::text,
    pg_temp.effect(GUESTV,
      format('update public.bookings set booking_status = ''cancelled'' where id = %L', B3),
      format('select cancelled_by::text from public.bookings where id = %L', B3)));

  perform pg_temp.check(10, 'and the host is told about it', 'CHANGED 0->1',
    pg_temp.effect(GUESTV,
      format('update public.bookings set booking_status = ''cancelled'' where id = %L', B3),
      format('select count(*)::text from public.notifications where user_id = %L and type = ''booking_cancelled'' and data->>''booking_id'' = %L', HOST1, B3)));

  perform pg_temp.check(11, 'guest cannot pin the cancellation on the host', 'REFUSED 42501',
    pg_temp.effect(GUESTV,
      format('update public.bookings set booking_status = ''cancelled'', cancelled_by = %L where id = %L', HOST1, B3),
      format('select cancelled_by::text from public.bookings where id = %L', B3)));

  perform pg_temp.check(12, 'guest cannot raise guest_count after booking', 'REFUSED 42501',
    pg_temp.effect(GUESTV,
      format('update public.bookings set guest_count = 50 where id = %L', B3),
      format('select guest_count::text from public.bookings where id = %L', B3)));

  perform pg_temp.check(13, 'guest cannot rewrite the listing title on the booking', 'REFUSED 42501',
    pg_temp.effect(GUESTV,
      format('update public.bookings set listing_title = ''HACKED'' where id = %L', B3),
      format('select listing_title from public.bookings where id = %L', B3)));

  perform pg_temp.check(14, 'guest cannot write the host''s message or confirmed_at', 'REFUSED 42501',
    pg_temp.effect(GUESTV,
      format('update public.bookings set host_message = ''lol'', confirmed_at = now() where id = %L', BP),
      format('select coalesce(host_message, ''-'') from public.bookings where id = %L', BP)));

  -- 140 gave these two refusals the 42501 + booking_transition_forbidden hint
  -- every other transition refusal already carried.
  perform pg_temp.check(15, 'guest still cannot accept their own request', 'REFUSED 42501',
    pg_temp.effect(GUESTV,
      format('update public.bookings set booking_status = ''confirmed'' where id = %L', BP),
      format('select booking_status::text from public.bookings where id = %L', BP)));

  perform pg_temp.check(16, 'host cancel through the app''s own fields still works', 'CHANGED confirmed->cancelled',
    pg_temp.effect(HOST1,
      format('update public.bookings set booking_status = ''cancelled'', cancelled_by = %L, cancelled_at = now() where id = %L', HOST1, B3),
      format('select booking_status::text from public.bookings where id = %L', B3)));

  -- ============================================ paid cancellation alert
  update public.bookings set payment_status = 'paid' where id = B3;   -- postgres: no uid, 132 lets it through

  perform pg_temp.check(17, 'cancelling a PAID booking puts a refund on every admin''s desk', 'CHANGED 0->1',
    pg_temp.effect(HOST1,
      format('update public.bookings set booking_status = ''cancelled'', cancelled_by = %L where id = %L', HOST1, B3),
      format('select count(*)::text from public.notifications where user_id = %L and title like ''Refund due%%'' and data->>''booking_id'' = %L', ADMIN, B3)));

  perform pg_temp.check(18, 'and tells the guest a refund is coming', 'CHANGED 0->1',
    pg_temp.effect(HOST1,
      format('update public.bookings set booking_status = ''cancelled'', cancelled_by = %L where id = %L', HOST1, B3),
      format('select count(*)::text from public.notifications where user_id = %L and title = ''Your refund is being arranged'' and data->>''booking_id'' = %L', GUESTV, B3)));

  update public.bookings set payment_status = 'unpaid', paid_at = null where id = B3;
  perform pg_temp.check(19, 'an UNPAID cancellation raises no refund alert (control)', 'NO-OP',
    pg_temp.effect(HOST1,
      format('update public.bookings set booking_status = ''cancelled'', cancelled_by = %L where id = %L', HOST1, B3),
      format('select count(*)::text from public.notifications where title like ''Refund due%%'' and data->>''booking_id'' = %L', B3)));

  -- ============================================ blocks are walls
  insert into public.user_blocks (blocker_id, blocked_id) values (HOST1, GUESTV);

  perform pg_temp.check(20, 'a guest the host blocked cannot book that host', 'REFUSED 42501',
    pg_temp.act(GUESTV,
      format('select public.create_marketplace_booking(%L, now() + interval ''30 days'', now() + interval ''30 days 2 hours'', ''hour'', 1, ''QA Guest Verified'')', L1)));

  perform pg_temp.check(21, 'nor open a thread with them', 'REFUSED 42501',
    pg_temp.act(GUESTV,
      format('select public.get_or_create_conversation(%L, %L)', GUESTV, HOST1)));

  perform pg_temp.check(22, 'nor post into the thread they already had', 'REFUSED 42501',
    pg_temp.act(GUESTV,
      format('insert into public.messages (conversation_id, sender_id, content, content_type) values (%L, %L, ''hi'', ''text'')', CONV, GUESTV)));

  perform pg_temp.check(23, 'the block cuts both ways: the blocker cannot post either', 'REFUSED 42501',
    pg_temp.act(HOST1,
      format('insert into public.messages (conversation_id, sender_id, content, content_type) values (%L, %L, ''hi'', ''text'')', CONV, HOST1)));

  -- Automated sends run with no uid on a booking that already exists; a host
  -- who blocks a guest mid-stay still owes them the checkout message.
  select count(*) into v_n from public.messages where conversation_id = CONV;
  delete from public.scheduled_message_sends where booking_id = B1 and trigger = 'check_out';
  perform public.send_checkout_for_booking(B1);
  select count(*) - v_n into v_n from public.messages where conversation_id = CONV;
  perform pg_temp.check(24, 'automated host messages still deliver across a block', '1', v_n::text);

  delete from public.user_blocks where blocker_id = HOST1 and blocked_id = GUESTV;
  perform pg_temp.check(25, 'with the block lifted, messaging works again (control)', 'OK',
    pg_temp.act(GUESTV,
      format('insert into public.messages (conversation_id, sender_id, content, content_type) values (%L, %L, ''hi'', ''text'')', CONV, GUESTV)));

  -- ============================================ conversations
  perform pg_temp.check(26, 'a participant cannot swap the other participant out', 'REFUSED 42501',
    pg_temp.effect(GUESTV,
      format('update public.conversations set participant_two_id = %L where id = %L', RACER1, CONV),
      format('select participant_one_id::text || participant_two_id::text from public.conversations where id = %L', CONV)));

  perform pg_temp.check(27, 'but can still archive the thread (control)', 'CHANGED',
    pg_temp.effect(GUESTV,
      format('update public.conversations set status = ''archived'' where id = %L', CONV),
      format('select status from public.conversations where id = %L', CONV)));

  perform pg_temp.check(28, 'a stranger cannot type into a conversation they are not in', 'REFUSED 42501',
    pg_temp.act(GUESTU,
      format('insert into public.typing_indicators (conversation_id, user_id) values (%L, %L)', CONV, GUESTU)));

  perform pg_temp.check(29, 'a participant can (control)', 'OK',
    pg_temp.act(GUESTV,
      format('insert into public.typing_indicators (conversation_id, user_id) values (%L, %L) on conflict do nothing', CONV, GUESTV)));

  perform pg_temp.check(30, 'a stranger cannot plant a read cursor either', 'REFUSED 42501',
    pg_temp.act(GUESTU,
      format('insert into public.read_cursors (conversation_id, user_id) values (%L, %L)', CONV, GUESTU)));

  -- ============================================ reviews
  perform pg_temp.keep(GUESTV, format(
    'insert into public.reviews (booking_id, listing_id, reviewer_id, reviewer_name, reviewee_id, review_type, overall_rating, cleanliness_rating, accuracy_rating, communication_rating, location_rating, value_rating, comment) values (%L, %L, %L, ''QA Guest Verified'', %L, ''guest_to_host'', 5, 5, 5, 5, 5, 5, ''Great stay'')',
    B2, L2, GUESTV, HOST1));
  perform pg_temp.keep(HOST1, format(
    'insert into public.reviews (booking_id, listing_id, reviewer_id, reviewer_name, reviewee_id, review_type, overall_rating, comment) values (%L, %L, %L, ''QA Host One'', %L, ''host_to_guest'', 4, ''Nice guest'')',
    B2, L2, HOST1, GUESTV));
  select bool_and(is_revealed) into v_ok from public.reviews where booking_id = B2;
  perform pg_temp.check(31, 'both reviews reveal the moment the second one lands', 'true', v_ok::text);

  select rating::text || '/' || review_count::text into v_txt from public.listings where id = L2;
  perform pg_temp.check(32, 'the listing''s stars follow its revealed reviews', '5.0/1', v_txt);

  perform pg_temp.check(33, 'a host cannot paint their own stars', 'REFUSED 42501',
    pg_temp.effect(HOST1,
      format('update public.listings set rating = 5, review_count = 999, is_superhost = true where id = %L', L1),
      format('select coalesce(rating::text, ''null'') || ''/'' || review_count::text || ''/'' || is_superhost::text from public.listings where id = %L', L1)));

  perform pg_temp.check(34, 'an admin can award the superhost badge', 'CHANGED',
    pg_temp.effect(ADMIN,
      format('update public.listings set is_superhost = true where id = %L', L1),
      format('select is_superhost::text from public.listings where id = %L', L1)));

  perform pg_temp.keep(HOST1, format(
    'insert into public.listings (owner_id, title, listing_type, city, hourly_rate, max_guests, rating, review_count, is_superhost, is_active) values (%L, ''QA fresh listing'', ''seat'', ''Dhaka'', 10, 1, 5, 999, true, true)',
    HOST1));
  select coalesce(rating::text, 'null') || '/' || review_count::text || '/' || is_superhost::text
    into v_txt from public.listings where title = 'QA fresh listing' and owner_id = HOST1;
  perform pg_temp.check(35, 'a brand-new listing starts with no stars whatever the client sent', 'null/0/false', v_txt);

  -- ============================================ review reminders
  update public.bookings set completed_at = now() - interval '3 days 5 hours' where id = B1;
  delete from public.notifications where type = 'review_reminder' and data->>'booking_id' = B1::text;
  perform public.send_review_reminders();
  select count(*) into v_n from public.notifications where type = 'review_reminder' and data->>'booking_id' = B1::text;
  perform pg_temp.check(36, 'a stay completed 3 days 5 hours ago is reminded at the daily sweep', '2', v_n::text);
  perform public.send_review_reminders();
  select count(*) into v_n from public.notifications where type = 'review_reminder' and data->>'booking_id' = B1::text;
  perform pg_temp.check(37, 'running the sweep twice does not double the reminders', '2', v_n::text);

  -- ============================================ message dates
  update public.bookings set booking_status = 'confirmed', starts_at = '2026-10-01 00:00+06', ends_at = '2026-10-03 00:00+06' where id = B6;
  delete from public.scheduled_message_sends where booking_id = B6;
  insert into public.message_templates (host_id, trigger, content, enabled, lead_days)
  values (HOST1, 'check_in', 'Check-in {{check_in_date}} out {{check_out_date}} nights {{nights}}', true, 14)
  on conflict (host_id, trigger) do update set content = excluded.content, enabled = true, lead_days = 14;
  perform public.send_precheckin_for_booking(B6);
  select m.content into v_txt from public.messages m
    join public.conversations c on c.id = m.conversation_id
   where c.booking_id = B6 and m.content like 'Check-in %' order by m.created_at desc limit 1;
  v_expected := 'Check-in ' || to_char(date '2026-10-01', 'FMDay, FMMonth FMDD')
             || ' out ' || to_char(date '2026-10-03', 'FMDay, FMMonth FMDD') || ' nights 2';
  perform pg_temp.check(38, 'the pre-check-in message says the day the guest will arrive, in Dhaka time', v_expected, v_txt);

  -- ============================================ identity resubmission
  update public.profiles set verification_status = 'rejected' where id = GUESTU;
  insert into public.owner_documents (user_id, document_type, file_path)
  values (GUESTU, 'nid_front', GUESTU::text || '/nid_front.jpg'),
         (GUESTU, 'nid_back',  GUESTU::text || '/nid_back.jpg');
  select verification_status::text into v_txt from public.profiles where id = GUESTU;
  perform pg_temp.check(39, 'a rejected applicant who uploads again is back in the queue', 'pending', v_txt);

  update public.profiles set verification_status = 'rejected' where id = GUESTU;
  insert into public.owner_documents (user_id, document_type, file_path)
  values (GUESTU, 'nid_front', GUESTU::text || '/nid_front_v2.jpg')
  on conflict (user_id, document_type) do update set file_path = excluded.file_path, uploaded_at = now();
  select verification_status::text into v_txt from public.profiles where id = GUESTU;
  perform pg_temp.check(40, 'and re-scanning ONE document (an upsert) is enough', 'pending', v_txt);

  -- ============================================ coupons
  perform pg_temp.check(41, 'redeem_coupon refuses a booking that never used the coupon', 'REFUSED 42501',
    pg_temp.act(GUESTV, format('select public.redeem_coupon(%L, %L, 99999)', COUP, B3)));

  perform pg_temp.check(42, 'and records the booking''s own discount when it did', 'CHANGED 0->1',
    pg_temp.effect(GUESTV,
      format('select public.redeem_coupon(%L, %L, 99999)', COUP, BC),
      format('select used_count::text from public.coupons where id = %L', COUP)));

  perform pg_temp.check(43, 'anon cannot call redeem_coupon at all', 'false',
    has_function_privilege('anon', 'public.redeem_coupon(uuid, uuid, numeric)', 'execute')::text);

  -- ============================================ contact card
  update public.profiles set mobile = '01700000001' where id = GUESTV;   -- the spoof
  update public.bookings set booking_status = 'confirmed' where id = B3;
  perform set_config('request.jwt.claims', json_build_object('sub', HOST1, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select guest_phone into v_txt from public.get_booking_contacts(B3);
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  perform pg_temp.check(44, 'the host is given the number the guest actually logged in with', '01700000003', v_txt);

  -- ============================================ realtime
  perform pg_temp.check(45, 'bookings is in the realtime publication', 'true',
    exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
             and schemaname = 'public' and tablename = 'bookings')::text);

  -- ============================================ storage
  perform pg_temp.check(46, 'chat-attachments now has a mime allowlist', 'true',
    (select allowed_mime_types is not null and 'application/pdf' = any(allowed_mime_types)
       from storage.buckets where id = 'chat-attachments')::text);
  perform pg_temp.check(47, 'and executables / HTML are not on it', 'true',
    (select not ('text/html' = any(allowed_mime_types))
        and not ('application/vnd.android.package-archive' = any(allowed_mime_types))
       from storage.buckets where id = 'chat-attachments')::text);
  perform pg_temp.check(48, 'a participant can delete their attachment on either Storage flavour', 'true',
    (select qual like '%owner_id%' from pg_policies
      where schemaname = 'storage' and policyname = 'chat_attachments_owner_delete')::text);

  -- ============================================ unchanged behaviour
  perform pg_temp.check(49, 'guest still cannot cancel a completed stay (control)', 'REFUSED 42501',
    pg_temp.effect(GUESTV,
      format('update public.bookings set booking_status = ''cancelled'' where id = %L', B1),
      format('select booking_status::text from public.bookings where id = %L', B1)));

  update public.bookings set booking_status = 'confirmed', starts_at = now() - interval '3 days', ends_at = now() - interval '2 days' where id = B3;
  perform public.auto_complete_elapsed_bookings();
  select booking_status::text into v_txt from public.bookings where id = B3;
  perform pg_temp.check(50, 'the auto-complete sweep still finalises an elapsed confirmed stay', 'completed', v_txt);

  -- ============================================ held payment on a closed booking
  update public.bookings set booking_status = 'cancelled', cancelled_by = GUESTV, cancelled_at = now(),
         payment_status = 'unpaid', paid_at = null where id = B3;
  insert into public.payments (booking_id, user_id, tran_id, amount, currency, status, risk_level)
  values (B3, GUESTV, 'QA-HELD-' || B3::text, 10, 'BDT', 'pending_review', '0')
  returning id into v_new_listing;   -- reusing the uuid slot
  -- The console calls these with the service-role key, whose JWT has no `sub`:
  -- auth.uid() is null and enforce_booking_update_rules trusts the caller. A
  -- non-null uuid here would be a "user" the trigger refuses (P0001), which
  -- is not what the console gets.
  perform pg_temp.check(53, 'an admin cannot RELEASE a held payment onto a cancelled booking', 'REFUSED 22023',
    pg_temp.act(null,
      format('select public.admin_release_payment(%L)', v_new_listing), 'service_role'));
  perform pg_temp.check(54, 'but can still reject it (control)', 'OK',
    pg_temp.act(null,
      format('select public.admin_reject_payment(%L, ''booking cancelled'')', v_new_listing), 'service_role'));
  update public.bookings set booking_status = 'confirmed' where id = B3;
  perform pg_temp.check(55, 'and CAN release one onto a confirmed booking (control)', 'OK',
    pg_temp.act(null,
      format('select public.admin_release_payment(%L)', v_new_listing), 'service_role'));

  -- ============================================ hidden listing, booked guest
  update public.listings set is_active = false where id = L1;
  perform set_config('request.jwt.claims', json_build_object('sub', GUESTV, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from public.listings where id = L1;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  perform pg_temp.check(56, 'a guest who booked a now-hidden listing can still read it', '1', v_n::text);
  -- GUESTU has no booking anywhere. (Not a racer: the seed leaves them with
  -- rejected requests on L1, and a rejected request is still "having booked
  -- it" — they saw the place while it was live.)
  perform set_config('request.jwt.claims', json_build_object('sub', GUESTU, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from public.listings where id = L1;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  perform pg_temp.check(57, 'a guest who never booked it cannot (control)', '0', v_n::text);
  update public.listings set is_active = true where id = L1;

  perform pg_temp.check(51, 'fn_users_blocked is not a public endpoint', 'false',
    has_function_privilege('authenticated', 'public.fn_users_blocked(uuid, uuid)', 'execute')::text);
  perform pg_temp.check(52, 'fn_identity_phone is not a public endpoint', 'false',
    (has_function_privilege('anon', 'public.fn_identity_phone(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_identity_phone(uuid)', 'execute'))::text);
end $$;

select n, name, expected, actual, case when ok then 'PASS' else 'FAIL' end as result
from t_result order by n;
select count(*) filter (where ok) as pass, count(*) filter (where not ok) as fail from t_result;

rollback;
