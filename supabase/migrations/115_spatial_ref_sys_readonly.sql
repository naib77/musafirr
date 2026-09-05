-- 115: make public.spatial_ref_sys unwritable through the API.
--
-- The Supabase linter reports this table as "public, but RLS has not been
-- enabled". That undersells it considerably.
--
-- Migration 001 creates PostGIS with `create extension if not exists postgis`
-- and no schema, so it lands in `public` — the schema PostgREST exposes — and
-- brings its own reference tables with it. The extension grants those to every
-- API role. Read off live's relacl:
--
--     anon=arwdDxtm/supabase_admin
--     authenticated=arwdDxtm/supabase_admin
--
-- a=INSERT r=SELECT w=UPDATE d=DELETE D=TRUNCATE. So this is not a missing
-- read policy, it is unauthenticated *write* access. Confirmed against live
-- rather than inferred from the catalog: an anonymous caller holding nothing
-- but the anon key that is compiled into the shipped web bundle gets
--
--     DELETE /rest/v1/spatial_ref_sys   ->   HTTP 204
--
-- and 8,500 rows of EPSG definitions go with it.
--
-- That is an availability bug, not a tidiness one. Geography operations
-- resolve their spheroid through this table, so an emptied spatial_ref_sys
-- turns every one of them into
--
--     ERROR: XX000: Cannot find SRID (4326) in spatial_ref_sys
--
-- which is `search_listings`, the radius tiers, the landmark ring, the geog
-- trigger on listing insert, and the default explore feed (an undated
-- `searchListingsFromDb(const SearchFilters())`). One unauthenticated HTTP
-- request takes marketplace search down until someone restores the table.
--
-- ── Why a trigger, when the linter asks for RLS ────────────────────────────
--
-- Because every more direct remedy is refused on this project. Each of these
-- was tried against live:
--
--     alter table public.spatial_ref_sys enable row level security;
--       -> 42501: must be owner of table spatial_ref_sys
--     alter table public.spatial_ref_sys owner to postgres;
--       -> 42501: must be owner of table spatial_ref_sys
--     alter extension postgis set schema extensions;
--       -> refused; pg_extension.extrelocatable = false for postgis
--
-- The table is owned by `supabase_admin`. Our `postgres` is not a superuser
-- and is not a member of that role, so the linter's own suggested remediation
-- is not executable here.
--
-- The REVOKE is the dangerous one, and it is the reason this file is long:
-- it is permitted, it reports success, and it does nothing.
--
--     revoke insert, update, delete, truncate
--       on public.spatial_ref_sys from anon, authenticated;
--
-- leaves relacl byte-identical, because a non-owner may only revoke grants it
-- made itself and these were made by supabase_admin. A migration built on that
-- REVOKE would apply green, record itself in schema_migrations, and leave the
-- hole exactly where it was. Do not "simplify" this file back into one.
--
-- What `postgres` does hold on this table is `t` — TRIGGER. That is the entire
-- lever available, so the read-only rule is enforced with one.
--
-- ── Both triggers are load-bearing ─────────────────────────────────────────
--
-- TRUNCATE does not fire row-level triggers, and anon holds `D`. Verified:
-- with only the row-level trigger installed, `set role anon; truncate
-- public.spatial_ref_sys;` left 0 rows behind. A row-only guard is therefore a
-- false fix — it looks correct and still loses the table to a one-word
-- statement. Removing the statement-level trigger below reopens the hole in
-- full.
--
-- ── SELECT is deliberately left alone ──────────────────────────────────────
--
-- Reads are not the problem: this is EPSG reference data, published standards,
-- no user data in it. It is also load-bearing — PostGIS resolves SRID 4326
-- through this table under the *caller's* own privileges, so `search_listings`
-- (SECURITY INVOKER, running as anon) needs to read it for search to work at
-- all. Blocking reads here would break exactly what this migration protects.

create or replace function public.fn_spatial_ref_sys_readonly()
returns trigger
language plpgsql
as $$
begin
  -- current_user, not session_user. PostgREST connects as `authenticator` and
  -- then SET ROLEs to anon/authenticated/service_role, so session_user is
  -- `authenticator` for every API request and would tell us nothing about who
  -- is actually asking. current_user is the role the statement runs as, which
  -- is the thing being gated — and it also means an impersonation test
  -- (`set local role anon`) exercises the same path a real request does.
  if current_user in ('postgres', 'supabase_admin')
     or coalesce((select rolsuper from pg_roles
                   where rolname = current_user), false)
  then
    -- Platform maintenance still has to work: `alter extension postgis update`
    -- rewrites this table, and a restore repopulates it. Both run as an owner
    -- or a superuser, neither of which is reachable through PostgREST.
    if tg_level = 'STATEMENT' then
      return null;  -- ignored for BEFORE TRUNCATE; OLD/NEW are unassigned here
    end if;
    return case tg_op when 'DELETE' then old else new end;
  end if;

  raise exception using
    errcode = '42501',
    message = format(
      'spatial_ref_sys is read-only reference data (attempted %s as %s)',
      tg_op, current_user),
    hint = 'PostGIS reference data is maintained by the platform, not the API.';
end;
$$;

comment on function public.fn_spatial_ref_sys_readonly() is
  'Blocks API-role writes to the PostGIS spatial_ref_sys table. RLS cannot be '
  'enabled on it (owned by supabase_admin) and the grants cannot be revoked '
  '(granted by supabase_admin), so a trigger is the only available guard. '
  'See migration 115.';

drop trigger if exists trg_spatial_ref_sys_readonly on public.spatial_ref_sys;
create trigger trg_spatial_ref_sys_readonly
  before insert or update or delete on public.spatial_ref_sys
  for each row execute function public.fn_spatial_ref_sys_readonly();

-- Not a duplicate of the above: TRUNCATE fires only statement-level triggers.
drop trigger if exists trg_spatial_ref_sys_no_truncate on public.spatial_ref_sys;
create trigger trg_spatial_ref_sys_no_truncate
  before truncate on public.spatial_ref_sys
  for each statement execute function public.fn_spatial_ref_sys_readonly();
