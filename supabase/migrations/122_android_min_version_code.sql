-- Migration 122: the oldest Android build allowed to talk to this database
-- becomes an admin setting.
--
-- Play updates installed apps on its own, silently, over Wi-Fi — so this is
-- not about delivering an update. It is about the gap before Play gets round
-- to it, which is hours to days and entirely outside anyone's control, and
-- about the one case where waiting is not acceptable.
--
-- ── Why an old Android build is a problem and an old web build is not ──────
--
-- `build/web` and this database are deployed by the same hands, so a web
-- visitor always has a bundle that matches. An APK does not: it sits on a
-- phone. And the client picks its PostgREST overload by the KEYS IT SENDS
-- (see the notes on 112 and 118 in CLAUDE.md), so a build that predates a
-- migration can ask for a function signature that no longer exists — and
-- `searchListingsFromDb`'s catch renders that as "no results" rather than as
-- an error. The user sees an empty, working-looking app.
--
-- `android_min_version_code` is the lever for that: set it to the first
-- versionCode that speaks the current schema and anything older is pushed
-- through Play's blocking updater at launch, without shipping a release to
-- make it happen.
--
-- ── The rule that makes it safe ───────────────────────────────────────────
--
-- This is the only setting in the table that can take the app away from a
-- user, so it is also the only one where a mistake is not recoverable by
-- editing the row back — the people who would need the fix are the people who
-- can no longer open the app.
--
-- Two things stand between it and that outcome, and both matter:
--
--   1. **The client asks Play first.** `appUpdateActionFor` returns "do
--      nothing" whenever Play reports no available update, whatever this
--      number says. Forcing an immediate update is asking Play to install
--      something newer; if Play has nothing newer the flow cannot complete and
--      the app is bricked for everyone at once. So a floor typed higher than
--      any published release is not a lock-out — it is a single forced update
--      to the newest build, after which the check finds nothing and falls
--      quiet.
--   2. **Zero means nobody.** It is the seed, the value an unreadable table
--      falls back to, and the value anything malformed parses to. Fail-open
--      here has to mean "don't force".
--
-- Nothing server-side enforces this, deliberately. Refusing an old client's
-- RPCs would be a second enforcer of a rule with no way to explain itself —
-- the old build would render the refusal as an empty screen, which is the
-- failure this exists to prevent.

-- ---------------------------------------------------------------------------
-- 1. Validation, in the established shape: one function per key.
-- ---------------------------------------------------------------------------

create or replace function public.fn_validate_setting_android_min_version_code(
  p_value text
) returns void
language plpgsql
immutable
set search_path to 'public'
as $$
declare n bigint;
begin
  if btrim(coalesce(p_value, '')) !~ '^[0-9]+$' then
    raise exception 'android_min_version_code must be a whole versionCode (0 disables forced updates)'
      using errcode = '22023';
  end if;
  n := btrim(p_value)::bigint;
  -- 2100000000 is Play's own ceiling for a versionCode, so a larger number
  -- cannot name a real release and could only ever be a typo. Rejected at the
  -- keystroke rather than clamped, because silently storing a different number
  -- than the admin typed is the wrong answer for a setting this sharp.
  if n > 2100000000 then
    raise exception 'android_min_version_code: % is above Play''s maximum versionCode (2100000000)', n
      using errcode = '22023';
  end if;
end;
$$;

-- The dispatcher, with one arm added. Recreated in full rather than patched:
-- it is a CASE, and a patch that drops an arm silently stops validating that
-- key. Verified against live before writing — the body below is 119's plus the
-- new `when`.
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
    when 'booking_accept_window_hours' then
      perform public.fn_validate_setting_booking_accept_hours(new.value);
    when 'android_min_version_code' then
      perform public.fn_validate_setting_android_min_version_code(new.value);
    else
      null;
  end case;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Seed the row, so the portal shows the value in force.
-- ---------------------------------------------------------------------------

-- 0: force nobody, which is what the app did before this existed. Inserted
-- rather than left absent so an admin opening Settings sees the number that
-- applies instead of an empty box they have to know the default for — and so
-- the box they type into is one the validator already guards.
insert into public.app_settings (key, value)
values ('android_min_version_code', '0')
on conflict (key) do nothing;
