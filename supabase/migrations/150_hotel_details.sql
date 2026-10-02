-- Migration 150: what a hotel listing describes, and how a host sets how many
-- rooms it sells.
--
-- Needs 149 COMMITTED first (55P04): the check constraint below names the
-- 'hotel' label, and a label cannot be used in the transaction that added it.
--
-- Three parts:
--
--   1. Columns. Three hotel-only facts (star rating, 24h front desk, ID at
--      check-in) guarded the way 121 guards turf's, plus three Room Matrix
--      facts (size, bathroom, toilet) that describe ANY stay and so carry no
--      type guard.
--   2. Amenity rows a hotel needs and the catalog did not have.
--   3. set_listing_unit_count -- the host's "this listing has N rooms". 147
--      gave every listing exactly one unit and no way to add another; a
--      hotel is the first type that needs more, but the function is
--      type-agnostic (a hostel's seats are units too).
--
-- Re-runnable: `if not exists` on columns, drop-then-add on constraints,
-- `on conflict do nothing` on rows, `or replace` on the function.

begin;

-- ---------------------------------------------------------------------------
-- 1. Columns
-- ---------------------------------------------------------------------------
alter table public.listings
  add column if not exists hotel_star_rating    smallint,
  add column if not exists hotel_front_desk_24h boolean,
  add column if not exists hotel_id_required    boolean,
  add column if not exists size_sqft            integer,
  add column if not exists bathroom_kind        text,
  add column if not exists toilet_kind          text;

alter table public.listings drop constraint if exists listings_hotel_star_rating_valid;
alter table public.listings drop constraint if exists listings_size_sqft_valid;
alter table public.listings drop constraint if exists listings_bathroom_kind_valid;
alter table public.listings drop constraint if exists listings_toilet_kind_valid;
alter table public.listings drop constraint if exists listings_hotel_fields_only_on_hotel;

alter table public.listings
  add constraint listings_hotel_star_rating_valid check (
    hotel_star_rating is null or hotel_star_rating between 1 and 5);

-- An upper bound because a typo of 50000 for 500 is the realistic failure,
-- and the listing page would print it.
alter table public.listings
  add constraint listings_size_sqft_valid check (
    size_sqft is null or size_sqft between 1 and 20000);

alter table public.listings
  add constraint listings_bathroom_kind_valid check (
    bathroom_kind is null or bathroom_kind in ('attached', 'common'));

-- 'indian' is what Bangladeshi listings call a squat toilet; it is a real
-- deciding factor for elderly and foreign guests, which is why the Room
-- Matrix sheet asks it at all.
alter table public.listings
  add constraint listings_toilet_kind_valid check (
    toilet_kind is null or toilet_kind in ('commode', 'indian'));

-- Same shape as listings_turf_fields_only_on_turf (121): a room carrying a
-- star rating is a data-entry accident the listing page would repeat. The
-- reverse is legal -- a hotel need not state its stars. The app's
-- scopeFieldsToType clears these when a host switches type away from hotel,
-- or this would refuse the save with 23514.
alter table public.listings
  add constraint listings_hotel_fields_only_on_hotel check (
    listing_type = 'hotel'
    or (hotel_star_rating is null and hotel_front_desk_24h is null
        and hotel_id_required is null));

comment on column public.listings.hotel_star_rating is
  'Star class the host claims, 1-5. Self-declared, not verified. Null for '
  'every non-hotel listing (listings_hotel_fields_only_on_hotel).';
comment on column public.listings.hotel_front_desk_24h is
  'Whether someone is at reception around the clock -- decides whether a '
  'late arrival can check in.';
comment on column public.listings.hotel_id_required is
  'Whether the hotel asks for NID/passport at check-in.';
comment on column public.listings.size_sqft is
  'Floor area of ONE unit, in square feet. Any stay type.';
comment on column public.listings.bathroom_kind is
  'attached = private to the unit; common = shared down the hall.';
comment on column public.listings.toilet_kind is
  'commode = sitting; indian = squat.';

-- ---------------------------------------------------------------------------
-- 2. Amenities. Matched BY NAME from lib/data/facility_catalog.dart (same
--    contract as 121/146): a name that disagrees does not error, the amenity
--    just never persists. Laundry Service already exists and is reused.
-- ---------------------------------------------------------------------------
insert into public.facilities (name, icon) values
  ('24h Front Desk',      'support_agent'),
  ('Room Service',        'room_service'),
  ('Restaurant',          'restaurant'),
  ('Breakfast Included',  'free_breakfast'),
  ('Housekeeping',        'cleaning_services'),
  ('Gym',                 'fitness_center'),
  ('Airport Pickup',      'airport_shuttle'),
  ('Luggage Storage',     'luggage'),
  ('In-room Safe',        'lock'),
  ('Keycard Access',      'key')
on conflict (name) do nothing;

-- ---------------------------------------------------------------------------
-- 3. set_listing_unit_count(listing, n) -> the active count afterwards.
--
--    Growing reactivates the oldest inactive units before inserting new
--    unlabelled ones, so a host who goes 10 -> 8 -> 10 gets the same two
--    rooms back (and their labels) rather than accumulating dead rows.
--
--    Shrinking deactivates, never deletes: bookings.unit_id references the
--    unit, and history must keep pointing somewhere. It only takes units with
--    no live future booking (pending/confirmed/active, ending after now()),
--    newest first, and it is all-or-nothing -- if fewer than needed are free
--    it refuses with hint `units_in_use` rather than shrinking part-way and
--    leaving the host to guess the result.
--
--    The race with create_marketplace_booking: that RPC picks a unit with
--    `for update of u skip locked` (148). Here the candidate units are locked
--    `for update` (waiting, not skipping) BEFORE their bookings are checked,
--    so a booking that already holds a unit finishes first and is then seen,
--    and one that starts after this lock skips the unit being retired. The
--    listing row is locked too, so two concurrent resizes serialise.
--
--    Definer because the bookings check must see every guest's booking, not
--    only what the host's RLS shows; the body does its own owner/admin check,
--    so EXECUTE is granted to authenticated only.
-- ---------------------------------------------------------------------------
create or replace function public.set_listing_unit_count(p_listing_id uuid, p_count integer)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_owner  uuid;
  v_active int;
  v_need   int;
  v_ids    uuid[];
  v_free   uuid[];
begin
  if p_count is null or p_count < 1 or p_count > 500 then
    raise exception 'A listing has between 1 and 500 units'
      using errcode = '22023', hint = 'unit_count_range';
  end if;

  select owner_id into v_owner from public.listings
   where id = p_listing_id for update;
  if not found then
    raise exception 'Listing not found' using errcode = 'P0002', hint = 'listing_not_found';
  end if;
  if v_owner is distinct from auth.uid() and not public.is_admin() then
    raise exception 'Only the host can change how many units a listing has'
      using errcode = '42501', hint = 'not_listing_owner';
  end if;

  select count(*) into v_active from public.listing_units
   where listing_id = p_listing_id and is_active;

  if p_count > v_active then
    v_need := p_count - v_active;
    update public.listing_units set is_active = true
     where id in (select id from public.listing_units
                   where listing_id = p_listing_id and not is_active
                   order by created_at, id limit v_need);
    get diagnostics v_active = row_count;
    v_need := v_need - v_active;
    if v_need > 0 then
      insert into public.listing_units (listing_id)
      select p_listing_id from generate_series(1, v_need);
    end if;

  elsif p_count < v_active then
    v_need := v_active - p_count;
    -- Lock every active unit first (waiting on any booking mid-flight), then
    -- judge them; a two-step so the bookings check runs after the locks.
    select array_agg(id) into v_ids from (
      select id from public.listing_units
       where listing_id = p_listing_id and is_active
       order by id for update) s;

    select array_agg(id) into v_free from (
      select u.id from public.listing_units u
       where u.id = any(v_ids)
         and not exists (
           select 1 from public.bookings b
            where b.unit_id = u.id
              and b.booking_status in ('pending', 'confirmed', 'active')
              and b.ends_at > now())
       order by u.created_at desc, u.id desc
       limit v_need) s;

    if coalesce(array_length(v_free, 1), 0) < v_need then
      raise exception 'Only % of the % units to remove have no upcoming booking',
        coalesce(array_length(v_free, 1), 0), v_need
        using errcode = '22023', hint = 'units_in_use';
    end if;

    update public.listing_units set is_active = false where id = any(v_free);
  end if;

  return (select count(*)::int from public.listing_units
           where listing_id = p_listing_id and is_active);
end $$;

revoke all on function public.set_listing_unit_count(uuid, integer) from public, anon, authenticated;
grant execute on function public.set_listing_unit_count(uuid, integer) to authenticated, service_role;

-- How many rooms a listing sells, for the host's own screens. Units are not
-- readable by guests (147), and the guest side gets availability through
-- listing_rooms_left; this is the host-side total, gated the same way.
create or replace function public.listing_unit_count(p_listing_id uuid)
returns integer
language sql stable security invoker set search_path = public as $$
  select count(*)::int from public.listing_units
   where listing_id = p_listing_id and is_active;
$$;
revoke all on function public.listing_unit_count(uuid) from public, anon;
grant execute on function public.listing_unit_count(uuid) to authenticated, service_role;

commit;
