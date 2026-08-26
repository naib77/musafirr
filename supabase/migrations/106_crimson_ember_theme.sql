-- 106: a third colour theme, `crimson_ember`.
--
-- A red-primary palette: the brand gradient is a red ramp (wine → crimson →
-- rose) and red carries navigation as well as the primary buttons, where
-- `indigo_crimson` keeps red for the ask alone. See `crimsonEmber` in
-- lib/core/theme/app_palettes.dart for why its error colour is a deep oxblood.
--
-- ─── Note what this migration does NOT touch ────────────────────────────────
--
-- `fn_validate_app_setting`, the dispatcher. 105 had to reproduce it to add the
-- `active_theme` branch, and 104's header explains at length why reproducing
-- that body is the risky part of changing settings validation — it is how 103
-- silently deleted 101's commission check.
--
-- Adding a *value* to an existing key needs none of that. The branch already
-- exists and still points here; only this one small function changes. That is
-- exactly the property 104 refactored the validators to have, and it is why
-- this file is nine lines of SQL instead of ninety.
--
-- The app is unaffected until an admin selects the theme: `active_theme` keeps
-- whatever it already holds, and a client too old to know `crimson_ember` falls
-- back to the default rather than failing.

-- Valid ids must match AppPalettes.all in lib/core/theme/app_palettes.dart.
-- test/core/theme/app_palettes_test.dart pins the same list, so the two drifting
-- apart fails a test rather than shipping a theme no admin can select.
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
  if v not in ('ocean_teal', 'indigo_crimson', 'crimson_ember') then
    raise exception 'unknown theme "%"; valid: ocean_teal, indigo_crimson, crimson_ember', v
      using errcode = '22023';
  end if;
end;
$$;

comment on function public.fn_validate_setting_active_theme(text) is
  'Valid ids must match AppPalettes.all in lib/core/theme/app_palettes.dart. Adding a palette there requires a migration adding its id here.';
