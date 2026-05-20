-- =============================================================
-- NOTIFICATIONS SYSTEM MIGRATION
-- Creates tables for notifications, preferences, and push tokens
-- =============================================================

-- Notification type enum
CREATE TYPE notification_type AS ENUM (
    'booking_request',
    'booking_confirmed',
    'booking_cancelled',
    'booking_reminder',
    'check_in_reminder',
    'check_out_reminder',
    'payment_received',
    'payment_failed',
    'refund_processed',
    'review_received',
    'review_reminder',
    'promotion_available',
    'discount_expiring',
    'referral_reward',
    'new_message',
    'message_read',
    'system_alert',
    'account_update',
    'security_alert'
);

-- Notification priority enum
CREATE TYPE notification_priority AS ENUM (
    'low',
    'normal',
    'high',
    'urgent'
);

-- Notification status enum
CREATE TYPE notification_status AS ENUM (
    'unread',
    'read',
    'archived',
    'deleted'
);

-- =============================================================
-- NOTIFICATIONS TABLE
-- =============================================================

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    type notification_type NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    status notification_status NOT NULL DEFAULT 'unread',
    priority notification_priority NOT NULL DEFAULT 'normal',
    data JSONB,
    image_url TEXT,
    action_url TEXT,
    group_key TEXT,
    read_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for common queries
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_user_status ON notifications(user_id, status);
CREATE INDEX idx_notifications_user_created ON notifications(user_id, created_at DESC);
CREATE INDEX idx_notifications_type ON notifications(type);
CREATE INDEX idx_notifications_group_key ON notifications(group_key) WHERE group_key IS NOT NULL;
CREATE INDEX idx_notifications_expires ON notifications(expires_at) WHERE expires_at IS NOT NULL;

-- Update timestamp trigger
CREATE OR REPLACE FUNCTION update_notifications_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notifications_updated_at
    BEFORE UPDATE ON notifications
    FOR EACH ROW
    EXECUTE FUNCTION update_notifications_updated_at();

-- =============================================================
-- NOTIFICATION PREFERENCES TABLE
-- =============================================================

CREATE TABLE IF NOT EXISTS notification_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    global_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    quiet_hours_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    quiet_hours_start TIME DEFAULT '22:00',
    quiet_hours_end TIME DEFAULT '07:00',
    quiet_hours_allow_urgent BOOLEAN NOT NULL DEFAULT TRUE,
    category_preferences JSONB NOT NULL DEFAULT '{}',
    email TEXT,
    phone_number TEXT,
    whatsapp_number TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT notification_preferences_user_unique UNIQUE(user_id)
);

-- Index for user lookup
CREATE INDEX idx_notification_preferences_user ON notification_preferences(user_id);

-- Update timestamp trigger
CREATE TRIGGER notification_preferences_updated_at
    BEFORE UPDATE ON notification_preferences
    FOR EACH ROW
    EXECUTE FUNCTION update_notifications_updated_at();

-- =============================================================
-- PUSH TOKENS TABLE
-- =============================================================

CREATE TABLE IF NOT EXISTS push_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
    device_id TEXT NOT NULL,
    device_name TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT push_tokens_user_device_unique UNIQUE(user_id, device_id)
);

-- Indexes
CREATE INDEX idx_push_tokens_user ON push_tokens(user_id);
CREATE INDEX idx_push_tokens_active ON push_tokens(user_id, is_active) WHERE is_active = TRUE;
CREATE INDEX idx_push_tokens_token ON push_tokens(token);

-- Update timestamp trigger
CREATE TRIGGER push_tokens_updated_at
    BEFORE UPDATE ON push_tokens
    FOR EACH ROW
    EXECUTE FUNCTION update_notifications_updated_at();

-- =============================================================
-- ROW LEVEL SECURITY POLICIES
-- =============================================================

-- Enable RLS
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE push_tokens ENABLE ROW LEVEL SECURITY;

-- Notifications: Users can only access their own notifications
CREATE POLICY notifications_select_own ON notifications
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY notifications_update_own ON notifications
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY notifications_delete_own ON notifications
    FOR DELETE USING (auth.uid() = user_id);

-- System can insert notifications for any user (via service role)
CREATE POLICY notifications_insert_service ON notifications
    FOR INSERT WITH CHECK (TRUE);

-- Notification Preferences: Users can only access their own preferences
CREATE POLICY notification_preferences_select_own ON notification_preferences
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY notification_preferences_insert_own ON notification_preferences
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY notification_preferences_update_own ON notification_preferences
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY notification_preferences_delete_own ON notification_preferences
    FOR DELETE USING (auth.uid() = user_id);

-- Push Tokens: Users can only access their own tokens
CREATE POLICY push_tokens_select_own ON push_tokens
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY push_tokens_insert_own ON push_tokens
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY push_tokens_update_own ON push_tokens
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY push_tokens_delete_own ON push_tokens
    FOR DELETE USING (auth.uid() = user_id);

-- =============================================================
-- FUNCTIONS FOR NOTIFICATION MANAGEMENT
-- =============================================================

-- Function to get unread count for a user
CREATE OR REPLACE FUNCTION get_unread_notification_count(p_user_id UUID)
RETURNS INTEGER AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)::INTEGER
        FROM notifications
        WHERE user_id = p_user_id AND status = 'unread'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to mark all notifications as read for a user
CREATE OR REPLACE FUNCTION mark_all_notifications_read(p_user_id UUID)
RETURNS INTEGER AS $$
DECLARE
    affected_rows INTEGER;
BEGIN
    UPDATE notifications
    SET status = 'read', read_at = NOW()
    WHERE user_id = p_user_id AND status = 'unread';

    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    RETURN affected_rows;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to cleanup expired notifications
CREATE OR REPLACE FUNCTION cleanup_expired_notifications()
RETURNS INTEGER AS $$
DECLARE
    affected_rows INTEGER;
BEGIN
    UPDATE notifications
    SET status = 'archived'
    WHERE expires_at IS NOT NULL
      AND expires_at < NOW()
      AND status NOT IN ('archived', 'deleted');

    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    RETURN affected_rows;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================
-- REALTIME CONFIGURATION
-- =============================================================

-- Enable realtime for notifications table
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;

-- =============================================================
-- BOOKING NOTIFICATION TRIGGERS
-- =============================================================

-- Function to create notification when booking status changes
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

-- Trigger for booking notifications
CREATE TRIGGER booking_notification_trigger
    AFTER INSERT OR UPDATE ON bookings
    FOR EACH ROW
    EXECUTE FUNCTION notify_on_booking_change();

-- =============================================================
-- SCHEDULED NOTIFICATION JOBS (requires pg_cron extension)
-- =============================================================

-- Cleanup expired notifications daily at 3 AM
-- SELECT cron.schedule('cleanup-expired-notifications', '0 3 * * *', 'SELECT cleanup_expired_notifications()');

-- =============================================================
-- COMMENTS
-- =============================================================

COMMENT ON TABLE notifications IS 'User notifications for various events in the system';
COMMENT ON TABLE notification_preferences IS 'User preferences for receiving notifications';
COMMENT ON TABLE push_tokens IS 'FCM push notification tokens for user devices';
COMMENT ON COLUMN notifications.group_key IS 'Key for grouping related notifications (e.g., booking_123)';
COMMENT ON COLUMN notifications.expires_at IS 'When the notification should be auto-archived (for time-sensitive notifications)';
