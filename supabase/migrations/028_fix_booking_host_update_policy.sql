-- Fix: Ensure hosts can update bookings for their listings
-- Drop the incomplete policy from 026 and recreate with WITH CHECK clause

-- Drop the policy we created in 026 (may not exist if migration wasn't applied)
DROP POLICY IF EXISTS "Hosts can update bookings for their listings" ON public.bookings;

-- The original policy "tenants_update_own_bookings_owner_updates_listing_bookings_admin_updates_all"
-- should already cover host updates. But let's verify by adding an explicit policy.

-- Create a complete policy with both USING and WITH CHECK
CREATE POLICY "Hosts can update bookings for their listings"
  ON public.bookings
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.listings
      WHERE listings.id = bookings.listing_id
      AND listings.owner_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.listings
      WHERE listings.id = bookings.listing_id
      AND listings.owner_id = auth.uid()
    )
  );
