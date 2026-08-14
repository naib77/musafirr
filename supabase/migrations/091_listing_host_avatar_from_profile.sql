-- 091_listing_host_avatar_from_profile.sql
-- Fix: guests never saw the host's profile picture on a listing.
--
-- search_listings returns each row as `to_jsonb(listings) || jsonb_build_object(...)`,
-- so the app's `host_avatar_url` came straight off the listings row's own
-- `host_avatar_url` column — which is NEVER written by any code path and is NULL
-- for every listing. The host's real, current avatar lives on profiles.avatar_url
-- (a public storage URL, safe for guests), exposed to anon via the public_profiles
-- view. So we merge that live value into the returned JSON, overriding the dead
-- column (the right-hand side of `||` wins on key conflict). Single source of
-- truth: no denormalized copy to backfill or keep in sync when a host changes
-- their picture.
--
-- Only the `base` CTE (added join + host_avatar) and the final jsonb_build_object
-- (added 'host_avatar_url') differ from the previous definition.

CREATE OR REPLACE FUNCTION public.search_listings(
  p_property_types text[] DEFAULT NULL::text[],
  p_guest_count integer DEFAULT 1,
  p_min_price numeric DEFAULT NULL::numeric,
  p_max_price numeric DEFAULT NULL::numeric,
  p_amenities text[] DEFAULT NULL::text[],
  p_location text DEFAULT NULL::text,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0,
  p_purpose_tags text[] DEFAULT NULL::text[],
  p_center_lat double precision DEFAULT NULL::double precision,
  p_center_lng double precision DEFAULT NULL::double precision,
  p_radius_m integer DEFAULT NULL::integer,
  p_radii integer[] DEFAULT NULL::integer[])
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with center as (
    select case
             when p_center_lat is not null and p_center_lng is not null
             then ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
           end as g
  ),
  -- Every filter except the expanding radius. dist is non-null whenever a
  -- center is set and the listing has coordinates.
  base as (
    select l.id as lid, l as row_l, lr.average_rating as rating,
           coalesce(lr.review_count, 0) as review_count,
           -- Live host avatar (public_profiles is anon-readable, no PII). The
           -- listings.host_avatar_url column is dead (never written), so we
           -- source the real, current picture from the owner's profile.
           pp.avatar_url as host_avatar,
           case when c.g is not null and l.geog is not null
                then ST_Distance(l.geog, c.g) end as dist
    from public.listings l
    left join public.listing_ratings lr on lr.listing_id = l.id
    left join public.public_profiles pp on pp.id = l.owner_id
    cross join center c
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
$function$;
