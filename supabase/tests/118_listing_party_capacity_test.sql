-- Verification for 118_listing_party_capacity.sql.
--
-- Mutating (it inserts listings), so it MUST run inside a transaction you roll
-- back:
--
--   begin;
--   \i supabase/tests/118_listing_party_capacity_test.sql
--   rollback;
--
-- Or against live via the Management API with the body between begin/rollback.
-- No psql metacommands, so it runs either way.
--
-- Every row PASS. Before 118 the whole file errors at the first `max_adults`
-- (column does not exist) rather than reporting FAIL -- which is its own clear
-- signal, and the reason row 01 checks the columns are actually there first.
--
-- The load-bearing rows are 05 (a null cap must NOT hide a listing -- that is
-- what would break all 40 existing rows) and 09 (a pet must not surface a
-- place that never agreed to one).

create temp table res(name text, value text) on commit drop;

-- A host to hang the fixtures off. Any owner will do; the predicate under test
-- never looks at ownership.
create temp table fixture_owner on commit drop as
  select id from public.profiles order by created_at limit 1;

-- Five listings covering the interesting shapes. All are active, available and
-- unblocked so that nothing but the party predicate can exclude them.
insert into public.listings
  (id, owner_id, title, description, listing_type, city, area, country,
   daily_rate, is_active, host_available, max_guests,
   max_adults, max_children, max_infants, max_pets, pets_allowed)
select
  x.id, (select id from fixture_owner), x.title, 'party capacity fixture',
  'room', 'Dhaka', 'Uttara', 'Bangladesh',
  1000, true, true, x.max_guests,
  x.max_adults, x.max_children, x.max_infants, x.max_pets, x.pets_allowed
from (values
  -- Unset everywhere: the shape every listing that predates 118 has.
  ('11111111-1111-1111-1111-111111111111'::uuid, 'zz_unset',
   8, null::int, null::int, null::int, null::int, false),
  -- Adults capped at 2, children at 1, under a roomy total.
  ('22222222-2222-2222-2222-222222222222'::uuid, 'zz_capped',
   8, 2, 1, 0, null, false),
  -- Pets welcome, at most one.
  ('33333333-3333-3333-3333-333333333333'::uuid, 'zz_one_pet',
   8, null, null, null, 1, true),
  -- Pets welcome with no stated number.
  ('44444444-4444-4444-4444-444444444444'::uuid, 'zz_pets_any',
   8, null, null, null, null, true),
  -- Adults only: max_children is 0, which is a STATED rule and must behave
  -- differently from the null on zz_unset.
  ('55555555-5555-5555-5555-555555555555'::uuid, 'zz_adults_only',
   8, null, 0, null, null, false)
) as x(id, title, max_guests, max_adults, max_children, max_infants,
       max_pets, pets_allowed);

-- Does search_listings return the named fixture for this party?
create or replace function pg_temp.finds(
  p_title text, p_adults int, p_children int, p_infants int, p_pets int
) returns boolean language sql as $$
  select exists (
    select 1
    from public.search_listings(
      p_guest_count => greatest(coalesce(p_adults,0) + coalesce(p_children,0), 1),
      p_limit       => 500,
      p_adults      => p_adults,
      p_children    => p_children,
      p_infants     => p_infants,
      p_pets        => p_pets
    ) r
    where r->>'title' = p_title
  );
$$;

-- 01 -- the columns exist and are nullable (the migration's own precondition)
insert into res
select '01_columns_nullable',
       string_agg(column_name || '=' || is_nullable, ',' order by column_name)
  from information_schema.columns
 where table_schema = 'public' and table_name = 'listings'
   and column_name in ('max_adults','max_children','max_infants','max_pets');

-- 02 -- a listing that states no limits is unaffected by ANY party. This is
--       the compatibility guarantee: every pre-118 row must keep matching
--       exactly what it matched before.
insert into res values ('02_unset_matches_plain',
  case when pg_temp.finds('zz_unset', 4, 0, 0, 0) then 'FOUND' else 'HIDDEN' end);
insert into res values ('02b_unset_matches_children',
  case when pg_temp.finds('zz_unset', 2, 4, 2, 0) then 'FOUND' else 'HIDDEN' end);

-- 03 -- a party inside every cap is found
insert into res values ('03_within_caps',
  case when pg_temp.finds('zz_capped', 2, 1, 0, 0) then 'FOUND' else 'HIDDEN' end);

-- 04 -- one adult too many, and the listing goes. The total (8) is nowhere
--       near reached, so ONLY max_adults can be doing this.
insert into res values ('04_too_many_adults',
  case when pg_temp.finds('zz_capped', 3, 0, 0, 0) then 'FOUND -- cap ignored' else 'HIDDEN' end);

-- 05 -- and one child too many, likewise
insert into res values ('05_too_many_children',
  case when pg_temp.finds('zz_capped', 1, 2, 0, 0) then 'FOUND -- cap ignored' else 'HIDDEN' end);

-- 06 -- max_children = 0 is a real rule (adults only) and must exclude a
--       child, where the null on zz_unset (row 02b) admits four. This is the
--       pair that proves zero and null are not the same value.
insert into res values ('06_zero_children_excludes_a_child',
  case when pg_temp.finds('zz_adults_only', 1, 1, 0, 0) then 'FOUND -- cap ignored' else 'HIDDEN' end);
insert into res values ('06b_zero_children_admits_adults',
  case when pg_temp.finds('zz_adults_only', 2, 0, 0, 0) then 'FOUND' else 'HIDDEN' end);

-- 07 -- infants: capped at 0 on zz_capped, so one infant excludes it even
--       though infants never tell against max_guests
insert into res values ('07_infant_over_cap',
  case when pg_temp.finds('zz_capped', 2, 1, 1, 0) then 'FOUND -- cap ignored' else 'HIDDEN' end);

-- 08 -- asking for no pets must not disturb anything, including a place that
--       does not take them. p_pets = 0 has to be inert, not "pets_allowed".
insert into res values ('08_zero_pets_is_inert',
  case when pg_temp.finds('zz_unset', 2, 0, 0, 0) then 'FOUND' else 'HIDDEN' end);

-- 09 -- THE pets rule: a listing that never opted in is excluded outright,
--       not merely capped. pets_allowed is false and max_pets is null on
--       zz_unset, and null must NOT be read as "no limit" here.
insert into res values ('09_pet_excludes_non_pet_listing',
  case when pg_temp.finds('zz_unset', 1, 0, 0, 1) then 'FOUND -- VULNERABLE' else 'HIDDEN' end);

-- 10 -- a pet-friendly listing with a number is found up to that number
insert into res values ('10_pet_within_number',
  case when pg_temp.finds('zz_one_pet', 1, 0, 0, 1) then 'FOUND' else 'HIDDEN' end);

-- 11 -- and hidden past it
insert into res values ('11_pet_over_number',
  case when pg_temp.finds('zz_one_pet', 1, 0, 0, 2) then 'FOUND -- cap ignored' else 'HIDDEN' end);

-- 12 -- pets_allowed with no number means "allowed, no stated limit", NOT none
insert into res values ('12_pets_allowed_no_number',
  case when pg_temp.finds('zz_pets_any', 1, 0, 0, 3) then 'FOUND' else 'HIDDEN' end);

-- 13 -- the total is still the backstop: 9 people exceeds max_guests = 8
--       regardless of the per-category caps being generous or absent.
insert into res values ('13_total_still_applies',
  case when pg_temp.finds('zz_unset', 9, 0, 0, 0) then 'FOUND -- total ignored' else 'HIDDEN' end);

-- 14 -- omitting the four arguments entirely (a pre-118 client) returns the
--       fixtures unfiltered. This is what makes the deploy order irrelevant.
insert into res
select '14_legacy_arity_unfiltered',
       count(*)::text || ' of 5'
  from public.search_listings(p_guest_count => 1, p_limit => 500) r
 where r->>'title' like 'zz_%';

-- 15 -- an anon caller can still run the new signature (search is public, and
--       116/112's grant lessons say to check rather than assume)
do $$ declare n int; begin
  execute 'set local role anon';
  select count(*) into n from public.search_listings(
    p_guest_count => 2, p_limit => 5, p_adults => 2, p_children => 0,
    p_infants => 0, p_pets => 0);
  reset role;
  insert into res values ('15_anon_can_call', 'OK');
exception when others then reset role;
  insert into res values ('15_anon_can_call', 'ERROR ' || sqlerrm);
end $$;

-- 16 -- the constraints refuse nonsense
do $$ begin
  update public.listings set max_adults = 0
   where id = '11111111-1111-1111-1111-111111111111';
  insert into res values ('16_zero_adults_refused', 'ACCEPTED -- no constraint');
exception when check_violation then
  insert into res values ('16_zero_adults_refused', 'REFUSED');
end $$;

do $$ begin
  update public.listings set max_pets = -1
   where id = '11111111-1111-1111-1111-111111111111';
  insert into res values ('17_negative_pets_refused', 'ACCEPTED -- no constraint');
exception when check_violation then
  insert into res values ('17_negative_pets_refused', 'REFUSED');
end $$;

select name,
       value,
       case
         when name like '01%' then
           case when value = 'max_adults=YES,max_children=YES,max_infants=YES,max_pets=YES'
                then 'PASS' else 'FAIL' end
         when name in ('02_unset_matches_plain','02b_unset_matches_children',
                       '03_within_caps','08_zero_pets_is_inert',
                       '10_pet_within_number','12_pets_allowed_no_number',
                       '06b_zero_children_admits_adults')
           then case when value = 'FOUND' then 'PASS' else 'FAIL' end
         when name like '04%' or name like '05%' or name like '06%'
           or name like '07%' or name like '09%' or name like '11%'
           or name like '13%'
           then case when value = 'HIDDEN' then 'PASS' else 'FAIL' end
         when name like '14%' then
           case when value = '5 of 5' then 'PASS' else 'FAIL' end
         when name like '15%' then
           case when value = 'OK' then 'PASS' else 'FAIL' end
         when name like '16%' or name like '17%' then
           case when value = 'REFUSED' then 'PASS' else 'FAIL' end
         else '?'
       end as verdict
  from res order by name;
