-- 082 — Listing purpose tags + landmarks ("stay near a hospital / exam center")
--
-- Adds a PURPOSE dimension to listings (separate from listing_type, which is the
-- unit: seat/room/fullHouse) and a curated landmarks table (hospitals, exam
-- centers, universities, tourist spots, business hubs). Guests browse by purpose
-- and rank stays by real distance to a chosen landmark, using PostGIS (already
-- enabled). Purpose is a fixed, app-validated set; landmarks are seeded here and
-- extensible by an admin later.

-- 1. purpose_tags on listings ------------------------------------------------
alter table public.listings
  add column if not exists purpose_tags text[] not null default '{}';
create index if not exists idx_listings_purpose_tags
  on public.listings using gin (purpose_tags);

-- 2. geography point for distance queries ------------------------------------
alter table public.listings
  add column if not exists geog geography(Point, 4326);

create or replace function public.set_listing_geog()
returns trigger language plpgsql as $$
begin
  if new.latitude is not null and new.longitude is not null then
    new.geog := ST_SetSRID(ST_MakePoint(new.longitude, new.latitude), 4326)::geography;
  else
    new.geog := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_set_listing_geog on public.listings;
create trigger trg_set_listing_geog
  before insert or update of latitude, longitude on public.listings
  for each row execute function public.set_listing_geog();

update public.listings
  set geog = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
  where latitude is not null and longitude is not null and geog is null;

create index if not exists idx_listings_geog on public.listings using gist (geog);

-- 3. landmarks table ---------------------------------------------------------
create table if not exists public.landmarks (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  type       text not null check (type in
               ('hospital','exam_center','university','tourist_spot','business_hub')),
  city       text,
  area       text,
  latitude   double precision not null,
  longitude  double precision not null,
  geog       geography(Point, 4326),
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

create or replace function public.set_landmark_geog()
returns trigger language plpgsql as $$
begin
  new.geog := ST_SetSRID(ST_MakePoint(new.longitude, new.latitude), 4326)::geography;
  return new;
end;
$$;

drop trigger if exists trg_set_landmark_geog on public.landmarks;
create trigger trg_set_landmark_geog
  before insert or update of latitude, longitude on public.landmarks
  for each row execute function public.set_landmark_geog();

create index if not exists idx_landmarks_geog on public.landmarks using gist (geog);
create index if not exists idx_landmarks_type on public.landmarks (type) where is_active;

alter table public.landmarks enable row level security;
drop policy if exists landmarks_public_read on public.landmarks;
create policy landmarks_public_read on public.landmarks
  for select using (is_active = true);
grant select on public.landmarks to anon, authenticated;

-- 4. seed (approximate coordinates; an admin can refine later) ----------------
insert into public.landmarks (name, type, city, area, latitude, longitude) values
  -- Hospitals
  ('Dhaka Medical College Hospital','hospital','Dhaka','Shahbagh',23.7256,90.3969),
  ('Bangabandhu Sheikh Mujib Medical University (BSMMU)','hospital','Dhaka','Shahbagh',23.7390,90.3945),
  ('Square Hospital','hospital','Dhaka','Panthapath',23.7530,90.3840),
  ('United Hospital','hospital','Dhaka','Gulshan',23.8009,90.4180),
  ('Evercare Hospital Dhaka','hospital','Dhaka','Bashundhara',23.8155,90.4260),
  ('Ibn Sina Hospital','hospital','Dhaka','Dhanmondi',23.7460,90.3760),
  ('Labaid Hospital','hospital','Dhaka','Dhanmondi',23.7470,90.3790),
  ('Chattogram Medical College Hospital','hospital','Chattogram','Chawkbazar',22.3600,91.8330),
  ('Sylhet MAG Osmani Medical College Hospital','hospital','Sylhet','Kajalshah',24.9040,91.8730),
  ('Rajshahi Medical College Hospital','hospital','Rajshahi','Laxmipur',24.3690,88.5990),
  -- Exam centers / universities
  ('University of Dhaka','university','Dhaka','Shahbagh',23.7330,90.3920),
  ('Bangladesh University of Engineering & Technology (BUET)','university','Dhaka','Palashi',23.7260,90.3925),
  ('North South University','university','Dhaka','Bashundhara',23.8150,90.4250),
  ('British Council Dhaka (IELTS)','exam_center','Dhaka','Fuller Road',23.7360,90.3930),
  ('IDP IELTS Dhaka','exam_center','Dhaka','Dhanmondi',23.7450,90.3760),
  ('University of Chittagong','university','Chattogram','Hathazari',22.4690,91.7880),
  ('University of Rajshahi','university','Rajshahi','Motihar',24.3630,88.6360),
  ('Shahjalal University of Science & Technology (SUST)','university','Sylhet','Kumargaon',24.9180,91.8320),
  -- Tourist spots
  ('Cox''s Bazar Sea Beach','tourist_spot','Cox''s Bazar','Kolatoli',21.4270,92.0058),
  ('Saint Martin''s Island','tourist_spot','Cox''s Bazar','Saint Martin',20.6270,92.3230),
  ('Sundarbans (Mongla)','tourist_spot','Bagerhat','Mongla',22.4900,89.5900),
  ('Jaflong','tourist_spot','Sylhet','Gowainghat',25.1650,92.0170),
  ('Srimangal Tea Gardens','tourist_spot','Moulvibazar','Srimangal',24.3080,91.7290),
  ('Ahsan Manzil','tourist_spot','Dhaka','Kumartoli',23.7085,90.4060),
  ('Lalbagh Fort','tourist_spot','Dhaka','Lalbagh',23.7190,90.3880),
  -- Business hubs
  ('Motijheel Commercial Area','business_hub','Dhaka','Motijheel',23.7330,90.4170),
  ('Gulshan','business_hub','Dhaka','Gulshan',23.7925,90.4145),
  ('Banani','business_hub','Dhaka','Banani',23.7940,90.4040),
  ('Karwan Bazar','business_hub','Dhaka','Karwan Bazar',23.7510,90.3930),
  ('Agrabad Commercial Area','business_hub','Chattogram','Agrabad',22.3260,91.8130),
  ('Uttara','business_hub','Dhaka','Uttara',23.8700,90.3790)
on conflict do nothing;

-- 5. nearby_landmarks: what's close to a listing's pin (host preview) ----------
create or replace function public.nearby_landmarks(
  p_lat   double precision,
  p_lng   double precision,
  p_limit integer default 5,
  p_type  text default null
)
returns setof jsonb language sql stable security invoker set search_path = public as $$
  select to_jsonb(x) from (
    select id, name, type, city, area, latitude, longitude,
           ST_Distance(geog, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography) as distance_m
    from public.landmarks
    where is_active and (p_type is null or type = p_type)
    order by geog <-> ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    limit greatest(coalesce(p_limit, 5), 0)
  ) x;
$$;
grant execute on function public.nearby_landmarks(double precision, double precision, integer, text)
  to anon, authenticated;

-- 6. search_landmarks: guest/host picker --------------------------------------
create or replace function public.search_landmarks(
  p_query text default null,
  p_type  text default null,
  p_limit integer default 20
)
returns setof jsonb language sql stable security invoker set search_path = public as $$
  select to_jsonb(x) from (
    select id, name, type, city, area, latitude, longitude
    from public.landmarks
    where is_active
      and (p_type is null or type = p_type)
      and (p_query is null or p_query = '' or
           name ilike '%' || p_query || '%' or
           area ilike '%' || p_query || '%' or
           city ilike '%' || p_query || '%')
    order by name
    limit greatest(coalesce(p_limit, 20), 0)
  ) x;
$$;
grant execute on function public.search_landmarks(text, text, integer) to anon, authenticated;

-- 7. extend search_listings with purpose + distance ---------------------------
-- Signature changes (4 new trailing params), so drop the old and recreate. The
-- app calls this by NAMED params, so existing 8-arg calls still resolve (new
-- params default to null → identical behaviour) — no break before the app ships.
drop function if exists public.search_listings(
  text[], integer, numeric, numeric, text[], text, integer, integer);

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
  p_radius_m       integer          default null
)
returns setof jsonb
language sql stable security invoker set search_path = public
as $$
  with center as (
    select case
             when p_center_lat is not null and p_center_lng is not null
             then ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
           end as g
  )
  select to_jsonb(l) || jsonb_build_object(
    'rating', lr.average_rating,
    'review_count', coalesce(lr.review_count, 0),
    'distance_m', case when c.g is not null and l.geog is not null
                       then ST_Distance(l.geog, c.g) end,
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
    and (c.g is null or p_radius_m is null or
         (l.geog is not null and ST_DWithin(l.geog, c.g, p_radius_m)))
  order by
    (case when c.g is not null and l.geog is not null
          then ST_Distance(l.geog, c.g) end) asc nulls last,
    coalesce(lr.average_rating, 0) desc,
    coalesce(lr.review_count, 0) desc,
    l.created_at desc
  limit greatest(coalesce(p_limit, 20), 0)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

grant execute on function public.search_listings(
  text[], integer, numeric, numeric, text[], text, integer, integer,
  text[], double precision, double precision, integer
) to anon, authenticated;
