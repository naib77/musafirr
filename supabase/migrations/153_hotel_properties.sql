-- 153_hotel_properties.sql
--
-- A hotel sells several room types (docs/plans/hotel-room-types.md). Until
-- now a hotel listing WAS one room type, so a hotel with four types was four
-- unrelated listings: four cards in search, the star rating and location
-- typed four times and drifting, four licences, reviews split four ways.
--
-- Option A of the plan: a listing stays one room type -- every price, capacity,
-- unit and booking rule already lives there and does not change -- and a new
-- parent row, `properties`, holds what belongs to the hotel. A listing with a
-- `property_id` is a room type of that hotel.
--
--   1. properties: the hotel's own facts and photos. Readable by anyone once
--      it has a live room type; written by its owner. Its exact address is
--      private (property_addresses) and copied into each type's
--      listing_addresses, which is what a booked guest sees.
--   2. listings.property_id, and a trigger that COPIES the hotel's facts onto
--      each room type on every write. Copy, not refuse: the deployed edit
--      form sends every column on save, and a refusal would break it; a copy
--      makes a child's own value for those columns meaningless, which is the
--      point. Search, the PostGIS filter and the detail screen keep reading
--      `listings` as before.
--   3. Room names unique across the hotel (active rooms only): a hotel has
--      one room 101, whichever type it is sold as.
--   4. add_listing_units / deactivate_listing_unit / move_listing_unit: the
--      host's named-room operations. 152 left hosts `update (label)` on units
--      and nothing else; that stays, these are definer functions with their
--      own checks.
--   5. listing_licence_verified answers for the hotel: one verified licence
--      badges every room type of it.
--   6. Backfill: every existing hotel listing becomes a hotel with one type.
--
-- Hotels without a property keep working exactly as before (the cached web
-- bundle creates them); nothing here requires one.

begin;

-- ---------------------------------------------------------------------------
-- 1. properties
-- ---------------------------------------------------------------------------
-- Location is stored the way listings store it (area-level address, snapped
-- coordinates; enforce_listing_public_location), because these are the
-- values copied onto every room type and then shown to guests.
create table if not exists public.properties (
  id                    uuid primary key default gen_random_uuid(),
  owner_id              uuid not null references public.profiles(id) on delete cascade,
  kind                  text not null default 'hotel',
  name                  text not null,
  description           text,
  area                  text,
  city                  text,
  country               text,
  postal_code           text,
  landmark              text,
  latitude              numeric,
  longitude             numeric,
  check_in_time         text,
  check_out_time        text,
  hotel_star_rating     smallint,
  hotel_front_desk_24h  boolean,
  hotel_id_required     boolean,
  image_urls            text[] not null default '{}',
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  -- Only hotels for now (plan R4); the column leaves room for guest houses.
  constraint properties_kind_valid check (kind in ('hotel')),
  constraint properties_name_len check (char_length(btrim(name)) between 1 and 120),
  constraint properties_description_len check (description is null or char_length(description) <= 5000),
  constraint properties_star_rating_valid check (hotel_star_rating is null or hotel_star_rating between 1 and 5),
  constraint properties_images_cap check (cardinality(image_urls) <= 30)
);

comment on table public.properties is
  'A hotel (153). Its room types are listings with property_id = id; the hotel facts here are copied onto them on every write.';

create index if not exists properties_owner_idx on public.properties (owner_id);

create or replace function public.fn_property_normalise()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.owner_id is distinct from old.owner_id then
    raise exception 'A hotel cannot change owner'
      using errcode = '42501', hint = 'property_owner_fixed';
  end if;
  new.name := btrim(new.name);
  new.latitude  := public.snap_coordinate(new.latitude);
  new.longitude := public.snap_coordinate(new.longitude);
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists trg_property_normalise on public.properties;
create trigger trg_property_normalise
  before insert or update on public.properties
  for each row execute function public.fn_property_normalise();

-- A suspended host cannot write a hotel either (same guard as listings).
drop trigger if exists trg_refuse_suspended_writer on public.properties;
create trigger trg_refuse_suspended_writer
  before insert or update on public.properties
  for each row execute function public.fn_refuse_suspended_writer();

-- ---------------------------------------------------------------------------
-- 2. listings.property_id and the copy-down
-- ---------------------------------------------------------------------------
-- No action on delete: a hotel with room types cannot be deleted; the host
-- removes the types first (a type with bookings cannot be deleted at all).
alter table public.listings
  add column if not exists property_id uuid references public.properties(id);
create index if not exists listings_property_idx
  on public.listings (property_id) where property_id is not null;

-- Named `a_…` so it fires before enforce_listing_public_location (BEFORE
-- triggers run in name order): the copied area and coordinates must be the
-- ones that get snapped and turned into `geog`.
create or replace function public.fn_listing_property_inherit()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_p public.properties;
begin
  if tg_op = 'UPDATE' and old.property_id is not null
     and new.property_id is distinct from old.property_id then
    raise exception 'A room type cannot leave its hotel'
      using errcode = '42501', hint = 'property_fixed';
  end if;
  if new.property_id is null then
    return new;
  end if;

  select * into v_p from public.properties where id = new.property_id;
  if not found then
    raise exception 'Hotel not found' using errcode = 'P0002', hint = 'property_not_found';
  end if;
  if v_p.owner_id is distinct from new.owner_id then
    raise exception 'A room type belongs to the hotel''s own host'
      using errcode = '42501', hint = 'property_owner_mismatch';
  end if;
  if new.listing_type::text <> 'hotel' then
    raise exception 'A hotel''s room types are hotel listings'
      using errcode = '22023', hint = 'property_child_type';
  end if;

  -- Joining a hotel (insert, or adopting an existing listing): its active
  -- room names must not collide with the hotel's.
  if (tg_op = 'INSERT' or old.property_id is null) and exists (
       select 1 from public.listing_units mine
         join public.listing_units theirs
           on lower(btrim(theirs.label)) = lower(btrim(mine.label))
         join public.listings l on l.id = theirs.listing_id
        where mine.listing_id = new.id and mine.is_active and mine.label is not null
          and theirs.is_active and l.property_id = new.property_id and l.id <> new.id) then
    raise exception 'A room of this type has a name the hotel already uses'
      using errcode = '23505', hint = 'room_label_taken';
  end if;

  new.area                 := v_p.area;
  new.city                 := v_p.city;
  new.country              := v_p.country;
  new.postal_code          := v_p.postal_code;
  new.landmark             := v_p.landmark;
  new.latitude             := v_p.latitude;
  new.longitude            := v_p.longitude;
  new.check_in_time        := v_p.check_in_time;
  new.check_out_time       := v_p.check_out_time;
  new.hotel_star_rating    := v_p.hotel_star_rating;
  new.hotel_front_desk_24h := v_p.hotel_front_desk_24h;
  new.hotel_id_required    := v_p.hotel_id_required;
  return new;
end $$;
drop trigger if exists a_listing_property_inherit on public.listings;
create trigger a_listing_property_inherit
  before insert or update on public.listings
  for each row execute function public.fn_listing_property_inherit();

-- An edit to the hotel reaches every room type now, not on their next save.
-- The latitude/longitude in the SET list matter: trg_set_listing_geog is an
-- `update of latitude, longitude` trigger and fires on named columns only.
create or replace function public.fn_property_push_down()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.listings
     set area = new.area, city = new.city, country = new.country,
         postal_code = new.postal_code, landmark = new.landmark,
         latitude = new.latitude, longitude = new.longitude,
         check_in_time = new.check_in_time, check_out_time = new.check_out_time,
         hotel_star_rating = new.hotel_star_rating,
         hotel_front_desk_24h = new.hotel_front_desk_24h,
         hotel_id_required = new.hotel_id_required,
         updated_at = now()
   where property_id = new.id;
  return null;
end $$;
drop trigger if exists trg_property_push_down on public.properties;
create trigger trg_property_push_down
  after update on public.properties
  for each row execute function public.fn_property_push_down();

-- RLS. Public once the hotel has a live room type: a hotel with nothing to
-- book is a draft. The inner select runs under listings' own RLS, which
-- already hides inactive listings from guests.
alter table public.properties enable row level security;

drop policy if exists properties_select on public.properties;
create policy properties_select on public.properties
  for select to anon, authenticated
  using (owner_id = auth.uid()
         or public.is_admin()
         or exists (select 1 from public.listings l
                     where l.property_id = properties.id and l.is_active
                       and not coalesce(l.suspended_hidden, false)));

drop policy if exists properties_owner_insert on public.properties;
create policy properties_owner_insert on public.properties
  for insert to authenticated
  with check (owner_id = auth.uid());

drop policy if exists properties_owner_update on public.properties;
create policy properties_owner_update on public.properties
  for update to authenticated
  using (owner_id = auth.uid() or public.is_admin())
  with check (owner_id = auth.uid() or public.is_admin());

drop policy if exists properties_owner_delete on public.properties;
create policy properties_owner_delete on public.properties
  for delete to authenticated
  using (owner_id = auth.uid());

revoke all on table public.properties from public, anon, authenticated;
grant select on table public.properties to anon, authenticated;
grant insert, update, delete on table public.properties to authenticated;
grant all on table public.properties to service_role;

-- The exact address, private the way listing_addresses is. `properties`
-- holds the area-level, snapped location that guests browse; the street and
-- the precise pin go here, and are copied into each room type's
-- listing_addresses row, which is what a booked guest is shown
-- (can_see_listing_address). Owner and admin only.
create table if not exists public.property_addresses (
  property_id    uuid primary key references public.properties(id) on delete cascade,
  house_no       text,
  street         text,
  exact_address  text,
  latitude       numeric,
  longitude      numeric,
  updated_at     timestamptz not null default now()
);
alter table public.property_addresses enable row level security;

drop policy if exists property_addresses_owner_all on public.property_addresses;
create policy property_addresses_owner_all on public.property_addresses
  for all to authenticated
  using (exists (select 1 from public.properties p
                  where p.id = property_addresses.property_id and p.owner_id = auth.uid())
         or public.is_admin())
  with check (exists (select 1 from public.properties p
                       where p.id = property_addresses.property_id and p.owner_id = auth.uid())
              or public.is_admin());

revoke all on table public.property_addresses from public, anon, authenticated;
grant select, insert, update, delete on table public.property_addresses to authenticated;
grant all on table public.property_addresses to service_role;

-- Copies one hotel's exact address onto its room types (all of them, or one).
create or replace function public.fn_copy_property_address(p_property_id uuid, p_listing_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.listing_addresses
    (listing_id, house_no, flat_floor, street, exact_address, latitude, longitude)
  select l.id, a.house_no, null, a.street, a.exact_address, a.latitude, a.longitude
    from public.property_addresses a
    join public.listings l on l.property_id = a.property_id
   where a.property_id = p_property_id
     and (p_listing_id is null or l.id = p_listing_id)
  on conflict (listing_id) do update
    set house_no = excluded.house_no, flat_floor = null, street = excluded.street,
        exact_address = excluded.exact_address,
        latitude = excluded.latitude, longitude = excluded.longitude;
end $$;
revoke all on function public.fn_copy_property_address(uuid, uuid) from public, anon, authenticated;

create or replace function public.fn_property_address_touch()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists trg_property_address_touch on public.property_addresses;
create trigger trg_property_address_touch
  before insert or update on public.property_addresses
  for each row execute function public.fn_property_address_touch();

create or replace function public.fn_property_address_copy_all()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.fn_copy_property_address(new.property_id);
  return null;
end $$;
drop trigger if exists trg_property_address_copy on public.property_addresses;
create trigger trg_property_address_copy
  after insert or update on public.property_addresses
  for each row execute function public.fn_property_address_copy_all();

-- A room type joining a hotel gets its address at once.
create or replace function public.fn_listing_property_address()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.property_id is not null
     and (tg_op = 'INSERT' or old.property_id is distinct from new.property_id) then
    perform public.fn_copy_property_address(new.property_id, new.id);
  end if;
  return null;
end $$;
drop trigger if exists trg_listing_property_address on public.listings;
create trigger trg_listing_property_address
  after insert or update of property_id on public.listings
  for each row execute function public.fn_listing_property_address();

-- ---------------------------------------------------------------------------
-- 3. Room names unique across the hotel
-- ---------------------------------------------------------------------------
-- Active rooms only: a retired room keeps its name for the bookings that
-- name it, and must not block a new room of that name. Case- and
-- space-insensitive, because "101 " and "101" is the same door. The hotel
-- row is locked so two concurrent adds of the same name serialise.
create or replace function public.fn_unit_label_unique_in_property()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_prop uuid;
begin
  if not new.is_active or new.label is null then
    return new;
  end if;
  select property_id into v_prop from public.listings where id = new.listing_id;
  if v_prop is null then
    return new;
  end if;
  perform 1 from public.properties where id = v_prop for update;
  if exists (select 1 from public.listing_units u
               join public.listings l on l.id = u.listing_id
              where l.property_id = v_prop and u.is_active and u.id <> new.id
                and lower(btrim(u.label)) = lower(btrim(new.label))) then
    raise exception 'This hotel already has a room named %', new.label
      using errcode = '23505', hint = 'room_label_taken';
  end if;
  return new;
end $$;
drop trigger if exists trg_unit_label_unique_in_property on public.listing_units;
create trigger trg_unit_label_unique_in_property
  before insert or update of label, is_active, listing_id on public.listing_units
  for each row execute function public.fn_unit_label_unique_in_property();

-- ---------------------------------------------------------------------------
-- 4. Named-room operations
-- ---------------------------------------------------------------------------
-- The caller must own the listing (or be an admin), the listing row is
-- locked so these serialise with set_listing_unit_count, and the bookings
-- checks are the same as 150's shrink (pending/confirmed/active, not ended).

create or replace function public.fn_lock_own_listing(p_listing_id uuid)
returns public.listings
language plpgsql security definer set search_path = public as $$
declare v public.listings;
begin
  select * into v from public.listings where id = p_listing_id for update;
  if not found then
    raise exception 'Listing not found' using errcode = 'P0002', hint = 'listing_not_found';
  end if;
  if v.owner_id is distinct from auth.uid() and not public.is_admin() then
    raise exception 'Only the host can change this listing''s rooms'
      using errcode = '42501', hint = 'not_listing_owner';
  end if;
  return v;
end $$;
-- An internal helper; definer, so closed to every client role.
revoke all on function public.fn_lock_own_listing(uuid) from public, anon, authenticated;

-- Adds named rooms. A name the listing used before and retired is brought
-- back (same row, so its old bookings and the new ones read as one room);
-- an active one is a duplicate. With p_name_unnamed, active unnamed rooms
-- that never had a booking are named first: a new room type starts with
-- 147's implicit unnamed unit, and "rooms 101–105" means five rooms, not six.
create or replace function public.add_listing_units(
  p_listing_id uuid,
  p_labels text[],
  p_name_unnamed boolean default false
) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_labels text[];
  v_label  text;
  v_unit   uuid;
  v_total  int;
begin
  perform public.fn_lock_own_listing(p_listing_id);

  select coalesce(array_agg(btrim(l) order by o), '{}') into v_labels
    from unnest(p_labels) with ordinality t(l, o)
   where nullif(btrim(l), '') is not null;
  if cardinality(v_labels) = 0 or cardinality(v_labels) > 200 then
    raise exception 'Add between 1 and 200 rooms at a time'
      using errcode = '22023', hint = 'unit_count_range';
  end if;
  if exists (select 1 from unnest(v_labels) l where char_length(l) > 40) then
    raise exception 'A room name is at most 40 characters'
      using errcode = '22023', hint = 'room_label_invalid';
  end if;
  if (select count(distinct lower(l)) from unnest(v_labels) l) <> cardinality(v_labels) then
    raise exception 'The same room name is listed twice'
      using errcode = '22023', hint = 'room_label_duplicate';
  end if;

  foreach v_label in array v_labels loop
    v_unit := null;
    select id into v_unit from public.listing_units
     where listing_id = p_listing_id and lower(btrim(label)) = lower(v_label);
    if v_unit is not null then
      update public.listing_units set is_active = true
       where id = v_unit and not is_active;
      if not found then
        raise exception 'This listing already has a room named %', v_label
          using errcode = '23505', hint = 'room_label_taken';
      end if;
      continue;
    end if;

    if p_name_unnamed then
      select u.id into v_unit from public.listing_units u
       where u.listing_id = p_listing_id and u.is_active and u.label is null
         and not exists (select 1 from public.bookings b where b.unit_id = u.id)
       order by u.created_at, u.id
       limit 1;
    end if;
    if v_unit is not null then
      update public.listing_units set label = v_label where id = v_unit;
    else
      insert into public.listing_units (listing_id, label) values (p_listing_id, v_label);
    end if;
  end loop;

  select count(*) into v_total from public.listing_units
   where listing_id = p_listing_id and is_active;
  if v_total > 500 then
    raise exception 'A listing has between 1 and 500 units'
      using errcode = '22023', hint = 'unit_count_range';
  end if;
  return v_total;
end $$;

-- Retires one named room. Deactivate, never delete: past bookings name it.
create or replace function public.deactivate_listing_unit(p_unit_id uuid)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_listing uuid;
  v_active  boolean;
begin
  select listing_id into v_listing from public.listing_units where id = p_unit_id;
  if not found then
    raise exception 'Room not found' using errcode = 'P0002', hint = 'unit_not_found';
  end if;
  perform public.fn_lock_own_listing(v_listing);
  -- Locked after the listing, waiting: a booking mid-flight on this room
  -- finishes first and is then seen below (150's ordering).
  select is_active into v_active from public.listing_units where id = p_unit_id for update;

  if v_active then
    if (select count(*) from public.listing_units
         where listing_id = v_listing and is_active) <= 1 then
      raise exception 'A listing keeps at least one room'
        using errcode = '22023', hint = 'unit_count_range';
    end if;
    if exists (select 1 from public.bookings b
                where b.unit_id = p_unit_id
                  and b.booking_status in ('pending', 'confirmed', 'active')
                  and b.ends_at > now()) then
      raise exception 'This room has an upcoming booking'
        using errcode = '22023', hint = 'units_in_use';
    end if;
    update public.listing_units set is_active = false where id = p_unit_id;
  end if;

  return (select count(*)::int from public.listing_units
           where listing_id = v_listing and is_active);
end $$;

-- Re-classifies a room into another type of the same hotel ("206 is a
-- Super Deluxe now"). The room's history stays with the old type: the unit
-- there is retired and the target gains a unit of the same name (or gets
-- its own retired one back), because bookings.unit_id must keep naming a
-- unit of the booking's listing (147).
create or replace function public.move_listing_unit(p_unit_id uuid, p_to_listing_id uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_unit   public.listing_units;
  v_from   public.listings;
  v_to     public.listings;
  v_target uuid;
begin
  select * into v_unit from public.listing_units where id = p_unit_id;
  if not found or not v_unit.is_active then
    raise exception 'Room not found' using errcode = 'P0002', hint = 'unit_not_found';
  end if;
  if v_unit.listing_id = p_to_listing_id then
    return p_unit_id;
  end if;
  -- Both listings, in id order so two opposite moves cannot deadlock.
  if v_unit.listing_id < p_to_listing_id then
    v_from := public.fn_lock_own_listing(v_unit.listing_id);
    v_to   := public.fn_lock_own_listing(p_to_listing_id);
  else
    v_to   := public.fn_lock_own_listing(p_to_listing_id);
    v_from := public.fn_lock_own_listing(v_unit.listing_id);
  end if;
  if v_from.property_id is null or v_from.property_id is distinct from v_to.property_id then
    raise exception 'A room moves only between types of the same hotel'
      using errcode = '22023', hint = 'unit_move_other_property';
  end if;

  perform public.deactivate_listing_unit(p_unit_id);

  select id into v_target from public.listing_units
   where listing_id = p_to_listing_id
     and lower(btrim(label)) is not distinct from lower(btrim(v_unit.label))
     and label is not null;
  if v_target is not null then
    update public.listing_units set is_active = true where id = v_target;
  else
    insert into public.listing_units (listing_id, label)
    values (p_to_listing_id, v_unit.label)
    returning id into v_target;
  end if;
  return v_target;
end $$;

revoke all on function public.add_listing_units(uuid, text[], boolean) from public, anon, authenticated;
grant execute on function public.add_listing_units(uuid, text[], boolean) to authenticated, service_role;
revoke all on function public.deactivate_listing_unit(uuid) from public, anon, authenticated;
grant execute on function public.deactivate_listing_unit(uuid) to authenticated, service_role;
revoke all on function public.move_listing_unit(uuid, uuid) from public, anon, authenticated;
grant execute on function public.move_listing_unit(uuid, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. The licence badge answers for the hotel
-- ---------------------------------------------------------------------------
-- The licence names the premises, so a verified one on any room type of the
-- hotel badges them all. Each licence row still needs its own listing to be
-- a hotel and its file to exist (152's conditions, unchanged).
create or replace function public.listing_licence_verified(p_listing_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1
      from public.listings me
      join public.listings l
        on l.id = me.id or (me.property_id is not null and l.property_id = me.property_id)
      join public.listing_trade_licences t on t.listing_id = l.id
     where me.id = p_listing_id
       and me.listing_type::text = 'hotel'
       and l.listing_type::text = 'hotel'
       and t.status = 'verified'
       and exists (select 1 from storage.objects o
                    where o.bucket_id = 'documents' and o.name = t.document_path)
  );
$$;
revoke all on function public.listing_licence_verified(uuid) from public;
grant execute on function public.listing_licence_verified(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Backfill: every hotel listing today is a hotel with one room type
-- ---------------------------------------------------------------------------
-- The listing's title names the hotel for now; the host renames either.
-- `address` is not carried: it is derived from area/city/postal code.
do $$
declare r record; v_id uuid;
begin
  for r in select * from public.listings
            where listing_type::text = 'hotel' and property_id is null loop
    insert into public.properties
      (owner_id, name, description, area, city, country, postal_code, landmark,
       latitude, longitude, check_in_time, check_out_time, hotel_star_rating,
       hotel_front_desk_24h, hotel_id_required, image_urls)
    values
      (r.owner_id, left(coalesce(nullif(btrim(r.title), ''), 'Hotel'), 120),
       left(r.description, 5000), r.area, r.city, r.country, r.postal_code,
       r.landmark, r.latitude, r.longitude, r.check_in_time, r.check_out_time,
       r.hotel_star_rating, r.hotel_front_desk_24h, r.hotel_id_required,
       coalesce(r.image_urls[1:30], '{}'))
    returning id into v_id;
    -- The exact address first, so the copy-down that the property_id
    -- update triggers writes the same values back, not nothing.
    insert into public.property_addresses (property_id, house_no, street, exact_address, latitude, longitude)
    select v_id, a.house_no, a.street, a.exact_address, a.latitude, a.longitude
      from public.listing_addresses a where a.listing_id = r.id;
    update public.listings set property_id = v_id where id = r.id;
  end loop;
end $$;

commit;
