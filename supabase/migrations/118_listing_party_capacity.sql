-- Migration 118: per-category party capacity.
--
-- The guest side has collected a breakdown -- adults / children / infants --
-- since the desktop Who panel shipped, but only their SUM ever reached the
-- database: guestCountFor() folds them into guestCount and search compares
-- that against listings.max_guests. So "2 adults, 2 children" and "4 adults"
-- were the same search, and a host had no way to say the four-bed room sleeps
-- four adults but the studio takes two adults and a cot.
--
-- This adds the host's side of that conversation, plus the one party category
-- the search never collected at all: pets.
--
-- ── The model: sub-caps under a total, not a replacement for it ────────────
--
-- max_guests stays exactly what it was -- the total the place holds, the
-- number create_marketplace_booking enforces (070/111/114), and the only one
-- a booking carries. The four new columns are OPTIONAL sub-caps beneath it:
--
--   max_guests   = 4     the place holds four people
--   max_adults   = 2     ...at most two of them adults
--   max_children = 3     ...at most three of them children
--
-- They are deliberately NOT constrained to be <= max_guests, and deliberately
-- do not have to sum to it. "Up to 4 people, at most 2 adults, at most 3
-- children" is a coherent thing for a host to mean and any of the obvious
-- constraints would forbid it. The total is the backstop; these only narrow.
--
-- NULL means "the host set no separate limit here", which is what every
-- existing row gets. That is what makes this migration invisible to the 40
-- listings already live: a null column drops out of the search predicate
-- entirely, so every listing matches exactly the searches it matched before.
--
-- ── Pets are the exception, and default to deny ────────────────────────────
--
-- Unlike the other three, pets already had a switch: house_rules.pets_allowed
-- (053), `not null default false`. So for pets alone, silence means NO, and
-- max_pets is only consulted for a host who has said yes. Searching with an
-- animal must not surface a place that never agreed to one -- that is a
-- refusal at the door rather than a preference, and it is why the predicate
-- below is shaped differently from the other three.
--
-- pets_allowed remains the source of truth for "at all"; max_pets only ever
-- narrows it. No constraint ties them together, so a host who flips the toggle
-- off does not need their number cleared first -- the predicate reads the
-- toggle first and never reaches the number.
--
-- ── Scope: search only, same line SearchFilters already drew ───────────────
--
-- Nothing here reaches bookings. create_marketplace_booking still takes one
-- guest number and still checks it against max_guests alone, so a stay found
-- as "2 adults, 1 child, 1 infant, 1 pet" is still booked as 3 guests. Making
-- the booking carry the split is a bookings-table migration plus the booking
-- sheet, the price breakdown and the host's reservation list -- out of scope,
-- and called out here so the next reader does not assume this migration did
-- it.

-- ---------------------------------------------------------------------------
-- 1. The columns.
-- ---------------------------------------------------------------------------

alter table public.listings
  add column if not exists max_adults   integer,
  add column if not exists max_children integer,
  add column if not exists max_infants  integer,
  add column if not exists max_pets     integer;

-- Non-negative, and at least one adult where a limit is stated at all: a
-- listing that admits zero adults is not a stay, it is a data-entry slip, and
-- it would silently vanish from every search rather than fail loudly.
alter table public.listings
  drop constraint if exists listings_max_adults_positive,
  add  constraint listings_max_adults_positive
       check (max_adults is null or max_adults >= 1);

alter table public.listings
  drop constraint if exists listings_max_children_nonneg,
  add  constraint listings_max_children_nonneg
       check (max_children is null or max_children >= 0);

alter table public.listings
  drop constraint if exists listings_max_infants_nonneg,
  add  constraint listings_max_infants_nonneg
       check (max_infants is null or max_infants >= 0);

alter table public.listings
  drop constraint if exists listings_max_pets_nonneg,
  add  constraint listings_max_pets_nonneg
       check (max_pets is null or max_pets >= 0);

comment on column public.listings.max_adults is
  'Optional sub-cap under max_guests: most adults allowed. NULL = no separate limit.';
comment on column public.listings.max_children is
  'Optional sub-cap under max_guests: most children (2-12) allowed. NULL = no separate limit.';
comment on column public.listings.max_infants is
  'Most infants (under 2) allowed. NULL = no separate limit. Infants never count towards max_guests.';
comment on column public.listings.max_pets is
  'Most pets allowed, and only meaningful when pets_allowed is true. NULL = allowed, no stated number.';

-- ---------------------------------------------------------------------------
-- 2. search_listings gains p_adults / p_children / p_infants / p_pets.
-- ---------------------------------------------------------------------------

-- Body is 112's verbatim plus the four predicates in `base`. All four new
-- parameters default to null, so a client built before this migration keeps
-- resolving to this same function by name and gets identical behaviour --
-- which matters because build/web is a committed artifact and the deployed
-- bundle always lags a migration.
--
-- The 19-argument signature is dropped rather than left beside this one: two
-- overloads differing only in trailing defaults make PostgREST's by-keys
-- resolution ambiguous, and 112 dropped its predecessor for the same reason.
drop function if exists public.search_listings(
  text[], integer, numeric, numeric, text[], text, integer, integer,
  text[], double precision, double precision, integer, integer[],
  double precision, double precision, double precision, double precision,
  timestamptz, timestamptz
);

create or replace function public.search_listings(
  p_property_types text[]           default null,
  p_guest_count    integer          default 1,
  p_min_price      numeric          default null,
  p_max_price      numeric          default null,
  p_amenities      text[]           default null,
  p_location       text             default null,
  p_limit          integer          default 20,
  p_offset         integer          default 0,
  p_purpose_tags   text[]           default null,
  p_center_lat     double precision default null,
  p_center_lng     double precision default null,
  p_radius_m       integer          default null,
  p_radii          integer[]        default null,
  p_ne_lat         double precision default null,
  p_ne_lng         double precision default null,
  p_sw_lat         double precision default null,
  p_sw_lng         double precision default null,
  p_check_in       timestamptz      default null,
  p_check_out      timestamptz      default null,
  p_adults         integer          default null,
  p_children       integer          default null,
  p_infants        integer          default null,
  p_pets           integer          default null
)
returns setof jsonb
language sql stable security invoker set search_path = public
as $$
  with center as (
    select case
             when p_center_lat is not null and p_center_lng is not null
             then ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
           end as g
  ),
  -- How many listings the nearest-N fallback may return when no tier matched.
  -- Admin-configurable; falls back to the historical 20 when the row is absent
  -- or unreadable, so search degrades to its old behaviour rather than to zero
  -- results. The validation trigger keeps the stored text numeric.
  fallback_cap as (
    select coalesce(
             (select btrim(value)::integer
              from public.app_settings
              where key = 'search_nearest_fallback_limit'
                and btrim(coalesce(value, '')) ~ '^[0-9]+$'),
             20) as n
  ),
  -- The bounding box is active only when all four corners are present and the
  -- box is non-degenerate (north-east actually north-east of south-west).
  bbox as (
    select (p_ne_lat is not null and p_ne_lng is not null
            and p_sw_lat is not null and p_sw_lng is not null
            and p_ne_lat > p_sw_lat and p_ne_lng > p_sw_lng) as active
  ),
  -- Every filter except the expanding radius. dist is non-null whenever a
  -- center is set and the listing has coordinates.
  base as (
    select l.id as lid, l as row_l, lr.average_rating as rating,
           coalesce(lr.review_count, 0) as review_count,
           -- Live host avatar (public_profiles is anon-readable, no PII). The
           -- listings.host_avatar_url column is dead (never written), so we
           -- source the real, current picture from the owner's profile. (091)
           pp.avatar_url as host_avatar,
           case when c.g is not null and l.geog is not null
                then ST_Distance(l.geog, c.g) end as dist
    from public.listings l
    left join public.listing_ratings lr on lr.listing_id = l.id
    left join public.public_profiles pp on pp.id = l.owner_id
    cross join center c
    cross join bbox bb
    where l.is_active = true
      and l.host_available = true
      and (p_property_types is null or l.listing_type::text = any(p_property_types))
      and l.max_guests >= coalesce(p_guest_count, 1)
      -- Per-category caps (118). Each is a sub-cap UNDER max_guests, not a
      -- replacement for it: the line above still rejects a party too big for
      -- the place, and these only narrow it further. A null column means the
      -- host set no separate limit for that category, so the total is the
      -- only thing standing -- which is why every existing listing keeps
      -- matching exactly what it matched before this migration.
      and (p_adults   is null or l.max_adults   is null or l.max_adults   >= p_adults)
      and (p_children is null or l.max_children is null or l.max_children >= p_children)
      and (p_infants  is null or l.max_infants  is null or l.max_infants  >= p_infants)
      -- Pets are the one category that defaults to DENY, because unlike the
      -- others it already had a switch: pets_allowed (053) is `not null
      -- default false`, so silence means no. A guest travelling with an animal
      -- must not be shown a place that never said yes -- that is a refusal at
      -- the door, not a preference. max_pets then narrows a host who does
      -- allow them; null there means "allowed, no stated number".
      and (coalesce(p_pets, 0) = 0
           or (l.pets_allowed and (l.max_pets is null or l.max_pets >= p_pets)))
      and (p_min_price is null or least(l.hourly_rate, l.daily_rate, l.monthly_rate) >= p_min_price)
      and (p_max_price is null or least(l.hourly_rate, l.daily_rate, l.monthly_rate) <= p_max_price)
      and (p_location is null or p_location = '' or
           l.city    ilike '%' || p_location || '%' or
           l.address ilike '%' || p_location || '%' or
           l.title   ilike '%' || p_location || '%')
      and (p_amenities is null or (
        select count(distinct f.name)
        from public.listing_facilities lf
        join public.facilities f on f.id = lf.facility_id
        where lf.listing_id = l.id and f.name = any(p_amenities)
      ) = array_length(p_amenities, 1))
      and (p_purpose_tags is null or l.purpose_tags && p_purpose_tags)
      -- bounding-box search: the listing must sit inside the place's extent.
      -- This is the exact area the guest searched, so it supersedes both radius
      -- paths (which are passed null in box mode anyway).
      and (not bb.active or
           (l.latitude between p_sw_lat and p_ne_lat and
            l.longitude between p_sw_lng and p_ne_lng))
      -- single fixed radius (purpose/landmark search) — unchanged
      and (c.g is null or p_radius_m is null or
           (l.geog is not null and ST_DWithin(l.geog, c.g, p_radius_m)))
      -- tiered search ranks by distance; listings without a pin can't qualify
      and (c.g is null or p_radii is null or l.geog is not null)
      -- Dates the guest asked for must be bookable: no host block (110) and no
      -- active booking. Delegated so this stays one rule with one home.
      --
      -- CASE, not `p_check_in is null or ... or is_booking_available(...)`:
      -- Postgres does not promise left-to-right OR evaluation, and a reversed
      -- window would reach tstzrange(lower > upper) and abort the search with
      -- 22000. CASE does promise it, so a degenerate window disables the
      -- filter instead of erroring. The client guards this too; a public RPC
      -- cannot rely on that.
      and case
            when p_check_in is null or p_check_out is null
                 or p_check_out <= p_check_in then true
            else public.is_booking_available(l.id, p_check_in, p_check_out)
          end
  ),
  -- Smallest tier that contains at least one match (null → nearest fallback).
  -- Reads `base`, so an unavailable listing cannot win a tier and then be
  -- filtered out of it, which would answer a dated search with an empty ring.
  chosen as (
    select min(r) as radius
    from unnest(coalesce(p_radii, '{}'::integer[])) r
    where (select min(dist) from base) <= r
  )
  select to_jsonb(b.row_l) || jsonb_build_object(
    'host_avatar_url', b.host_avatar,
    'rating', b.rating,
    'review_count', b.review_count,
    'distance_m', b.dist,
    'search_radius_m', (select radius from chosen),
    'radius_fallback',
      (p_radii is not null and (select radius from chosen) is null),
    'listing_facilities',
    coalesce((
      select jsonb_agg(jsonb_build_object(
               'facility_id', lf.facility_id,
               'facilities', jsonb_build_object('name', f.name)))
      from public.listing_facilities lf
      join public.facilities f on f.id = lf.facility_id
      where lf.listing_id = b.lid
    ), '[]'::jsonb)
  )
  from base b
  where p_radii is null
     or (select radius from chosen) is null            -- fallback: nearest N
     or b.dist <= (select radius from chosen)
  order by b.dist asc nulls last,
           coalesce(b.rating, 0) desc,
           b.review_count desc,
           (b.row_l).created_at desc
  limit case
          when p_radii is not null and (select radius from chosen) is null
          then least(greatest(coalesce(p_limit, 20), 0), (select n from fallback_cap))
          else greatest(coalesce(p_limit, 20), 0)
        end
  offset greatest(coalesce(p_offset, 0), 0);
$$;
grant execute on function public.search_listings(
  text[], integer, numeric, numeric, text[], text, integer, integer,
  text[], double precision, double precision, integer, integer[],
  double precision, double precision, double precision, double precision,
  timestamptz, timestamptz, integer, integer, integer, integer
) to anon, authenticated;

comment on function public.search_listings is
  'Marketplace search. Four geography modes (plain, landmark ring, place box, '
  'expanding tiers); date-filtered via is_booking_available when p_check_in/'
  'p_check_out are given (112); and narrowed by per-category party capacity '
  'when p_adults/p_children/p_infants/p_pets are given (118).';
