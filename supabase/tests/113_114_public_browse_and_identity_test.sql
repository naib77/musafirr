-- Verification for 113_public_browse_grants.sql and
-- 114_verified_identity_enforcement.sql.
--
-- Proves the two halves of making Explore public: a signed-out visitor can read
-- everything the feed and a listing page need, can read nothing they shouldn't,
-- and cannot act -- while identity verification stops being a Dart-only
-- request and becomes a database rule.
--
-- Run wrapped in a transaction you roll back. It MUTATES profiles to construct
-- its subjects (roles and verification verdicts) and inserts listings, so the
-- rollback is not optional:
--
--   begin;
--   \i supabase/tests/113_114_public_browse_and_identity_test.sql
--   rollback;
--
-- Or against live through the Management API SQL endpoint with the file's
-- contents between `begin;` and `rollback;` -- see
-- scripts/dump_live_schema.py for how the CLI keychain token is read. There are
-- deliberately no psql metacommands in here, so it runs either way.
--
-- Must run as a superuser/table owner: it switches role to impersonate anon and
-- individual authenticated users, and it writes verification verdicts, which
-- 095's trigger only permits for an admin or a NULL uid.
--
-- Expected result -- and note rows 02-04 FAIL before 113, which is the point.
-- Measured on live pre-113: facilities 0, amenity search 0, chips 0.
--
--   BROWSE (anon must succeed)
--   01_anon_listings              >0 rows
--   02_anon_facilities            >0 rows      <- 0 before 113
--   03_anon_amenity_search        >0 rows      <- 0 before 113, silently
--   04_anon_amenity_chips         >0 rows      <- 0 before 113, silently
--   05_anon_listing_ratings       >0 rows
--   06_anon_blocked_ranges        >0 rows
--   07_anon_public_profiles       >0 rows
--
--   PRIVACY (anon must NOT succeed)
--   08_anon_listing_addresses     PERMISSION DENIED   (grant revoked by 093)
--   09_anon_bookings              0 rows
--   10_anon_profiles              0 rows
--   11_anon_blocks_table          0 rows              (host's private note)
--
--   IDENTITY (114)
--   12_unverified_book            IDENTITY BLOCKED
--   13_verified_book              passed identity check
--   14_unverified_publish         BLOCKED
--   15_verified_tenant_publish    BLOCKED   <- role gate; pre-114 an account
--                                              in this exact state published
--                                              three real listings
--   16_verified_owner_publish     ALLOWED

create temp table res(name text, value text);
grant all on res to public;

-- ---------------------------------------------------------------------------
-- Subjects, resolved from live data so this runs in any environment.
-- ---------------------------------------------------------------------------
do $$
declare
  v_listing uuid;
  v_blocked uuid;
  v_owner   uuid;   -- verified, role owner, has a listing
  v_unverif uuid;   -- role owner, verification forced to 'none'
  v_tenant  uuid;   -- verified, role forced to 'tenant'
begin
  select l.id into v_listing
    from public.listings l where l.is_active order by l.created_at limit 1;

  -- A listing that actually HAS blocks, so 06 distinguishes "readable" from
  -- "empty". Falls back to the subject listing when none exist.
  select coalesce((select listing_id from public.listing_availability_blocks limit 1),
                  v_listing)
    into v_blocked;

  select p.id into v_owner
    from public.profiles p
    join public.listings l on l.owner_id = p.id
   where p.verification_status = 'verified' and p.role = 'owner'
   limit 1;

  -- The other two are CONSTRUCTED, not found. The interesting combinations are
  -- not guaranteed to exist -- in particular a VERIFIED account with role
  -- 'tenant', which is the only thing that isolates the role gate from the
  -- identity gate. Rolled back with everything else.
  select p.id into v_unverif from public.profiles p
   where p.id <> v_owner order by p.created_at limit 1;
  select p.id into v_tenant from public.profiles p
   where p.id <> v_owner and p.id <> v_unverif order by p.created_at limit 1;

  update public.profiles set role = 'owner',  verification_status = 'none'
   where id = v_unverif;
  update public.profiles set role = 'tenant', verification_status = 'verified'
   where id = v_tenant;

  create temp table subj(listing uuid, blocked uuid, owner uuid,
                         unverif uuid, tenant uuid);
  grant all on subj to public;
  insert into subj values (v_listing, v_blocked, v_owner, v_unverif, v_tenant);
  insert into res values ('00_subjects',
    format('listing=%s blocked=%s owner=%s unverified=%s verified_tenant=%s',
           v_listing, v_blocked, v_owner, v_unverif, v_tenant));
end $$;

-- ---------------------------------------------------------------------------
-- Reusable reader
-- ---------------------------------------------------------------------------

-- Counts rows from an arbitrary query as `who`/`uid`, recording a permission
-- error as such rather than letting it abort the run. That distinction is the
-- whole of 08 vs 09-11: a revoked GRANT and an empty RLS result look identical
-- to a client but mean very different things.
create or replace function pg_temp.chk(label text, who text, uid uuid, q text)
returns void language plpgsql as $$
declare n bigint;
begin
  begin
    execute format('set local role %I', who);
    perform set_config('request.jwt.claims',
      json_build_object('sub', uid, 'role', who)::text, true);
    execute q into n;
    reset role;
    insert into res values (label, n::text || ' rows');
  exception when insufficient_privilege then
    reset role;
    insert into res values (label, 'PERMISSION DENIED');
  end;
end $$;
grant execute on function pg_temp.chk(text, text, uuid, text) to public;

-- BROWSE -------------------------------------------------------------------
-- anon carries no sub claim; the zero uuid stands in for "nobody".
select pg_temp.chk('01_anon_listings', 'anon', '00000000-0000-0000-0000-000000000000',
  'select count(*) from public.listings');
select pg_temp.chk('02_anon_facilities', 'anon', '00000000-0000-0000-0000-000000000000',
  'select count(*) from public.facilities');
-- Uses the most-used real amenity name rather than a guess: an amenity nobody
-- has returns zero for everyone and would pass vacuously.
select pg_temp.chk('03_anon_amenity_search', 'anon', '00000000-0000-0000-0000-000000000000',
  $q$select count(*) from public.search_listings(
       p_amenities => array[(select f.name from public.listing_facilities lf
                               join public.facilities f on f.id = lf.facility_id
                              group by f.name order by count(*) desc limit 1)])$q$);
select pg_temp.chk('04_anon_amenity_chips', 'anon', '00000000-0000-0000-0000-000000000000',
  $q$select coalesce((select jsonb_array_length(s->'listing_facilities')
                        from public.search_listings() s
                       where jsonb_array_length(s->'listing_facilities') > 0
                       limit 1), 0)$q$);
select pg_temp.chk('05_anon_listing_ratings', 'anon', '00000000-0000-0000-0000-000000000000',
  'select count(*) from public.listing_ratings');
select pg_temp.chk('06_anon_blocked_ranges', 'anon', '00000000-0000-0000-0000-000000000000',
  'select count(*) from public.listing_blocked_ranges((select blocked from subj))');
select pg_temp.chk('07_anon_public_profiles', 'anon', '00000000-0000-0000-0000-000000000000',
  'select count(*) from public.public_profiles');

-- PRIVACY ------------------------------------------------------------------
select pg_temp.chk('08_anon_listing_addresses', 'anon', '00000000-0000-0000-0000-000000000000',
  'select count(*) from public.listing_addresses');
select pg_temp.chk('09_anon_bookings', 'anon', '00000000-0000-0000-0000-000000000000',
  'select count(*) from public.bookings');
select pg_temp.chk('10_anon_profiles', 'anon', '00000000-0000-0000-0000-000000000000',
  'select count(*) from public.profiles');
-- The TABLE, not the function: it carries the host's private `note`, which is
-- why 110 made its SELECT policy owner-scoped and gave guests the function.
select pg_temp.chk('11_anon_blocks_table', 'anon', '00000000-0000-0000-0000-000000000000',
  'select count(*) from public.listing_availability_blocks');

-- IDENTITY (114) -----------------------------------------------------------

-- Asserts on the identity check BY ITS HINT, never its prose -- the mistake
-- bookingConflictTypeFrom was rewritten to stop making. A verified caller then
-- trips some later rule (dates, pricing, availability) and that counts as a
-- pass: 111 already covers those, and re-pinning them here would break this
-- test every time seed data moves.
create or replace function pg_temp.try_book(label text, uid uuid)
returns void language plpgsql as $$
declare v_l uuid; v_hint text;
begin
  select listing into v_l from subj;
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
      json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform public.create_marketplace_booking(
      v_l, now() + interval '400 days', now() + interval '402 days',
      'day', 1, 'Test Guest', null, null);
    reset role;
    insert into res values (label, 'passed identity check');
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    reset role;
    insert into res values (label,
      case when v_hint = 'identity_unverified'
           then 'IDENTITY BLOCKED'
           else 'passed identity check' end);
  end;
end $$;
grant execute on function pg_temp.try_book(text, uuid) to public;

select pg_temp.try_book('12_unverified_book', (select unverif from subj));
select pg_temp.try_book('13_verified_book',   (select owner   from subj));

-- Publishing. `title` is the only NOT NULL column without a default, so the
-- insert stays minimal -- anything more would couple this test to the listings
-- schema for no gain.
create or replace function pg_temp.try_publish(label text, uid uuid)
returns void language plpgsql as $$
begin
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
      json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    insert into public.listings (owner_id, title) values (uid, '114 test listing');
    reset role;
    insert into res values (label, 'ALLOWED');
  exception when insufficient_privilege or check_violation then
    reset role;
    insert into res values (label, 'BLOCKED');
  end;
end $$;
grant execute on function pg_temp.try_publish(text, uuid) to public;

select pg_temp.try_publish('14_unverified_publish',      (select unverif from subj));
select pg_temp.try_publish('15_verified_tenant_publish', (select tenant  from subj));
select pg_temp.try_publish('16_verified_owner_publish',  (select owner   from subj));

select name, value from res order by name;
