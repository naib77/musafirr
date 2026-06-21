-- ============================================
-- Add booking context fields to conversations
-- ============================================
-- These fields are denormalized for display purposes
-- (listing title, booking dates, listing type)

ALTER TABLE public.conversations
ADD COLUMN IF NOT EXISTS listing_title TEXT,
ADD COLUMN IF NOT EXISTS booking_start TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS booking_end TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS listing_type TEXT;

-- Add comments for documentation
COMMENT ON COLUMN public.conversations.listing_title IS 'Denormalized listing title for display';
COMMENT ON COLUMN public.conversations.booking_start IS 'Booking start date for display';
COMMENT ON COLUMN public.conversations.booking_end IS 'Booking end date for display';
COMMENT ON COLUMN public.conversations.listing_type IS 'Listing type (seat, room, full_house) for display';
