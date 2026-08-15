-- 092: search within a place's real extent (bounding box), not a fixed ring.
--
-- The problem this fixes: a typed place was reduced to a center point and a
-- one-size-fits-all radius (expanding 1/3/5/10 km tiers, or a fixed 15 km ring
-- for landmarks). A circle can't represent a place's real shape or size, so
-- "Uttara" (a small thana) leaked into Tongi as the ring widened, and "Dhaka"
-- (a whole city) either under-covered or, via the nearest-N fallback, pulled in
-- Gazipur. Google already tells us each place's true extent — its geocoded
-- `bounds`/`viewport` box — so the app now forwards that box and we filter to
-- listings inside it, distance-ranked to the box's center.
--
-- search_listings gains p_ne_lat/p_ne_lng/p_sw_lat/p_sw_lng. When all four are
-- present (a resolved area), that box wins: radius tiers and the fixed ring are
-- ignored, every listing inside the rectangle is returned, and there is no
-- distance fallback (a box is already the exact area the guest asked for).
-- 'search_radius_m' is null and 'radius_fallback' false in box mode, so the
-- radius chip in the UI simply doesn't show.
--
-- The point+radius paths (tiers for a bare point, 15 km ring for a landmark)
-- are unchanged, and the host-avatar join from 091 is carried forward verbatim.
-- Signature grows by four trailing defaulted params; the app calls by NAMED
-- params, so older 13-arg calls still resolve here with the box params null.

drop function if exists public.search_listings(
  text[], integer, numeric, numeric, text[], text, integer, integer,
  text[], double precision, double precision, integer, integer[]);

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
  p_sw_lng         double precision default null
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
  ),
  -- Smallest tier that contains at least one match (null → nearest fallback).
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
          then least(greatest(coalesce(p_limit, 20), 0), 20)
          else greatest(coalesce(p_limit, 20), 0)
        end
  offset greatest(coalesce(p_offset, 0), 0);
$$;

grant execute on function public.search_listings(
  text[], integer, numeric, numeric, text[], text, integer, integer,
  text[], double precision, double precision, integer, integer[],
  double precision, double precision, double precision, double precision
) to anon, authenticated;
