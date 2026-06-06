-- Fix: Add default value for updated_at in messages table
-- This prevents null values when inserting new messages

ALTER TABLE public.messages
  ALTER COLUMN updated_at SET DEFAULT NOW();
