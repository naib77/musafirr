-- Migration: Fix reviews RLS policy
-- Purpose: Fix the INSERT policy that was preventing reviews from being created

-- First, ensure 'active' status exists in the enum (in case migrations were run out of order)
DO $$
BEGIN
    -- Check if 'active' exists in booking_status enum
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum
        WHERE enumlabel = 'active'
        AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'booking_status')
    ) THEN
        ALTER TYPE public.booking_status ADD VALUE 'active' AFTER 'confirmed';
    END IF;
END $$;

-- Drop the existing INSERT policy
DROP POLICY IF EXISTS reviews_insert ON public.reviews;

-- Create a more permissive INSERT policy with better logic
-- The policy now:
-- 1. Allows the reviewer to insert their own review
-- 2. Checks the booking is completed (primary requirement for reviews)
-- 3. Properly checks tenant_id for guest reviews
-- 4. Properly checks owner_id for host reviews
CREATE POLICY reviews_insert ON public.reviews
    FOR INSERT
    WITH CHECK (
        -- Must be inserting as yourself
        auth.uid() = reviewer_id
        AND
        -- Booking must exist and be completed
        EXISTS (
            SELECT 1 FROM public.bookings b
            WHERE b.id = booking_id
            AND b.booking_status = 'completed'
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

-- Also add a policy for service role to bypass RLS (for admin operations)
DROP POLICY IF EXISTS reviews_service_insert ON public.reviews;
CREATE POLICY reviews_service_insert ON public.reviews
    FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role')
    WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

-- Add helpful comment
COMMENT ON POLICY reviews_insert ON public.reviews IS
    'Allow authenticated users to insert reviews for their completed/active bookings';
