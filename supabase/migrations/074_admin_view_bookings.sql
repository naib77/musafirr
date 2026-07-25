-- 074: Let admins read every booking.
--
-- Problem this closes: the `bookings` SELECT policies only covered the tenant
-- ("Users can view their own bookings", auth.uid() = tenant_id) and the host
-- ("Hosts can view bookings for their listings"). An admin account (which owns
-- no listings and is a tenant on nothing) therefore saw ZERO bookings — the
-- admin panel's Bookings list and Reports came up empty. Every other admin
-- surface already had an is_admin() branch (profiles, listings,
-- owner_documents); bookings was the outlier.
--
-- Fix: an additive, read-only admin SELECT policy using the existing
-- SECURITY DEFINER helper public.is_admin() (migration 061), which returns true
-- when profiles.role = 'admin'. No admin INSERT/UPDATE is granted — bookings
-- stay created/mutated only through their existing paths; this is view-only.
--
-- This migration is ADDITIVE and safe to apply anytime; it was already applied
-- live via the Management API on 2026-07-25 and is captured here for tracking.

drop policy if exists "Admins can view all bookings" on public.bookings;

create policy "Admins can view all bookings" on public.bookings
  for select
  to authenticated
  using (public.is_admin());

comment on policy "Admins can view all bookings" on public.bookings is
  'Admins (profiles.role = ''admin'') can read all bookings for the admin panel. Read-only; no admin write policy.';
