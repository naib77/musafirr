-- 093_listing_address_privacy.sql
--
-- A listing's exact address names a host's front door. Until now `public.listings`
-- held `address`, `house_no`, `flat_floor`, `street` and the exact
-- `latitude`/`longitude`, and both `anon` and `authenticated` held SELECT on all
-- 49 columns with a policy of `is_active = true OR auth.uid() = owner_id`. So
-- anyone holding the publishable anon key could read every active listing's
-- street address — and, alongside the booking calendar, work out when the place
-- was empty. The app redacts this in its UI, but a UI is not an access control.
--
-- The fix is row-level rather than column-level, because that is the only thing
-- Postgres can actually enforce per-viewer:
--
--   * `public.listings` structurally CANNOT hold a door-level address or an
--     exact coordinate any more. The door-identifying columns are gone, and a
--     BEFORE trigger derives `address` from area/city and snaps the coordinates
--     to a ~110m grid on every write. A buggy or malicious client cannot put a
--     precise location back in.
--   * The exact address moves to `public.listing_addresses`, one row per
--     listing, with RLS that admits only the owner, an admin, or a guest whose
--     booking the host has ACCEPTED (confirmed / active / completed).
--
-- Deliberately NOT column-level REVOKE on `public.listings`: `search_listings`
-- is SECURITY INVOKER and selects `to_jsonb(l)`, and the admin portal selects
-- `address` by name — revoking columns would break both, while row-level
-- policies leave them working untouched.
--
-- Coordinates are snapped to a FIXED grid, never randomly jittered: a random
-- offset re-rolled per read can be averaged over enough samples to recover the
-- true point, whereas a fixed grid reveals nothing beyond which cell a listing
-- is in. The app draws a 300m circle around the snapped point, which comfortably
-- contains the true position (worst-case offset ~55m).

begin;

-- ---------------------------------------------------------------------------
-- 1. The redaction rules, in one place so the trigger, the backfill and any
--    future caller cannot disagree about them.
-- ---------------------------------------------------------------------------

-- The public form of an address: area and city (with postcode, which is
-- thana-level in Bangladesh and identifies nobody). House, flat and road are
-- exactly what must not appear.
create or replace function public.listing_area_address(
  p_area        text,
  p_city        text,
  p_postal_code text
) returns text
language sql
immutable
as $$
  select nullif(
    concat_ws(', ',
      nullif(btrim(coalesce(p_area, '')), ''),
      nullif(btrim(concat_ws(' ',
        nullif(btrim(coalesce(p_city, '')), ''),
        nullif(btrim(coalesce(p_postal_code, '')), '')
      )), '')
    ),
  '');
$$;

comment on function public.listing_area_address(text, text, text) is
  'Area-level address shown to anyone without an accepted booking. Never includes house/flat/road.';

-- ~0.001 degrees is ~110m of latitude, so the true point stays within ~55m of
-- the snapped one. Must match ListingLocation._gridDegrees in the Flutter app,
-- or the app''s circle will be centred somewhere the server did not intend.
create or replace function public.snap_coordinate(p_degrees numeric)
returns numeric
language sql
immutable
as $$
  select round(p_degrees / 0.001) * 0.001;
$$;

comment on function public.snap_coordinate(numeric) is
  'Snaps a coordinate to a fixed ~110m grid. Fixed, not random: random jitter can be averaged away to recover the true point.';

-- ---------------------------------------------------------------------------
-- 2. Where the exact address lives from now on.
-- ---------------------------------------------------------------------------

create table if not exists public.listing_addresses (
  listing_id    uuid primary key
                  references public.listings(id) on delete cascade,
  house_no      text,
  flat_floor    text,
  street        text,
  -- The full composed line, as the host entered it. Kept alongside the parts so
  -- a reader does not have to re-compose it (and so historical formatting is
  -- preserved for rows written before the structured columns existed).
  exact_address text,
  latitude      numeric,
  longitude     numeric,
  updated_at    timestamptz not null default now()
);

comment on table public.listing_addresses is
  'Exact street address and coordinates per listing. Readable only by the owner, an admin, or a guest with an accepted booking (RLS). public.listings holds the redacted, area-level version.';

create or replace function public.touch_listing_address()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_touch_listing_address on public.listing_addresses;
create trigger trg_touch_listing_address
  before update on public.listing_addresses
  for each row execute function public.touch_listing_address();

-- Carry the existing exact data across BEFORE it is redacted below.
insert into public.listing_addresses (
  listing_id, house_no, flat_floor, street, exact_address, latitude, longitude)
select l.id, l.house_no, l.flat_floor, l.street, l.address, l.latitude, l.longitude
from public.listings l
on conflict (listing_id) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Who may read it.
-- ---------------------------------------------------------------------------

-- SECURITY DEFINER so the policy below does not re-enter the RLS of `listings`
-- and `bookings` (and so an inactive listing still resolves for its owner).
-- Mirrors the existing public.is_admin() pattern.
create or replace function public.can_see_listing_address(p_listing_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    -- Admins run the safety/verification queues and need the real address.
    public.is_admin()
    -- The host knows their own address.
    or exists (
      select 1 from public.listings l
      where l.id = p_listing_id and l.owner_id = auth.uid()
    )
    -- A guest the host has ACCEPTED. `pending` is excluded on purpose: asking
    -- to stay somewhere must not be enough to learn where it is. `rejected` and
    -- `cancelled` are excluded too — an acceptance that fell through is not a
    -- standing invitation.
    or exists (
      select 1 from public.bookings b
      where b.listing_id = p_listing_id
        and b.tenant_id = auth.uid()
        and b.booking_status in ('confirmed', 'active', 'completed')
    );
$$;

comment on function public.can_see_listing_address(uuid) is
  'True when the caller is the listing owner, an admin, or a guest with a confirmed/active/completed booking on it.';

revoke all on function public.can_see_listing_address(uuid) from public;
grant execute on function public.can_see_listing_address(uuid) to authenticated;

alter table public.listing_addresses enable row level security;

drop policy if exists listing_addresses_select_entitled on public.listing_addresses;
create policy listing_addresses_select_entitled
  on public.listing_addresses
  for select
  to authenticated
  using (public.can_see_listing_address(listing_id));

drop policy if exists listing_addresses_owner_insert on public.listing_addresses;
create policy listing_addresses_owner_insert
  on public.listing_addresses
  for insert
  to authenticated
  with check (
    exists (select 1 from public.listings l
            where l.id = listing_id and l.owner_id = auth.uid())
  );

drop policy if exists listing_addresses_owner_update on public.listing_addresses;
create policy listing_addresses_owner_update
  on public.listing_addresses
  for update
  to authenticated
  using (
    exists (select 1 from public.listings l
            where l.id = listing_id and l.owner_id = auth.uid())
  )
  with check (
    exists (select 1 from public.listings l
            where l.id = listing_id and l.owner_id = auth.uid())
  );

drop policy if exists listing_addresses_owner_delete on public.listing_addresses;
create policy listing_addresses_owner_delete
  on public.listing_addresses
  for delete
  to authenticated
  using (
    exists (select 1 from public.listings l
            where l.id = listing_id and l.owner_id = auth.uid())
  );

-- Supabase's ALTER DEFAULT PRIVILEGES on `public` hands every new table to
-- `anon` and `authenticated` automatically, so `create table` above already
-- granted anon SELECT/INSERT/UPDATE/DELETE. RLS keeps anon out (it matches no
-- policy), but that is one mis-written `to public` policy away from a leak.
-- Take the grant away instead of relying on the policies alone.
revoke all on public.listing_addresses from anon, public;
grant select, insert, update, delete on public.listing_addresses to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Make it impossible for public.listings to hold a precise location.
-- ---------------------------------------------------------------------------

create or replace function public.enforce_listing_public_location()
returns trigger
language plpgsql
as $$
begin
  -- Derived, never client-supplied: whatever `address` a client sends is
  -- discarded in favour of the area-level form.
  new.address   := public.listing_area_address(new.area, new.city, new.postal_code);
  new.latitude  := public.snap_coordinate(new.latitude);
  new.longitude := public.snap_coordinate(new.longitude);

  -- Re-derive the PostGIS columns from the SNAPPED coordinates. The existing
  -- listing_location_trigger / trg_set_listing_geog do this too, but they fire
  -- in trigger-name order and `listing_location_trigger` sorts before this one,
  -- so it would otherwise stamp `location` with the exact point. Doing it here
  -- as well makes the outcome independent of trigger ordering.
  if new.latitude is not null and new.longitude is not null then
    new.location := ST_SetSRID(ST_MakePoint(new.longitude, new.latitude), 4326)::geography;
    new.geog     := ST_SetSRID(ST_MakePoint(new.longitude, new.latitude), 4326)::geography;
  else
    new.location := null;
    new.geog     := null;
  end if;

  return new;
end;
$$;

comment on function public.enforce_listing_public_location() is
  'Keeps public.listings area-level: derives address from area/city and snaps coordinates on every write.';

drop trigger if exists enforce_listing_public_location on public.listings;
create trigger enforce_listing_public_location
  before insert or update on public.listings
  for each row execute function public.enforce_listing_public_location();

-- Redact the rows that already exist. The exact values are safe in
-- listing_addresses by now (inserted above).
update public.listings
   set address   = public.listing_area_address(area, city, postal_code),
       latitude  = public.snap_coordinate(latitude),
       longitude = public.snap_coordinate(longitude);

-- The columns that name a door. Dropping them rather than blanking them is the
-- point: `search_listings` returns `to_jsonb(l)`, so anything left on this table
-- reaches every client automatically. They live on in listing_addresses.
alter table public.listings
  drop column if exists house_no,
  drop column if exists flat_floor,
  drop column if exists street;

-- ---------------------------------------------------------------------------
-- 5. The one legitimate server-side discloser: the check-in map message.
-- ---------------------------------------------------------------------------

-- send_booking_map posts a `location` chat message to the guest, and is called
-- from send_booking_accept_messages — i.e. at the exact moment the host accepts
-- and the guest becomes entitled. It read l.address / l.latitude / l.longitude,
-- which are now redacted, so it has to read the gated table instead. It is
-- already SECURITY DEFINER, and its own `booking_status = 'confirmed'` guard is
-- the same entitlement check can_see_listing_address applies.
create or replace function public.send_booking_map(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
    rec RECORD;
    v_conv_id UUID;
    v_address TEXT;
    v_lang TEXT;
BEGIN
    SELECT b.id AS booking_id, b.tenant_id, b.listing_id,
           COALESCE(b.listing_title, l.title) AS listing_title,
           -- Exact address + coordinates from the gated table, falling back to
           -- the listing's public (area-level) values so a listing with no
           -- listing_addresses row still gets a usable map pin.
           COALESCE(la.exact_address, l.address) AS listing_address,
           l.city AS listing_city,
           COALESCE(la.latitude, l.latitude) AS listing_lat,
           COALESCE(la.longitude, l.longitude) AS listing_lng,
           l.owner_id AS host_id,
           COALESCE(p.message_language, 'en') AS message_language
    INTO rec
    FROM public.bookings b
    JOIN public.listings l ON l.id = b.listing_id
    LEFT JOIN public.listing_addresses la ON la.listing_id = l.id
    LEFT JOIN public.profiles p ON p.id = l.owner_id
    WHERE b.id = p_booking_id AND b.booking_status = 'confirmed'
      AND b.tenant_id IS NOT NULL;

    IF NOT FOUND THEN RETURN; END IF;
    IF rec.listing_lat IS NULL OR rec.listing_lng IS NULL THEN RETURN; END IF;
    IF EXISTS (SELECT 1 FROM public.scheduled_message_sends s
               WHERE s.booking_id = rec.booking_id AND s.trigger = 'map') THEN
        RETURN;
    END IF;

    v_lang := rec.message_language;
    v_address := NULLIF(TRIM(BOTH ', ' FROM
        COALESCE(rec.listing_address, '') ||
        CASE WHEN rec.listing_city IS NOT NULL
                  AND (rec.listing_address IS NULL
                       OR rec.listing_address NOT ILIKE '%' || rec.listing_city || '%')
             THEN ', ' || rec.listing_city ELSE '' END), '');

    v_conv_id := public.get_or_create_conversation(
        rec.tenant_id, rec.host_id, rec.booking_id, rec.listing_id);

    INSERT INTO public.messages
        (conversation_id, sender_id, content, content_type, metadata)
    VALUES (
        v_conv_id, rec.host_id,
        COALESCE(v_address, rec.listing_title,
                 CASE WHEN v_lang = 'bn' THEN 'লিস্টিং লোকেশন' ELSE 'Listing location' END),
        'location',
        jsonb_build_object(
            'latitude', rec.listing_lat,
            'longitude', rec.listing_lng,
            'address', v_address,
            'place_name', rec.listing_title
        )
    );

    INSERT INTO public.scheduled_message_sends (booking_id, trigger)
    VALUES (rec.booking_id, 'map');
END;
$function$;

revoke execute on function public.send_booking_map(uuid) from public, anon, authenticated;

commit;
