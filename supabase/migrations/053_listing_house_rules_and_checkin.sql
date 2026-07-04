-- =============================================================
-- 053 — House rules, expanded amenities, and check-in/access details
--
-- Adds the listing-creation data that Airbnb collects but Musafir did not:
--   1. A larger, grouped amenity catalog (grouping lives client-side; the
--      table just needs the rows so listing_facilities can reference them).
--   2. House rules + check-in/out times on the listing (non-sensitive; shown
--      on the listing page, like Airbnb).
--   3. A SEPARATE host-only table for sensitive check-in access details
--      (directions, Wi-Fi, door code). These must NOT be world-readable, so
--      they live behind their own RLS instead of on the public listings row.
--      Guests receive them via the pre-check-in message (sent server-side),
--      never by reading the row directly.
-- =============================================================

-- 1. Expanded amenity catalog -------------------------------------------------
-- Insert only names that don't already exist. This uses just the `name` column
-- (the only one the app relies on and the only one guaranteed present across
-- environments) and is idempotent without depending on a unique constraint.
insert into public.facilities (id, name)
select gen_random_uuid(), v.name
from (
  values
    ('Hot Water'),
    ('Drinking Water'),
    ('Refrigerator'),
    ('Washing Machine'),
    ('TV'),
    ('Workspace'),
    ('Balcony'),
    ('Elevator'),
    ('Backup Generator'),
    ('Power Backup (IPS)'),
    ('Prayer Space'),
    ('Wardrobe'),
    ('Smoke Alarm'),
    ('Fire Extinguisher'),
    ('First Aid Kit'),
    ('CCTV Security'),
    ('Security Guard')
) as v(name)
where not exists (
  select 1 from public.facilities f where f.name = v.name
);

-- 2. House rules + check-in/out times on the listing --------------------------
alter table public.listings
  add column if not exists check_in_time text,
  add column if not exists check_out_time text,
  add column if not exists smoking_allowed boolean not null default false,
  add column if not exists pets_allowed boolean not null default false,
  add column if not exists parties_allowed boolean not null default false,
  add column if not exists quiet_hours text,
  add column if not exists additional_rules text;

-- 3. Host-only check-in access details ----------------------------------------
create table if not exists public.listing_checkin_details (
  listing_id uuid primary key references public.listings (id) on delete cascade,
  directions text,
  wifi_name text,
  wifi_password text,
  access_code text,
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.listing_checkin_details enable row level security;

-- Only the listing owner can read or write these. Guests never read them
-- directly — the pre-check-in cron (service_role, which bypasses RLS) injects
-- them into a message. No anon/authenticated grants beyond the owner policy.
drop policy if exists "owner_manages_checkin_details" on public.listing_checkin_details;
create policy "owner_manages_checkin_details"
  on public.listing_checkin_details
  for all
  to authenticated
  using (
    exists (
      select 1 from public.listings l
      where l.id = listing_checkin_details.listing_id
        and l.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.listings l
      where l.id = listing_checkin_details.listing_id
        and l.owner_id = auth.uid()
    )
  );
