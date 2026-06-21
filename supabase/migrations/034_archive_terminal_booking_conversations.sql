-- ============================================
-- Archive conversations whose booking is already over
-- ============================================
-- The archive_conversation_on_booking_end trigger (030) is forward-only: it
-- fires on future booking status changes. Conversations tied to bookings that
-- were ALREADY terminal (completed/cancelled/rejected) when 030 ran — and only
-- linked to those bookings by 031/032 — were never archived. They remain
-- status='active', so the chat UI shows a message input, but the messages
-- INSERT policy (030) blocks the send because the booking is terminal → 42501.
--
-- This aligns conversation status with booking status for existing rows. New
-- transitions are handled by the trigger going forward.

UPDATE public.conversations c
SET status = 'archived', updated_at = NOW()
FROM public.bookings b
WHERE c.booking_id = b.id
  AND c.status = 'active'
  AND b.booking_status IN ('completed', 'cancelled', 'rejected');

DO $$
DECLARE
    archived_count INTEGER;
BEGIN
    GET DIAGNOSTICS archived_count = ROW_COUNT;
    RAISE NOTICE 'Archived % conversations tied to terminal bookings', archived_count;
END $$;
