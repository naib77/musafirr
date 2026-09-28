-- Migration 112: make search date-aware.
--
-- PROBLEM: search_listings has never taken a date. SearchFilters carries
-- checkIn/checkOut (and the hourly singleDate + start/end times), the guest
-- picks them in the explore filter sheet, and the client simply never sent
-- them. So search filtered on is_active and host_available only, and a guest
-- searching 10-15 September was shown:
--
--   * listings the host had blocked for exactly those dates (110), and
--   * listings already booked solid for them.
--
-- Both were then refused at the Reserve step. Migrations 110/111 closed the
-- booking hole; this closes the discovery hole in front of it, so a guest stops
-- being walked into a dead end.
--
-- SCOPE: a block hides the listing only from searches whose dates OVERLAP it.
-- A host who blocks one weekend must still be findable for every other date --
-- that is the whole point of 110 ("block dates without hiding your listing"),
-- and hosts already have host_available (038) and is_active for stepping out
-- entirely. An undated search is unfiltered, because there is no window to
-- test against.
--
-- The rule itself is NOT reimplemented here. is_booking_available (111) already
-- answers exactly this question -- no active booking and no host block, both
-- half-open '[)' -- so search calls it. Two implementations of one availability
-- rule is the mistake 111's own commit message is about.

-- ---------------------------------------------------------------------------
-- 1. Let anonymous callers ask the availability question.
-- ---------------------------------------------------------------------------

-- search_listings is granted to anon (browsing does not require an account) and
-- runs SECURITY INVOKER, so its body executes with the caller's privileges: an
-- anon search calling is_booking_available without this grant fails the whole
-- query with 42501 rather than degrading. 111 granted it to `authenticated`
-- only because the booking form is behind a login.
--
-- What this discloses to an unauthenticated caller is one boolean about one
-- listing over one window -- the same fact any booking calendar publishes, and
-- strictly less than the row it is derived from. It is deliberately NOT a way
-- to read bookings: the function is SECURITY DEFINER precisely so it can look
-- across guests without ever returning their rows.
grant execute on function public.is_booking_available(uuid, timestamptz, timestamptz)
  to anon;

-- ---------------------------------------------------------------------------
-- 2. search_listings gains p_check_in / p_check_out.
-- ---------------------------------------------------------------------------

-- Body is 097's verbatim, plus the one date predicate in `base`. Both new
-- parameters default to null, so a client built before this migration keeps
-- resolving to this function by name and gets the old, unfiltered behaviour --
-- which matters because build/web is a committed artifact and the deployed
-- bundle always lags a migration.
drop function if exists public.search_listings(
  text[], integer, numeric, numeric, text[], text, integer, integer,
  text[], double precision, double precision, integer, integer[],
  double precision, double precision, double precision, double precision
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
  p_check_out      timestamptz      default null
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
  timestamptz, timestamptz
) to anon, authenticated;

comment on function public.search_listings is
  'Marketplace search. Four geography modes (plain, landmark ring, place box, '
  'expanding tiers) and, when p_check_in/p_check_out are both given, only '
  'listings bookable across that window per is_booking_available (112).';
