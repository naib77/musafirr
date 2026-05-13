-- =============================================
-- Musafir Messaging System Schema
-- Migration: 003_messaging.sql
-- =============================================

-- =============================================
-- ENUMS
-- =============================================

-- Message content types
CREATE TYPE message_content_type AS ENUM (
  'text',
  'image',
  'location',
  'booking_card',
  'system',
  'file'
);

-- Message status
CREATE TYPE message_status AS ENUM (
  'sending',
  'sent',
  'delivered',
  'read',
  'failed'
);

-- Conversation status
CREATE TYPE conversation_status AS ENUM (
  'active',
  'archived',
  'blocked'
);

-- =============================================
-- TABLES
-- =============================================

-- Conversations table
CREATE TABLE conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Participants (for 1-on-1 chats, we store both user IDs)
  participant_one_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  participant_two_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Optional booking context
  booking_id UUID REFERENCES bookings(id) ON DELETE SET NULL,
  listing_id UUID REFERENCES listings(id) ON DELETE SET NULL,

  -- Conversation metadata
  status conversation_status DEFAULT 'active',

  -- Last message preview (denormalized for performance)
  last_message_id UUID,
  last_message_text TEXT,
  last_message_at TIMESTAMPTZ,
  last_message_sender_id UUID,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  -- Ensure unique conversation between two users (regardless of order)
  CONSTRAINT unique_conversation UNIQUE (
    LEAST(participant_one_id, participant_two_id),
    GREATEST(participant_one_id, participant_two_id)
  ),

  -- Prevent self-conversations
  CONSTRAINT no_self_conversation CHECK (participant_one_id != participant_two_id)
);

-- Messages table
CREATE TABLE messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Content
  content_type message_content_type DEFAULT 'text',
  content TEXT NOT NULL,

  -- Rich content (JSON for structured data)
  -- For images: { "url": "...", "thumbnail_url": "...", "width": 800, "height": 600 }
  -- For location: { "latitude": 23.8103, "longitude": 90.4125, "address": "..." }
  -- For booking_card: { "booking_id": "...", "listing_name": "...", "dates": "..." }
  metadata JSONB DEFAULT '{}',

  -- Message status
  status message_status DEFAULT 'sent',

  -- Reply threading
  reply_to_id UUID REFERENCES messages(id) ON DELETE SET NULL,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  -- Soft delete
  deleted_at TIMESTAMPTZ
);

-- Read cursors (tracks where each user has read up to)
CREATE TABLE read_cursors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Last read message
  last_read_message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
  last_read_at TIMESTAMPTZ DEFAULT NOW(),

  -- Unique cursor per user per conversation
  CONSTRAINT unique_read_cursor UNIQUE (conversation_id, user_id)
);

-- Typing indicators (ephemeral, could also use Realtime Presence)
CREATE TABLE typing_indicators (
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ DEFAULT NOW(),

  PRIMARY KEY (conversation_id, user_id)
);

-- =============================================
-- INDEXES
-- =============================================

-- Conversations indexes
CREATE INDEX idx_conversations_participant_one ON conversations(participant_one_id);
CREATE INDEX idx_conversations_participant_two ON conversations(participant_two_id);
CREATE INDEX idx_conversations_booking ON conversations(booking_id) WHERE booking_id IS NOT NULL;
CREATE INDEX idx_conversations_last_message_at ON conversations(last_message_at DESC NULLS LAST);
CREATE INDEX idx_conversations_status ON conversations(status) WHERE status = 'active';

-- Messages indexes
CREATE INDEX idx_messages_conversation ON messages(conversation_id);
CREATE INDEX idx_messages_sender ON messages(sender_id);
CREATE INDEX idx_messages_conversation_created ON messages(conversation_id, created_at DESC);
CREATE INDEX idx_messages_reply_to ON messages(reply_to_id) WHERE reply_to_id IS NOT NULL;
CREATE INDEX idx_messages_not_deleted ON messages(conversation_id, created_at DESC) WHERE deleted_at IS NULL;

-- Read cursors indexes
CREATE INDEX idx_read_cursors_user ON read_cursors(user_id);
CREATE INDEX idx_read_cursors_conversation ON read_cursors(conversation_id);

-- Typing indicators index (for cleanup)
CREATE INDEX idx_typing_indicators_started ON typing_indicators(started_at);

-- =============================================
-- FUNCTIONS
-- =============================================

-- Function to get or create a conversation between two users
CREATE OR REPLACE FUNCTION get_or_create_conversation(
  user_one UUID,
  user_two UUID,
  p_booking_id UUID DEFAULT NULL,
  p_listing_id UUID DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
  conv_id UUID;
BEGIN
  -- Check if conversation exists
  SELECT id INTO conv_id
  FROM conversations
  WHERE (participant_one_id = LEAST(user_one, user_two)
    AND participant_two_id = GREATEST(user_one, user_two));

  -- If not, create it
  IF conv_id IS NULL THEN
    INSERT INTO conversations (
      participant_one_id,
      participant_two_id,
      booking_id,
      listing_id
    ) VALUES (
      LEAST(user_one, user_two),
      GREATEST(user_one, user_two),
      p_booking_id,
      p_listing_id
    )
    RETURNING id INTO conv_id;

    -- Create read cursors for both users
    INSERT INTO read_cursors (conversation_id, user_id)
    VALUES (conv_id, user_one), (conv_id, user_two);
  END IF;

  RETURN conv_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to update conversation last message (called by trigger)
CREATE OR REPLACE FUNCTION update_conversation_last_message()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE conversations
  SET
    last_message_id = NEW.id,
    last_message_text = CASE
      WHEN NEW.content_type = 'text' THEN LEFT(NEW.content, 100)
      WHEN NEW.content_type = 'image' THEN 'Sent an image'
      WHEN NEW.content_type = 'location' THEN 'Shared a location'
      WHEN NEW.content_type = 'booking_card' THEN 'Booking details'
      WHEN NEW.content_type = 'file' THEN 'Sent a file'
      ELSE 'New message'
    END,
    last_message_at = NEW.created_at,
    last_message_sender_id = NEW.sender_id,
    updated_at = NOW()
  WHERE id = NEW.conversation_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get unread count for a user in a conversation
CREATE OR REPLACE FUNCTION get_unread_count(
  p_conversation_id UUID,
  p_user_id UUID
) RETURNS INTEGER AS $$
DECLARE
  last_read_id UUID;
  last_read_time TIMESTAMPTZ;
  unread INTEGER;
BEGIN
  -- Get user's read cursor
  SELECT last_read_message_id, last_read_at INTO last_read_id, last_read_time
  FROM read_cursors
  WHERE conversation_id = p_conversation_id AND user_id = p_user_id;

  -- Count messages after the last read
  IF last_read_id IS NULL THEN
    -- User hasn't read any messages
    SELECT COUNT(*) INTO unread
    FROM messages
    WHERE conversation_id = p_conversation_id
      AND sender_id != p_user_id
      AND deleted_at IS NULL;
  ELSE
    SELECT COUNT(*) INTO unread
    FROM messages
    WHERE conversation_id = p_conversation_id
      AND sender_id != p_user_id
      AND deleted_at IS NULL
      AND created_at > (SELECT created_at FROM messages WHERE id = last_read_id);
  END IF;

  RETURN COALESCE(unread, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to clean up old typing indicators (run periodically)
CREATE OR REPLACE FUNCTION cleanup_typing_indicators()
RETURNS void AS $$
BEGIN
  DELETE FROM typing_indicators
  WHERE started_at < NOW() - INTERVAL '10 seconds';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- TRIGGERS
-- =============================================

-- Update conversation when new message is sent
CREATE TRIGGER trigger_update_conversation_last_message
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION update_conversation_last_message();

-- Update timestamps
CREATE TRIGGER trigger_conversations_updated_at
  BEFORE UPDATE ON conversations
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_messages_updated_at
  BEFORE UPDATE ON messages
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- =============================================
-- ROW LEVEL SECURITY
-- =============================================

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE read_cursors ENABLE ROW LEVEL SECURITY;
ALTER TABLE typing_indicators ENABLE ROW LEVEL SECURITY;

-- Conversations policies
CREATE POLICY "Users can view their own conversations"
  ON conversations FOR SELECT
  USING (
    auth.uid() = participant_one_id OR
    auth.uid() = participant_two_id
  );

CREATE POLICY "Users can update their own conversations"
  ON conversations FOR UPDATE
  USING (
    auth.uid() = participant_one_id OR
    auth.uid() = participant_two_id
  );

-- Messages policies
CREATE POLICY "Users can view messages in their conversations"
  ON messages FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = messages.conversation_id
        AND (c.participant_one_id = auth.uid() OR c.participant_two_id = auth.uid())
    )
  );

CREATE POLICY "Users can send messages in their conversations"
  ON messages FOR INSERT
  WITH CHECK (
    sender_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = conversation_id
        AND (c.participant_one_id = auth.uid() OR c.participant_two_id = auth.uid())
        AND c.status = 'active'
    )
  );

CREATE POLICY "Users can update their own messages"
  ON messages FOR UPDATE
  USING (sender_id = auth.uid());

CREATE POLICY "Users can soft delete their own messages"
  ON messages FOR DELETE
  USING (sender_id = auth.uid());

-- Read cursors policies
CREATE POLICY "Users can view their own read cursors"
  ON read_cursors FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "Users can update their own read cursors"
  ON read_cursors FOR UPDATE
  USING (user_id = auth.uid());

CREATE POLICY "Users can insert their own read cursors"
  ON read_cursors FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- Typing indicators policies
CREATE POLICY "Users can view typing in their conversations"
  ON typing_indicators FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = typing_indicators.conversation_id
        AND (c.participant_one_id = auth.uid() OR c.participant_two_id = auth.uid())
    )
  );

CREATE POLICY "Users can set their own typing indicator"
  ON typing_indicators FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can remove their own typing indicator"
  ON typing_indicators FOR DELETE
  USING (user_id = auth.uid());

-- =============================================
-- ENABLE REALTIME
-- =============================================

-- Enable realtime for messages (for live chat)
ALTER PUBLICATION supabase_realtime ADD TABLE messages;

-- Enable realtime for typing indicators
ALTER PUBLICATION supabase_realtime ADD TABLE typing_indicators;

-- Enable realtime for conversations (for unread badge updates)
ALTER PUBLICATION supabase_realtime ADD TABLE conversations;

-- =============================================
-- SAMPLE DATA (for development)
-- =============================================

-- Note: Sample data should be inserted via the application
-- This is just a placeholder showing the expected data structure

/*
-- Example: Create a conversation
SELECT get_or_create_conversation(
  'user-uuid-1',
  'user-uuid-2',
  'booking-uuid',
  'listing-uuid'
);

-- Example: Send a text message
INSERT INTO messages (conversation_id, sender_id, content_type, content)
VALUES ('conv-uuid', 'sender-uuid', 'text', 'Hello! Is the property available?');

-- Example: Send an image message
INSERT INTO messages (conversation_id, sender_id, content_type, content, metadata)
VALUES (
  'conv-uuid',
  'sender-uuid',
  'image',
  'Photo of the property',
  '{"url": "https://...", "thumbnail_url": "https://...", "width": 800, "height": 600}'
);

-- Example: Send a location message
INSERT INTO messages (conversation_id, sender_id, content_type, content, metadata)
VALUES (
  'conv-uuid',
  'sender-uuid',
  'location',
  'Meeting point',
  '{"latitude": 23.8103, "longitude": 90.4125, "address": "Dhaka, Bangladesh"}'
);

-- Example: Mark messages as read
UPDATE read_cursors
SET last_read_message_id = 'message-uuid', last_read_at = NOW()
WHERE conversation_id = 'conv-uuid' AND user_id = 'user-uuid';
*/
