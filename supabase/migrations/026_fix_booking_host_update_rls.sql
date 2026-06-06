-- Fix: Allow hosts to update bookings for their listings
-- This was missing, causing host accept/reject actions to fail silently

-- Add UPDATE policy for hosts
CREATE POLICY "Hosts can update bookings for their listings"
  ON public.bookings
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.listings
      WHERE listings.id = bookings.listing_id
      AND listings.owner_id = auth.uid()
    )
  );
