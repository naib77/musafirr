-- ============================================
-- Conversation Participants table (N-way support)
-- ============================================
-- This table supports N-way conversations while maintaining
-- backwards compatibility with the existing two-participant model.
--
-- Migration Path:
-- 1. Create this table alongside existing conversations
-- 2. Populate from existing participant_one_id, participant_two_id
-- 3. Gradually migrate queries to use this table
-- 4. Eventually deprecate the hardcoded fields

CREATE TABLE IF NOT EXISTS public.conversation_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'guest' CHECK (role IN ('host', 'guest', 'support')),
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  left_at TIMESTAMPTZ,
  is_active BOOLEAN NOT NULL DEFAULT true,

  -- Prevent duplicate participants in the same conversation
  CONSTRAINT unique_participant UNIQUE (conversation_id, user_id)
);

-- ============================================
-- Indexes
-- ============================================
CREATE INDEX IF NOT EXISTS idx_conv_participants_conversation ON public.conversation_participants(conversation_id);
CREATE INDEX IF NOT EXISTS idx_conv_participants_user ON public.conversation_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_conv_participants_active ON public.conversation_participants(is_active) WHERE is_active = true;

-- ============================================
-- RLS Policies
-- ============================================
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;

-- Users can view participants in their conversations
CREATE POLICY "Users can view participants in own conversations" ON public.conversation_participants
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = conversation_id
      AND cp.user_id = auth.uid()
      AND cp.is_active = true
    )
  );

-- Users can add participants to conversations they're in
CREATE POLICY "Users can add participants" ON public.conversation_participants
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = conversation_id
      AND cp.user_id = auth.uid()
      AND cp.is_active = true
    )
  );

-- Users can leave conversations
CREATE POLICY "Users can leave conversations" ON public.conversation_participants
  FOR UPDATE USING (user_id = auth.uid());

-- ============================================
-- Function to migrate existing conversations
-- ============================================
CREATE OR REPLACE FUNCTION public.migrate_conversation_participants()
RETURNS INTEGER AS $$
DECLARE
  migrated INTEGER := 0;
  conv RECORD;
BEGIN
  FOR conv IN SELECT id, participant_one_id, participant_two_id FROM public.conversations LOOP
    -- Insert participant one if not exists
    INSERT INTO public.conversation_participants (conversation_id, user_id, role)
    VALUES (conv.id, conv.participant_one_id, 'guest')
    ON CONFLICT (conversation_id, user_id) DO NOTHING;

    -- Insert participant two if not exists
    INSERT INTO public.conversation_participants (conversation_id, user_id, role)
    VALUES (conv.id, conv.participant_two_id, 'guest')
    ON CONFLICT (conversation_id, user_id) DO NOTHING;

    migrated := migrated + 1;
  END LOOP;

  RETURN migrated;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- Function to get conversation participants
-- ============================================
CREATE OR REPLACE FUNCTION public.get_conversation_participants(p_conversation_id UUID)
RETURNS TABLE (
  user_id UUID,
  role TEXT,
  joined_at TIMESTAMPTZ,
  user_name TEXT,
  avatar_url TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    cp.user_id,
    cp.role,
    cp.joined_at,
    p.full_name as user_name,
    p.avatar_url
  FROM public.conversation_participants cp
  LEFT JOIN public.profiles p ON p.id = cp.user_id
  WHERE cp.conversation_id = p_conversation_id
    AND cp.is_active = true
  ORDER BY cp.joined_at;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- Enable Realtime (optional - for participant changes)
-- ============================================
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.conversation_participants;
