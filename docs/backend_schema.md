# Musafir Backend Schema

This document defines the first real backend target for Musafir using `Supabase + PostgreSQL + PostGIS`.

## Core decisions

- `auth.users` is the source of truth for authentication
- `profiles` stores app-specific user data and role
- `listings` stores seats, rooms, and full houses
- `facilities` is normalized for filtering and reuse
- `bookings` stores time-based reservations
- `PostGIS` is used for area search
- booking overlap protection is enforced in PostgreSQL, not only in Flutter

## User roles

The app has three roles:

- `admin`
- `owner`
- `tenant`

Each authenticated user has one row in `profiles`.

## Main tables

### `profiles`

Stores role, display name, and mobile number.

Important fields:

- `id uuid`: references `auth.users.id`
- `role app_role`
- `full_name text`
- `mobile text`

### `listings`

Stores rental inventory created by owners.

Important fields:

- `owner_id uuid`: references `profiles.id`
- `listing_type listing_type`
- `title text`
- `description text`
- `address text`
- `latitude numeric`
- `longitude numeric`
- `location geography(Point, 4326)`
- `hourly_rate numeric`
- `daily_rate numeric`
- `monthly_rate numeric`
- `is_active boolean`
- `approval_status listing_approval_status`

### `facilities`

Shared facility catalog.

Examples:

- Wi-Fi
- AC
- Attached Bath
- Kitchen
- Parking

### `listing_facilities`

Join table between `listings` and `facilities`.

### `bookings`

Stores tenant reservations.

Important fields:

- `listing_id uuid`
- `tenant_id uuid`
- `starts_at timestamptz`
- `ends_at timestamptz`
- `booking_status booking_status`
- `pricing_unit pricing_unit`
- `unit_count integer`
- `total_price numeric`

## Booking conflict rule

Two active bookings must not overlap for the same listing.

Active statuses:

- `pending`
- `confirmed`
- `active`

Non-blocking statuses:

- `completed`
- `cancelled`
- `rejected`

This rule is enforced with a PostgreSQL exclusion constraint using:

- `btree_gist`
- `tstzrange(starts_at, ends_at, '[)')`

That means one booking can end at exactly the same moment another starts.

## Area search strategy

Listings are stored with a `geography(Point, 4326)` column.

For tenant search:

1. use `ST_DWithin` for radius filtering
2. optionally filter by `listing_type`
3. exclude listings with conflicting active bookings for the requested time range
4. sort by distance with `ST_Distance`

## Approval flow

Recommended behavior:

- owner creates listing
- listing starts as `pending`
- admin reviews and changes it to `approved`
- only `approved` and `is_active = true` listings appear in tenant search

## Supabase auth and RLS model

Recommended rules:

- anyone authenticated can read their own `profiles` row
- owners can create and manage only their own listings
- tenants can create bookings only for themselves
- admins can read and manage everything
- public/anonymous reads should be avoided until moderation rules are clear

## Flutter integration direction

The app should keep the repository abstraction already added in `lib/repositories/`.

Recommended mapping:

- `InMemoryMusafirRepository` for local demo mode
- `SupabaseMusafirRepository` for production mode

Next implementation steps in Flutter:

1. add `supabase_flutter`
2. initialize Supabase in `main.dart`
3. inject `SupabaseMusafirRepository`
4. map SQL rows into Dart models
5. replace placeholder search and booking logic with RPC/query calls
