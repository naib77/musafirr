-- Configurable app-wide settings (key/value) + host proof-of-address.
--
-- Feature: a user must upload a proof-of-address document (utility bill, etc.)
-- before they can add a listing. Whether this is enforced is controlled by the
-- `require_listing_address_proof` setting, which an admin can flip in the
-- Supabase dashboard with no app release.

-- 1. Generic key/value settings table, readable by the app at startup.
CREATE TABLE IF NOT EXISTS public.app_settings (
  key TEXT PRIMARY KEY,
  value TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- Anyone (incl. anon) may read settings; only the service role / dashboard
-- writes them (no INSERT/UPDATE policy is granted to clients).
DROP POLICY IF EXISTS "app_settings_select_all" ON public.app_settings;
CREATE POLICY "app_settings_select_all"
ON public.app_settings FOR SELECT
USING (true);

-- Seed the flag. Enabled by default (the feature's intent); flip to 'false'
-- to turn the requirement off:
--   update public.app_settings set value = 'false'
--   where key = 'require_listing_address_proof';
INSERT INTO public.app_settings (key, value)
VALUES ('require_listing_address_proof', 'true')
ON CONFLICT (key) DO NOTHING;

-- 2. Where the host's proof-of-address file lives (path in the `documents`
-- bucket). Presence of a value is what unlocks listing creation.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS address_proof_path TEXT;
