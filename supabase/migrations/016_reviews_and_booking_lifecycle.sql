-- Migration: Reviews table and booking lifecycle fields
-- Purpose: Support bidirectional reviews with simultaneous reveal and booking lifecycle tracking

-- ============================================================================
-- ADD MISSING NOTIFICATION TYPES (safe approach)
-- ============================================================================

-- Add new notification types for booking lifecycle
-- Note: Using DO block since ADD VALUE IF NOT EXISTS requires PG 9.3+
DO $$
BEGIN
    BEGIN
        ALTER TYPE notification_type ADD VALUE 'booking_rejected';
    EXCEPTION WHEN duplicate_object THEN
        NULL;
    END;
    BEGIN
        ALTER TYPE notification_type ADD VALUE 'checked_in';
    EXCEPTION WHEN duplicate_object THEN
        NULL;
    END;
    BEGIN
        ALTER TYPE notification_type ADD VALUE 'review_prompt';
    EXCEPTION WHEN duplicate_object THEN
        NULL;
    END;
END $$;

-- ============================================================================
-- BOOKING LIFECYCLE FIELDS
-- ============================================================================

-- Add new columns to bookings table for lifecycle tracking
ALTER TABLE public.bookings
ADD COLUMN IF NOT EXISTS host_message text,
ADD COLUMN IF NOT EXISTS rejection_reason text,
ADD COLUMN IF NOT EXISTS confirmed_at timestamptz,
ADD COLUMN IF NOT EXISTS actual_check_in timestamptz,
ADD COLUMN IF NOT EXISTS completed_at timestamptz,
ADD COLUMN IF NOT EXISTS cancelled_by uuid REFERENCES public.profiles(id),
ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;

-- Add comment for documentation
COMMENT ON COLUMN public.bookings.host_message IS 'Optional message from host when accepting booking';
COMMENT ON COLUMN public.bookings.rejection_reason IS 'Optional reason from host when rejecting booking';
COMMENT ON COLUMN public.bookings.confirmed_at IS 'Timestamp when host confirmed the booking';
COMMENT ON COLUMN public.bookings.actual_check_in IS 'Timestamp when host marked guest as arrived';
COMMENT ON COLUMN public.bookings.completed_at IS 'Timestamp when host marked service as complete';
COMMENT ON COLUMN public.bookings.cancelled_by IS 'User ID of who cancelled (guest or host)';
COMMENT ON COLUMN public.bookings.cancelled_at IS 'Timestamp when booking was cancelled';

-- ============================================================================
-- REVIEW TYPE ENUM
-- ============================================================================

-- Create review type enum if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'review_type') THEN
        CREATE TYPE public.review_type AS ENUM (
            'guest_to_host',
            'host_to_guest'
        );
    END IF;
END $$;

-- ============================================================================
-- REVIEWS TABLE
-- ============================================================================

-- Drop existing reviews table (had different schema without booking_id)
DROP TABLE IF EXISTS public.reviews CASCADE;

-- Create reviews table
CREATE TABLE public.reviews (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id uuid NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
    listing_id uuid REFERENCES public.listings(id) ON DELETE SET NULL,
    reviewer_id uuid NOT NULL REFERENCES public.profiles(id),
    reviewer_name text NOT NULL,
    reviewer_avatar_url text,
    reviewee_id uuid NOT NULL REFERENCES public.profiles(id),
    review_type public.review_type NOT NULL,

    -- Ratings
    overall_rating numeric(2,1) NOT NULL CHECK (overall_rating >= 1 AND overall_rating <= 5),

    -- Category ratings (for guest reviews only)
    cleanliness_rating numeric(2,1) CHECK (cleanliness_rating >= 1 AND cleanliness_rating <= 5),
    accuracy_rating numeric(2,1) CHECK (accuracy_rating >= 1 AND accuracy_rating <= 5),
    communication_rating numeric(2,1) CHECK (communication_rating >= 1 AND communication_rating <= 5),
    location_rating numeric(2,1) CHECK (location_rating >= 1 AND location_rating <= 5),
    value_rating numeric(2,1) CHECK (value_rating >= 1 AND value_rating <= 5),

    -- Content
    comment text,

    -- Simultaneous reveal
    is_revealed boolean NOT NULL DEFAULT false,
    revealed_at timestamptz,

    -- Timestamps
    created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
    updated_at timestamptz NOT NULL DEFAULT timezone('utc', now()),

    -- Constraints
    CONSTRAINT review_comment_required_for_guest CHECK (
        review_type = 'host_to_guest' OR (review_type = 'guest_to_host' AND comment IS NOT NULL AND comment != '')
    ),
    CONSTRAINT review_categories_for_guest CHECK (
        review_type = 'host_to_guest' OR (
            review_type = 'guest_to_host' AND
            cleanliness_rating IS NOT NULL AND
            accuracy_rating IS NOT NULL AND
            communication_rating IS NOT NULL AND
            location_rating IS NOT NULL AND
            value_rating IS NOT NULL
        )
    )
);

-- Create unique constraint: one review per reviewer per booking per type
CREATE UNIQUE INDEX reviews_unique_per_booking
ON public.reviews (booking_id, reviewer_id, review_type);

-- Create indexes for common queries
CREATE INDEX reviews_by_booking ON public.reviews (booking_id);
CREATE INDEX reviews_by_listing ON public.reviews (listing_id) WHERE listing_id IS NOT NULL;
CREATE INDEX reviews_by_reviewee ON public.reviews (reviewee_id);
CREATE INDEX reviews_revealed ON public.reviews (is_revealed, review_type);

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

-- Users can view revealed reviews
CREATE POLICY reviews_select_revealed ON public.reviews
    FOR SELECT
    USING (is_revealed = true);

-- Users can view their own reviews (even before reveal)
CREATE POLICY reviews_select_own ON public.reviews
    FOR SELECT
    USING (auth.uid() = reviewer_id);

-- Users can insert reviews for their completed bookings
CREATE POLICY reviews_insert ON public.reviews
    FOR INSERT
    WITH CHECK (
        auth.uid() = reviewer_id AND
        EXISTS (
            SELECT 1 FROM public.bookings b
            WHERE b.id = booking_id
            AND b.booking_status = 'completed'
            AND (
                (review_type = 'guest_to_host' AND b.tenant_id = auth.uid()) OR
                (review_type = 'host_to_guest' AND EXISTS (
                    SELECT 1 FROM public.listings l
                    WHERE l.id = b.listing_id AND l.owner_id = auth.uid()
                ))
            )
        )
    );

-- Users can update their own reviews (before reveal only)
CREATE POLICY reviews_update_own ON public.reviews
    FOR UPDATE
    USING (auth.uid() = reviewer_id AND is_revealed = false)
    WITH CHECK (auth.uid() = reviewer_id);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Trigger to update updated_at
CREATE OR REPLACE FUNCTION public.update_reviews_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc', now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS reviews_updated_at ON public.reviews;
CREATE TRIGGER reviews_updated_at
    BEFORE UPDATE ON public.reviews
    FOR EACH ROW
    EXECUTE FUNCTION public.update_reviews_updated_at();

-- Trigger to check and reveal reviews when both parties submit
CREATE OR REPLACE FUNCTION public.check_and_reveal_reviews()
RETURNS TRIGGER AS $$
DECLARE
    other_review_exists boolean;
BEGIN
    -- Check if the other party has already submitted a review
    SELECT EXISTS (
        SELECT 1 FROM public.reviews
        WHERE booking_id = NEW.booking_id
        AND review_type != NEW.review_type
        AND is_revealed = false
    ) INTO other_review_exists;

    -- If both reviews exist, reveal them both
    IF other_review_exists THEN
        UPDATE public.reviews
        SET is_revealed = true, revealed_at = timezone('utc', now())
        WHERE booking_id = NEW.booking_id AND is_revealed = false;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS reveal_reviews_on_insert ON public.reviews;
CREATE TRIGGER reveal_reviews_on_insert
    AFTER INSERT ON public.reviews
    FOR EACH ROW
    EXECUTE FUNCTION public.check_and_reveal_reviews();

-- ============================================================================
-- LISTING RATING VIEW
-- ============================================================================

-- Create a view for listing aggregate ratings
CREATE OR REPLACE VIEW public.listing_ratings AS
SELECT
    listing_id,
    COUNT(*) AS review_count,
    ROUND(AVG(overall_rating)::numeric, 1) AS average_rating,
    ROUND(AVG(cleanliness_rating)::numeric, 1) AS average_cleanliness,
    ROUND(AVG(accuracy_rating)::numeric, 1) AS average_accuracy,
    ROUND(AVG(communication_rating)::numeric, 1) AS average_communication,
    ROUND(AVG(location_rating)::numeric, 1) AS average_location,
    ROUND(AVG(value_rating)::numeric, 1) AS average_value
FROM public.reviews
WHERE review_type = 'guest_to_host' AND is_revealed = true AND listing_id IS NOT NULL
GROUP BY listing_id;

-- Create a view for guest aggregate ratings
CREATE OR REPLACE VIEW public.guest_ratings AS
SELECT
    reviewee_id AS guest_id,
    COUNT(*) AS review_count,
    ROUND(AVG(overall_rating)::numeric, 1) AS average_rating
FROM public.reviews
WHERE review_type = 'host_to_guest' AND is_revealed = true
GROUP BY reviewee_id;

-- Grant access to views
GRANT SELECT ON public.listing_ratings TO authenticated;
GRANT SELECT ON public.guest_ratings TO authenticated;
