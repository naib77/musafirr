-- 097: the search area becomes admin-configurable.
--
-- The size of a proximity search was compiled into the app in three places:
--   • the expanding tiers [1000,3000,5000,10000] (repository constant),
--   • the 15 km landmark ring (Explore search sheet),
--   • the nearest-N fallback cap of 20 (a literal in search_listings below).
-- Tuning any of them meant a Dart change, a rebuild, and a redeploy of the
-- committed web bundle. They are now rows in app_settings, editable from the
-- admin portal and picked up by the app on next load.
--
-- Split of responsibility: the two radius settings are read by the CLIENT
-- (it already loads app_settings at startup, and it is the client that decides
-- which of the three search modes applies). The fallback cap is read HERE,
-- because it is applied inside the query's LIMIT and was never a parameter.
--
-- Reads of these keys must stay public — the guest app is anon when it
-- searches — so is_public keeps its default of true (see 075). Writes remain
-- admin-only (086).

-- ── 1. Seed the settings ────────────────────────────────────────────────────
-- Values are the ones the app already hardcoded, so applying this migration on
-- its own changes nothing about how search behaves.
insert into public.app_settings (key, value) values
  ('search_radius_tiers_m',          '1000,3000,5000,10000'),
  ('search_landmark_radius_m',       '15000'),
  ('search_nearest_fallback_limit',  '20')
on conflict (key) do nothing;

-- ── 2. Reject settings that would break search ──────────────────────────────
-- The app sanitises whatever it reads (SearchAreaSettings), so a bad value can
-- never blank out Explore. But silently correcting an admin's input means the
-- portal shows one thing and the app does another, so the write is refused at
-- the source instead — the admin finds out immediately, at the keystroke.
--
-- Only the search keys are validated; every other key passes through untouched.
create or replace function public.fn_validate_app_setting()
returns trigger
language plpgsql
as $$
declare
  parts text[];
  part  text;
  n     integer;
  prev  integer := null;
begin
  if new.key = 'search_radius_tiers_m' then
    parts := string_to_array(coalesce(new.value, ''), ',');
    if array_length(parts, 1) is null then
      raise exception 'search_radius_tiers_m needs at least one radius in metres'
        using errcode = '22023';
    end if;
    if array_length(parts, 1) > 6 then
      raise exception 'search_radius_tiers_m allows at most 6 tiers (got %)',
        array_length(parts, 1) using errcode = '22023';
    end if;
    foreach part in array parts loop
      if btrim(part) !~ '^[0-9]+$' then
        raise exception 'search_radius_tiers_m: "%" is not a whole number of metres',
          btrim(part) using errcode = '22023';
      end if;
      n := btrim(part)::integer;
      if n < 100 or n > 200000 then
        raise exception 'search_radius_tiers_m: % m is outside 100–200000 m', n
          using errcode = '22023';
      end if;
      -- Ascending order is load-bearing: the RPC takes the smallest tier that
      -- contains a match, so an unsorted list would pick the wrong ring.
      if prev is not null and n <= prev then
        raise exception 'search_radius_tiers_m must ascend (% came after %)', n, prev
          using errcode = '22023';
      end if;
      prev := n;
    end loop;

  elsif new.key in ('search_landmark_radius_m', 'search_nearest_fallback_limit') then
    if btrim(coalesce(new.value, '')) !~ '^[0-9]+$' then
      raise exception '% must be a whole number', new.key using errcode = '22023';
    end if;
    n := btrim(new.value)::integer;
    if new.key = 'search_landmark_radius_m' and (n < 100 or n > 200000) then
      raise exception 'search_landmark_radius_m: % m is outside 100–200000 m', n
        using errcode = '22023';
    end if;
    if new.key = 'search_nearest_fallback_limit' and (n < 1 or n > 100) then
      raise exception 'search_nearest_fallback_limit: % is outside 1–100', n
        using errcode = '22023';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validate_app_setting on public.app_settings;
create trigger trg_validate_app_setting
  before insert or update on public.app_settings
  for each row execute function public.fn_validate_app_setting();

-- ── 3. search_listings: read the fallback cap from settings ─────────────────
-- Identical to 092 except that the literal 20 in the LIMIT is now the
-- configured value. The signature is unchanged, so no client update is needed
-- and older builds pick this up automatically.
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
          then least(greatest(coalesce(p_limit, 20), 0), (select n from fallback_cap))
          else greatest(coalesce(p_limit, 20), 0)
        end
  offset greatest(coalesce(p_offset, 0), 0);
$$;

grant execute on function public.search_listings(
  text[], integer, numeric, numeric, text[], text, integer, integer,
  text[], double precision, double precision, integer, integer[],
  double precision, double precision, double precision, double precision
) to anon, authenticated;
