-- ============================================
-- Backfill existing conversations with booking context
-- ============================================
-- This migration populates listing_type, booking_start, booking_end, and listing_title
-- for conversations that have a booking_id but missing context fields.

UPDATE public.conversations c
SET
    listing_type = l.listing_type::text,
    booking_start = b.starts_at,
    booking_end = b.ends_at,
    listing_title = COALESCE(c.listing_title, b.listing_title, l.title)
FROM public.bookings b
JOIN public.listings l ON l.id = b.listing_id
WHERE c.booking_id = b.id
  AND (c.listing_type IS NULL OR c.booking_start IS NULL OR c.booking_end IS NULL);

-- Log how many rows were updated
DO $$
DECLARE
    updated_count INTEGER;
BEGIN
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RAISE NOTICE 'Backfilled % conversations with booking context', updated_count;
END $$;
