-- 154: search shows a hotel once, not once per room type.
--
-- 153 made a hotel a property whose room types (Deluxe, Super Deluxe, Sea
-- Front) are ordinary listings. search_listings still returned every one of
-- them, so the feed and every search showed the same hotel as several cards.
-- This collapses each property to its cheapest matching room type and adds
-- two keys to the row:
--
--   property_name        the hotel's name, for the card headline
--   room_types_matching  how many of its types passed every filter
--
-- Both are null for a listing outside a hotel, and the function's signature
-- and return type (setof jsonb) are unchanged: an older build ignores the
-- new keys and simply sees one card per hotel. The client opens the hotel
-- page from any room type's row (property_id is already in the row).
--
-- Rewritten from the LIVE definition (pg_get_functiondef, 2026-10-02), not
-- from the last migration that touched it -- the live database has drifted
-- before. CREATE OR REPLACE keeps the existing grants.

CREATE OR REPLACE FUNCTION public.search_listings(p_property_types text[] DEFAULT NULL::text[], p_guest_count integer DEFAULT 1, p_min_price numeric DEFAULT NULL::numeric, p_max_price numeric DEFAULT NULL::numeric, p_amenities text[] DEFAULT NULL::text[], p_location text DEFAULT NULL::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0, p_purpose_tags text[] DEFAULT NULL::text[], p_center_lat double precision DEFAULT NULL::double precision, p_center_lng double precision DEFAULT NULL::double precision, p_radius_m integer DEFAULT NULL::integer, p_radii integer[] DEFAULT NULL::integer[], p_ne_lat double precision DEFAULT NULL::double precision, p_ne_lng double precision DEFAULT NULL::double precision, p_sw_lat double precision DEFAULT NULL::double precision, p_sw_lng double precision DEFAULT NULL::double precision, p_check_in timestamp with time zone DEFAULT NULL::timestamp with time zone, p_check_out timestamp with time zone DEFAULT NULL::timestamp with time zone, p_adults integer DEFAULT NULL::integer, p_children integer DEFAULT NULL::integer, p_infants integer DEFAULT NULL::integer, p_pets integer DEFAULT NULL::integer)
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
  -- One result per hotel (154). A hotel's room types are separate listings
  -- (153), and before this each one was its own card, so Sea Crown showed up
  -- three times in a row. Collapse to the cheapest type that matched every
  -- filter above (dates and party included, so the price shown is one the
  -- guest can actually book) and say how many types matched. A listing with
  -- no property is its own group, so nothing else changes.
  --
  -- Done here, before the tier choice, the ordering and limit/offset:
  -- collapsing after paging would return short pages and could split a
  -- hotel across two of them. The tie-breaks keep the pick deterministic, so
  -- the same type wins on every page.
  ranked as (
    select b.*,
           count(*) over (partition by coalesce((b.row_l).property_id, b.lid))
             as types_matching,
           row_number() over (
             partition by coalesce((b.row_l).property_id, b.lid)
             order by least((b.row_l).hourly_rate, (b.row_l).daily_rate,
                            (b.row_l).monthly_rate) asc nulls last,
                      coalesce(b.rating, 0) desc,
                      (b.row_l).created_at asc,
                      b.lid
           ) as pick
    from base b
  ),
  collapsed as (
    select * from ranked where pick = 1
  ),
  -- Smallest tier that contains at least one match (null → nearest fallback).
  -- Reads `collapsed` (so `base`), so an unavailable listing cannot win a tier and then be
  -- filtered out of it, which would answer a dated search with an empty ring.
  chosen as (
    select min(r) as radius
    from unnest(coalesce(p_radii, '{}'::integer[])) r
    where (select min(dist) from collapsed) <= r
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
    ), '[]'::jsonb),
    -- Null for a listing outside a hotel. The name comes through the
    -- properties select policy (this is an invoker function), which shows a
    -- hotel exactly when it has a live room type: the same condition that
    -- let this row through.
    'property_name',
      (select p.name from public.properties p where p.id = (b.row_l).property_id),
    'room_types_matching',
      case when (b.row_l).property_id is not null then b.types_matching end
  )
  from collapsed b
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
$function$
;
