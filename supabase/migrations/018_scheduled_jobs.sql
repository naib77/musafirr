-- Migration: Scheduled jobs for booking expiration and review reveal
-- Purpose: Auto-expire pending bookings after 24 hours, auto-reveal reviews after 14 days

-- ============================================================================
-- ENABLE PG_CRON EXTENSION (if available)
-- ============================================================================
-- Note: pg_cron must be enabled in Supabase Dashboard > Database > Extensions
-- If pg_cron is not available, the functions will still work but need to be
-- called manually or via Edge Functions.

DO $$
BEGIN
    -- Try to create pg_cron extension
    CREATE EXTENSION IF NOT EXISTS pg_cron;
    -- Grant usage to postgres
    GRANT USAGE ON SCHEMA cron TO postgres;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron extension not available. Jobs will need to be triggered manually or via Edge Functions.';
END $$;

-- ============================================================================
-- FUNCTION: Expire stale pending bookings
-- ============================================================================
-- Bookings that remain in 'pending' status for more than 24 hours are
-- automatically set to 'rejected' with a system-generated reason.

CREATE OR REPLACE FUNCTION public.expire_stale_bookings()
RETURNS integer AS $$
DECLARE
    expired_count integer;
    booking_record RECORD;
    listing_record RECORD;
    guest_record RECORD;
BEGIN
    expired_count := 0;

    -- Find and expire stale bookings
    FOR booking_record IN
        SELECT b.*
        FROM public.bookings b
        WHERE b.booking_status = 'pending'
        AND b.created_at < NOW() - INTERVAL '24 hours'
    LOOP
        -- Update booking to rejected
        UPDATE public.bookings
        SET
            booking_status = 'rejected',
            rejection_reason = 'Booking request expired after 24 hours without host response'
        WHERE id = booking_record.id;

        -- Get listing info for notification
        SELECT l.title, l.owner_id INTO listing_record
        FROM public.listings l
        WHERE l.id = booking_record.listing_id;

        -- Get guest info
        SELECT p.full_name INTO guest_record
        FROM public.profiles p
        WHERE p.id = booking_record.tenant_id;

        -- Notify guest about expiration
        INSERT INTO public.notifications (
            user_id, type, title, body, priority, action_url, data
        ) VALUES (
            booking_record.tenant_id,
            'booking_rejected'::notification_type,
            'Booking Request Expired',
            format('Your booking request for %s expired. The host did not respond within 24 hours.',
                COALESCE(listing_record.title, 'the property')),
            'normal'::notification_priority,
            '/trips/' || booking_record.id,
            jsonb_build_object(
                'booking_id', booking_record.id,
                'listing_id', booking_record.listing_id,
                'reason', 'expired',
                'expired_at', NOW()
            )
        );

        -- Notify host about missed booking
        INSERT INTO public.notifications (
            user_id, type, title, body, priority, action_url, data
        ) VALUES (
            listing_record.owner_id,
            'booking_cancelled'::notification_type,
            'Booking Request Expired',
            format('A booking request from %s for %s expired because you did not respond within 24 hours.',
                COALESCE(guest_record.full_name, 'a guest'),
                COALESCE(listing_record.title, 'your property')),
            'normal'::notification_priority,
            '/host/reservations/' || booking_record.id,
            jsonb_build_object(
                'booking_id', booking_record.id,
                'listing_id', booking_record.listing_id,
                'reason', 'expired',
                'expired_at', NOW()
            )
        );

        expired_count := expired_count + 1;
    END LOOP;

    -- Log the result
    IF expired_count > 0 THEN
        RAISE NOTICE 'Expired % pending bookings', expired_count;
    END IF;

    RETURN expired_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: Auto-reveal reviews after 14 days
-- ============================================================================
-- Reviews that have been submitted but not revealed for 14 days are
-- automatically revealed, even if the other party hasn't submitted their review.

CREATE OR REPLACE FUNCTION public.auto_reveal_old_reviews()
RETURNS integer AS $$
DECLARE
    revealed_count integer;
    review_record RECORD;
    booking_record RECORD;
    listing_record RECORD;
BEGIN
    revealed_count := 0;

    -- Find reviews older than 14 days that haven't been revealed
    FOR review_record IN
        SELECT r.*
        FROM public.reviews r
        WHERE r.is_revealed = false
        AND r.created_at < NOW() - INTERVAL '14 days'
    LOOP
        -- Reveal the review
        UPDATE public.reviews
        SET
            is_revealed = true,
            revealed_at = NOW()
        WHERE id = review_record.id;

        -- Get booking and listing info for notification
        SELECT b.*, l.title AS listing_title, l.owner_id AS host_id
        INTO booking_record
        FROM public.bookings b
        LEFT JOIN public.listings l ON l.id = b.listing_id
        WHERE b.id = review_record.booking_id;

        -- Notify the reviewee that they received a review
        INSERT INTO public.notifications (
            user_id, type, title, body, priority, action_url, data
        ) VALUES (
            review_record.reviewee_id,
            'review_received'::notification_type,
            'New Review Available',
            CASE
                WHEN review_record.review_type = 'guest_to_host' THEN
                    format('You received a %s star review for %s',
                        review_record.overall_rating,
                        COALESCE(booking_record.listing_title, 'your property'))
                ELSE
                    format('You received a %s star review from a host', review_record.overall_rating)
            END,
            'normal'::notification_priority,
            CASE
                WHEN review_record.review_type = 'guest_to_host' THEN '/listing/' || review_record.listing_id || '/reviews'
                ELSE '/profile/reviews'
            END,
            jsonb_build_object(
                'review_id', review_record.id,
                'booking_id', review_record.booking_id,
                'rating', review_record.overall_rating,
                'review_type', review_record.review_type,
                'auto_revealed', true
            )
        );

        revealed_count := revealed_count + 1;
    END LOOP;

    -- Log the result
    IF revealed_count > 0 THEN
        RAISE NOTICE 'Auto-revealed % reviews', revealed_count;
    END IF;

    RETURN revealed_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: Send review reminders
-- ============================================================================
-- Send reminders to users who haven't submitted reviews for completed bookings
-- after 3 days and 7 days.

CREATE OR REPLACE FUNCTION public.send_review_reminders()
RETURNS integer AS $$
DECLARE
    reminder_count integer;
    booking_record RECORD;
    listing_record RECORD;
    existing_guest_review boolean;
    existing_host_review boolean;
BEGIN
    reminder_count := 0;

    -- Find completed bookings that are 3 or 7 days old
    FOR booking_record IN
        SELECT b.*
        FROM public.bookings b
        WHERE b.booking_status = 'completed'
        AND b.completed_at IS NOT NULL
        AND (
            -- 3-day reminder
            (b.completed_at >= NOW() - INTERVAL '3 days 1 hour'
             AND b.completed_at < NOW() - INTERVAL '3 days')
            OR
            -- 7-day reminder
            (b.completed_at >= NOW() - INTERVAL '7 days 1 hour'
             AND b.completed_at < NOW() - INTERVAL '7 days')
        )
    LOOP
        -- Get listing info
        SELECT l.title, l.owner_id INTO listing_record
        FROM public.listings l
        WHERE l.id = booking_record.listing_id;

        -- Check if guest has already reviewed
        SELECT EXISTS (
            SELECT 1 FROM public.reviews r
            WHERE r.booking_id = booking_record.id
            AND r.review_type = 'guest_to_host'
        ) INTO existing_guest_review;

        -- Check if host has already reviewed
        SELECT EXISTS (
            SELECT 1 FROM public.reviews r
            WHERE r.booking_id = booking_record.id
            AND r.review_type = 'host_to_guest'
        ) INTO existing_host_review;

        -- Send reminder to guest if they haven't reviewed
        IF NOT existing_guest_review THEN
            INSERT INTO public.notifications (
                user_id, type, title, body, priority, action_url, data
            ) VALUES (
                booking_record.tenant_id,
                'review_reminder'::notification_type,
                'Don''t Forget to Review!',
                format('Share your experience at %s. Your review helps other travelers!',
                    COALESCE(listing_record.title, 'your recent stay')),
                'normal'::notification_priority,
                '/review/' || booking_record.id || '/guest',
                jsonb_build_object(
                    'booking_id', booking_record.id,
                    'listing_id', booking_record.listing_id,
                    'reminder_type', 'guest'
                )
            );
            reminder_count := reminder_count + 1;
        END IF;

        -- Send reminder to host if they haven't reviewed
        IF NOT existing_host_review THEN
            INSERT INTO public.notifications (
                user_id, type, title, body, priority, action_url, data
            ) VALUES (
                listing_record.owner_id,
                'review_reminder'::notification_type,
                'Review Your Guest',
                format('Don''t forget to review your guest from %s. Your feedback helps the community!',
                    COALESCE(listing_record.title, 'your property')),
                'normal'::notification_priority,
                '/review/' || booking_record.id || '/host',
                jsonb_build_object(
                    'booking_id', booking_record.id,
                    'listing_id', booking_record.listing_id,
                    'reminder_type', 'host'
                )
            );
            reminder_count := reminder_count + 1;
        END IF;
    END LOOP;

    IF reminder_count > 0 THEN
        RAISE NOTICE 'Sent % review reminders', reminder_count;
    END IF;

    RETURN reminder_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- SCHEDULE CRON JOBS (if pg_cron is available)
-- ============================================================================
-- Note: These jobs run in the postgres database context
-- If pg_cron is not available, use the Edge Function at:
--   supabase/functions/scheduled-jobs/index.ts

DO $schedule_jobs$
BEGIN
    -- Check if cron schema exists (pg_cron is enabled)
    IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'cron') THEN
        -- Remove existing jobs if they exist (ignore errors)
        BEGIN
            PERFORM cron.unschedule('expire-stale-bookings');
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        BEGIN
            PERFORM cron.unschedule('auto-reveal-reviews');
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        BEGIN
            PERFORM cron.unschedule('send-review-reminders');
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        -- Run booking expiration every hour
        PERFORM cron.schedule(
            'expire-stale-bookings',
            '0 * * * *',
            'SELECT public.expire_stale_bookings()'
        );

        -- Run review auto-reveal daily at 2 AM UTC
        PERFORM cron.schedule(
            'auto-reveal-reviews',
            '0 2 * * *',
            'SELECT public.auto_reveal_old_reviews()'
        );

        -- Run review reminders daily at 10 AM UTC
        PERFORM cron.schedule(
            'send-review-reminders',
            '0 10 * * *',
            'SELECT public.send_review_reminders()'
        );

        RAISE NOTICE 'Cron jobs scheduled successfully';
    ELSE
        RAISE NOTICE 'pg_cron not available. Use Edge Functions or external scheduler to trigger jobs.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Could not schedule cron jobs: %. Use Edge Functions instead.', SQLERRM;
END $schedule_jobs$;

-- ============================================================================
-- ADD REVIEW_REMINDER NOTIFICATION TYPE (if not exists)
-- ============================================================================

DO $$
BEGIN
    BEGIN
        ALTER TYPE notification_type ADD VALUE 'review_reminder';
    EXCEPTION WHEN duplicate_object THEN
        NULL;
    END;
    BEGIN
        ALTER TYPE notification_type ADD VALUE 'review_received';
    EXCEPTION WHEN duplicate_object THEN
        NULL;
    END;
END $$;

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.expire_stale_bookings() TO service_role;
GRANT EXECUTE ON FUNCTION public.auto_reveal_old_reviews() TO service_role;
GRANT EXECUTE ON FUNCTION public.send_review_reminders() TO service_role;

-- ============================================================================
-- MANUAL EXECUTION FUNCTIONS (for testing/admin)
-- ============================================================================

-- Wrapper function to manually trigger expiration (for testing)
CREATE OR REPLACE FUNCTION public.admin_expire_bookings()
RETURNS integer AS $$
BEGIN
    -- Only allow service_role to execute
    IF current_setting('role') != 'service_role' THEN
        RAISE EXCEPTION 'Only service_role can execute this function';
    END IF;

    RETURN public.expire_stale_bookings();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Wrapper function to manually trigger review reveal (for testing)
CREATE OR REPLACE FUNCTION public.admin_reveal_reviews()
RETURNS integer AS $$
BEGIN
    -- Only allow service_role to execute
    IF current_setting('role') != 'service_role' THEN
        RAISE EXCEPTION 'Only service_role can execute this function';
    END IF;

    RETURN public.auto_reveal_old_reviews();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.expire_stale_bookings() IS 'Expires pending bookings older than 24 hours';
COMMENT ON FUNCTION public.auto_reveal_old_reviews() IS 'Auto-reveals reviews older than 14 days';
COMMENT ON FUNCTION public.send_review_reminders() IS 'Sends review reminders at 3 and 7 days after checkout';
