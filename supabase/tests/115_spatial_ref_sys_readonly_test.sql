-- Verification for 115_spatial_ref_sys_readonly.sql.
--
-- Proves the PostGIS reference table cannot be written by any role PostgREST
-- can hand a request to, that the platform can still maintain it, and that the
-- guard did not cost us the geography reads the whole app runs on.
--
-- Run wrapped in a transaction you roll back. It attempts real writes against
-- spatial_ref_sys -- the rollback is not optional:
--
--   begin;
--   \i supabase/tests/115_spatial_ref_sys_readonly_test.sql
--   rollback;
--
-- Or against live through the Management API SQL endpoint with the file's
-- contents between `begin;` and `rollback;` -- see scripts/dump_live_schema.py
-- for how the CLI keychain token is read. There are deliberately no psql
-- metacommands in here, so it runs either way.
--
-- Must run as postgres (or the table owner): it switches role to impersonate
-- anon, authenticated and service_role.
--
-- Expected result -- rows 01-06 all FAIL before 115, which is the point.
-- Measured on live pre-115: every one of them ALLOWED, and 07 returned 0 rows
-- (an emptied table), which is the outage this migration exists to prevent.
--
--   WRITES (every API role must be blocked)
--   01_anon_insert                BLOCKED     <- ALLOWED before 115
--   02_anon_update                BLOCKED     <- ALLOWED before 115
--   03_anon_delete                BLOCKED     <- ALLOWED before 115
--   04_anon_truncate              BLOCKED     <- ALLOWED before 115, and NOT
--                                                caught by the row-level
--                                                trigger alone
--   05_authenticated_delete       BLOCKED     <- ALLOWED before 115
--   06_service_role_delete        BLOCKED     <- ALLOWED before 115
--
--   MAINTENANCE (must still work)
--   07_postgres_write             ALLOWED
--
--   READS (must be untouched -- search depends on them)
--   08_anon_select_4326           1
--   09_anon_geography_search      ALLOWED

create temp table res (name text, value text) on commit drop;

-- Each attempt runs in its own subtransaction so a raise does not poison the
-- outer one, and resets role on both paths -- a test that leaves the session
-- as anon would silently mis-report every row after the first failure.
--
-- 42501 arrives as insufficient_privilege. A check_violation would mean the
-- write got PAST the trigger and was stopped by PostGIS's own srid range
-- constraint, which is emphatically not "blocked" for our purposes, so it is
-- deliberately not caught here.
create or replace function pg_temp.try_write(label text, role_name text, stmt text)
returns void language plpgsql as $$
begin
  begin
    execute format('set local role %I', role_name);
    execute stmt;
    reset role;
    insert into res values (label, 'ALLOWED');
  exception when insufficient_privilege then
    reset role;
    insert into res values (label, 'BLOCKED');
  end;
end $$;
grant execute on function pg_temp.try_write(text, text, text) to public;

-- 990000 is inside PostGIS's own `srid > 0 and srid <= 998999` check and holds
-- no row, so a rejected insert here is the trigger talking and nothing else.
select pg_temp.try_write('01_anon_insert', 'anon',
  $q$insert into public.spatial_ref_sys(srid,auth_name,auth_srid,srtext,proj4text)
     values (990000,'test',1,'t','t')$q$);
select pg_temp.try_write('02_anon_update', 'anon',
  $q$update public.spatial_ref_sys set auth_name='pwned' where srid=4326$q$);
select pg_temp.try_write('03_anon_delete', 'anon',
  $q$delete from public.spatial_ref_sys where srid=4326$q$);
-- The one that a row-level trigger does not see. anon holds TRUNCATE (`D`).
select pg_temp.try_write('04_anon_truncate', 'anon',
  $q$truncate public.spatial_ref_sys$q$);
select pg_temp.try_write('05_authenticated_delete', 'authenticated',
  $q$delete from public.spatial_ref_sys where srid=4326$q$);
-- service_role is not reachable with the anon key, but it is what a leaked
-- service key would hold, and it has no business rewriting EPSG data either.
select pg_temp.try_write('06_service_role_delete', 'service_role',
  $q$delete from public.spatial_ref_sys where srid=4326$q$);

-- Platform maintenance must survive: `alter extension postgis update` rewrites
-- this table, and a restore repopulates it. A guard that blocked those would
-- trade a security hole for an upgrade failure.
do $$
begin
  begin
    insert into public.spatial_ref_sys(srid,auth_name,auth_srid,srtext,proj4text)
      values (990000,'test',1,'t','t');
    delete from public.spatial_ref_sys where srid=990000;
    insert into res values ('07_postgres_write', 'ALLOWED');
  exception when insufficient_privilege then
    insert into res values ('07_postgres_write', 'BLOCKED');
  end;
end $$;

-- Reads are deliberately untouched. PostGIS resolves SRID 4326 through this
-- table under the caller's own privileges, so anon must keep SELECT or
-- `search_listings` (SECURITY INVOKER) stops working -- which is the very
-- outage 115 prevents, arrived at from the other direction.
-- Read as anon, then reset BEFORE recording: anon has no INSERT on a temp
-- table owned by postgres, so writing the result while still impersonating
-- fails the whole script with a permission error that looks like a finding and
-- is not one.
do $$
declare n bigint;
begin
  execute 'set local role anon';
  select count(*) into n from public.spatial_ref_sys where srid = 4326;
  reset role;
  insert into res values ('08_anon_select_4326', n::text);
end $$;

do $$
declare n bigint;
begin
  begin
    execute 'set local role anon';
    select count(*) into n from public.listings
      where st_dwithin(geog,
                       st_setsrid(st_makepoint(90.4125, 23.8103), 4326)::geography,
                       5000);
    reset role;
    insert into res values ('09_anon_geography_search', 'ALLOWED');
  exception when others then
    reset role;
    insert into res values ('09_anon_geography_search', 'FAILED: ' || sqlerrm);
  end;
end $$;

select name, value from res order by name;
