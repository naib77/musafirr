-- 058 — Let owners see (and therefore hide) their own listings
--
-- Symptom: hosts hit `42501 new row violates row-level security policy for
-- table "listings"` (HTTP 403) when hiding a listing (setting is_active=false).
-- Showing a listing (is_active=true) works; only hiding fails.
--
-- Root cause: the live SELECT policy on public.listings is
--   "Anyone can view active listings"  USING (is_active = true)
-- PostgreSQL requires that the row produced by an UPDATE remain visible to the
-- actor through the SELECT policy. Setting is_active=false makes the new row
-- invisible under `is_active = true`, so the UPDATE is rejected with 42501.
-- (The same policy also prevents a host from ever SELECTing their own hidden
-- listings — so hidden listings silently disappear from the host's dashboard.)
--
-- NOTE: The live database's listings policies were created by hand and never
-- matched this repo's 001_initial_schema.sql (different names, roles = public,
-- no admin clause). This migration edits the policy that actually exists.
--
-- Fix: broaden the SELECT policy so an owner can always see their own listing
-- regardless of is_active. This is strictly additive — guests still see only
-- active listings; owners additionally see their own hidden ones. Confirmed by
-- reproducing the failing hide under RLS impersonation before and after.

alter policy "Anyone can view active listings"
on public.listings
using (is_active = true or auth.uid() = owner_id);
