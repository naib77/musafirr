-- Migration: get_listing_owner function
-- Purpose: Let guests resolve a listing's owner when submitting a review,
-- even if the listing is inactive or outside the client's paginated cache.
-- Guests could not read owner_id for inactive listings (RLS only exposes
-- is_active = true), so reviews were saved with an empty reviewee_id and the
-- insert failed silently.
--
-- SECURITY DEFINER bypasses listings RLS inside the function; access is
-- limited to listings that are active OR that the caller has booked.

CREATE OR REPLACE FUNCTION public.get_listing_owner(p_listing_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT l.owner_id
    FROM public.listings l
    WHERE l.id = p_listing_id
    AND (
        l.is_active
        OR EXISTS (
            SELECT 1 FROM public.bookings b
            WHERE b.listing_id = l.id
            AND b.tenant_id = auth.uid()
        )
    );
$$;

REVOKE ALL ON FUNCTION public.get_listing_owner(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_listing_owner(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_listing_owner(uuid) IS
    'Returns the owner of a listing for active listings or listings the caller has booked. Used for review reviewee resolution.';
