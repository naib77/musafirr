-- Migration: Auto-complete elapsed confirmed/active bookings
-- Purpose: Resolve the "confirmed but never checked in and the date is over"
-- case. Mirrors expire_stale_bookings() (018) but for the other end of the
-- lifecycle: a booking the host accepted (confirmed) or checked in (active)
-- whose checkout passed is presumed complete after a grace period. This opens
-- the review window and files the booking under past reservations instead of
-- leaving it stranded in "Upcoming" forever.
--
-- Best-practice note: check-in (active) is OPTIONAL bookkeeping, not a gate to
-- completion — so both 'confirmed' and 'active' are auto-completed. A host who
-- needs a different outcome (no-show / dispute) acts within the grace window.
-- The grace period here MUST match BookingRules.autoCompleteGracePeriod (24h).

-- ============================================================================
-- FUNCTION: Auto-complete elapsed bookings
-- ============================================================================

CREATE OR REPLACE FUNCTION public.auto_complete_elapsed_bookings()
RETURNS integer AS $$
DECLARE
    completed_count integer;
    booking_record RECORD;
    listing_record RECORD;
    guest_record RECORD;
BEGIN
    completed_count := 0;

    FOR booking_record IN
        SELECT b.*
        FROM public.bookings b
        WHERE b.booking_status IN ('confirmed', 'active')
        AND b.ends_at < NOW() - INTERVAL '24 hours'
    LOOP
        -- Presume the stay happened: move to completed and stamp completed_at.
        UPDATE public.bookings
        SET
            booking_status = 'completed',
            completed_at = NOW()
        WHERE id = booking_record.id;

        -- Listing info for notifications
        SELECT l.title, l.owner_id INTO listing_record
        FROM public.listings l
        WHERE l.id = booking_record.listing_id;

        -- Guest info
        SELECT p.full_name INTO guest_record
        FROM public.profiles p
        WHERE p.id = booking_record.tenant_id;

        -- Nudge the guest to leave a review (opens the review window)
        INSERT INTO public.notifications (
            user_id, type, title, body, priority, action_url, data
        ) VALUES (
            booking_record.tenant_id,
            'review_prompt'::notification_type,
            'How was your stay?',
            format('Your stay at %s is complete. Leave a review to help other travelers!',
                COALESCE(listing_record.title, 'the property')),
            'normal'::notification_priority,
            '/review/' || booking_record.id || '/guest',
            jsonb_build_object(
                'booking_id', booking_record.id,
                'listing_id', booking_record.listing_id,
                'reason', 'auto_completed',
                'completed_at', NOW()
            )
        );

        -- Nudge the host to review the guest
        INSERT INTO public.notifications (
            user_id, type, title, body, priority, action_url, data
        ) VALUES (
            listing_record.owner_id,
            'review_prompt'::notification_type,
            'Reservation completed',
            format('%s''s stay at %s is complete. Leave a review for your guest.',
                COALESCE(guest_record.full_name, 'Your guest'),
                COALESCE(listing_record.title, 'your property')),
            'normal'::notification_priority,
            '/review/' || booking_record.id || '/host',
            jsonb_build_object(
                'booking_id', booking_record.id,
                'listing_id', booking_record.listing_id,
                'reason', 'auto_completed',
                'completed_at', NOW()
            )
        );

        completed_count := completed_count + 1;
    END LOOP;

    IF completed_count > 0 THEN
        RAISE NOTICE 'Auto-completed % elapsed bookings', completed_count;
    END IF;

    RETURN completed_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.auto_complete_elapsed_bookings() IS
    'Completes confirmed/active bookings whose checkout passed >24h ago (grace period). Mirrors BookingRules.autoCompleteGracePeriod.';

GRANT EXECUTE ON FUNCTION public.auto_complete_elapsed_bookings() TO service_role;

-- ============================================================================
-- SCHEDULE (if pg_cron is available)
-- ============================================================================
-- Runs hourly, alongside expire-stale-bookings. If pg_cron is unavailable,
-- trigger via the scheduled-jobs Edge Function / external scheduler instead.

DO $schedule_autocomplete$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'cron') THEN
        BEGIN
            PERFORM cron.unschedule('auto-complete-elapsed-bookings');
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        PERFORM cron.schedule(
            'auto-complete-elapsed-bookings',
            '30 * * * *',
            'SELECT public.auto_complete_elapsed_bookings()'
        );

        RAISE NOTICE 'Scheduled auto-complete-elapsed-bookings';
    ELSE
        RAISE NOTICE 'pg_cron not available. Trigger auto_complete_elapsed_bookings() via Edge Function or external scheduler.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Could not schedule auto-complete job: %. Use Edge Functions instead.', SQLERRM;
END $schedule_autocomplete$;

-- Admin/testing wrapper
CREATE OR REPLACE FUNCTION public.admin_auto_complete_bookings()
RETURNS integer AS $$
BEGIN
    IF current_setting('role') != 'service_role' THEN
        RAISE EXCEPTION 'Only service_role can execute this function';
    END IF;
    RETURN public.auto_complete_elapsed_bookings();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
