-- 059 — Let authenticated users read the facilities catalog
--
-- The live `facilities` table had RLS enabled with ZERO policies, so
-- authenticated users could read none of its 22 rows. Effects:
--   * Saving a listing's amenities silently no-ops: _saveListingFacilities()
--     reads the catalog to map names -> ids, gets an empty set, inserts nothing.
--   * Any join to facilities (explore feed, listing detail) returns no amenity
--     names for guests or hosts.
--
-- 001_initial_schema.sql declares "facilities_read_authenticated" but it was
-- not present on the live database (migration drift). This restores it.
-- The catalog is non-sensitive reference data, so a blanket read is correct.

drop policy if exists "facilities_read_authenticated" on public.facilities;

create policy "facilities_read_authenticated"
on public.facilities
for select
to authenticated
using (true);
