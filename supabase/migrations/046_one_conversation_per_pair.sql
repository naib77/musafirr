-- Migration: One conversation per guest↔host pair (Airbnb-style)
--
-- Conversations were keyed per (pair, booking), so every new booking with the
-- same host opened ANOTHER thread — the inbox showed the same person many
-- times. Airbnb keeps one continuous thread per relationship and updates the
-- reservation context inside it.
--
-- Also fixes a latent inbox bug: the live conversations table (created by
-- migration 024) has no last_message_id/text/sender_id columns and no trigger
-- maintaining them, so the client (which reads last_message_text) showed
-- "No messages yet" on every thread and sorted the inbox by stale timestamps.
--
-- 1. Add the denormalized last-message columns the client reads.
-- 2. Merge duplicate threads: keep the most recently active thread per pair,
--    move all messages/read-cursors into it, delete the rest.
-- 3. Backfill last-message previews for ALL conversations.
-- 4. Enforce one-per-pair uniqueness.
-- 5. get_or_create_conversation matches by pair only and refreshes the
--    thread's booking context to the latest booking.
-- 6. Maintain last-message denormalization on every new message.
-- 7. Threads never auto-archive — messaging is always on.

-- ============================================================
-- 1. Denormalized last-message columns (client reads these)
-- ============================================================

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS last_message_id UUID,
  ADD COLUMN IF NOT EXISTS last_message_text TEXT,
  ADD COLUMN IF NOT EXISTS last_message_sender_id UUID;

-- ============================================================
-- 2. Merge duplicate threads per pair
-- ============================================================

CREATE TEMP TABLE conv_merge ON COMMIT DROP AS
WITH ranked AS (
    SELECT id,
           created_at,
           LEAST(participant_one_id, participant_two_id) AS p_lo,
           GREATEST(participant_one_id, participant_two_id) AS p_hi,
           ROW_NUMBER() OVER (
               PARTITION BY LEAST(participant_one_id, participant_two_id),
                            GREATEST(participant_one_id, participant_two_id)
               ORDER BY COALESCE(last_message_at, updated_at, created_at) DESC,
                        created_at DESC
           ) AS rn
    FROM public.conversations
)
SELECT d.id AS dup_id, k.id AS keeper_id
FROM ranked d
JOIN ranked k ON k.p_lo = d.p_lo AND k.p_hi = d.p_hi AND k.rn = 1
WHERE d.rn > 1;

-- Remember the newest booking context among each merged set (by check-in
-- date) BEFORE deleting the duplicates, so the keeper shows the latest trip.
CREATE TEMP TABLE conv_latest_ctx ON COMMIT DROP AS
WITH members AS (
    SELECT cm.keeper_id AS target_id, c.*
    FROM public.conversations c
    JOIN conv_merge cm ON c.id = cm.dup_id
    UNION ALL
    SELECT DISTINCT cm.keeper_id AS target_id, c.*
    FROM public.conversations c
    JOIN conv_merge cm ON c.id = cm.keeper_id
)
SELECT DISTINCT ON (target_id)
       target_id, booking_id, listing_id, listing_title,
       booking_start, booking_end, listing_type
FROM members
WHERE booking_id IS NOT NULL
ORDER BY target_id, booking_start DESC NULLS LAST, created_at DESC;

-- Move messages to the keeper thread.
UPDATE public.messages m
SET conversation_id = cm.keeper_id
FROM conv_merge cm
WHERE m.conversation_id = cm.dup_id;

-- Merge read cursors, keeping each user's most recent read position.
-- DISTINCT ON collapses cursors from several duplicate threads first —
-- ON CONFLICT cannot touch the same (keeper, user) row twice in one command.
INSERT INTO public.read_cursors (conversation_id, user_id, last_read_message_id, last_read_at)
SELECT DISTINCT ON (cm.keeper_id, rc.user_id)
       cm.keeper_id, rc.user_id, rc.last_read_message_id, rc.last_read_at
FROM public.read_cursors rc
JOIN conv_merge cm ON rc.conversation_id = cm.dup_id
ORDER BY cm.keeper_id, rc.user_id, rc.last_read_at DESC NULLS LAST
ON CONFLICT (conversation_id, user_id) DO UPDATE
SET last_read_message_id = CASE
        WHEN EXCLUDED.last_read_at > read_cursors.last_read_at
        THEN EXCLUDED.last_read_message_id
        ELSE read_cursors.last_read_message_id
    END,
    last_read_at = GREATEST(read_cursors.last_read_at, EXCLUDED.last_read_at);

-- Delete the duplicate threads (their remaining cursors/typing rows cascade).
DELETE FROM public.conversations c
USING conv_merge cm
WHERE c.id = cm.dup_id;

-- Keeper shows the latest booking context of the merged set.
UPDATE public.conversations c
SET booking_id = ctx.booking_id,
    listing_id = ctx.listing_id,
    listing_title = ctx.listing_title,
    booking_start = ctx.booking_start,
    booking_end = ctx.booking_end,
    listing_type = ctx.listing_type
FROM conv_latest_ctx ctx
WHERE c.id = ctx.target_id;

-- ============================================================
-- 3. Backfill last-message previews for ALL conversations
-- ============================================================

UPDATE public.conversations c
SET last_message_id = lm.id,
    last_message_text = CASE
        WHEN lm.content_type = 'text' THEN LEFT(lm.content, 100)
        WHEN lm.content_type = 'booking_card' THEN 'Booking details'
        WHEN lm.content_type = 'image' THEN 'Sent an image'
        WHEN lm.content_type = 'location' THEN 'Shared a location'
        WHEN lm.content_type = 'file' THEN 'Sent a file'
        ELSE LEFT(lm.content, 100)
    END,
    last_message_at = lm.created_at,
    last_message_sender_id = lm.sender_id,
    last_message_preview = LEFT(lm.content, 100),
    updated_at = GREATEST(c.updated_at, lm.created_at)
FROM (
    SELECT DISTINCT ON (conversation_id)
           conversation_id, id, content, content_type, created_at, sender_id
    FROM public.messages
    WHERE deleted_at IS NULL
    ORDER BY conversation_id, created_at DESC
) lm
WHERE lm.conversation_id = c.id;

-- ============================================================
-- 4. One thread per pair, enforced
-- ============================================================

DROP INDEX IF EXISTS uniq_conversation_pair_booking;
DROP INDEX IF EXISTS uniq_conversation_pair_general;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_conversation_per_pair
    ON public.conversations (
        LEAST(participant_one_id, participant_two_id),
        GREATEST(participant_one_id, participant_two_id)
    );

-- ============================================================
-- 5. get_or_create_conversation: pair-scoped, refreshes context
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
  SELECT id INTO conv_id FROM public.conversations
  WHERE LEAST(participant_one_id, participant_two_id) = LEAST(user_one, user_two)
    AND GREATEST(participant_one_id, participant_two_id) = GREATEST(user_one, user_two)
  LIMIT 1;

  IF conv_id IS NULL THEN
    INSERT INTO public.conversations (participant_one_id, participant_two_id, booking_id, listing_id)
    VALUES (user_one, user_two, p_booking_id, p_listing_id)
    RETURNING id INTO conv_id;
  ELSIF p_booking_id IS NOT NULL OR p_listing_id IS NOT NULL THEN
    -- The single thread follows the latest booking/listing context.
    UPDATE public.conversations
    SET booking_id = COALESCE(p_booking_id, booking_id),
        listing_id = COALESCE(p_listing_id, listing_id),
        status = 'active',
        updated_at = NOW()
    WHERE id = conv_id;
  END IF;

  RETURN conv_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 6. Keep last-message denormalization fresh on every send
-- ============================================================

CREATE OR REPLACE FUNCTION public.update_conversation_last_message()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.conversations
  SET
    last_message_id = NEW.id,
    last_message_text = CASE
      WHEN NEW.content_type = 'text' THEN LEFT(NEW.content, 100)
      WHEN NEW.content_type = 'booking_card' THEN 'Booking details'
      WHEN NEW.content_type = 'image' THEN 'Sent an image'
      WHEN NEW.content_type = 'location' THEN 'Shared a location'
      WHEN NEW.content_type = 'file' THEN 'Sent a file'
      ELSE LEFT(NEW.content, 100)
    END,
    last_message_at = NEW.created_at,
    last_message_sender_id = NEW.sender_id,
    last_message_preview = LEFT(NEW.content, 100),
    updated_at = NOW()
  WHERE id = NEW.conversation_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trigger_update_conversation_last_message ON public.messages;
CREATE TRIGGER trigger_update_conversation_last_message
  AFTER INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.update_conversation_last_message();

-- ============================================================
-- 7. Threads never archive
-- ============================================================

DROP TRIGGER IF EXISTS trigger_archive_conversation_on_booking_end ON public.bookings;
DROP FUNCTION IF EXISTS public.archive_conversation_on_booking_end();

UPDATE public.conversations SET status = 'active' WHERE status <> 'active';
