-- Migration: Fix booking_status enum to include all required values
-- Purpose: Ensure 'rejected' and 'active' values exist in the enum

-- Add 'rejected' if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum
        WHERE enumlabel = 'rejected'
        AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'booking_status')
    ) THEN
        ALTER TYPE public.booking_status ADD VALUE 'rejected' AFTER 'confirmed';
    END IF;
END $$;

-- Add 'active' if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum
        WHERE enumlabel = 'active'
        AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'booking_status')
    ) THEN
        ALTER TYPE public.booking_status ADD VALUE 'active' AFTER 'confirmed';
    END IF;
END $$;
