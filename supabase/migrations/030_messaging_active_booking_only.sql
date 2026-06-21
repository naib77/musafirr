-- ============================================
-- Restrict messaging to active bookings only
-- ============================================
-- Users can only send messages when:
-- 1. Conversation exists
-- 2. Associated booking status is 'confirmed' or 'active'
-- 3. Sender is a participant in the conversation

-- Drop existing INSERT policy
DROP POLICY IF EXISTS "Users can send messages" ON public.messages;

-- Create new INSERT policy with booking status check
CREATE POLICY "Users can send messages in active bookings" ON public.messages
  FOR INSERT WITH CHECK (
    auth.uid() = sender_id
    AND EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = conversation_id
      AND (c.participant_one_id = auth.uid() OR c.participant_two_id = auth.uid())
      AND (
        -- Allow if no booking_id (general conversation) - for backwards compatibility
        c.booking_id IS NULL
        OR
        -- Allow if booking is confirmed or active
        EXISTS (
          SELECT 1 FROM public.bookings b
          WHERE b.id = c.booking_id
          AND b.booking_status IN ('confirmed', 'active')
        )
      )
    )
  );

-- ============================================
-- Function to auto-archive conversation when booking ends
-- ============================================
CREATE OR REPLACE FUNCTION public.archive_conversation_on_booking_end()
RETURNS TRIGGER AS $$
BEGIN
  -- When booking status changes to completed, cancelled, or rejected
  IF NEW.booking_status IN ('completed', 'cancelled', 'rejected')
     AND OLD.booking_status NOT IN ('completed', 'cancelled', 'rejected') THEN

    -- Archive any conversations linked to this booking
    UPDATE public.conversations
    SET status = 'archived', updated_at = NOW()
    WHERE booking_id = NEW.id
    AND status = 'active';

  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger on bookings table
DROP TRIGGER IF EXISTS trigger_archive_conversation_on_booking_end ON public.bookings;
CREATE TRIGGER trigger_archive_conversation_on_booking_end
  AFTER UPDATE ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.archive_conversation_on_booking_end();
