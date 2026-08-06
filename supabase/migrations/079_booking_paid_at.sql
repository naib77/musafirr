-- Migration 079: Record WHEN a booking was paid, for accurate month-by-month
-- host earnings.
--
-- Earnings are now payment-driven (078-era client change), but "this month"
-- could only be attributed by completed_at / checkout — bookings have no payment
-- timestamp (payment dates live only in the payments table). This adds a
-- `paid_at` column, stamped automatically whenever payment_status flips to
-- 'paid' — covering BOTH settle paths (the SSLCommerz IPN and mark_cash_payment
-- both do a direct UPDATE on bookings.payment_status) via a trigger, so no edge
-- function redeploy is needed.

ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS paid_at timestamptz;

-- Stamp paid_at the moment payment_status becomes 'paid' (and never overwrite an
-- existing value). BEFORE INSERT OR UPDATE so every write path is covered.
CREATE OR REPLACE FUNCTION public.set_booking_paid_at()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.payment_status = 'paid' AND NEW.paid_at IS NULL THEN
        NEW.paid_at := now();
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_set_booking_paid_at ON public.bookings;
CREATE TRIGGER trg_set_booking_paid_at
    BEFORE INSERT OR UPDATE OF payment_status ON public.bookings
    FOR EACH ROW
    EXECUTE FUNCTION public.set_booking_paid_at();

-- Backfill existing paid bookings from the authoritative payments table: the
-- earliest 'paid' payment row's validated_at (fallback created_at).
UPDATE public.bookings b
SET paid_at = p.ts
FROM (
    SELECT booking_id, min(COALESCE(validated_at, created_at)) AS ts
    FROM public.payments
    WHERE status = 'paid'
    GROUP BY booking_id
) p
WHERE b.id = p.booking_id
  AND b.payment_status = 'paid'
  AND b.paid_at IS NULL;

-- Safety net for any paid booking with no matching payments row (shouldn't
-- happen, but keep paid_at non-null so month attribution has something to use).
UPDATE public.bookings
SET paid_at = COALESCE(completed_at, created_at)
WHERE payment_status = 'paid' AND paid_at IS NULL;
