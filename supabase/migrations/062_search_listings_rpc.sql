-- 062 — Server-side listing search + ranking (search_listings RPC)
--
-- Before this, Explore search filtered only the listings already paginated into
-- the client's memory (missing anything not yet scrolled to), and the default
-- feed was ordered purely by created_at with host_available filtered only on the
-- client. This RPC searches the FULL catalog server-side, applies every filter
-- in SQL, and returns a consistent ranking. Both the default feed (all params
-- null) and an active search call it.
--
-- SECURITY INVOKER: runs under the caller's RLS. It only ever returns
-- is_active listings, which are already world-readable, so this is safe.
--
-- Returns each listing as jsonb shaped exactly like the existing
-- `select *, listing_facilities(facility_id, facilities(name))` query, so the
-- client's _listingFromJson parses the result unchanged.
--
-- Ranking: rating desc, then review_count desc, then newest. Ratings come from
-- the listing_ratings view (the listings.rating/review_count columns are stale;
-- the client already reads ratings from that view), and are injected into the
-- returned json so _listingFromJson picks them up. Price filtering uses
-- least(hourly, daily, monthly) — Postgres least() ignores NULLs, matching the
-- app's displayPrice = cheapest offered rate.

create or replace function public.search_listings(
  p_property_types text[]   default null,
  p_guest_count    integer  default 1,
  p_min_price      numeric  default null,
  p_max_price      numeric  default null,
  p_amenities      text[]   default null,
  p_location       text     default null,
  p_limit          integer  default 20,
  p_offset         integer  default 0
)
returns setof jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select to_jsonb(l) || jsonb_build_object(
    'rating', lr.average_rating,
    'review_count', coalesce(lr.review_count, 0),
    'listing_facilities',
    coalesce((
      select jsonb_agg(jsonb_build_object(
               'facility_id', lf.facility_id,
               'facilities', jsonb_build_object('name', f.name)))
      from public.listing_facilities lf
      join public.facilities f on f.id = lf.facility_id
      where lf.listing_id = l.id
    ), '[]'::jsonb)
  )
  from public.listings l
  left join public.listing_ratings lr on lr.listing_id = l.id
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
  order by coalesce(lr.average_rating, 0) desc,
           coalesce(lr.review_count, 0) desc,
           l.created_at desc
  limit greatest(coalesce(p_limit, 20), 0)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

grant execute on function public.search_listings(
  text[], integer, numeric, numeric, text[], text, integer, integer
) to anon, authenticated;
