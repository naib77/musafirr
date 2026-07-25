-- 071: Lock down direct booking inserts (breaking — apply AFTER app rollout).
--
-- ⚠️ ORDERING: Do NOT apply this until every shipped app build creates bookings
-- via `create_marketplace_booking` (migration 070). Until then, the live app
-- still does a direct `insert into bookings`, which this migration blocks — so
-- applying it early breaks booking for all users on the old build.
--
-- What it does: removes the permissive INSERT policy (`auth.uid() = tenant_id`)
-- that let clients set their own `total_price`. After this, the ONLY way to
-- create a booking is the SECURITY DEFINER RPC, which computes the price
-- server-side. SELECT/UPDATE policies are untouched.

drop policy if exists "Users can create bookings" on public.bookings;

-- No replacement INSERT policy: with RLS enabled and no INSERT policy, direct
-- inserts by `authenticated` are denied. `create_marketplace_booking` runs as
-- the definer (table owner) and bypasses RLS, so bookings still get created —
-- only through the priced path.

comment on table public.bookings is
  'Bookings are created exclusively via create_marketplace_booking() (server-priced). Direct inserts are disabled (migration 071).';
