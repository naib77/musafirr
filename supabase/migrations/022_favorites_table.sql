-- Migration: Favorites table
-- Purpose: Persist user favorites to database

-- Create favorites table
CREATE TABLE IF NOT EXISTS public.favorites (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    listing_id uuid NOT NULL REFERENCES public.listings(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),

    -- Each user can only favorite a listing once
    CONSTRAINT favorites_unique_per_user UNIQUE (user_id, listing_id)
);

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS favorites_by_user ON public.favorites (user_id);
CREATE INDEX IF NOT EXISTS favorites_by_listing ON public.favorites (listing_id);
CREATE INDEX IF NOT EXISTS favorites_by_created ON public.favorites (user_id, created_at DESC);

-- Enable RLS
ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY;

-- Users can view their own favorites
CREATE POLICY favorites_select_own ON public.favorites
    FOR SELECT
    USING (auth.uid() = user_id);

-- Users can insert their own favorites
CREATE POLICY favorites_insert_own ON public.favorites
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can delete their own favorites
CREATE POLICY favorites_delete_own ON public.favorites
    FOR DELETE
    USING (auth.uid() = user_id);

-- Add comment for documentation
COMMENT ON TABLE public.favorites IS 'User favorites/wishlist for listings';
