-- Migration: Fix listing_ratings view
-- Purpose: Show all guest reviews immediately (remove is_revealed filter)

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
WHERE review_type = 'guest_to_host' AND listing_id IS NOT NULL
GROUP BY listing_id;

-- Note: Removed "is_revealed = true" filter so ratings show immediately
-- instead of waiting for both guest and host to review
