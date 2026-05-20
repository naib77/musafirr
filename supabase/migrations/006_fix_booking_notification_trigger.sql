-- =============================================================
-- FIX BOOKING NOTIFICATION TRIGGER
-- Fixes column references and enables the trigger
-- =============================================================

-- Drop existing trigger if exists (safe to re-run)
DROP TRIGGER IF EXISTS booking_notification_trigger ON bookings;

-- Recreate the function with correct column names
CREATE OR REPLACE FUNCTION notify_on_booking_change()
RETURNS TRIGGER AS $$
DECLARE
    v_host_id UUID;
    v_guest_id UUID;
    v_listing_title TEXT;
BEGIN
    -- Get listing owner (host) and title
    SELECT l.owner_id, l.title INTO v_host_id, v_listing_title
    FROM listings l WHERE l.id = NEW.listing_id;

    v_guest_id := NEW.tenant_id;

    -- Determine notification type based on status change
    IF TG_OP = 'INSERT' THEN
        -- New booking request - notify host
        INSERT INTO notifications (user_id, type, title, body, priority, data, action_url, group_key)
        VALUES (
            v_host_id,
            'booking_request',
            'New Booking Request',
            format('%s wants to book "%s"', COALESCE(NEW.tenant_name, 'A guest'), v_listing_title),
            'high',
            jsonb_build_object(
                'booking_id', NEW.id,
                'listing_id', NEW.listing_id,
                'tenant_id', NEW.tenant_id,
                'tenant_name', NEW.tenant_name,
                'starts_at', NEW.starts_at,
                'ends_at', NEW.ends_at,
                'total_price', NEW.total_price
            ),
            format('/host/reservations/%s', NEW.id),
            format('booking_%s', NEW.id)
        );
    ELSIF TG_OP = 'UPDATE' THEN
        -- Status changed
        IF OLD.booking_status IS DISTINCT FROM NEW.booking_status THEN
            CASE NEW.booking_status
                WHEN 'confirmed' THEN
                    -- Notify guest of confirmation
                    INSERT INTO notifications (user_id, type, title, body, priority, data, action_url, group_key)
                    VALUES (
                        v_guest_id,
                        'booking_confirmed',
                        'Booking Confirmed!',
                        format('Your booking at "%s" has been confirmed', v_listing_title),
                        'high',
                        jsonb_build_object(
                            'booking_id', NEW.id,
                            'listing_id', NEW.listing_id,
                            'starts_at', NEW.starts_at,
                            'ends_at', NEW.ends_at
                        ),
                        format('/trips/%s', NEW.id),
                        format('booking_%s', NEW.id)
                    );
                WHEN 'cancelled' THEN
                    -- Notify both parties
                    INSERT INTO notifications (user_id, type, title, body, priority, data, action_url, group_key)
                    VALUES
                    (
                        v_guest_id,
                        'booking_cancelled',
                        'Booking Cancelled',
                        format('Your booking at "%s" has been cancelled', v_listing_title),
                        'high',
                        jsonb_build_object('booking_id', NEW.id, 'listing_id', NEW.listing_id),
                        format('/trips/%s', NEW.id),
                        format('booking_%s', NEW.id)
                    ),
                    (
                        v_host_id,
                        'booking_cancelled',
                        'Booking Cancelled',
                        format('A booking for "%s" has been cancelled', v_listing_title),
                        'normal',
                        jsonb_build_object('booking_id', NEW.id, 'listing_id', NEW.listing_id),
                        format('/host/reservations/%s', NEW.id),
                        format('booking_%s', NEW.id)
                    );
                WHEN 'completed' THEN
                    -- Notify guest to leave a review
                    INSERT INTO notifications (user_id, type, title, body, priority, data, action_url, group_key)
                    VALUES (
                        v_guest_id,
                        'review_reminder',
                        'How was your stay?',
                        format('Share your experience at "%s"', v_listing_title),
                        'normal',
                        jsonb_build_object('booking_id', NEW.id, 'listing_id', NEW.listing_id),
                        format('/review/%s', NEW.id),
                        format('booking_%s', NEW.id)
                    );
                ELSE
                    -- No notification for other status changes
                    NULL;
            END CASE;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger
CREATE TRIGGER booking_notification_trigger
    AFTER INSERT OR UPDATE ON bookings
    FOR EACH ROW
    EXECUTE FUNCTION notify_on_booking_change();

-- Grant execute permission to authenticated users (for RLS to work)
GRANT EXECUTE ON FUNCTION notify_on_booking_change() TO authenticated;
