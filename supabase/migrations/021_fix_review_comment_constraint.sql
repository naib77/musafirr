-- Migration: Fix review comment constraint
-- Purpose: Allow empty/null comments for guest reviews (made optional in UI)

-- Drop the existing constraint that requires non-empty comment for guest reviews
ALTER TABLE public.reviews
DROP CONSTRAINT IF EXISTS review_comment_required_for_guest;

-- Add a more permissive constraint (comment can be null or empty for all review types)
-- No constraint needed - comment is now truly optional

-- Also update the RLS policy to be more flexible with booking status
-- Allow reviews for 'completed' OR 'active' bookings (some users may review while still checked in)
DROP POLICY IF EXISTS reviews_insert ON public.reviews;

CREATE POLICY reviews_insert ON public.reviews
    FOR INSERT
    WITH CHECK (
        -- Must be inserting as yourself
        auth.uid() = reviewer_id
        AND
        -- Booking must exist and be completed or active
        EXISTS (
            SELECT 1 FROM public.bookings b
            WHERE b.id = booking_id
            AND b.booking_status IN ('completed', 'active')
            AND (
                -- Guest reviewing host: guest must be the tenant
                (review_type = 'guest_to_host' AND b.tenant_id = auth.uid())
                OR
                -- Host reviewing guest: host must own the listing
                (review_type = 'host_to_guest' AND EXISTS (
                    SELECT 1 FROM public.listings l
                    WHERE l.id = b.listing_id AND l.owner_id = auth.uid()
                ))
            )
        )
    );

-- Add comment for documentation
COMMENT ON POLICY reviews_insert ON public.reviews IS
    'Allow authenticated users to insert reviews for their completed or active bookings. Comments are optional.';
