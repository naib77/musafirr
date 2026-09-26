-- =============================================
-- 134 / 135 / 136 / 137 — the QA fixes of 2026-09-19
--
-- One rolled-back transaction, impersonating real seeded accounts through
-- `request.jwt.claims` the way PostgREST does.
--
-- Two rules this file is built around, both learned the hard way in the QA
-- round these migrations came out of:
--
--   * **Measure the effect, not the exception.** An UPDATE or DELETE whose
--     rows RLS filters out matches nothing and raises NOTHING. "No error"
--     reads as success while the database in fact refused. Every write test
--     below reads a probe value before and after. (An INSERT is the
--     exception to the exception: a WITH CHECK failure does raise, 42501.)
--   * **Clear `request.jwt.claims` when you drop back to postgres.** A stale
--     `sub` leaves `auth.uid()` non-null and the guards correctly refuse even
--     postgres, which reads as the fix being broken.
--
-- Run: psql "$DB" -f supabase/tests/134_137_qa_fixes_test.sql
-- =============================================

begin;

create temp table t_result(n int, name text, expected text, actual text, ok boolean);

-- Impersonate, run one statement, report REFUSED <sqlstate> or the effect on
-- a probe, then undo. The ZZ999 raise rolls back this block's own
-- subtransaction; plpgsql does not roll back variable assignments, so the
-- measurement survives the undo.
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

-- Same, for a call whose success is the answer (an RPC, an INSERT).
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
  L3     uuid := 'aaaaaaaa-0000-0000-0000-000000000003'; -- HOST2, turf
  v_obj  uuid;
  v_bk   uuid;
  v_pay  uuid;
begin
  -- A listing image that belongs to HOST1, shaped the way the app writes one.
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values ('listing-images', L1::text || '/qa_fixture.jpg', HOST1, HOST1::text,
          '{"size": 1}'::jsonb)
  returning id into v_obj;

  -- ============================================ 134 storage ownership
  perform pg_temp.check(1, '134 another host cannot overwrite an image', 'NO-OP',
    pg_temp.effect(HOST2,
      format('update storage.objects set metadata = ''{"hacked": true}''::jsonb where id = %L', v_obj),
      format('select metadata::text from storage.objects where id = %L', v_obj)));

  perform pg_temp.check(2, '134 a guest cannot overwrite an image', 'NO-OP',
    pg_temp.effect(GUESTV,
      format('update storage.objects set metadata = ''{"hacked": true}''::jsonb where id = %L', v_obj),
      format('select metadata::text from storage.objects where id = %L', v_obj)));

  perform pg_temp.check(3, '134 the owning host CAN still overwrite it', 'CHANGED',
    pg_temp.effect(HOST1,
      format('update storage.objects set metadata = ''{"size": 2}''::jsonb where id = %L', v_obj),
      format('select metadata::text from storage.objects where id = %L', v_obj)));

  perform pg_temp.check(4, '134 an admin can overwrite it', 'CHANGED',
    pg_temp.effect(ADMIN,
      format('update storage.objects set metadata = ''{"size": 3}''::jsonb where id = %L', v_obj),
      format('select metadata::text from storage.objects where id = %L', v_obj)));

  -- Deleting through plain SQL cannot reach the policy at all: Supabase's own
  -- statement-level `protect_objects_delete` refuses every direct DELETE on
  -- storage.objects, so the Storage API is the only door. That is exactly why
  -- the QA round reported deletion as "refused, but not by us" — so the
  -- policy is asserted from the catalog instead of by driving it.
  perform pg_temp.check(5, '134 a direct SQL delete never reaches the policy',
    'REFUSED 42501',
    pg_temp.effect(HOST2,
      format('delete from storage.objects where id = %L', v_obj),
      format('select count(*)::text from storage.objects where id = %L', v_obj)));

  perform pg_temp.check(5.1::int, '134 the delete policy names an owner', 'true',
    (select (qual like '%owner%')::text from pg_policies
      where schemaname = 'storage' and policyname = 'listing_images_owner_delete'));

  perform pg_temp.check(6, '134 a guest cannot upload into listing-images', 'REFUSED 42501',
    pg_temp.act(GUESTV,
      'insert into storage.objects (bucket_id, name, owner, owner_id, metadata)'
      || format(' values (''listing-images'', ''x/%s.jpg'', %L, %L, ''{}''::jsonb)',
                gen_random_uuid(), GUESTV, GUESTV)));

  perform pg_temp.check(7, '134 a verified host CAN upload', 'OK',
    pg_temp.act(HOST1,
      'insert into storage.objects (bucket_id, name, owner, owner_id, metadata)'
      || format(' values (''listing-images'', ''y/%s.jpg'', %L, %L, ''{}''::jsonb)',
                gen_random_uuid(), HOST1, HOST1)));

  -- The recreated listings INSERT policy must behave exactly as before.
  perform pg_temp.check(8, '134 a verified owner can still publish a listing', 'OK',
    pg_temp.act(HOST1, format(
      'insert into public.listings (owner_id, owner_name, title, description, address, city, country, listing_type, hourly_rate, max_guests, is_active) '
      || 'values (%L, ''QA Host One'', ''QA regression listing'', ''x'', ''Uttara'', ''Dhaka'', ''Bangladesh'', ''seat'', 10, 2, true)', HOST1)));

  -- The upload gate is deliberately looser than the publish gate: live has
  -- four listings belonging to two accounts that predate 114 and could no
  -- longer publish, and they must still be able to change their own photos.
  -- HOST1 is pushed into exactly that state for one row — rolled back with
  -- the rest of the transaction — because a row that did not first make the
  -- publish check FAIL would pass for the wrong reason.
  update public.profiles set verification_status = 'none' where id = HOST1;

  perform pg_temp.check(8.5::int, '134 an existing owner who could not publish can still upload',
    'OK',
    pg_temp.act(HOST1,
      'insert into storage.objects (bucket_id, name, owner, owner_id, metadata)'
      || format(' values (''listing-images'', ''z/%s.jpg'', %L, %L, ''{}''::jsonb)',
                gen_random_uuid(), HOST1, HOST1)));

  perform pg_temp.check(8.6::int, '134 …and that owner really could not publish',
    'REFUSED 42501',
    pg_temp.act(HOST1, format(
      'insert into public.listings (owner_id, owner_name, title, description, address, city, country, listing_type, hourly_rate, max_guests, is_active) '
      || 'values (%L, ''QA Host One'', ''QA blocked listing'', ''x'', ''Uttara'', ''Dhaka'', ''Bangladesh'', ''seat'', 10, 2, true)', HOST1)));

  update public.profiles set verification_status = 'verified' where id = HOST1;

  perform pg_temp.check(9, '134 an unverified tenant still cannot publish', 'REFUSED 42501',
    pg_temp.act(GUESTU, format(
      'insert into public.listings (owner_id, owner_name, title, description, address, city, country, listing_type, hourly_rate, max_guests, is_active) '
      || 'values (%L, ''QA Guest'', ''QA bad listing'', ''x'', ''Uttara'', ''Dhaka'', ''Bangladesh'', ''seat'', 10, 2, true)', GUESTU)));

  -- ============================================ 135 booking sanity
  perform pg_temp.check(10, '135 a host cannot book their own listing', 'REFUSED 42501',
    pg_temp.act(HOST1, format(
      $q$select public.create_marketplace_booking(%L, now()+interval '500 days', now()+interval '500 days 1 hour', 'hour', 1, 'QA')$q$, L1)));

  perform pg_temp.check(11, '135 a booking in the past is refused', 'REFUSED 22023',
    pg_temp.act(GUESTV, format(
      $q$select public.create_marketplace_booking(%L, now()-interval '10 days', now()-interval '10 days'+interval '1 hour', 'hour', 1, 'QA')$q$, L1)));

  perform pg_temp.check(12, '135 a booking starting now is still allowed', 'OK',
    pg_temp.act(GUESTV, format(
      $q$select public.create_marketplace_booking(%L, now()+interval '2 minutes', now()+interval '62 minutes', 'hour', 1, 'QA')$q$, L1)));

  perform pg_temp.check(13, '135 an ordinary future booking still works', 'OK',
    pg_temp.act(GUESTV, format(
      $q$select public.create_marketplace_booking(%L, now()+interval '501 days', now()+interval '501 days 1 hour', 'hour', 1, 'QA')$q$, L1)));

  perform pg_temp.check(14, '135 a guest may still book someone else''s turf', 'OK',
    pg_temp.act(GUESTV, format(
      $q$select public.create_marketplace_booking(%L, now()+interval '502 days', now()+interval '502 days 1 hour', 'hour', 1, 'QA')$q$, L3)));

  -- ============================================ 136 payment hygiene
  insert into public.bookings (listing_id, tenant_id, tenant_name, starts_at, ends_at,
    pricing_unit, unit_count, total_price, guest_count, booking_status, payment_status, listing_title)
  values (L1, GUESTV, 'QA Guest Verified', now()+interval '600 days', now()+interval '600 days 1 hour',
    'hour', 1, 10, 1, 'confirmed', 'unpaid', 'QA cheap hourly seat')
  returning id into v_bk;

  insert into public.payments (booking_id, user_id, tran_id, amount, currency, status, created_at)
  values (v_bk, GUESTV, 'QA-OLD-1', 10, 'BDT', 'initiated', now() - interval '3 hours');
  insert into public.payments (booking_id, user_id, tran_id, amount, currency, status, created_at)
  values (v_bk, GUESTV, 'QA-NEW-1', 10, 'BDT', 'initiated', now() - interval '5 minutes');

  perform public.expire_stale_payment_attempts();

  perform pg_temp.check(15, '136 the sweep abandons an hour-old attempt', 'abandoned',
    (select status from public.payments where tran_id = 'QA-OLD-1'));
  perform pg_temp.check(16, '136 the sweep leaves a fresh attempt alone', 'initiated',
    (select status from public.payments where tran_id = 'QA-NEW-1'));

  perform pg_temp.check(17, '136 the sweep is not reachable by a signed-in user', 'REFUSED 42501',
    pg_temp.act(GUESTV, 'select public.expire_stale_payment_attempts()'));

  -- A risk-flagged settlement, as the IPN now writes it.
  insert into public.payments (booking_id, user_id, tran_id, amount, currency, status, risk_level, risk_title)
  values (v_bk, GUESTV, 'QA-RISKY-1', 10, 'BDT', 'pending_review', '1', 'Suspicious')
  returning id into v_pay;

  perform pg_temp.check(18, '136 pending_review is an allowed payment status', 'pending_review',
    (select status from public.payments where id = v_pay));

  perform pg_temp.check(19, '136 releasing a held payment is not open to an admin''s JWT',
    'REFUSED 42501',
    pg_temp.act(ADMIN, format('select public.admin_release_payment(%L)', v_pay)));

  perform pg_temp.check(20, '136 service_role releases it and the booking becomes paid',
    'CHANGED unpaid->paid',
    pg_temp.effect(ADMIN, format('select public.admin_release_payment(%L)', v_pay),
      format('select payment_status from public.bookings where id = %L', v_bk),
      'service_role'));

  perform pg_temp.check(21, '136 rejecting a held payment marks it failed',
    'CHANGED pending_review->failed',
    pg_temp.effect(ADMIN, format('select public.admin_reject_payment(%L, ''qa'')', v_pay),
      format('select status from public.payments where id = %L', v_pay),
      'service_role'));

  -- ============================================ the IPN's notification types
  --
  -- `sslcommerz-ipn` sent `paymentReceived`; the enum has `payment_received`.
  -- Postgres refused it, the insert sat inside a try/catch, and the error was
  -- swallowed — so every online payment on live notified NOBODY, twelve of
  -- them, while the three cash notifications worked and hid the gap (QA
  -- report 2026-09-18, F2). A one-word fault that cost the whole feature, and
  -- nothing could have caught it but this: the three labels that function now
  -- sends, cast to the enum.
  --
  -- Keep this in step by hand when the function learns a new type. There is
  -- no seam between Deno and Postgres that could do it automatically, which
  -- is exactly why the bug was possible.
  perform pg_temp.check(25, 'F2 the IPN''s notification types all exist', 'ok',
    (select 'ok' from (select unnest(array['payment_received', 'system_alert',
                                           'security_alert'])::public.notification_type) q
      limit 1));

  -- ============================================ 137 admin may refund
  update public.bookings set payment_status = 'paid' where id = v_bk;

  perform pg_temp.check(22, '137 an admin can mark a paid booking refunded',
    'CHANGED paid->refunded',
    pg_temp.effect(ADMIN,
      format('update public.bookings set payment_status = ''refunded'' where id = %L and payment_status = ''paid''', v_bk),
      format('select payment_status from public.bookings where id = %L', v_bk)));

  -- REFUSED, not NO-OP: 132's settlement guard is a trigger and raises before
  -- the question of which rows RLS would have matched ever arises.
  perform pg_temp.check(23, '137 a guest still cannot mark their booking refunded', 'REFUSED 42501',
    pg_temp.effect(GUESTV,
      format('update public.bookings set payment_status = ''refunded'' where id = %L', v_bk),
      format('select payment_status from public.bookings where id = %L', v_bk)));

  perform pg_temp.check(24, '137 the host still cannot either', 'REFUSED 42501',
    pg_temp.effect(HOST1,
      format('update public.bookings set payment_status = ''refunded'' where id = %L', v_bk),
      format('select payment_status from public.bookings where id = %L', v_bk)));
end $$;

select n, name, expected, actual,
       case when ok then 'PASS' else 'FAIL' end as result
from t_result order by n;

select count(*) filter (where ok) as passed,
       count(*) filter (where not ok) as failed
from t_result;

rollback;
