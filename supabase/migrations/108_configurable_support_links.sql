-- 108: the Support menu's destinations become admin-configurable.
--
-- "Get help", "Terms of service" and "Privacy policy" in Profile → Support
-- opened three `static const` strings in lib/config/legal_links.dart — and
-- they are still the placeholders that file was shipped with
-- (musaafir.app/terms, support@musaafir.app). Correcting a legal URL, moving
-- the terms to a new host, or pointing help at a real help desk meant a Dart
-- edit, a rebuild and a redeploy of the committed web bundle, for a decision
-- that is legal and operational rather than technical.
--
-- The app now reads these three keys and falls back to the compiled-in values
-- per key, so an absent row or an unreadable table still opens a working link
-- rather than a dead menu item (see lib/models/support_links.dart).
--
-- Reads stay public: the terms and privacy policy must be reachable by an
-- anonymous user, who has a right to read them BEFORE creating an account.
-- Writes remain admin-only (086).

-- ── 1. Validator for the three URL keys ─────────────────────────────────────
-- One function for all three, like fn_validate_setting_search_scalar: the rule
-- is identical and only the key name differs in the message.
--
-- The scheme test is an ALLOW-LIST, not a spell-check. This value is handed to
-- the platform's URL launcher on the device, so `javascript:`, `file:` and
-- `intent:` must never be storable here — refusing them at the table is the
-- only guard that covers every client, present and future. The app repeats the
-- check (sanitiseSupportUrl) because a row written before this migration is
-- not covered by it.
create or replace function public.fn_validate_setting_support_url(
  p_key text, p_value text
)
returns void language plpgsql immutable set search_path to 'public' as $$
declare v text := btrim(coalesce(p_value, ''));
begin
  -- Empty is refused rather than read as "use the default", exactly as
  -- active_theme does (105): an admin who cleared the field almost certainly
  -- meant to type something, and silently reverting a legal URL to a
  -- placeholder baked into an old app build is the worst outcome available.
  if v = '' then
    raise exception '% cannot be empty — give a full URL, e.g. https://example.com/terms, or mailto:help@example.com', p_key
      using errcode = '22023';
  end if;

  -- Length caps a runaway paste long before it reaches a device. Generous:
  -- real help-desk URLs carry tracking parameters.
  if length(v) > 500 then
    raise exception '% is too long (% characters, max 500)', p_key, length(v)
      using errcode = '22023';
  end if;

  -- Case-insensitive on the SCHEME only. The value is stored exactly as typed:
  -- paths and mailto addresses are case-sensitive in practice, and the app
  -- reads this cell without lowercasing it for precisely that reason.
  if lower(v) !~ '^(https?://[^[:space:]]+|mailto:[^[:space:]@]+@[^[:space:]@]+)$' then
    raise exception '% must be an http(s) URL or a mailto: address, with no spaces — got "%"', p_key, v
      using errcode = '22023';
  end if;
end;
$$;

comment on function public.fn_validate_setting_support_url(text, text) is
  'Validates support_help_url / terms_url / privacy_url. The scheme list is an allow-list: these values reach a device URL launcher. Mirrored by sanitiseSupportUrl in lib/models/support_links.dart.';

-- ── 2. The dispatcher ───────────────────────────────────────────────────────
-- Reproduced from 105 with one line added. 104's header explains why this body
-- is the one thing here that still gets rewritten wholesale, and why that is
-- tolerable when the change is a single additive line. (106 and 107 added
-- themes without touching this function, so 105 is the latest version of it in
-- the repo.)
--
-- BEFORE APPLYING: the live function has drifted from the repo before — that is
-- the entire subject of 104. Diff the live body against this one first
-- (`select prosrc from pg_proc where proname = 'fn_validate_app_setting'`) and
-- carry across anything present live that is missing below, or applying this
-- silently deletes another key's validation exactly as 103 did.
create or replace function public.fn_validate_app_setting()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  case new.key
    when 'search_radius_tiers_m' then
      perform public.fn_validate_setting_search_radius_tiers(new.value);
    when 'search_landmark_radius_m', 'search_nearest_fallback_limit' then
      perform public.fn_validate_setting_search_scalar(new.key, new.value);
    when 'payout_channels_enabled' then
      perform public.fn_validate_setting_payout_channels(new.value);
    when 'address_disclosure_grace_days' then
      perform public.fn_validate_setting_address_grace(new.value);
    when 'platform_commission_pct' then
      perform public.fn_validate_setting_commission_pct(new.value);
    when 'active_theme' then
      perform public.fn_validate_setting_active_theme(new.value);
    when 'support_help_url', 'terms_url', 'privacy_url' then
      perform public.fn_validate_setting_support_url(new.key, new.value);
    else
      null;
  end case;
  return new;
end;
$$;

comment on function public.fn_validate_app_setting() is
  'Dispatcher for app_settings validation. Add a key by adding fn_validate_setting_<key>() and one line here — never by reproducing this body (see 104).';

-- ── 3. Deliberately NOT seeded ──────────────────────────────────────────────
-- The compiled-in values are placeholders, and seeding them would present
-- them in the portal as though someone had chosen them — an admin would see a
-- filled-in Privacy Policy URL and reasonably assume it resolves. Absent rows
-- read as "not configured": the app opens its fallback, and the portal shows
-- that fallback greyed in as the placeholder of an empty field, which is the
-- honest description of the situation.
