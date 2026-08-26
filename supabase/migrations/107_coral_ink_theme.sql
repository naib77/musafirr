-- 107: a fourth colour theme, `coral_ink`.
--
-- Modelled on Airbnb's live product palette: near-black structure with a single
-- coral-red reserved for primary actions. See `coralInk` in
-- lib/core/theme/app_palettes.dart, which documents where it follows Airbnb's
-- own hex values and the three places it deliberately does not (their palette
-- does not meet WCAG AA; this one does).
--
-- Like 106, this touches only the one small validator — not the
-- `fn_validate_app_setting` dispatcher. See 106's header, and 104's, for why
-- that distinction is the whole point of how these validators are split.
--
-- No effect until an admin selects the theme: `active_theme` keeps whatever it
-- holds, and a client too old to know `coral_ink` falls back to the default.

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
  if v not in ('ocean_teal', 'indigo_crimson', 'crimson_ember', 'coral_ink') then
    raise exception 'unknown theme "%"; valid: ocean_teal, indigo_crimson, crimson_ember, coral_ink', v
      using errcode = '22023';
  end if;
end;
$$;

comment on function public.fn_validate_setting_active_theme(text) is
  'Valid ids must match AppPalettes.all in lib/core/theme/app_palettes.dart. Adding a palette there requires a migration adding its id here.';
