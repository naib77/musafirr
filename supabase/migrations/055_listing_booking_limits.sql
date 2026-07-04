-- =============================================================
-- 055 — Per-plan min/max booking duration on listings
--
-- Lets a host set a minimum (and optional maximum) booking length per plan:
--   hourly  → min/max hours
--   daily   → min/max nights
--   monthly → min/max months
-- A NULL minimum means "1"; a NULL maximum means "no cap". Enforced in the
-- booking form so a guest can't book below the host's minimum.
-- =============================================================

alter table public.listings
  add column if not exists min_hours integer,
  add column if not exists max_hours integer,
  add column if not exists min_nights integer,
  add column if not exists max_nights integer,
  add column if not exists min_months integer,
  add column if not exists max_months integer;
