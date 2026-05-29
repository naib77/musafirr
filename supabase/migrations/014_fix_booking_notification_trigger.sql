-- =============================================
-- Fix Booking Notification Trigger
-- The original trigger referenced non-existent columns
-- =============================================

-- Drop existing triggers that might conflict
DROP TRIGGER IF EXISTS booking_notification_trigger ON public.bookings;
DROP TRIGGER IF EXISTS on_booking_created_notify_host ON public.bookings;
DROP TRIGGER IF EXISTS on_booking_confirmed_notify_guest ON public.bookings;
DROP TRIGGER IF EXISTS on_booking_cancelled_notify ON public.bookings;

-- Drop old functions
DROP FUNCTION IF EXISTS notify_on_booking_change();
DROP FUNCTION IF EXISTS notify_host_on_booking();
DROP FUNCTION IF EXISTS notify_guest_on_booking_confirmed();
DROP FUNCTION IF EXISTS notify_on_booking_cancelled();

-- Create corrected notification function
CREATE OR REPLACE FUNCTION notify_on_booking_change()
RETURNS TRIGGER AS $$
DECLARE
    v_host_id UUID;
    v_guest_id UUID;
    v_listing_title TEXT;
    v_guest_name TEXT;
    v_starts_at TEXT;
    v_ends_at TEXT;
BEGIN
    -- Get listing owner (host) and title
    SELECT l.owner_id, l.title
    INTO v_host_id, v_listing_title
    FROM public.listings l
    WHERE l.id = NEW.listing_id;

    -- Get guest name from profiles
    SELECT COALESCE(p.full_name, p.mobile, 'A guest')
    INTO v_guest_name
    FROM public.profiles p
    WHERE p.id = NEW.tenant_id;

    v_guest_id := NEW.tenant_id;

    -- Format dates
    v_starts_at := to_char(NEW.starts_at, 'Mon DD, YYYY');
    v_ends_at := to_char(NEW.ends_at, 'Mon DD, YYYY');

    -- Determine notification type based on operation
    IF TG_OP = 'INSERT' THEN
        -- New booking request - notify host
        INSERT INTO public.notifications (user_id, type, title, body, priority, data, action_url, group_key)
        VALUES (
            v_host_id,
            'booking_request',
            'New Booking Request',
            v_guest_name || ' wants to book "' || v_listing_title || '" from ' || v_starts_at || ' to ' || v_ends_at,
            'high',
            jsonb_build_object(
                'booking_id', NEW.id,
                'listing_id', NEW.listing_id,
                'tenant_id', NEW.tenant_id,
                'guest_name', v_guest_name,
                'starts_at', NEW.starts_at,
                'ends_at', NEW.ends_at,
                'total_price', NEW.total_price
            ),
            '/host/reservations/' || NEW.id,
            'booking_' || NEW.id
        );

        RAISE NOTICE 'Created booking notification for host %', v_host_id;

    ELSIF TG_OP = 'UPDATE' THEN
        -- Status changed
        IF OLD.booking_status IS DISTINCT FROM NEW.booking_status THEN
            CASE NEW.booking_status
                WHEN 'confirmed' THEN
                    -- Notify guest of confirmation
                    INSERT INTO public.notifications (user_id, type, title, body, priority, data, action_url, group_key)
                    VALUES (
                        v_guest_id,
                        'booking_confirmed',
                        'Booking Confirmed!',
                        'Your booking at "' || v_listing_title || '" has been confirmed. Check-in: ' || v_starts_at,
                        'high',
                        jsonb_build_object(
                            'booking_id', NEW.id,
                            'listing_id', NEW.listing_id,
                            'starts_at', NEW.starts_at,
                            'ends_at', NEW.ends_at
                        ),
                        '/trips/' || NEW.id,
                        'booking_' || NEW.id
                    );

                WHEN 'cancelled' THEN
                    -- Notify guest
                    INSERT INTO public.notifications (user_id, type, title, body, priority, data, action_url, group_key)
                    VALUES (
                        v_guest_id,
                        'booking_cancelled',
                        'Booking Cancelled',
                        'Your booking at "' || v_listing_title || '" has been cancelled',
                        'high',
                        jsonb_build_object('booking_id', NEW.id, 'listing_id', NEW.listing_id),
                        '/trips/' || NEW.id,
                        'booking_' || NEW.id
                    );

                    -- Also notify host
                    INSERT INTO public.notifications (user_id, type, title, body, priority, data, action_url, group_key)
                    VALUES (
                        v_host_id,
                        'booking_cancelled',
                        'Booking Cancelled',
                        'A booking for "' || v_listing_title || '" has been cancelled',
                        'normal',
                        jsonb_build_object('booking_id', NEW.id, 'listing_id', NEW.listing_id),
                        '/host/reservations/' || NEW.id,
                        'booking_' || NEW.id
                    );

                WHEN 'completed' THEN
                    -- Notify guest to leave a review
                    INSERT INTO public.notifications (user_id, type, title, body, priority, data, action_url, group_key)
                    VALUES (
                        v_guest_id,
                        'review_reminder',
                        'How was your stay?',
                        'Share your experience at "' || v_listing_title || '"',
                        'normal',
                        jsonb_build_object('booking_id', NEW.id, 'listing_id', NEW.listing_id),
                        '/review/' || NEW.id,
                        'booking_' || NEW.id
                    );

                ELSE
                    -- No notification for other status changes
                    NULL;
            END CASE;
        END IF;
    END IF;

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Log error but don't fail the booking
        RAISE WARNING 'Notification trigger error: %', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger
CREATE TRIGGER booking_notification_trigger
    AFTER INSERT OR UPDATE ON public.bookings
    FOR EACH ROW
    EXECUTE FUNCTION notify_on_booking_change();

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION notify_on_booking_change() TO authenticated;
GRANT EXECUTE ON FUNCTION notify_on_booking_change() TO service_role;
