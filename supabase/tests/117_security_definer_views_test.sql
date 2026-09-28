-- Verification for 117_security_definer_views.sql.
--
-- The load-bearing assertion is view_escalation: before 117 an anon UPDATE
-- through public_profiles set a host's role to admin; after, it is refused and
-- the role is unchanged. The rest guards against a fix that closes the hole by
-- breaking the app -- host names must still render, search must still return,
-- and the two ratings views must read as the caller now.
--
-- Mutating (it writes role in a subtxn that is caught, and it revokes grants),
-- so it MUST run inside a transaction you roll back:
--
--   begin;
--   \i supabase/tests/117_security_definer_views_test.sql
--   rollback;
--
-- Or against live via the Management API with the body between begin/rollback.
-- No psql metacommands, so it runs either way. Must run as postgres: it
-- impersonates anon and reads the catalog.
--
-- Every row PASS. Before 117, rows 01/02/07 FAIL (escalation succeeds, both
-- ratings views are definer) -- that is the point.

create temp table res(name text, value text) on commit drop;
create temp table victim on commit drop as
  select id, role from public.profiles where is_host order by created_at limit 1;
grant select on victim to anon;

-- 01 -- the escalation. Caught in a subtxn so a raise does not abort the file.
do $$
begin
  execute 'set local role anon';
  begin
    update public.public_profiles set role='admin' where id=(select id from victim);
    reset role; insert into res values ('01_view_escalation','ALLOWED -- VULNERABLE');
  exception when insufficient_privilege then
    reset role; insert into res values ('01_view_escalation','BLOCKED');
  end;
end $$;

-- 02 -- and the row is untouched either way (belt to 01's braces)
insert into res select '02_victim_role_unchanged',
  case when p.role = v.role then 'UNCHANGED' else 'MUTATED to '||p.role::text end
  from victim v join public.profiles p on p.id = v.id;

-- 03 -- anon can still read the public projection (host names)
do $$ declare n int; begin
  execute 'set local role anon'; select count(*) into n from public.public_profiles; reset role;
  insert into res values ('03_anon_reads_public_profiles', n::text || ' rows');
end $$;

-- 04 -- search still works for a signed-out visitor (it joins the view)
do $$ declare n int; begin
  execute 'set local role anon'; select count(*) into n from search_listings(); reset role;
  insert into res values ('04_anon_search_listings', n::text || ' rows');
exception when others then reset role;
  insert into res values ('04_anon_search_listings','ERROR '||sqlerrm);
end $$;

-- 05 -- anon no longer holds a direct grant on the profiles table
do $$ declare ok text; begin
  execute 'set local role anon';
  begin perform 1 from public.profiles limit 1; ok:='STILL GRANTED';
  exception when insufficient_privilege then ok:='REVOKED'; end;
  reset role; insert into res values ('05_anon_profiles_table_grant', ok);
end $$;

-- 06 -- public_profiles is DELIBERATELY still a definer view (see migration).
insert into res select '06_public_profiles_is_definer',
  case when coalesce(array_to_string(reloptions,','),'') ~ 'security_invoker=(true|on)'
       then 'INVOKER -- would break host-name reads'
       else 'DEFINER (intended)' end
  from pg_class where oid='public.public_profiles'::regclass;

-- 07 -- the two aggregate views ARE invoker now, so they read as the caller
--       and stop leaking unrevealed reviews into public averages
insert into res
  select '07_'||relname||'_invoker',
         case when coalesce(array_to_string(reloptions,','),'') ~ 'security_invoker=(true|on)'
              then 'INVOKER' else 'DEFINER -- leaks unrevealed reviews' end
    from pg_class
   where oid in ('public.listing_ratings'::regclass,'public.guest_ratings'::regclass);

select name,
       value,
       case
         when name like '01%' then case when value='BLOCKED' then 'PASS' else 'FAIL' end
         when name like '02%' then case when value='UNCHANGED' then 'PASS' else 'FAIL' end
         when name like '05%' then case when value='REVOKED' then 'PASS' else 'FAIL' end
         when name like '06%' then case when value like 'DEFINER%' then 'PASS' else 'FAIL' end
         when name like '07%' then case when value='INVOKER' then 'PASS' else 'FAIL' end
         when name like '03%' or name like '04%'
           then case when value ~ '^[1-9][0-9]* rows$' then 'PASS' else 'FAIL' end
         else '?'
       end as verdict
  from res order by name;
