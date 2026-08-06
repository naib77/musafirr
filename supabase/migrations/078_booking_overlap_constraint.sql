-- Migration 078: Make double-booking impossible at the database level + fix
-- the availability check's status set.
--
-- PROBLEM (race): create_marketplace_booking() does a check-then-insert with NO
-- database constraint and NO row lock. Under READ COMMITTED two concurrent calls
-- can BOTH pass the `if exists(... overlap ...)` guard (neither sees the other's
-- uncommitted row) and BOTH insert → a silent double-booking. The reported
-- "second user got a generic error" is only the lucky timing where one committed
-- first; the dangerous timing is both succeeding.
--
-- FIX: a GiST exclusion constraint. Even if both transactions pass the app-level
-- guard, the second COMMIT fails with SQLSTATE 23P01 — the same errcode the
-- manual guard already raises, so create_marketplace_booking's error contract is
-- unchanged. Blocking statuses match the function's guard and BookingStatus.isActive.
--
-- Verified before writing: zero existing overlapping active bookings on live
-- (the constraint build would fail otherwise), and btree_gist is available.

-- Needed for `listing_id WITH =` (uuid equality) inside a GiST index.
CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE public.bookings
    ADD CONSTRAINT bookings_no_overlap
    EXCLUDE USING gist (
        listing_id WITH =,
        tstzrange(starts_at, ends_at, '[)') WITH &&
    )
    WHERE (booking_status IN ('pending', 'confirmed', 'active'));

COMMENT ON CONSTRAINT bookings_no_overlap ON public.bookings IS
    'Prevents two active (pending/confirmed/active) bookings for the same listing '
    'from overlapping in time. The authoritative race-safe backstop for '
    'create_marketplace_booking''s pre-insert conflict check.';

-- Align is_booking_available with create_marketplace_booking's blocking set: it
-- was missing 'active', so a checked-in stay showed as "available" and then
-- failed at booking time. Now both use pending/confirmed/active.
CREATE OR REPLACE FUNCTION public.is_booking_available(
    p_listing_id uuid, p_starts_at timestamptz, p_ends_at timestamptz)
RETURNS boolean
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN NOT EXISTS (
        SELECT 1
        FROM public.bookings
        WHERE listing_id = p_listing_id
          AND booking_status IN ('pending', 'confirmed', 'active')
          AND tstzrange(starts_at, ends_at, '[)') && tstzrange(p_starts_at, p_ends_at, '[)')
    );
END;
$function$;
