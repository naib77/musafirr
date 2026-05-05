create extension if not exists pgcrypto;
create extension if not exists postgis;
create extension if not exists btree_gist;

create type public.app_role as enum ('admin', 'owner', 'tenant');
create type public.listing_type as enum ('seat', 'room', 'full_house');
create type public.listing_approval_status as enum ('pending', 'approved', 'rejected');
create type public.booking_status as enum ('pending', 'confirmed', 'active', 'completed', 'cancelled', 'rejected');
create type public.pricing_unit as enum ('hour', 'day', 'month');

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role public.app_role not null,
  full_name text not null,
  mobile text not null unique,
  avatar_url text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint mobile_format_check check (char_length(mobile) >= 8)
);

create table public.facilities (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  created_at timestamptz not null default timezone('utc', now())
);

create table public.listings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  listing_type public.listing_type not null,
  title text not null,
  description text,
  address text not null,
  latitude numeric(9, 6) not null,
  longitude numeric(9, 6) not null,
  location geography(Point, 4326) generated always as (
    ST_SetSRID(ST_MakePoint(longitude::double precision, latitude::double precision), 4326)::geography
  ) stored,
  hourly_rate numeric(12, 2) not null default 0,
  daily_rate numeric(12, 2) not null default 0,
  monthly_rate numeric(12, 2) not null default 0,
  currency_code text not null default 'BDT',
  is_active boolean not null default true,
  approval_status public.listing_approval_status not null default 'pending',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint listing_lat_check check (latitude between -90 and 90),
  constraint listing_lng_check check (longitude between -180 and 180),
  constraint listing_price_check check (
    hourly_rate >= 0 and daily_rate >= 0 and monthly_rate >= 0
  )
);

create table public.listing_facilities (
  listing_id uuid not null references public.listings (id) on delete cascade,
  facility_id uuid not null references public.facilities (id) on delete restrict,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (listing_id, facility_id)
);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete cascade,
  tenant_id uuid not null references public.profiles (id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  booking_status public.booking_status not null default 'pending',
  pricing_unit public.pricing_unit not null,
  unit_count integer not null,
  total_price numeric(12, 2) not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint booking_time_check check (ends_at > starts_at),
  constraint booking_unit_count_check check (unit_count > 0),
  constraint booking_total_price_check check (total_price >= 0)
);

create index listings_owner_id_idx on public.listings (owner_id);
create index listings_approval_status_idx on public.listings (approval_status, is_active);
create index listings_location_gix on public.listings using gist (location);
create index listing_facilities_facility_id_idx on public.listing_facilities (facility_id);
create index bookings_listing_id_idx on public.bookings (listing_id);
create index bookings_tenant_id_idx on public.bookings (tenant_id);
create index bookings_status_idx on public.bookings (booking_status);
create index bookings_range_gix on public.bookings using gist (
  listing_id,
  tstzrange(starts_at, ends_at, '[)')
);

alter table public.bookings
add constraint bookings_no_overlap
exclude using gist (
  listing_id with =,
  tstzrange(starts_at, ends_at, '[)') with &&
)
where (booking_status in ('pending', 'confirmed', 'active'));

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, role, full_name, mobile)
  values (
    new.id,
    coalesce((new.raw_user_meta_data ->> 'role')::public.app_role, 'tenant'),
    coalesce(new.raw_user_meta_data ->> 'full_name', 'New User'),
    coalesce(new.raw_user_meta_data ->> 'mobile', new.phone, 'unknown')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create trigger profiles_touch_updated_at
before update on public.profiles
for each row execute procedure public.touch_updated_at();

create trigger listings_touch_updated_at
before update on public.listings
for each row execute procedure public.touch_updated_at();

create trigger bookings_touch_updated_at
before update on public.bookings
for each row execute procedure public.touch_updated_at();

insert into public.facilities (code, name)
values
  ('wifi', 'Wi-Fi'),
  ('ac', 'AC'),
  ('attached_bath', 'Attached Bath'),
  ('kitchen', 'Kitchen'),
  ('parking', 'Parking')
on conflict (code) do nothing;

create or replace function public.find_available_listings(
  center_lat double precision,
  center_lng double precision,
  radius_meters double precision,
  requested_start timestamptz default null,
  requested_end timestamptz default null,
  requested_type public.listing_type default null
)
returns table (
  id uuid,
  owner_id uuid,
  listing_type public.listing_type,
  title text,
  description text,
  address text,
  latitude numeric,
  longitude numeric,
  hourly_rate numeric,
  daily_rate numeric,
  monthly_rate numeric,
  currency_code text,
  distance_meters double precision
)
language sql
stable
as $$
  select
    l.id,
    l.owner_id,
    l.listing_type,
    l.title,
    l.description,
    l.address,
    l.latitude,
    l.longitude,
    l.hourly_rate,
    l.daily_rate,
    l.monthly_rate,
    l.currency_code,
    ST_Distance(
      l.location,
      ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography
    ) as distance_meters
  from public.listings l
  where l.is_active = true
    and l.approval_status = 'approved'
    and ST_DWithin(
      l.location,
      ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography,
      radius_meters
    )
    and (requested_type is null or l.listing_type = requested_type)
    and (
      requested_start is null
      or requested_end is null
      or not exists (
        select 1
        from public.bookings b
        where b.listing_id = l.id
          and b.booking_status in ('pending', 'confirmed', 'active')
          and tstzrange(b.starts_at, b.ends_at, '[)') &&
              tstzrange(requested_start, requested_end, '[)')
      )
    )
  order by distance_meters asc;
$$;

alter table public.profiles enable row level security;
alter table public.facilities enable row level security;
alter table public.listings enable row level security;
alter table public.listing_facilities enable row level security;
alter table public.bookings enable row level security;

create policy "profiles_select_self_or_admin"
on public.profiles
for select
using (
  auth.uid() = id
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);

create policy "profiles_update_self_or_admin"
on public.profiles
for update
using (
  auth.uid() = id
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);

create policy "facilities_read_authenticated"
on public.facilities
for select
to authenticated
using (true);

create policy "listings_read_approved_authenticated"
on public.listings
for select
to authenticated
using (
  approval_status = 'approved'
  or owner_id = auth.uid()
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);

create policy "owners_insert_own_listings"
on public.listings
for insert
to authenticated
with check (
  owner_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role in ('owner', 'admin')
  )
);

create policy "owners_update_own_listings_or_admin"
on public.listings
for update
to authenticated
using (
  owner_id = auth.uid()
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
)
with check (
  owner_id = auth.uid()
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);

create policy "listing_facilities_read_authenticated"
on public.listing_facilities
for select
to authenticated
using (true);

create policy "owners_manage_listing_facilities_or_admin"
on public.listing_facilities
for all
to authenticated
using (
  exists (
    select 1
    from public.listings l
    where l.id = listing_id
      and (
        l.owner_id = auth.uid()
        or exists (
          select 1
          from public.profiles p
          where p.id = auth.uid() and p.role = 'admin'
        )
      )
  )
)
with check (
  exists (
    select 1
    from public.listings l
    where l.id = listing_id
      and (
        l.owner_id = auth.uid()
        or exists (
          select 1
          from public.profiles p
          where p.id = auth.uid() and p.role = 'admin'
        )
      )
  )
);

create policy "tenants_read_own_bookings_owner_reads_listing_bookings_admin_reads_all"
on public.bookings
for select
to authenticated
using (
  tenant_id = auth.uid()
  or exists (
    select 1
    from public.listings l
    where l.id = listing_id and l.owner_id = auth.uid()
  )
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);

create policy "tenants_insert_own_bookings"
on public.bookings
for insert
to authenticated
with check (
  tenant_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role in ('tenant', 'admin')
  )
);

create policy "tenants_update_own_bookings_owner_updates_listing_bookings_admin_updates_all"
on public.bookings
for update
to authenticated
using (
  tenant_id = auth.uid()
  or exists (
    select 1
    from public.listings l
    where l.id = listing_id and l.owner_id = auth.uid()
  )
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
)
with check (
  tenant_id = auth.uid()
  or exists (
    select 1
    from public.listings l
    where l.id = listing_id and l.owner_id = auth.uid()
  )
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);
