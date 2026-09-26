-- Synthetic QA fixtures for the LOCAL database only. No real person, phone or
-- listing appears here. Loaded last by tool/local_db_from_live.sh.
--
-- Shape follows what supabase/tests/*.sql reach for: the oldest profile is a
-- verified host with an active listing; there is one admin; there is an
-- unverified guest; bookings exist in every status. Users are inserted into
-- auth.users directly — on_auth_user_created (handle_new_user) makes the
-- profile row, exactly as a real signup would — with a known password so
-- GoTrue's local password grant can mint a JWT for PostgREST-level tests.
-- NOTE: verify-otp ROTATES a user's password on every login by design, so after
-- driving an account through the master-OTP path its qa-password stops working;
-- reset with: update auth.users set encrypted_password =
--   extensions.crypt('qa-password', extensions.gen_salt('bf')) where email = …;
create extension if not exists pgcrypto with schema extensions;

create or replace function pg_temp.mk_user(p_id uuid, p_email text, p_phone text, p_name text, p_role text, p_when timestamptz)
returns void language plpgsql as $$
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
    email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', p_id, 'authenticated', 'authenticated', p_email,
    extensions.crypt('qa-password', extensions.gen_salt('bf')), p_when,
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', p_name, 'mobile', p_phone, 'role', p_role),
    p_when, p_when, '', '', '', '')
  on conflict (id) do nothing;
  insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
  values (p_id, p_id, p_email, 'email', jsonb_build_object('sub', p_id::text, 'email', p_email), p_when, p_when, p_when)
  on conflict do nothing;
end $$;

select pg_temp.mk_user('11111111-1111-1111-1111-111111111111', 'phone.1700000001@musaafir.app', '01700000001', 'QA Host One',  'owner',  now() - interval '400 days');
select pg_temp.mk_user('22222222-2222-2222-2222-222222222222', 'phone.1700000002@musaafir.app', '01700000002', 'QA Host Two',  'owner',  now() - interval '300 days');
select pg_temp.mk_user('33333333-3333-3333-3333-333333333333', 'phone.1700000003@musaafir.app', '01700000003', 'QA Guest Verified', 'tenant', now() - interval '200 days');
select pg_temp.mk_user('44444444-4444-4444-4444-444444444444', 'phone.1700000004@musaafir.app', '01700000004', 'QA Guest Unverified', 'tenant', now() - interval '100 days');
select pg_temp.mk_user('55555555-5555-5555-5555-555555555555', 'admin@musafir.local',           '01700000005', 'QA Admin',     'admin',  now() - interval '50 days');

update public.profiles set verification_status = 'verified', is_host = true  where id in ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222');
update public.profiles set verification_status = 'verified'                  where id = '33333333-3333-3333-3333-333333333333';
update public.profiles set verification_status = 'none'                      where id = '44444444-4444-4444-4444-444444444444';
update public.profiles set role = 'admin', verification_status = 'verified'  where id = '55555555-5555-5555-5555-555555555555';

insert into public.listings (id, owner_id, owner_name, title, description, address, city, country, listing_type,
  latitude, longitude, hourly_rate, daily_rate, monthly_rate, max_guests, is_active, host_available, min_hours, max_hours, created_at)
values
 ('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','QA Host One','QA cheap hourly seat','fixture','Uttara Sector 7','Dhaka','Bangladesh','seat', 23.8759, 90.3795, 10, 1500, null, 2, true, true, 1, 12, now() - interval '390 days'),
 ('aaaaaaaa-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','QA Host One','QA daily room','fixture','Dhanmondi 27','Dhaka','Bangladesh','room', 23.7561, 90.3745, 150, 1500, 30000, 4, true, true, null, null, now() - interval '380 days'),
 ('aaaaaaaa-0000-0000-0000-000000000003','22222222-2222-2222-2222-222222222222','QA Host Two','QA turf ground','fixture','Uttara Sector 10','Dhaka','Bangladesh','turf', 23.8700, 90.3900, 2000, null, null, 14, true, true, 1, 3, now() - interval '290 days'),
 ('aaaaaaaa-0000-0000-0000-000000000004','22222222-2222-2222-2222-222222222222','QA Host Two','QA inactive house','fixture','Banani','Dhaka','Bangladesh','fullHouse', 23.7937, 90.4066, null, 6000, null, 8, false, true, null, null, now() - interval '280 days')
on conflict (id) do nothing;
update public.listings set turf_sport = 'football', turf_format = '7-a-side', turf_surface = 'artificial' where id = 'aaaaaaaa-0000-0000-0000-000000000003';

-- Bookings by the verified guest on host one's listings, one per status.
insert into public.bookings (id, tenant_id, tenant_name, listing_id, listing_title, listing_city, starts_at, ends_at,
  guest_count, total_price, booking_status, payment_status, pricing_unit, unit_count, created_at)
values
 ('bbbbbbbb-0000-0000-0000-000000000001','33333333-3333-3333-3333-333333333333','QA Guest Verified','aaaaaaaa-0000-0000-0000-000000000002','QA daily room','Dhaka', now() - interval '30 days', now() - interval '28 days', 2, 3000, 'completed', 'paid',   'day', 2, now() - interval '35 days'),
 ('bbbbbbbb-0000-0000-0000-000000000002','33333333-3333-3333-3333-333333333333','QA Guest Verified','aaaaaaaa-0000-0000-0000-000000000002','QA daily room','Dhaka', now() - interval '20 days', now() - interval '19 days', 1, 1500, 'completed', 'unpaid', 'day', 1, now() - interval '25 days'),
 ('bbbbbbbb-0000-0000-0000-000000000003','33333333-3333-3333-3333-333333333333','QA Guest Verified','aaaaaaaa-0000-0000-0000-000000000001','QA cheap hourly seat','Dhaka', now() + interval '2 days', now() + interval '2 days 1 hour', 1, 10, 'confirmed', 'unpaid', 'hour', 1, now() - interval '1 day'),
 ('bbbbbbbb-0000-0000-0000-000000000004','33333333-3333-3333-3333-333333333333','QA Guest Verified','aaaaaaaa-0000-0000-0000-000000000001','QA cheap hourly seat','Dhaka', now() + interval '5 days', now() + interval '5 days 2 hours', 1, 20, 'pending',   'unpaid', 'hour', 2, now() - interval '1 hour'),
 ('bbbbbbbb-0000-0000-0000-000000000005','33333333-3333-3333-3333-333333333333','QA Guest Verified','aaaaaaaa-0000-0000-0000-000000000003','QA turf ground','Dhaka', now() - interval '10 days', now() - interval '10 days' + interval '1 hour', 10, 2000, 'rejected',  'unpaid', 'hour', 1, now() - interval '12 days'),
 ('bbbbbbbb-0000-0000-0000-000000000006','33333333-3333-3333-3333-333333333333','QA Guest Verified','aaaaaaaa-0000-0000-0000-000000000002','QA daily room','Dhaka', now() - interval '5 days', now() - interval '4 days', 1, 1500, 'cancelled', 'unpaid', 'day', 1, now() - interval '7 days')
on conflict (id) do nothing;

insert into public.payments (booking_id, user_id, tran_id, amount, currency, status, validated_at, card_type)
values ('bbbbbbbb-0000-0000-0000-000000000001','33333333-3333-3333-3333-333333333333','MSFR-QA000001-SEED0001', 3000, 'BDT', 'paid', now() - interval '34 days', 'BKASH-BKash')
on conflict (tran_id) do nothing;

-- One account with no usable phone, as live has (a `pending_<uuid>` mobile):
-- 128/129's reach rows assume the audience is smaller than the profile count.
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
values ('00000000-0000-0000-0000-000000000000','66666666-6666-6666-6666-666666666666','authenticated','authenticated','nophone@musafir.local', extensions.crypt('qa-password', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"full_name":"QA No Phone"}'::jsonb, now() - interval '10 days', now() - interval '10 days','','','','')
on conflict (id) do nothing;
-- Amenities so an anon amenity search has something to find (113 rows 03/04).
insert into public.listing_facilities (listing_id, facility_id)
select l.id, f.id from public.listings l cross join public.facilities f
 where l.id in ('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000002') and f.name in ('WiFi','Parking','Air Conditioning','AC')
on conflict do nothing;

-- Eight more verified guests, for the concurrency scenario: several guests
-- trying to book the same slot at the same moment. They need real auth.users
-- rows because create_marketplace_booking reads auth.uid() and checks
-- profiles.verification_status.
do $$
declare i int; uid uuid; em text;
begin
  for i in 1..8 loop
    uid := ('77777777-0000-0000-0000-00000000000' || i)::uuid;
    em  := 'phone.17100000' || lpad(i::text, 2, '0') || '@musaafir.app';
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', em,
      extensions.crypt('qa-password', extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('full_name', 'QA Racer ' || i, 'mobile', '0171000000' || i, 'role', 'tenant'),
      now() - interval '30 days', now(), '', '', '', '')
    on conflict (id) do nothing;
    insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
    values (uid, uid, em, 'email', jsonb_build_object('sub', uid::text, 'email', em), now(), now(), now())
    on conflict do nothing;
    update public.profiles set verification_status = 'verified' where id = uid;
  end loop;
end $$;
