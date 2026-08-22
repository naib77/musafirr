-- Migration 098: give a rejection a timestamp, and make bookings.updated_at
-- mean something.
--
-- Two gaps found while building the admin console's booking timeline:
--
--   1. `bookings` stamps confirmed_at, paid_at, actual_check_in, completed_at
--      and cancelled_at — but not rejection. A rejected booking (32 of the 95
--      live rows) could say *that* it was rejected and why, never *when*. The
--      only record of the moment was audit_log, whose trigger only arrived in
--      089, so it covers 2 of the 32.
--
--   2. `bookings_touch_updated_at` was declared in 001 and is absent from the
--      live database — dropped out of band, since no migration removes it. The
--      consequence is that updated_at equals created_at on every row in the
--      table, so nothing can tell when a booking last changed. profiles and
--      listings lost the same trigger; this migration restores only bookings,
--      which is the table the console needs it on.

-- ── 1. rejected_at ─────────────────────────────────────────────────────────

ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS rejected_at timestamptz;

COMMENT ON COLUMN public.bookings.rejected_at IS
  'When booking_status became ''rejected'' — set by trg_set_booking_rejected_at, covering both the host declining and expire_stale_bookings timing out. Never cleared: it records that a rejection happened, which stays true even if an admin later moves the booking on.';

-- Mirrors set_booking_paid_at (079): stamp on entry, never overwrite. BEFORE
-- INSERT OR UPDATE so every write path is covered — the host's decline from the
-- app, expire_stale_bookings / admin_expire_bookings, and an admin's direct
-- update all go through a plain UPDATE on booking_status.
CREATE OR REPLACE FUNCTION public.set_booking_rejected_at()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.booking_status = 'rejected' AND NEW.rejected_at IS NULL THEN
        NEW.rejected_at := now();
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_set_booking_rejected_at ON public.bookings;
CREATE TRIGGER trg_set_booking_rejected_at
    BEFORE INSERT OR UPDATE OF booking_status ON public.bookings
    FOR EACH ROW
    EXECUTE FUNCTION public.set_booking_rejected_at();

-- Backfill from the notification the lifecycle trigger raised at the moment of
-- rejection. That is a recorded event, not an estimate: on the two bookings
-- that also have an audit row, the two timestamps agree to the millisecond.
-- min() because one rejection notifies both parties.
UPDATE public.bookings b
SET rejected_at = n.at
FROM (
    SELECT (data->>'booking_id')::uuid AS booking_id, min(created_at) AS at
    FROM public.notifications
    WHERE type = 'booking_rejected' AND data ? 'booking_id'
    GROUP BY 1
) n
WHERE b.id = n.booking_id
  AND b.booking_status = 'rejected'
  AND b.rejected_at IS NULL;

-- Fallback for any rejection that predates the notification trigger.
UPDATE public.bookings b
SET rejected_at = a.at
FROM (
    SELECT record_id AS booking_id, min(occurred_at) AS at
    FROM public.audit_log
    WHERE table_name = 'bookings'
      AND new_data->>'booking_status' = 'rejected'
    GROUP BY 1
) a
WHERE b.id = a.booking_id
  AND b.booking_status = 'rejected'
  AND b.rejected_at IS NULL;

-- ── 2. updated_at ──────────────────────────────────────────────────────────

-- Re-declared because the live database has neither the function nor the
-- trigger. One deliberate change from 001: `now()` rather than
-- `timezone('utc', now())`. The latter returns a naive timestamp that the
-- timestamptz column then reads back in the session's timezone — correct only
-- while the server stays on UTC. `now()` is already an absolute instant, so it
-- is right in any session. This matches touch_payments_updated_at (072).
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS bookings_touch_updated_at ON public.bookings;
CREATE TRIGGER bookings_touch_updated_at
    BEFORE UPDATE ON public.bookings
    FOR EACH ROW
    EXECUTE FUNCTION public.touch_updated_at();

-- Existing rows keep updated_at = created_at. Reconstructing a "last changed"
-- for them from the stamps we do have would be a guess, and a guess is worse
-- than an obviously untouched value: from here on the column is trustworthy,
-- and before this migration it was never written.

-- Note on trigger order: BEFORE UPDATE triggers fire in name order, so this
-- runs before trg_enforce_booking_update_rules, trg_set_booking_paid_at and
-- trg_set_booking_rejected_at. None of them reads updated_at, and the audit
-- trigger (trg_audit_bookings_upd) has a WHEN clause on the financial columns,
-- so a touch of updated_at alone will not add audit rows.
