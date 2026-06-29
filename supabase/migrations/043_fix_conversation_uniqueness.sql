-- Fix messaging: conversations could not be created for a second booking
-- between the same host & guest.
--
-- Migration 003 created conversations with:
--   CONSTRAINT unique_conversation UNIQUE (LEAST(p1,p2), GREATEST(p1,p2))
-- i.e. ONE conversation per user-pair, ignoring the booking. But the live
-- `get_or_create_conversation` (from 024) inserts a NEW row per (pair, booking,
-- listing). So the moment a host & guest had a *second* booking, the insert hit
-- a duplicate-key violation, conversation creation threw, and the host's
-- welcome message (and all chat) silently failed to send.
--
-- Fix: replace the pair-only constraint with booking-aware uniqueness that
-- matches how conversations are actually keyed:
--   * booking conversations  -> one per (pair, booking)
--   * general conversations   -> one per (pair) when there's no booking
--
-- Safe to run: the old constraint enforced one-per-pair, so no duplicate rows
-- exist today — the more permissive indexes below cannot fail on existing data.

-- 1. Drop the overly-strict pair-only constraint (idempotent).
ALTER TABLE public.conversations
  DROP CONSTRAINT IF EXISTS unique_conversation;

-- 2. One conversation per (user-pair, booking) for booking-scoped chats.
--    LEAST/GREATEST makes it order-agnostic (A↔B == B↔A).
CREATE UNIQUE INDEX IF NOT EXISTS uniq_conversation_pair_booking
  ON public.conversations (
    LEAST(participant_one_id, participant_two_id),
    GREATEST(participant_one_id, participant_two_id),
    booking_id
  )
  WHERE booking_id IS NOT NULL;

-- 3. One general conversation per user-pair when not tied to a booking.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_conversation_pair_general
  ON public.conversations (
    LEAST(participant_one_id, participant_two_id),
    GREATEST(participant_one_id, participant_two_id)
  )
  WHERE booking_id IS NULL;
