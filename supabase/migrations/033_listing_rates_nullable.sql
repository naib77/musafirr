-- ============================================
-- Make listing rate columns nullable
-- ============================================
-- A NULL rate means the host does not offer that booking plan.
-- Previously these were NOT NULL DEFAULT 0, which could not distinguish
-- "plan not offered" from "free", and forced every listing to carry all three.
--
-- The existing CHECK (hourly_rate >= 0 AND daily_rate >= 0 AND monthly_rate >= 0)
-- is kept: a CHECK only fails on FALSE, and NULL >= 0 evaluates to NULL, so
-- NULL rates pass. Existing rows keep their values (they offer all three).
-- No backfill required.

ALTER TABLE public.listings
  ALTER COLUMN hourly_rate DROP NOT NULL,
  ALTER COLUMN daily_rate DROP NOT NULL,
  ALTER COLUMN monthly_rate DROP NOT NULL;

-- Drop DEFAULT 0 so an omitted rate is stored as NULL ("not offered")
-- instead of silently becoming 0 ("free").
ALTER TABLE public.listings
  ALTER COLUMN hourly_rate DROP DEFAULT,
  ALTER COLUMN daily_rate DROP DEFAULT,
  ALTER COLUMN monthly_rate DROP DEFAULT;
