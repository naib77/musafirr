-- =============================================
-- Database Trigger for Booking Push Notifications
-- =============================================

-- Function to send push notification when booking is created
CREATE OR REPLACE FUNCTION notify_host_on_booking()
RETURNS TRIGGER AS $$
DECLARE
    v_host_id UUID;
    v_listing_title TEXT;
    v_guest_name TEXT;
    v_check_in TEXT;
    v_check_out TEXT;
    v_supabase_url TEXT;
    v_service_role_key TEXT;
BEGIN
    -- Get the listing details and host ID
    SELECT l.owner_id, l.title
    INTO v_host_id, v_listing_title
    FROM public.listings l
    WHERE l.id = NEW.listing_id;

    -- Get guest name from profiles
    SELECT COALESCE(p.full_name, p.phone, 'A guest')
    INTO v_guest_name
    FROM public.profiles p
    WHERE p.id = NEW.tenant_id;

    -- Format dates
    v_check_in := to_char(NEW.check_in, 'Mon DD, YYYY');
    v_check_out := to_char(NEW.check_out, 'Mon DD, YYYY');

    -- Insert in-app notification for host
    INSERT INTO public.notifications (
        user_id,
        type,
        title,
        body,
        data,
        action_url
    ) VALUES (
        v_host_id,
        'booking_request',
        'New Booking Request',
        v_guest_name || ' wants to book "' || v_listing_title || '" from ' || v_check_in || ' to ' || v_check_out,
        jsonb_build_object(
            'booking_id', NEW.id,
            'listing_id', NEW.listing_id,
            'guest_name', v_guest_name,
            'check_in', NEW.check_in,
            'check_out', NEW.check_out
        ),
        '/host/reservations/' || NEW.id
    );

    -- Call Edge Function to send push notification
    -- Note: This uses pg_net extension for async HTTP calls
    -- If pg_net is not available, the in-app notification above still works
    BEGIN
        PERFORM net.http_post(
            url := current_setting('app.supabase_url', true) || '/functions/v1/send-push-notification',
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || current_setting('app.supabase_service_role_key', true)
            ),
            body := jsonb_build_object(
                'user_id', v_host_id,
                'title', 'New Booking Request',
                'body', v_guest_name || ' wants to book "' || v_listing_title || '"',
                'data', jsonb_build_object(
                    'type', 'booking_request',
                    'booking_id', NEW.id::text,
                    'action_url', '/host/reservations/' || NEW.id
                )
            )::text
        );
    EXCEPTION
        WHEN OTHERS THEN
            -- Log error but don't fail the booking
            RAISE WARNING 'Failed to send push notification: %', SQLERRM;
    END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger on bookings table
DROP TRIGGER IF EXISTS on_booking_created_notify_host ON public.bookings;

CREATE TRIGGER on_booking_created_notify_host
    AFTER INSERT ON public.bookings
    FOR EACH ROW
    EXECUTE FUNCTION notify_host_on_booking();

-- Function to notify guest when booking is confirmed
CREATE OR REPLACE FUNCTION notify_guest_on_booking_confirmed()
RETURNS TRIGGER AS $$
DECLARE
    v_listing_title TEXT;
    v_host_name TEXT;
    v_check_in TEXT;
BEGIN
    -- Only trigger when status changes to 'confirmed'
    IF NEW.status = 'confirmed' AND (OLD.status IS NULL OR OLD.status != 'confirmed') THEN
        -- Get listing details
        SELECT l.title, COALESCE(p.full_name, 'Host')
        INTO v_listing_title, v_host_name
        FROM public.listings l
        LEFT JOIN public.profiles p ON p.id = l.owner_id
        WHERE l.id = NEW.listing_id;

        v_check_in := to_char(NEW.check_in, 'Mon DD, YYYY');

        -- Insert in-app notification for guest
        INSERT INTO public.notifications (
            user_id,
            type,
            title,
            body,
            data,
            action_url
        ) VALUES (
            NEW.tenant_id,
            'booking_confirmed',
            'Booking Confirmed!',
            'Your booking at "' || v_listing_title || '" has been confirmed. Check-in: ' || v_check_in,
            jsonb_build_object(
                'booking_id', NEW.id,
                'listing_id', NEW.listing_id,
                'host_name', v_host_name,
                'check_in', NEW.check_in
            ),
            '/trips/' || NEW.id
        );

        -- Send push notification to guest
        BEGIN
            PERFORM net.http_post(
                url := current_setting('app.supabase_url', true) || '/functions/v1/send-push-notification',
                headers := jsonb_build_object(
                    'Content-Type', 'application/json',
                    'Authorization', 'Bearer ' || current_setting('app.supabase_service_role_key', true)
                ),
                body := jsonb_build_object(
                    'user_id', NEW.tenant_id,
                    'title', 'Booking Confirmed!',
                    'body', 'Your booking at "' || v_listing_title || '" has been confirmed',
                    'data', jsonb_build_object(
                        'type', 'booking_confirmed',
                        'booking_id', NEW.id::text,
                        'action_url', '/trips/' || NEW.id
                    )
                )::text
            );
        EXCEPTION
            WHEN OTHERS THEN
                RAISE WARNING 'Failed to send push notification: %', SQLERRM;
        END;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for booking confirmation
DROP TRIGGER IF EXISTS on_booking_confirmed_notify_guest ON public.bookings;

CREATE TRIGGER on_booking_confirmed_notify_guest
    AFTER UPDATE ON public.bookings
    FOR EACH ROW
    EXECUTE FUNCTION notify_guest_on_booking_confirmed();

-- Function to notify on booking cancellation
CREATE OR REPLACE FUNCTION notify_on_booking_cancelled()
RETURNS TRIGGER AS $$
DECLARE
    v_listing_title TEXT;
    v_notify_user_id UUID;
    v_cancelled_by TEXT;
BEGIN
    -- Only trigger when status changes to 'cancelled'
    IF NEW.status = 'cancelled' AND (OLD.status IS NULL OR OLD.status != 'cancelled') THEN
        -- Get listing title
        SELECT l.title INTO v_listing_title
        FROM public.listings l
        WHERE l.id = NEW.listing_id;

        -- Notify both host and guest
        -- Notify guest
        INSERT INTO public.notifications (
            user_id,
            type,
            title,
            body,
            data,
            action_url
        ) VALUES (
            NEW.tenant_id,
            'booking_cancelled',
            'Booking Cancelled',
            'Your booking at "' || v_listing_title || '" has been cancelled',
            jsonb_build_object('booking_id', NEW.id, 'listing_id', NEW.listing_id),
            '/trips/' || NEW.id
        );

        -- Send push to guest
        BEGIN
            PERFORM net.http_post(
                url := current_setting('app.supabase_url', true) || '/functions/v1/send-push-notification',
                headers := jsonb_build_object(
                    'Content-Type', 'application/json',
                    'Authorization', 'Bearer ' || current_setting('app.supabase_service_role_key', true)
                ),
                body := jsonb_build_object(
                    'user_id', NEW.tenant_id,
                    'title', 'Booking Cancelled',
                    'body', 'Your booking at "' || v_listing_title || '" has been cancelled',
                    'data', jsonb_build_object(
                        'type', 'booking_cancelled',
                        'booking_id', NEW.id::text
                    )
                )::text
            );
        EXCEPTION
            WHEN OTHERS THEN
                RAISE WARNING 'Failed to send push notification: %', SQLERRM;
        END;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for booking cancellation
DROP TRIGGER IF EXISTS on_booking_cancelled_notify ON public.bookings;

CREATE TRIGGER on_booking_cancelled_notify
    AFTER UPDATE ON public.bookings
    FOR EACH ROW
    EXECUTE FUNCTION notify_on_booking_cancelled();
