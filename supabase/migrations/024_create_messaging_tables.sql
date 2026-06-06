-- ============================================
-- Conversations table
-- ============================================
CREATE TABLE IF NOT EXISTS public.conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  participant_one_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  participant_two_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  booking_id UUID,
  listing_id UUID,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived', 'blocked')),
  last_message_at TIMESTAMPTZ,
  last_message_preview TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT unique_conversation UNIQUE (participant_one_id, participant_two_id, booking_id, listing_id)
);

-- ============================================
-- Messages table
-- ============================================
CREATE TABLE IF NOT EXISTS public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  content_type TEXT NOT NULL DEFAULT 'text',
  metadata JSONB DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'sent',
  reply_to_id UUID REFERENCES public.messages(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ
);

-- ============================================
-- Read cursors table
-- ============================================
CREATE TABLE IF NOT EXISTS public.read_cursors (
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  last_read_message_id UUID REFERENCES public.messages(id),
  last_read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  PRIMARY KEY (conversation_id, user_id)
);

-- ============================================
-- Typing indicators table
-- ============================================
CREATE TABLE IF NOT EXISTS public.typing_indicators (
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  PRIMARY KEY (conversation_id, user_id)
);

-- ============================================
-- Indexes
-- ============================================
CREATE INDEX IF NOT EXISTS idx_conversations_participant_one ON public.conversations(participant_one_id);
CREATE INDEX IF NOT EXISTS idx_conversations_participant_two ON public.conversations(participant_two_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON public.messages(created_at DESC);

-- ============================================
-- RPC Functions
-- ============================================

-- Get or create conversation
CREATE OR REPLACE FUNCTION public.get_or_create_conversation(
  user_one UUID,
  user_two UUID,
  p_booking_id UUID DEFAULT NULL,
  p_listing_id UUID DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
  conv_id UUID;
BEGIN
  -- Check for existing conversation
  SELECT id INTO conv_id FROM public.conversations
  WHERE (
    (participant_one_id = user_one AND participant_two_id = user_two) OR
    (participant_one_id = user_two AND participant_two_id = user_one)
  )
  AND (booking_id IS NOT DISTINCT FROM p_booking_id)
  AND (listing_id IS NOT DISTINCT FROM p_listing_id)
  LIMIT 1;

  IF conv_id IS NULL THEN
    INSERT INTO public.conversations (participant_one_id, participant_two_id, booking_id, listing_id)
    VALUES (user_one, user_two, p_booking_id, p_listing_id)
    RETURNING id INTO conv_id;
  END IF;

  RETURN conv_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get unread count for a conversation
CREATE OR REPLACE FUNCTION public.get_unread_count(
  p_conversation_id UUID,
  p_user_id UUID
) RETURNS INTEGER AS $$
DECLARE
  last_read_at TIMESTAMPTZ;
  unread INTEGER;
BEGIN
  SELECT rc.last_read_at INTO last_read_at
  FROM public.read_cursors rc
  WHERE rc.conversation_id = p_conversation_id AND rc.user_id = p_user_id;

  IF last_read_at IS NULL THEN
    SELECT COUNT(*) INTO unread
    FROM public.messages m
    WHERE m.conversation_id = p_conversation_id
      AND m.sender_id != p_user_id
      AND m.deleted_at IS NULL;
  ELSE
    SELECT COUNT(*) INTO unread
    FROM public.messages m
    WHERE m.conversation_id = p_conversation_id
      AND m.sender_id != p_user_id
      AND m.created_at > last_read_at
      AND m.deleted_at IS NULL;
  END IF;

  RETURN COALESCE(unread, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- Enable RLS
-- ============================================
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.read_cursors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.typing_indicators ENABLE ROW LEVEL SECURITY;

-- ============================================
-- RLS Policies
-- ============================================

-- Conversations: users can only see their own conversations
CREATE POLICY "Users can view own conversations" ON public.conversations
  FOR SELECT USING (auth.uid() = participant_one_id OR auth.uid() = participant_two_id);

CREATE POLICY "Users can insert conversations" ON public.conversations
  FOR INSERT WITH CHECK (auth.uid() = participant_one_id OR auth.uid() = participant_two_id);

CREATE POLICY "Users can update own conversations" ON public.conversations
  FOR UPDATE USING (auth.uid() = participant_one_id OR auth.uid() = participant_two_id);

-- Messages: users can see messages in their conversations
CREATE POLICY "Users can view messages in own conversations" ON public.messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = conversation_id
      AND (c.participant_one_id = auth.uid() OR c.participant_two_id = auth.uid())
    )
  );

CREATE POLICY "Users can send messages" ON public.messages
  FOR INSERT WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Users can update own messages" ON public.messages
  FOR UPDATE USING (auth.uid() = sender_id);

-- Read cursors
CREATE POLICY "Users can manage own read cursors" ON public.read_cursors
  FOR ALL USING (auth.uid() = user_id);

-- Typing indicators
CREATE POLICY "Users can manage own typing" ON public.typing_indicators
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view typing in own conversations" ON public.typing_indicators
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = conversation_id
      AND (c.participant_one_id = auth.uid() OR c.participant_two_id = auth.uid())
    )
  );

-- ============================================
-- Enable Realtime
-- ============================================
ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.typing_indicators;
