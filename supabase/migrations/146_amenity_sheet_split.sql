-- 146: the amenity set from the product sheets (Amenities / Space Features /
-- Security, 2026-10-01).
--
-- Three new plain amenities: Freezer (a separate appliance from Refrigerator
-- here -- a deep freezer is its own purchase in Bangladesh), Laundry Service
-- and Swimming Pool.
--
-- Three amenities the sheet qualifies are SPLIT, because `facilities` is a
-- yes/no catalog and a qualifier on the join row would mean teaching
-- search_listings' p_amenities match a second dimension:
--   Parking   -> Car Parking   / Bike Parking
--   Kitchen   -> Shared Kitchen / Private Kitchen
--   Workspace -> Shared Workspace / Private Workspace
--
-- The generic rows are NOT deleted. A turf still offers plain Parking (121
-- reuses the stay row), and a client still running a pre-146 bundle -- the
-- web entry point can be served stale from the edge, see CLAUDE.md -- keeps
-- writing the old names; deleting the rows would make that save skip them
-- silently. Dart upgrades such a set on the next edit
-- (FacilityCatalog.upgradeLegacy), using the same rule as the backfill below.
--
-- Names are matched BY NAME from Dart and an unknown one is silently skipped
-- (see 121), so these must equal lib/data/facility_catalog.dart exactly.
begin;

insert into public.facilities (name, icon) values
  ('Freezer',            'kitchen_outlined'),
  ('Laundry Service',    'local_laundry_service_outlined'),
  ('Swimming Pool',      'pool_outlined'),
  ('Car Parking',        'local_parking_outlined'),
  ('Bike Parking',       'two_wheeler_outlined'),
  ('Shared Kitchen',     'soup_kitchen_outlined'),
  ('Private Kitchen',    'soup_kitchen_outlined'),
  ('Shared Workspace',   'desk_outlined'),
  ('Private Workspace',  'desk_outlined')
on conflict (name) do nothing;

-- Backfill stays that carry a generic amenity. Nobody recorded which kind it
-- was, so this is a rule, not a fact, and the host can correct it:
--   * a full house is the guest's alone, so its kitchen/workspace is private;
--     a room or seat shares the rest of the home, so it is shared.
--   * plain Parking on a stay becomes Car Parking -- a listing that says
--     "parking" in Dhaka means a garage slot; bike parking is the extra.
-- Turfs are left alone: plain Parking is still their amenity.
with mapping(old_name, kind, new_name) as (values
  ('Kitchen',   'fullHouse', 'Private Kitchen'),
  ('Kitchen',   'shared',    'Shared Kitchen'),
  ('Workspace', 'fullHouse', 'Private Workspace'),
  ('Workspace', 'shared',    'Shared Workspace'),
  ('Parking',   'fullHouse', 'Car Parking'),
  ('Parking',   'shared',    'Car Parking')
), legacy as (
  select lf.id, lf.listing_id, m.new_name
  from public.listing_facilities lf
  join public.facilities f on f.id = lf.facility_id
  join public.listings l on l.id = lf.listing_id
  join mapping m on m.old_name = f.name
   and m.kind = case when l.listing_type = 'fullHouse' then 'fullHouse' else 'shared' end
  where l.listing_type is distinct from 'turf'
), added as (
  insert into public.listing_facilities (listing_id, facility_id)
  select distinct lg.listing_id, nf.id
  from legacy lg join public.facilities nf on nf.name = lg.new_name
  on conflict (listing_id, facility_id) do nothing
  returning 1
)
delete from public.listing_facilities lf
using legacy lg
where lf.id = lg.id;

commit;
