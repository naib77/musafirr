-- ============================================
-- Link existing conversations to bookings
-- ============================================
-- This migration finds conversations without booking_id and tries to
-- link them to bookings based on participants (guest + host).

-- Step 1: Update conversations to link with bookings based on participants
-- A conversation between user A and user B should link to a booking where:
-- - One user is the tenant (guest)
-- - The other user is the host (owner of the listing)

UPDATE public.conversations c
SET
    booking_id = matched.booking_id,
    listing_id = matched.listing_id,
    listing_type = matched.listing_type,
    booking_start = matched.booking_start,
    booking_end = matched.booking_end,
    listing_title = matched.listing_title
FROM (
    SELECT DISTINCT ON (c2.id)
        c2.id as conversation_id,
        b.id as booking_id,
        b.listing_id,
        l.listing_type::text as listing_type,
        b.starts_at as booking_start,
        b.ends_at as booking_end,
        COALESCE(b.listing_title, l.title) as listing_title
    FROM public.conversations c2
    JOIN public.bookings b ON b.tenant_id IN (c2.participant_one_id, c2.participant_two_id)
    JOIN public.listings l ON l.id = b.listing_id
        AND l.owner_id IN (c2.participant_one_id, c2.participant_two_id)
        AND l.owner_id != b.tenant_id  -- Host must be different from guest
    WHERE c2.booking_id IS NULL
    ORDER BY c2.id, b.created_at DESC  -- Take the most recent booking if multiple
) AS matched
WHERE c.id = matched.conversation_id
  AND c.booking_id IS NULL;

-- Step 2: For conversations that already have booking_id but missing context,
-- populate the context fields
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
