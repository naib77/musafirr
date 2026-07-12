-- 065 — Structured (Airbnb-style) address fields for listings
--
-- The form previously captured a single free-text `address`. Hosts need to
-- enter the address in parts (Bangladesh convention): flat/floor, house/
-- building, road/street, area/locality, postal code, and an optional landmark.
-- City stays in the existing `city` column; `address` stays as a composed
-- human-readable display string (built app-side from these parts) so all
-- existing read paths keep working unchanged.
--
-- All columns are nullable text and purely additive — existing rows keep their
-- current `address`/`city`. The search_listings RPC returns to_jsonb(l), so
-- these flow through automatically with no RPC change.

alter table public.listings
  add column if not exists flat_floor  text,
  add column if not exists house_no    text,
  add column if not exists street      text,
  add column if not exists area        text,
  add column if not exists postal_code text,
  add column if not exists landmark    text;
