-- Migration: Booking lifecycle notification triggers
-- Purpose: Send notifications for all booking lifecycle events

-- ============================================================================
-- DROP OLD TRIGGERS FIRST
-- ============================================================================

-- Drop the old booking notification trigger (from 002_notifications.sql)
DROP TRIGGER IF EXISTS booking_notification_trigger ON public.bookings;

-- ============================================================================
-- ENHANCED BOOKING NOTIFICATION TRIGGER
-- ============================================================================

CREATE OR REPLACE FUNCTION public.notify_on_booking_lifecycle()
RETURNS TRIGGER AS $$
DECLARE
    listing_record RECORD;
    guest_record RECORD;
    notification_title text;
    notification_body text;
    notification_type text;
    notification_priority text;
    target_user_id uuid;
    action_url text;
BEGIN
    -- Get listing info (using owner_id, not host_id)
    SELECT l.title, l.owner_id INTO listing_record
    FROM public.listings l
    WHERE l.id = NEW.listing_id;

    -- Get guest info from profiles
    SELECT p.full_name INTO guest_record
    FROM public.profiles p
    WHERE p.id = NEW.tenant_id;

    -- Handle different status transitions
    CASE
        -- New booking request
        WHEN TG_OP = 'INSERT' AND NEW.booking_status = 'pending' THEN
            notification_title := 'New Booking Request';
            notification_body := format('%s wants to book %s',
                COALESCE(guest_record.full_name, 'A guest'),
                COALESCE(listing_record.title, 'your property'));
            notification_type := 'booking_request';
            notification_priority := 'high';
            target_user_id := listing_record.owner_id;
            action_url := '/host/reservations/' || NEW.id;

        -- Booking confirmed
        WHEN TG_OP = 'UPDATE' AND OLD.booking_status = 'pending' AND NEW.booking_status = 'confirmed' THEN
            notification_title := 'Booking Confirmed!';
            notification_body := format('Your booking at %s has been confirmed',
                COALESCE(listing_record.title, 'the property'));
            notification_type := 'booking_confirmed';
            notification_priority := 'high';
            target_user_id := NEW.tenant_id;
            action_url := '/trips/' || NEW.id;

        -- Booking rejected
        WHEN TG_OP = 'UPDATE' AND OLD.booking_status = 'pending' AND NEW.booking_status = 'rejected' THEN
            notification_title := 'Booking Declined';
            notification_body := CASE
                WHEN NEW.rejection_reason IS NOT NULL THEN
                    format('Your booking was declined: %s', NEW.rejection_reason)
                ELSE
                    format('Your booking at %s was declined', COALESCE(listing_record.title, 'the property'))
            END;
            notification_type := 'booking_rejected';
            notification_priority := 'normal';
            target_user_id := NEW.tenant_id;
            action_url := '/trips/' || NEW.id;

        -- Guest checked in
        WHEN TG_OP = 'UPDATE' AND OLD.booking_status = 'confirmed' AND NEW.booking_status = 'active' THEN
            notification_title := 'Enjoy Your Stay!';
            notification_body := format('You are now checked in at %s',
                COALESCE(listing_record.title, 'the property'));
            notification_type := 'checked_in';
            notification_priority := 'normal';
            target_user_id := NEW.tenant_id;
            action_url := '/trips/' || NEW.id;

        -- Service completed
        WHEN TG_OP = 'UPDATE' AND OLD.booking_status = 'active' AND NEW.booking_status = 'completed' THEN
            -- Notify guest to leave review
            notification_title := 'How Was Your Stay?';
            notification_body := format('Your stay at %s is complete. Leave a review!',
                COALESCE(listing_record.title, 'the property'));
            notification_type := 'review_prompt';
            notification_priority := 'normal';
            target_user_id := NEW.tenant_id;
            action_url := '/review/' || NEW.id || '/guest';

            -- Insert notification for guest
            INSERT INTO public.notifications (
                user_id, type, title, body, priority, action_url, data
            ) VALUES (
                target_user_id,
                notification_type::notification_type,
                notification_title,
                notification_body,
                notification_priority::notification_priority,
                action_url,
                jsonb_build_object(
                    'booking_id', NEW.id,
                    'listing_id', NEW.listing_id,
                    'listing_title', listing_record.title
                )
            );

            -- Also notify host to leave review
            notification_title := 'Leave a Guest Review';
            notification_body := format('Your guest %s has checked out. Leave a review!',
                COALESCE(guest_record.full_name, 'your guest'));
            target_user_id := listing_record.owner_id;
            action_url := '/review/' || NEW.id || '/host';

        -- Booking cancelled by guest
        WHEN TG_OP = 'UPDATE' AND NEW.booking_status = 'cancelled' AND NEW.cancelled_by = NEW.tenant_id THEN
            notification_title := 'Booking Cancelled';
            notification_body := format('%s cancelled their booking at %s',
                COALESCE(guest_record.full_name, 'A guest'),
                COALESCE(listing_record.title, 'your property'));
            notification_type := 'booking_cancelled';
            notification_priority := 'high';
            target_user_id := listing_record.owner_id;
            action_url := '/host/reservations/' || NEW.id;

        -- Booking cancelled by host
        WHEN TG_OP = 'UPDATE' AND NEW.booking_status = 'cancelled' AND NEW.cancelled_by != NEW.tenant_id THEN
            notification_title := 'Booking Cancelled by Host';
            notification_body := format('Your booking at %s was cancelled by the host',
                COALESCE(listing_record.title, 'the property'));
            notification_type := 'booking_cancelled';
            notification_priority := 'high';
            target_user_id := NEW.tenant_id;
            action_url := '/trips/' || NEW.id;

        ELSE
            -- No notification needed for other cases
            RETURN NEW;
    END CASE;

    -- Insert notification
    INSERT INTO public.notifications (
        user_id, type, title, body, priority, action_url, data
    ) VALUES (
        target_user_id,
        notification_type::notification_type,
        notification_title,
        notification_body,
        notification_priority::notification_priority,
        action_url,
        jsonb_build_object(
            'booking_id', NEW.id,
            'listing_id', NEW.listing_id,
            'tenant_id', NEW.tenant_id,
            'listing_title', listing_record.title,
            'guest_name', guest_record.full_name,
            'check_in', NEW.starts_at,
            'check_out', NEW.ends_at,
            'total_price', NEW.total_price
        )
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop old trigger if exists
DROP TRIGGER IF EXISTS booking_lifecycle_notifications ON public.bookings;

-- Create new trigger
CREATE TRIGGER booking_lifecycle_notifications
    AFTER INSERT OR UPDATE OF booking_status, cancelled_by
    ON public.bookings
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_on_booking_lifecycle();

-- ============================================================================
-- REVIEW NOTIFICATION TRIGGER
-- ============================================================================

CREATE OR REPLACE FUNCTION public.notify_on_review_revealed()
RETURNS TRIGGER AS $$
DECLARE
    booking_record RECORD;
    listing_record RECORD;
BEGIN
    -- Only trigger when review is revealed
    IF NEW.is_revealed = true AND (OLD.is_revealed = false OR OLD IS NULL) THEN
        -- Get booking and listing info
        SELECT b.*, l.title AS listing_title, l.owner_id
        INTO booking_record
        FROM public.bookings b
        LEFT JOIN public.listings l ON l.id = b.listing_id
        WHERE b.id = NEW.booking_id;

        -- Notify the reviewee that they received a review
        INSERT INTO public.notifications (
            user_id, type, title, body, priority, action_url, data
        ) VALUES (
            NEW.reviewee_id,
            'review_received'::notification_type,
            'New Review',
            CASE
                WHEN NEW.review_type = 'guest_to_host' THEN
                    format('You received a %s star review for %s',
                        NEW.overall_rating,
                        COALESCE(booking_record.listing_title, 'your property'))
                ELSE
                    format('You received a %s star review from a host', NEW.overall_rating)
            END,
            'normal'::notification_priority,
            CASE
                WHEN NEW.review_type = 'guest_to_host' THEN '/listing/' || NEW.listing_id || '/reviews'
                ELSE '/profile/reviews'
            END,
            jsonb_build_object(
                'review_id', NEW.id,
                'booking_id', NEW.booking_id,
                'rating', NEW.overall_rating,
                'review_type', NEW.review_type
            )
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger
DROP TRIGGER IF EXISTS review_revealed_notification ON public.reviews;
CREATE TRIGGER review_revealed_notification
    AFTER UPDATE OF is_revealed
    ON public.reviews
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_on_review_revealed();

-- ============================================================================
-- REVIEW REMINDER (scheduled job placeholder)
-- ============================================================================

-- This would typically be handled by a pg_cron job or external scheduler
-- Example: Run daily to send reminders for reviews due in 7 days

-- CREATE OR REPLACE FUNCTION public.send_review_reminders()
-- RETURNS void AS $$
-- BEGIN
--     -- Find completed bookings that are 7 days old without reviews
--     INSERT INTO public.notifications (user_id, type, title, body, priority, action_url, data)
--     SELECT
--         b.tenant_id,
--         'review_reminder'::notification_type,
--         'Don''t Forget to Review',
--         format('Share your experience at %s', l.title),
--         'normal'::notification_priority,
--         '/review/' || b.id || '/guest',
--         jsonb_build_object('booking_id', b.id)
--     FROM public.bookings b
--     LEFT JOIN public.listings l ON l.id = b.listing_id
--     WHERE b.booking_status = 'completed'
--     AND b.completed_at <= now() - interval '7 days'
--     AND b.completed_at > now() - interval '8 days'
--     AND NOT EXISTS (
--         SELECT 1 FROM public.reviews r
--         WHERE r.booking_id = b.id AND r.review_type = 'guest_to_host'
--     );
-- END;
-- $$ LANGUAGE plpgsql;
