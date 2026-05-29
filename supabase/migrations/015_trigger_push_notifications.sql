-- =============================================
-- Trigger to Send Push Notifications when notification is created
-- Uses pg_net extension to call Edge Function
-- =============================================

-- Function to send push notification when a notification row is inserted
CREATE OR REPLACE FUNCTION send_push_on_notification_insert()
RETURNS TRIGGER AS $$
BEGIN
    -- Call the Edge Function to send push notification
    -- pg_net makes async HTTP calls
    PERFORM net.http_post(
        url := 'https://bojkmonskqlhuakxhzcb.supabase.co/functions/v1/send-push-notification',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJvamttb25za3FsaHVha3hoemNiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDcwNTcwMTQsImV4cCI6MjA2MjYzMzAxNH0.gPd0QWSQ2XNjBccqEST97fqAV2HP9NMqwShTqpJlilk'
        ),
        body := jsonb_build_object(
            'user_id', NEW.user_id,
            'title', NEW.title,
            'body', NEW.body,
            'data', COALESCE(NEW.data, '{}'::jsonb) || jsonb_build_object(
                'type', NEW.type::text,
                'notification_id', NEW.id::text,
                'action_url', COALESCE(NEW.action_url, '')
            )
        )
    );

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Log error but don't fail the notification insert
        RAISE WARNING 'Push notification error: %', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing trigger if exists
DROP TRIGGER IF EXISTS on_notification_send_push ON public.notifications;

-- Create trigger on notifications table
CREATE TRIGGER on_notification_send_push
    AFTER INSERT ON public.notifications
    FOR EACH ROW
    EXECUTE FUNCTION send_push_on_notification_insert();

-- Grant permissions
GRANT USAGE ON SCHEMA net TO postgres, service_role;
