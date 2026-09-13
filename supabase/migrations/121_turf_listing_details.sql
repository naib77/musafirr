-- Migration 121: what a turf listing describes, and the amenities it offers.
--
-- MUST be applied after 120 has COMMITTED. 120 adds the 'turf' enum label and
-- Postgres refuses to let a new label be used in the transaction that created
-- it (55P04) -- the check constraint below mentions 'turf', so running the two
-- together fails. They are separate files for that reason, not for tidiness.
--
-- ── Three columns, not thirteen ────────────────────────────────────────────
--
-- A turf reuses almost the whole listings row as it stands. Title, area, the
-- map pin, photos, hourly_rate, min_hours/max_hours, host_available and
-- max_guests all mean exactly what they already meant -- max_guests is the
-- number of PLAYERS, which is the same "how many people fit" question wearing
-- different words, so it needs no column of its own and no second predicate in
-- search_listings.
--
-- What a guest actually chooses between, and cannot infer from a photo, is
-- three things: which sport the ground is marked for, how big a side it takes,
-- and what it is surfaced with. Those are the columns. Everything else a turf
-- host wants to advertise -- floodlights, changing rooms, equipment hire -- is
-- an amenity, which is the mechanism this schema already has for "optional
-- feature a guest may filter on" and which search_listings already supports
-- through p_amenities. Adding them as booleans would have been three more
-- columns that only one listing type ever reads, plus a second implementation
-- of amenity filtering.
--
-- All three are nullable: a turf that says nothing is legal, and every one of
-- the 20 listings that exist today keeps a null it will never read. The check
-- constraints allow null for exactly that reason.
--
-- ── Why the vocabularies are constrained here rather than in Dart ──────────
--
-- `listings` is written through PostgREST by the owner (addListing inserts
-- straight into the table), so the host form is not the only writer and "the
-- form only offers four options" is not enforcement -- the same reasoning as
-- 110/111. A check constraint is cheap and makes junk impossible; the cost is
-- that a fifth sport needs a migration, which is the right trade for a
-- vocabulary that changes once a year.

alter table public.listings
  add column if not exists turf_sport   text,
  add column if not exists turf_format  text,
  add column if not exists turf_surface text;

-- Dropped first so the file is re-runnable: `add constraint if not exists` is
-- not valid syntax, and a half-applied migration must be able to run again.
alter table public.listings drop constraint if exists listings_turf_sport_valid;
alter table public.listings drop constraint if exists listings_turf_format_valid;
alter table public.listings drop constraint if exists listings_turf_surface_valid;
alter table public.listings drop constraint if exists listings_turf_fields_only_on_turf;

alter table public.listings
  add constraint listings_turf_sport_valid check (
    turf_sport is null or turf_sport in
      ('football', 'cricket', 'badminton', 'basketball', 'volleyball', 'multi')
  );

alter table public.listings
  add constraint listings_turf_format_valid check (
    turf_format is null or turf_format in
      ('5-a-side', '6-a-side', '7-a-side', '9-a-side', '11-a-side', 'other')
  );

alter table public.listings
  add constraint listings_turf_surface_valid check (
    turf_surface is null or turf_surface in
      ('artificial', 'natural', 'concrete', 'wooden', 'clay')
  );

-- A room with a turf_sport is a data-entry accident, and it would show up as a
-- football pitch on the listing page. Cheap to forbid outright; the reverse is
-- deliberately NOT forbidden, because a turf with no sport stated is legal.
alter table public.listings
  add constraint listings_turf_fields_only_on_turf check (
    listing_type = 'turf'
    or (turf_sport is null and turf_format is null and turf_surface is null)
  );

comment on column public.listings.turf_sport is
  'Which sport the ground is marked for. Null for every non-turf listing '
  '(enforced by listings_turf_fields_only_on_turf).';
comment on column public.listings.turf_format is
  'Side size the pitch is built for, e.g. 7-a-side. Descriptive only -- the '
  'number of players a booking may bring is max_guests, same as every other '
  'listing type.';
comment on column public.listings.turf_surface is
  'What the playing surface is made of.';

-- ── Amenities ─────────────────────────────────────────────────────────────
--
-- `facilities` rows are matched BY NAME from Dart (_saveListingFacilities
-- lowercases both sides and silently skips an unknown name), so a name here
-- that disagrees with lib/data/facility_catalog.dart does not error -- the
-- amenity just never persists. Keep the two in step; the catalog file carries
-- the same warning.
--
-- Only genuinely new ones are inserted. Parking, Drinking Water, CCTV
-- Security, First Aid Kit and Security Guard already exist and a turf reuses
-- them rather than gaining near-duplicates that split the amenity filter.
insert into public.facilities (name, icon) values
  ('Floodlights',        'light_mode'),
  ('Changing Room',      'checkroom'),
  ('Showers',            'shower'),
  ('Washroom',           'wc'),
  ('Equipment Rental',   'sports_soccer'),
  ('Covered Turf',       'roofing'),
  ('Spectator Seating',  'event_seat')
on conflict (name) do nothing;
