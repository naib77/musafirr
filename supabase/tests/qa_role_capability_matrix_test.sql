-- =============================================
-- QA — what a host, a guest, a stranger and an anonymous visitor can actually
-- do. Run inside begin; … rollback; against the LOCAL mirror.
--
-- **Local only**, unlike the numbered migration tests: it leans on the
-- synthetic accounts and listings in supabase/baseline/qa_seed.sql. Against
-- live it would need real ids, and several rows here deliberately attempt
-- writes that must not be attempted against production data.
--
-- The question every row answers is "who is stopped by the DATABASE", not by
-- the Flutter app. CLAUDE.md's recurring lesson is that a check in the form is
-- not enforcement; each ALLOWED below is a real capability and each REFUSED is
-- a real wall.
--
-- Fixtures (qa_seed.sql):
--   HOST1  11111111…  owner, verified — listings …0001 (৳10/hr seat), …0002
--   HOST2  22222222…  owner, verified — listings …0003 (turf), …0004 (inactive)
--   GUESTV 33333333…  tenant, verified
--   GUESTU 44444444…  tenant, UNverified
--   ADMIN  55555555…  admin
-- =============================================

create temp table t_result (n int, area text, name text, expected text, got text, ok boolean) on commit drop;
grant select, insert on t_result to anon, authenticated, service_role;

-- Measure what a write actually DID, not whether it threw.
--
-- This distinction is the whole reason the first version of this file was
-- wrong. Under RLS an UPDATE or DELETE whose rows are filtered out matches
-- nothing and raises NOTHING — so "no exception" reads as success while the
-- database in fact refused. Every write row below therefore probes a value
-- before and after and reports CHANGED / NO-OP / REFUSED.
--
-- The deliberate ZZ999 at the end rolls the write back inside its own
-- subtransaction, so each row is independent; plpgsql does not roll back
-- variable assignments, so the measurement taken before the raise survives it.
-- Without that, row 9 (host accepts) would leave the fixture confirmed and
-- row 13 (host marks paid) would silently measure a no-op change.
create or replace function pg_temp.effect(p_uid uuid, p_sql text, p_probe text)
returns text language plpgsql as $$
declare v_before text; v_after text; res text;
begin
  execute p_probe into v_before;
  begin
    perform set_config('request.jwt.claims',
      json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    execute p_sql;
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', '', true);
    execute p_probe into v_after;
    res := case when v_after is distinct from v_before
                then 'CHANGED ' || coalesce(v_before, 'null') || '->' || coalesce(v_after, 'null')
                else 'NO-OP' end;
    raise exception using errcode = 'ZZ999', message = 'undo';
  exception when others then
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', '', true);
    if sqlstate <> 'ZZ999' then res := 'REFUSED ' || sqlstate; end if;
  end;
  return res;
end $$;

-- For calls whose point is the call itself (an RPC that either runs or raises).
create or replace function pg_temp.act(p_uid uuid, p_sql text) returns text language plpgsql as $$
declare res text;
begin
  begin
    perform set_config('request.jwt.claims',
      json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    execute p_sql;
    res := 'ALLOWED';
    raise exception using errcode = 'ZZ999', message = 'undo';
  exception when others then
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', '', true);
    if sqlstate <> 'ZZ999' then res := 'REFUSED ' || sqlstate; end if;
  end;
  return res;
end $$;

-- How many rows can this identity see? -1 means the read itself was refused
-- (a missing grant), which is a stronger "no" than an empty result.
create or replace function pg_temp.seen(p_uid uuid, p_sql text) returns text
language plpgsql as $$
declare n int;
begin
  if p_uid is null then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'anon', true);
  else
    perform set_config('request.jwt.claims',
      json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
  end if;
  begin execute p_sql into n; exception when others then n := -1; end;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  return coalesce(n::text, 'null');
end $$;

create or replace function pg_temp.chk(p_n int, p_area text, p_name text, p_expected text, p_got text)
returns void language plpgsql as $$
begin
  insert into t_result values (p_n, p_area, p_name, p_expected, p_got,
    p_got like p_expected || '%');
end $$;

do $$
declare
  HOST1  uuid := '11111111-1111-1111-1111-111111111111';
  HOST2  uuid := '22222222-2222-2222-2222-222222222222';
  GUESTV uuid := '33333333-3333-3333-3333-333333333333';
  GUESTU uuid := '44444444-4444-4444-4444-444444444444';
  ADMINU uuid := '55555555-5555-5555-5555-555555555555';
  L1     uuid := 'aaaaaaaa-0000-0000-0000-000000000001';  -- HOST1's ৳10/hr seat
  L3     uuid := 'aaaaaaaa-0000-0000-0000-000000000003';  -- HOST2's turf
  L4     uuid := 'aaaaaaaa-0000-0000-0000-000000000004';  -- HOST2's INACTIVE
  B_DONE uuid := 'bbbbbbbb-0000-0000-0000-000000000001';  -- completed + paid, GUESTV
  B_CONF uuid := 'bbbbbbbb-0000-0000-0000-000000000003';  -- confirmed + unpaid, GUESTV
  v_pm   uuid;
  v_img  text := L1::text || '/qa-fixture.jpg';
  v_doc  text := GUESTV::text || '/qa-nid.jpg';
  v_all  text;
begin
  -- Storage fixtures are made as postgres, because rows 29-31 and 36-38 test
  -- READING and OVERWRITING an object that already exists; creating them
  -- through the helpers would undo them again.
  insert into storage.objects (bucket_id, name, owner, owner_id)
    values ('listing-images', v_img, HOST1, HOST1::text),
           ('documents', v_doc, GUESTV, GUESTV::text)
    on conflict do nothing;
  -- A payout method to act on, likewise.
  perform set_config('request.jwt.claims',
    json_build_object('sub', HOST1, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.add_payout_method('bkash', 'QA Host One', '01711111111');
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  select id into v_pm from public.payout_methods where user_id = HOST1 order by created_at desc limit 1;
  select count(*)::text into v_all from public.profiles;

  ------------------------------------------------------------------ HOST
  perform pg_temp.chk(1, 'host', 'publish a listing (verified owner)', 'ALLOWED',
    pg_temp.act(HOST1, format($q$insert into public.listings (owner_id, title, city, listing_type, daily_rate, max_guests)
      values (%L, 'QA new listing', 'Dhaka', 'room', 900, 2)$q$, HOST1)));

  perform pg_temp.chk(2, 'host', 'publish while identity unverified', 'REFUSED',
    pg_temp.act(GUESTU, format($q$insert into public.listings (owner_id, title, city, listing_type, daily_rate, max_guests)
      values (%L, 'QA unverified listing', 'Dhaka', 'room', 900, 2)$q$, GUESTU)));

  perform pg_temp.chk(3, 'host', 'publish a listing under another owner_id', 'REFUSED',
    pg_temp.act(HOST2, format($q$insert into public.listings (owner_id, title, city, listing_type, daily_rate, max_guests)
      values (%L, 'QA impersonated listing', 'Dhaka', 'room', 900, 2)$q$, HOST1)));

  perform pg_temp.chk(4, 'host', 'edit own listing', 'CHANGED',
    pg_temp.effect(HOST1, format($q$update public.listings set title='QA edited' where id=%L$q$, L1),
                   format($q$select title from public.listings where id=%L$q$, L1)));

  perform pg_temp.chk(5, 'host', 'edit another host''s listing', 'NO-OP',
    pg_temp.effect(HOST1, format($q$update public.listings set title='QA hijacked' where id=%L$q$, L3),
                   format($q$select title from public.listings where id=%L$q$, L3)));

  perform pg_temp.chk(6, 'host', 'delete another host''s listing', 'NO-OP',
    pg_temp.effect(HOST1, format($q$delete from public.listings where id=%L$q$, L3),
                   format($q$select count(*)::text from public.listings where id=%L$q$, L3)));

  perform pg_temp.chk(7, 'host', 'block dates on own listing', 'ALLOWED',
    pg_temp.act(HOST1, format($q$select public.block_listing_dates(%L, (now()+interval '200 days')::date, (now()+interval '201 days')::date, 'QA')$q$, L1)));

  perform pg_temp.chk(8, 'host', 'block dates on another host''s listing', 'REFUSED',
    pg_temp.act(HOST1, format($q$select public.block_listing_dates(%L, (now()+interval '200 days')::date, (now()+interval '201 days')::date, 'QA')$q$, L3)));

  -- B_CONF is seeded 'confirmed', so the host move to drive here is check-in.
  perform pg_temp.chk(9, 'host', 'check a guest in on own listing', 'CHANGED',
    pg_temp.effect(HOST1, format($q$update public.bookings set booking_status='active' where id=%L$q$, B_CONF),
                   format($q$select booking_status::text from public.bookings where id=%L$q$, B_CONF)));

  perform pg_temp.chk(10, 'host', 'change a booking on another host''s listing', 'NO-OP',
    pg_temp.effect(HOST2, format($q$update public.bookings set booking_status='cancelled' where id=%L$q$, B_CONF),
                   format($q$select booking_status::text from public.bookings where id=%L$q$, B_CONF)));

  perform pg_temp.chk(11, 'host', 'confirm cash on own listing''s booking', 'ALLOWED',
    pg_temp.act(HOST1, format($q$select public.mark_cash_payment(%L)$q$, B_CONF)));

  perform pg_temp.chk(12, 'host', 'confirm cash on a stranger''s booking', 'REFUSED',
    pg_temp.act(HOST2, format($q$select public.mark_cash_payment(%L)$q$, B_CONF)));

  perform pg_temp.chk(13, 'host', 'mark a booking paid by table write (132)', 'REFUSED',
    pg_temp.effect(HOST1, format($q$update public.bookings set payment_status='paid' where id=%L$q$, B_CONF),
                   format($q$select payment_status from public.bookings where id=%L$q$, B_CONF)));

  ------------------------------------------------------------- HOST MONEY
  perform pg_temp.chk(14, 'payout', 'add own payout method', 'ALLOWED',
    pg_temp.act(HOST1, $q$select public.add_payout_method('bkash','QA Second','01713333333')$q$));

  perform pg_temp.chk(15, 'payout', 'read another host''s payout methods', '0',
    pg_temp.seen(HOST2, format($q$select count(*) from public.payout_methods where user_id=%L$q$, HOST1)));

  perform pg_temp.chk(16, 'payout', 'read own payout methods', '1',
    pg_temp.seen(HOST1, format($q$select count(*) from public.payout_methods where user_id=%L$q$, HOST1)));

  perform pg_temp.chk(17, 'payout', 'make another user''s method the default', 'REFUSED',
    pg_temp.act(HOST2, format($q$select public.set_default_payout_method(%L)$q$, v_pm)));

  perform pg_temp.chk(18, 'payout', 'retire another user''s method', 'REFUSED',
    pg_temp.act(HOST2, format($q$select public.retire_payout_method(%L)$q$, v_pm)));

  perform pg_temp.chk(19, 'payout', 'insert a payout method directly (no policy)', 'REFUSED',
    pg_temp.act(HOST1, format($q$insert into public.payout_methods (user_id, channel, account_name, account_number)
      values (%L,'bkash','Direct','01712222222')$q$, HOST1)));

  perform pg_temp.chk(20, 'payout', 'self-verify own payout method', 'NO-OP',
    pg_temp.effect(HOST1, format($q$update public.payout_methods set status='verified' where id=%L$q$, v_pm),
                   format($q$select status::text from public.payout_methods where id=%L$q$, v_pm)));

  ------------------------------------------------------------- PROFILE
  perform pg_temp.chk(21, 'profile', 'edit own name and bio', 'CHANGED',
    pg_temp.effect(HOST1, format($q$update public.profiles set full_name='QA Host One Edited' where id=%L$q$, HOST1),
                   format($q$select full_name from public.profiles where id=%L$q$, HOST1)));

  perform pg_temp.chk(22, 'profile', 'edit another user''s profile', 'NO-OP',
    pg_temp.effect(HOST1, format($q$update public.profiles set full_name='QA Hijacked' where id=%L$q$, GUESTV),
                   format($q$select full_name from public.profiles where id=%L$q$, GUESTV)));

  perform pg_temp.chk(23, 'profile', 'promote self to admin', 'REFUSED',
    pg_temp.effect(HOST1, format($q$update public.profiles set role='admin' where id=%L$q$, HOST1),
                   format($q$select role::text from public.profiles where id=%L$q$, HOST1)));

  perform pg_temp.chk(24, 'profile', 'self-approve own identity verification', 'REFUSED',
    pg_temp.effect(GUESTU, format($q$update public.profiles set verification_status='verified' where id=%L$q$, GUESTU),
                   format($q$select verification_status::text from public.profiles where id=%L$q$, GUESTU)));

  perform pg_temp.chk(25, 'profile', 'read another user''s phone from profiles', '0',
    pg_temp.seen(GUESTV, format($q$select count(*) from public.profiles where id=%L and mobile is not null$q$, HOST1)));

  perform pg_temp.chk(26, 'profile', 'anon reads the profiles table at all', '-1',
    pg_temp.seen(null, $q$select count(*) from public.profiles$q$));

  perform pg_temp.chk(27, 'profile', 'anon reads public_profiles (host names)', v_all,
    pg_temp.seen(null, $q$select count(*) from public.public_profiles$q$));

  ------------------------------------------------------------- STORAGE
  perform pg_temp.chk(28, 'storage', 'host uploads a listing image', 'ALLOWED',
    pg_temp.act(HOST1, format($q$insert into storage.objects (bucket_id, name, owner, owner_id)
      values ('listing-images', %L, %L, %L::text)$q$, L1::text || '/new.jpg', HOST1, HOST1)));

  perform pg_temp.chk(29, 'storage', 'anon reads a listing image', '1',
    pg_temp.seen(null, format($q$select count(*) from storage.objects where bucket_id='listing-images' and name=%L$q$, v_img)));

  perform pg_temp.chk(30, 'storage', 'ANOTHER host overwrites that image', 'NO-OP',
    pg_temp.effect(HOST2, format($q$update storage.objects set metadata='{"hacked":true}'::jsonb
      where bucket_id='listing-images' and name=%L$q$, v_img),
      format($q$select coalesce(metadata::text,'none') from storage.objects where bucket_id='listing-images' and name=%L$q$, v_img)));

  -- Stopped by storage's own protect_objects_delete trigger, not by the policy
  -- (which would have allowed it) — a stronger refusal than RLS would give.
  perform pg_temp.chk(31, 'storage', 'ANOTHER host deletes that image', 'REFUSED',
    pg_temp.effect(HOST2, format($q$delete from storage.objects where bucket_id='listing-images' and name=%L$q$, v_img),
      format($q$select count(*)::text from storage.objects where bucket_id='listing-images' and name=%L$q$, v_img)));

  perform pg_temp.chk(32, 'storage', 'a guest who hosts nothing uploads into listing-images', 'REFUSED',
    pg_temp.act(GUESTV, format($q$insert into storage.objects (bucket_id, name, owner, owner_id)
      values ('listing-images', %L, %L, %L::text)$q$, L1::text || '/guest.jpg', GUESTV, GUESTV)));

  perform pg_temp.chk(33, 'storage', 'guest uploads own avatar (uid filename)', 'ALLOWED',
    pg_temp.act(GUESTV, format($q$insert into storage.objects (bucket_id, name, owner, owner_id)
      values ('avatars', %L, %L, %L::text)$q$, GUESTV::text || '.jpg', GUESTV, GUESTV)));

  perform pg_temp.chk(34, 'storage', 'guest uploads an avatar named as another user', 'REFUSED',
    pg_temp.act(GUESTV, format($q$insert into storage.objects (bucket_id, name, owner, owner_id)
      values ('avatars', %L, %L, %L::text)$q$, HOST1::text || '.jpg', GUESTV, GUESTV)));

  perform pg_temp.chk(35, 'storage', 'guest uploads own identity document', 'ALLOWED',
    pg_temp.act(GUESTV, format($q$insert into storage.objects (bucket_id, name, owner, owner_id)
      values ('documents', %L, %L, %L::text)$q$, GUESTV::text || '/new-nid.jpg', GUESTV, GUESTV)));

  perform pg_temp.chk(36, 'storage', 'another signed-in user reads that document', '0',
    pg_temp.seen(HOST1, format($q$select count(*) from storage.objects where bucket_id='documents' and name=%L$q$, v_doc)));

  perform pg_temp.chk(37, 'storage', 'anon reads that document', '0',
    pg_temp.seen(null, format($q$select count(*) from storage.objects where bucket_id='documents' and name=%L$q$, v_doc)));

  perform pg_temp.chk(38, 'storage', 'admin reads that document', '1',
    pg_temp.seen(ADMINU, format($q$select count(*) from storage.objects where bucket_id='documents' and name=%L$q$, v_doc)));

  ------------------------------------------------------------- GUEST
  -- 4 seeded listings, one of them deliberately inactive.
  perform pg_temp.chk(39, 'guest', 'browse listings while signed out', '3',
    pg_temp.seen(null, $q$select count(*) from public.listings where is_active$q$));

  perform pg_temp.chk(40, 'guest', 'book while identity unverified', 'REFUSED',
    pg_temp.act(GUESTU, format($q$select public.create_marketplace_booking(%L, now()+interval '300 days', now()+interval '300 days 1 hour', 'hour', 1, 'QA')$q$, L1)));

  perform pg_temp.chk(41, 'guest', 'book while verified', 'ALLOWED',
    pg_temp.act(GUESTV, format($q$select public.create_marketplace_booking(%L, now()+interval '301 days', now()+interval '301 days 1 hour', 'hour', 1, 'QA')$q$, L1)));

  perform pg_temp.chk(42, 'guest', 'book your OWN listing', 'REFUSED',
    pg_temp.act(HOST1, format($q$select public.create_marketplace_booking(%L, now()+interval '302 days', now()+interval '302 days 1 hour', 'hour', 1, 'QA')$q$, L1)));

  perform pg_temp.chk(43, 'guest', 'book more guests than the listing holds', 'REFUSED',
    pg_temp.act(GUESTV, format($q$select public.create_marketplace_booking(%L, now()+interval '303 days', now()+interval '303 days 1 hour', 'hour', 99, 'QA')$q$, L1)));

  perform pg_temp.chk(44, 'guest', 'book a reversed window', 'REFUSED',
    pg_temp.act(GUESTV, format($q$select public.create_marketplace_booking(%L, now()+interval '305 days', now()+interval '304 days', 'hour', 1, 'QA')$q$, L1)));

  perform pg_temp.chk(45, 'guest', 'book a slot that is already in the PAST', 'REFUSED',
    pg_temp.act(GUESTV, format($q$select public.create_marketplace_booking(%L, now()-interval '10 days', now()-interval '10 days'+interval '1 hour', 'hour', 1, 'QA')$q$, L1)));

  perform pg_temp.chk(46, 'guest', 'book an inactive listing', 'REFUSED',
    pg_temp.act(GUESTV, format($q$select public.create_marketplace_booking(%L, now()+interval '306 days', now()+interval '307 days', 'day', 1, 'QA')$q$, L4)));

  perform pg_temp.chk(47, 'guest', 'cancel own booking', 'CHANGED',
    pg_temp.effect(GUESTV, format($q$update public.bookings set booking_status='cancelled' where id=%L$q$, B_CONF),
                   format($q$select booking_status::text from public.bookings where id=%L$q$, B_CONF)));

  perform pg_temp.chk(48, 'guest', 'cancel a stranger''s booking', 'NO-OP',
    pg_temp.effect(GUESTU, format($q$update public.bookings set booking_status='cancelled' where id=%L$q$, B_DONE),
                   format($q$select booking_status::text from public.bookings where id=%L$q$, B_DONE)));

  perform pg_temp.chk(49, 'guest', 'accept own booking (play host)', 'REFUSED',
    pg_temp.effect(GUESTV, format($q$update public.bookings set booking_status='confirmed' where id=%L$q$, B_DONE),
                   format($q$select booking_status::text from public.bookings where id=%L$q$, B_DONE)));

  perform pg_temp.chk(50, 'guest', 'read a stranger''s booking', '0',
    pg_temp.seen(GUESTU, format($q$select count(*) from public.bookings where id=%L$q$, B_DONE)));

  perform pg_temp.chk(51, 'guest', 'read a stranger''s payment row', '0',
    pg_temp.seen(GUESTU, format($q$select count(*) from public.payments where booking_id=%L$q$, B_DONE)));

  perform pg_temp.chk(52, 'guest', 'read own payment row', '1',
    pg_temp.seen(GUESTV, format($q$select count(*) from public.payments where booking_id=%L$q$, B_DONE)));

  perform pg_temp.chk(53, 'guest', 'host reads the payment on their listing', '1',
    pg_temp.seen(HOST1, format($q$select count(*) from public.payments where booking_id=%L$q$, B_DONE)));

  perform pg_temp.chk(54, 'guest', 'mark own booking paid by table write (132)', 'REFUSED',
    pg_temp.effect(GUESTV, format($q$update public.bookings set payment_status='unpaid' where id=%L$q$, B_DONE),
                   format($q$select payment_status from public.bookings where id=%L$q$, B_DONE)));

  perform pg_temp.chk(55, 'guest', 'read the exact address of a listing never booked', '0',
    pg_temp.seen(GUESTU, format($q$select count(*) from public.listing_addresses where listing_id=%L$q$, L1)));

  ------------------------------------------------------- REVIEWS / SOCIAL
  perform pg_temp.chk(56, 'review', 'review your own completed booking', 'ALLOWED',
    pg_temp.act(GUESTV, format($q$insert into public.reviews (booking_id, listing_id, reviewer_id, reviewer_name, reviewee_id, review_type, overall_rating,
       cleanliness_rating, accuracy_rating, communication_rating, location_rating, value_rating, comment)
      values (%L, 'aaaaaaaa-0000-0000-0000-000000000002', %L, 'QA Guest Verified', %L, 'guest_to_host', 5, 5,5,5,5,5, 'QA review')$q$, B_DONE, GUESTV, HOST1)));

  perform pg_temp.chk(57, 'review', 'review a booking that is not yours', 'REFUSED',
    pg_temp.act(GUESTU, format($q$insert into public.reviews (booking_id, listing_id, reviewer_id, reviewer_name, reviewee_id, review_type, overall_rating,
       cleanliness_rating, accuracy_rating, communication_rating, location_rating, value_rating, comment)
      values (%L, 'aaaaaaaa-0000-0000-0000-000000000002', %L, 'QA Guest Unverified', %L, 'guest_to_host', 1, 1,1,1,1,1, 'QA fake')$q$, B_DONE, GUESTU, HOST1)));

  perform pg_temp.chk(58, 'social', 'add own favourite', 'ALLOWED',
    pg_temp.act(GUESTV, format($q$insert into public.favorites (user_id, listing_id) values (%L, %L)$q$, GUESTV, L1)));

  perform pg_temp.chk(59, 'social', 'read another user''s favourites', '0',
    pg_temp.seen(GUESTU, format($q$select count(*) from public.favorites where user_id=%L$q$, GUESTV)));

  perform pg_temp.chk(60, 'social', 'insert a notification for another user', 'REFUSED',
    pg_temp.act(GUESTV, format($q$insert into public.notifications (user_id, type, title, body)
      values (%L, 'system_alert', 'QA forged', 'forged')$q$, HOST1)));

  perform pg_temp.chk(61, 'social', 'read another user''s notifications', '0',
    pg_temp.seen(GUESTU, format($q$select count(*) from public.notifications where user_id=%L$q$, HOST1)));
end $$;

select n, area, name, expected, got, case when ok then 'PASS' else 'FAIL' end as verdict
  from t_result order by n;
