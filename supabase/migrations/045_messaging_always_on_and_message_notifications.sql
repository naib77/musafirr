-- Migration: Messaging always-on + notifications for new messages
--
-- 1. New chat messages now create an in-app notification for the recipient.
--    The existing on_notification_send_push trigger (015) then delivers the
--    FCM push automatically, and the client already deep-links
--    '/messages/{conversationId}' taps into the conversation.
--    Previously a new message produced NO notification of any kind — users
--    only saw messages if the app was open on the inbox.
--
-- 2. Messaging is never blocked: participants can message each other at any
--    time, including after the booking completes or is cancelled. The old
--    INSERT policy required the booking to be confirmed/active.
--
-- 3. get_or_create_conversation: general (bookingless) conversations are
--    unique per user-pair (uniq_conversation_pair_general, migration 043),
--    but the lookup also matched on listing_id — so an inquiry about a
--    SECOND listing missed the existing row and hit a duplicate-key error.
--    Match general conversations by pair only.

-- ============================================================
-- 1. Notify recipient on new message
-- ============================================================

CREATE OR REPLACE FUNCTION public.notify_recipient_on_new_message()
RETURNS TRIGGER AS $$
DECLARE
    v_recipient_id UUID;
    v_sender_name TEXT;
    v_preview TEXT;
BEGIN
    -- The recipient is the conversation participant who isn't the sender.
    SELECT CASE
             WHEN c.participant_one_id = NEW.sender_id THEN c.participant_two_id
             ELSE c.participant_one_id
           END
    INTO v_recipient_id
    FROM public.conversations c
    WHERE c.id = NEW.conversation_id;

    IF v_recipient_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT COALESCE(p.full_name, 'New message')
    INTO v_sender_name
    FROM public.profiles p
    WHERE p.id = NEW.sender_id;

    v_preview := CASE
        WHEN NEW.content_type = 'text' THEN LEFT(NEW.content, 140)
        WHEN NEW.content_type = 'booking_card' THEN LEFT(NEW.content, 140)
        WHEN NEW.content_type = 'image' THEN '📷 Sent a photo'
        WHEN NEW.content_type = 'location' THEN '📍 Shared a location'
        WHEN NEW.content_type = 'file' THEN '📎 Sent a file'
        ELSE 'Sent a message'
    END;

    -- The on_notification_send_push trigger (migration 015) picks this row
    -- up and delivers the FCM push.
    INSERT INTO public.notifications (
        user_id,
        type,
        title,
        body,
        data,
        group_key,
        action_url
    ) VALUES (
        v_recipient_id,
        'new_message',
        COALESCE(v_sender_name, 'New message'),
        v_preview,
        jsonb_build_object(
            'conversation_id', NEW.conversation_id,
            'message_id', NEW.id,
            'sender_id', NEW.sender_id
        ),
        'conversation_' || NEW.conversation_id,
        '/messages/' || NEW.conversation_id
    );

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Never block the message insert because notifying failed.
        RAISE WARNING 'new-message notification error: %', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_message_notify_recipient ON public.messages;
CREATE TRIGGER on_message_notify_recipient
    AFTER INSERT ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_recipient_on_new_message();

-- ============================================================
-- 2. Participants can always message — no booking-status gate
-- ============================================================

DROP POLICY IF EXISTS "Users can send messages in active bookings" ON public.messages;
DROP POLICY IF EXISTS "Users can send messages" ON public.messages;

CREATE POLICY "Participants can send messages" ON public.messages
  FOR INSERT WITH CHECK (
    auth.uid() = sender_id
    AND EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = conversation_id
      AND (c.participant_one_id = auth.uid() OR c.participant_two_id = auth.uid())
    )
  );

COMMENT ON POLICY "Participants can send messages" ON public.messages IS
    'Conversation participants can always message each other — before, during, and after a booking.';

-- ============================================================
-- 3. General conversations match by user-pair only
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_or_create_conversation(
  user_one UUID,
  user_two UUID,
  p_booking_id UUID DEFAULT NULL,
  p_listing_id UUID DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
  conv_id UUID;
BEGIN
  IF p_booking_id IS NULL THEN
    -- General/inquiry chat: one per user-pair regardless of listing
    -- (matches uniq_conversation_pair_general).
    SELECT id INTO conv_id FROM public.conversations
    WHERE LEAST(participant_one_id, participant_two_id) = LEAST(user_one, user_two)
      AND GREATEST(participant_one_id, participant_two_id) = GREATEST(user_one, user_two)
      AND booking_id IS NULL
    LIMIT 1;
  ELSE
    -- Booking chat: one per (user-pair, booking)
    -- (matches uniq_conversation_pair_booking).
    SELECT id INTO conv_id FROM public.conversations
    WHERE (
      (participant_one_id = user_one AND participant_two_id = user_two) OR
      (participant_one_id = user_two AND participant_two_id = user_one)
    )
    AND booking_id = p_booking_id
    LIMIT 1;
  END IF;

  IF conv_id IS NULL THEN
    INSERT INTO public.conversations (participant_one_id, participant_two_id, booking_id, listing_id)
    VALUES (user_one, user_two, p_booking_id, p_listing_id)
    RETURNING id INTO conv_id;
  END IF;

  RETURN conv_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
