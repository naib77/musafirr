-- 155: hotel amenities.
--
-- 1. New amenity rows. The in-room ones are things a guest compares room types
--    on (kettle, toiletries, bathtub ...); the hotel-level ones are things
--    ShareTrip-style listings show once per hotel (tour desk, wheelchair
--    access, event hall ...). Names must match lib/data/facility_catalog.dart:
--    the app saves amenities by name and silently skips a name with no row.
--
-- 2. Hotel-wide amenities belong to the hotel. Before this, a host with five
--    room types ticked "Gym", "Restaurant" and "CCTV Security" five times,
--    and the room types disagreed whenever they forgot one. Now the hotel
--    holds them (`property_facilities`) and the database copies them onto
--    every room type's `listing_facilities`.
--
--    The copy stays in `listing_facilities` on purpose: search_listings'
--    amenity filter, the listing page and every older bundle read that table,
--    so a room type keeps answering "has a gym?" without any of them
--    changing.
--
--    The catch is that the app saves a listing's amenities by deleting all of
--    its rows and inserting the ticked ones (_saveListingFacilities), and the
--    room-type form no longer shows hotel-wide amenities. Two guard triggers
--    make that harmless, whatever bundle is doing it:
--      * a delete of a row the hotel provides is skipped (return null), so
--        the delete-all leaves the hotel's rows in place;
--      * an insert of a row that already exists is skipped, so an older
--        bundle that re-sends the hotel's amenities does not hit the
--        (listing_id, facility_id) unique index with 23505.
--    "Provided by the hotel" is decided by looking at property_facilities,
--    not by a flag on the row, so a listing delete (cascade: the listing is
--    already gone) and the hotel removing an amenity (the property row is
--    already gone) both delete normally.

-- ---------------------------------------------------------------------------
-- 1. New amenities.
insert into public.facilities (name, icon) values
  -- In the room
  ('Kettle',                'coffee_maker'),
  ('Toiletries',            'soap'),
  ('Slippers',              'dry_cleaning'),
  ('Hairdryer',             'air'),
  ('Iron',                  'iron'),
  ('Minibar',               'liquor'),
  ('Telephone',             'phone'),
  ('Bathtub',               'bathtub'),
  -- The hotel
  ('Tour Desk',             'tour'),
  ('Wheelchair Accessible', 'accessible'),
  ('Event Hall',            'groups'),
  ('Family Friendly',       'family_restroom'),
  ('Beach Access',          'beach_access')
on conflict (name) do nothing;

-- ---------------------------------------------------------------------------
-- 2. The hotel's amenities.
create table if not exists public.property_facilities (
  property_id uuid not null references public.properties(id) on delete cascade,
  facility_id uuid not null references public.facilities(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (property_id, facility_id)
);
create index if not exists property_facilities_facility_idx
  on public.property_facilities (facility_id);

alter table public.property_facilities enable row level security;

-- Visible exactly when the hotel is (properties_select runs inside the
-- exists): public once it has a live room type, else owner and admin only.
drop policy if exists property_facilities_select on public.property_facilities;
create policy property_facilities_select on public.property_facilities
  for select to anon, authenticated
  using (exists (select 1 from public.properties p
                  where p.id = property_facilities.property_id));

drop policy if exists property_facilities_owner_insert on public.property_facilities;
create policy property_facilities_owner_insert on public.property_facilities
  for insert to authenticated
  with check (exists (select 1 from public.properties p
                       where p.id = property_facilities.property_id
                         and p.owner_id = auth.uid())
              or public.is_admin());

drop policy if exists property_facilities_owner_delete on public.property_facilities;
create policy property_facilities_owner_delete on public.property_facilities
  for delete to authenticated
  using (exists (select 1 from public.properties p
                  where p.id = property_facilities.property_id
                    and p.owner_id = auth.uid())
         or public.is_admin());

-- No update: a row is a pair of ids, so a change is a delete and an insert,
-- and both of those go through the push-down below.
revoke all on table public.property_facilities from public, anon, authenticated;
grant select on table public.property_facilities to anon, authenticated;
grant insert, delete on table public.property_facilities to authenticated;
grant all on table public.property_facilities to service_role;

-- ---------------------------------------------------------------------------
-- 3. Guards on listing_facilities (see the header).
create or replace function public.fn_listing_facility_keep_hotel_row()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1
               from public.listings l
               join public.property_facilities pf on pf.property_id = l.property_id
              where l.id = old.listing_id and pf.facility_id = old.facility_id) then
    return null;
  end if;
  return old;
end $$;
revoke all on function public.fn_listing_facility_keep_hotel_row() from public, anon, authenticated;
drop trigger if exists trg_listing_facility_keep_hotel_row on public.listing_facilities;
create trigger trg_listing_facility_keep_hotel_row
  before delete on public.listing_facilities
  for each row execute function public.fn_listing_facility_keep_hotel_row();

create or replace function public.fn_listing_facility_skip_duplicate()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.listing_facilities lf
              where lf.listing_id = new.listing_id and lf.facility_id = new.facility_id) then
    return null;
  end if;
  return new;
end $$;
revoke all on function public.fn_listing_facility_skip_duplicate() from public, anon, authenticated;
drop trigger if exists trg_listing_facility_skip_duplicate on public.listing_facilities;
create trigger trg_listing_facility_skip_duplicate
  before insert on public.listing_facilities
  for each row execute function public.fn_listing_facility_skip_duplicate();

-- ---------------------------------------------------------------------------
-- 4. Push-down: the hotel's amenities onto its room types.
create or replace function public.fn_property_facility_push()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.listing_facilities (listing_id, facility_id)
    select l.id, new.facility_id from public.listings l
     where l.property_id = new.property_id
    on conflict (listing_id, facility_id) do nothing;
    return null;
  end if;
  -- Hotel-wide means hotel-wide: removing it from the hotel removes it from
  -- every room type, including one that had it ticked before 155. The guard
  -- lets these through because the property_facilities row is already gone.
  delete from public.listing_facilities lf
   using public.listings l
   where l.id = lf.listing_id and l.property_id = old.property_id
     and lf.facility_id = old.facility_id;
  return null;
end $$;
revoke all on function public.fn_property_facility_push() from public, anon, authenticated;
drop trigger if exists trg_property_facility_push on public.property_facilities;
create trigger trg_property_facility_push
  after insert or delete on public.property_facilities
  for each row execute function public.fn_property_facility_push();

-- A room type joining a hotel (new, or moved) gets the hotel's amenities.
-- One leaving keeps what it had: those are its rows now, and the guard no
-- longer protects them, so the host can untick them like any other.
create or replace function public.fn_listing_property_facilities()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.property_id is not null
     and (tg_op = 'INSERT' or new.property_id is distinct from old.property_id) then
    insert into public.listing_facilities (listing_id, facility_id)
    select new.id, pf.facility_id from public.property_facilities pf
     where pf.property_id = new.property_id
    on conflict (listing_id, facility_id) do nothing;
  end if;
  return null;
end $$;
revoke all on function public.fn_listing_property_facilities() from public, anon, authenticated;
drop trigger if exists trg_listing_property_facilities on public.listings;
create trigger trg_listing_property_facilities
  after insert or update of property_id on public.listings
  for each row execute function public.fn_listing_property_facilities();

-- ---------------------------------------------------------------------------
-- 5. Backfill. A hotel-wide amenity any of a hotel's room types has becomes
-- the hotel's (and so, through the push-down, every type's): if one type
-- says the hotel has a gym, it has a gym. The names are the hotel-level
-- groups of FacilityCatalog.hotelPropertyGroups.
insert into public.property_facilities (property_id, facility_id)
select distinct l.property_id, lf.facility_id
  from public.listings l
  join public.listing_facilities lf on lf.listing_id = l.id
  join public.facilities f on f.id = lf.facility_id
 where l.property_id is not null
   and f.name in (
     -- Hotel services
     '24h Front Desk', 'Room Service', 'Restaurant', 'Housekeeping',
     'Laundry Service', 'Luggage Storage', 'Airport Pickup', 'Tour Desk',
     -- The building
     'Car Parking', 'Bike Parking', 'Elevator', 'Gym', 'Swimming Pool',
     'Prayer Space', 'Shared Workspace', 'Wheelchair Accessible',
     'Event Hall', 'Family Friendly', 'Beach Access',
     -- Power
     'Backup Generator', 'Power Backup (IPS)',
     -- Safety
     'Smoke Alarm', 'Fire Extinguisher', 'First Aid Kit', 'CCTV Security',
     'Security Guard')
on conflict do nothing;
