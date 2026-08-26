-- 105: the app's colour theme becomes admin-configurable.
--
-- Musaafir's palette was a compile-time fact: ~300 `static const` colour
-- references resolving to one teal identity. Changing it meant a Dart edit, a
-- rebuild, and a redeploy of the committed web bundle — for a decision that is
-- branding, not engineering.
--
-- The app now ships several compiled-in palettes and picks one at runtime from
-- this key. Only colours move; type scale, radii and component geometry stay in
-- Dart, so this setting cannot change the app's layout.
--
-- Read must stay public — the guest app is anon when it paints its first frame,
-- and the theme is needed before login (see 075, is_public defaults true).
-- Writes remain admin-only (086).
--
-- ─── The list of valid ids lives in two places, deliberately ────────────────
--
-- The app can only wear a palette it was compiled with, so `AppPalettes.all` in
-- lib/core/theme/app_palettes.dart is the real constraint. This validator
-- repeats it so the portal cannot save a theme users would never see: without
-- it, an admin could set `active_theme = 'midnight_gold'`, the portal would show
-- it as applied, and every client would quietly fall back to the default. That
-- silent disagreement is exactly what validating on write exists to prevent.
--
-- The duplication is guarded from the other side too:
-- test/core/theme/app_palettes_test.dart pins the same slug list, so adding a
-- palette without a follow-up migration fails a test rather than shipping a
-- theme no admin can select.
--
-- ADDING A PALETTE = a new id in AppPalettes.all + a new id here.

-- ── 1. Validator for the new key ────────────────────────────────────────────
-- Its own function, per 104: a future migration adding another key writes a new
-- function and one `perform` line rather than reproducing anyone else's body.
create or replace function public.fn_validate_setting_active_theme(p_value text)
returns void language plpgsql immutable set search_path to 'public' as $$
declare v text := lower(btrim(coalesce(p_value, '')));
begin
  -- Empty is refused rather than treated as "the default". The app does read an
  -- absent row as the default, but an admin who cleared the field almost
  -- certainly meant to type something, and silently reverting their theme is a
  -- worse outcome than telling them.
  if v = '' then
    raise exception 'active_theme cannot be empty — name a theme, e.g. ocean_teal'
      using errcode = '22023';
  end if;
  if v not in ('ocean_teal', 'indigo_crimson') then
    raise exception 'unknown theme "%"; valid: ocean_teal, indigo_crimson', v
      using errcode = '22023';
  end if;
end;
$$;

comment on function public.fn_validate_setting_active_theme(text) is
  'Valid ids must match AppPalettes.all in lib/core/theme/app_palettes.dart. Adding a palette there requires a migration adding its id here.';

-- ── 2. The dispatcher ───────────────────────────────────────────────────────
-- Reproduced from 104 with one line added. 104's header explains why this body
-- is the one thing here that still gets rewritten wholesale, and why that is
-- tolerable when the change is a single additive line.
--
-- BEFORE APPLYING: the live function has drifted from the repo before — that is
-- the entire subject of 104. Diff the live body against this one first
-- (`select prosrc from pg_proc where proname = 'fn_validate_app_setting'`) and
-- carry across anything present live that is missing below, or applying this
-- silently deletes another key's validation exactly as 103 did.
--
-- Checked 2026-08-26: live matched 104 exactly, and `active_theme` was not yet a
-- row. Re-check anyway — that was true when this was written, not when you run
-- it.
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
    else
      null;
  end case;
  return new;
end;
$$;

comment on function public.fn_validate_app_setting() is
  'Dispatcher for app_settings validation. Add a key by adding fn_validate_setting_<key>() and one line here — never by reproducing this body (see 104).';

-- ── 3. Seed the current identity ────────────────────────────────────────────
-- Seeded to the palette the app already wore, so applying this migration on its
-- own changes nothing on screen. Switching themes is then a deliberate edit.
-- `do nothing` on conflict: never stomp a theme an admin has already chosen.
insert into public.app_settings (key, value) values
  ('active_theme', 'ocean_teal')
on conflict (key) do nothing;
