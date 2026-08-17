-- Verification for 093_listing_address_privacy.sql.
--
-- Proves the entitlement rule that migration 093 moved out of the Flutter app
-- and into RLS: only the host, an admin, or a guest whose booking the host has
-- ACCEPTED may read a listing's exact address.
--
-- Run it wrapped in a transaction you roll back, so the test bookings it inserts
-- never persist:
--
--   begin;
--   \i supabase/tests/093_listing_address_privacy_test.sql
--   rollback;
--
-- Or against the live project through the Management API SQL endpoint, with the
-- file's contents between `begin;` and `rollback;` (see
-- scripts/dump_live_schema.py for how the CLI keychain token is used).
--
-- Must run as a superuser/table owner, because it switches roles to impersonate
-- anon and individual authenticated users. Expected result:
--
--   1_anon                      PERMISSION DENIED   (grant revoked, not just RLS)
--   2_owner                     1 rows
--   3_guest_completed_booking   1 rows
--   4_stranger_no_booking       0 rows
--   5_stranger_pending_booking  0 rows   <- the point of the whole change
--   6_stranger_after_accept     1 rows
--   7_stranger_after_reject     0 rows
--   7b_stranger_after_cancel    0 rows
--   8_stranger_write            0 rows affected (blocked by RLS)
--   9_guest_sees_addresses      area-level labels only, no house/flat/road
--
-- The subject listing/host/guest ids are resolved from live data, so they differ
-- per environment; `subjects` echoes what was picked.

create temp table res(name text, value text);
grant all on res to public;

-- L: listing owned by OWNER, with a completed booking from GUEST_OK
-- STRANGER: a profile with no booking on L
do $$
declare
  v_l uuid := '9c5181a0-b69f-476c-958f-0202c8f8f4d4';
  v_owner uuid := '5969711b-0e43-45f1-9664-ddc1836a8850';
  v_ok uuid := '8322efdf-22d1-4f18-8913-cd1d4b30250d';
  v_stranger uuid;
begin
  select p.id into v_stranger from public.profiles p
   where p.id not in (select tenant_id from public.bookings where listing_id = v_l and tenant_id is not null)
     and p.id <> v_owner limit 1;
  insert into res values ('subjects', format('L=%s owner=%s ok=%s stranger=%s', v_l, v_owner, v_ok, v_stranger));
  create temp table subj(l uuid, owner uuid, ok uuid, stranger uuid);
  grant all on subj to public;
  insert into subj values (v_l, v_owner, v_ok, v_stranger);
end $$;

-- Reusable check: run a count as `who` with uid `uid`, record it.
create or replace function pg_temp.chk(label text, who text, uid uuid) returns void
language plpgsql as $$
declare n int; v_l uuid;
begin
  select l into v_l from subj;
  begin
    execute format('set local role %I', who);
    perform set_config('request.jwt.claims',
      json_build_object('sub', uid, 'role', who)::text, true);
    select count(*) into n from public.listing_addresses where listing_id = v_l;
    reset role;
    insert into res values (label, n::text || ' rows');
  exception when insufficient_privilege then
    reset role;
    insert into res values (label, 'PERMISSION DENIED');
  end;
end $$;
grant execute on function pg_temp.chk(text, text, uuid) to public;

select pg_temp.chk('1_anon', 'anon', '00000000-0000-0000-0000-000000000000');
select pg_temp.chk('2_owner', 'authenticated', (select owner from subj));
select pg_temp.chk('3_guest_completed_booking', 'authenticated', (select ok from subj));
select pg_temp.chk('4_stranger_no_booking', 'authenticated', (select stranger from subj));

-- A pending booking must NOT unlock it. Inserted/deleted rather than
-- status-updated: enforce_booking_update_rules() blocks a guest-side
-- pending -> confirmed transition. Far-future dates dodge the overlap
-- exclusion constraint against real bookings.
create or replace function pg_temp.seed(p_status text) returns void
language plpgsql as $$
begin
  delete from public.bookings where tenant_name = 'RLS Test Guest';
  insert into public.bookings (listing_id, tenant_id, tenant_name, starts_at, ends_at,
                               total_price, booking_status, guest_count)
  select l, stranger, 'RLS Test Guest',
         now() + interval '400 days', now() + interval '402 days',
         100, p_status::public.booking_status, 1 from subj;
end $$;

select pg_temp.seed('pending');
select pg_temp.chk('5_stranger_pending_booking', 'authenticated', (select stranger from subj));

select pg_temp.seed('confirmed');
select pg_temp.chk('6_stranger_after_accept', 'authenticated', (select stranger from subj));

select pg_temp.seed('rejected');
select pg_temp.chk('7_stranger_after_reject', 'authenticated', (select stranger from subj));

select pg_temp.seed('cancelled');
select pg_temp.chk('7b_stranger_after_cancel', 'authenticated', (select stranger from subj));

delete from public.bookings where tenant_name = 'RLS Test Guest';

-- A non-owner must not be able to write an address row.
do $$
declare v_l uuid; v_s uuid;
begin
  select l, stranger into v_l, v_s from subj;
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_s, 'role', 'authenticated')::text, true);
    update public.listing_addresses set street = 'HACKED' where listing_id = v_l;
    reset role;
    insert into res values ('8_stranger_write',
      case when (select street from public.listing_addresses where listing_id = v_l) = 'HACKED'
           then 'WROTE (BAD)' else '0 rows affected (blocked by RLS)' end);
  exception when others then
    reset role;
    insert into res values ('8_stranger_write', 'ERROR: ' || sqlerrm);
  end;
end $$;

-- And listings itself must be clean for an ordinary guest.
do $$
declare v_s uuid; v_txt text;
begin
  select stranger into v_s from subj;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_s, 'role', 'authenticated')::text, true);
  select string_agg(distinct coalesce(address,'(null)'), ' | ') into v_txt
    from public.listings where is_active = true;
  reset role;
  insert into res values ('9_guest_sees_addresses', left(v_txt, 300));
end $$;

select jsonb_pretty(jsonb_object_agg(name, value)) as rls_test from res;
