-- 104_restore_commission_setting_validation.sql
--
-- Repairs a regression introduced by 103, and removes the trap that caused it.
--
-- ─── What happened ──────────────────────────────────────────────────────────
--
-- `fn_validate_app_setting` guards every app_settings key, and the house style
-- since 100 has been "add a branch by reproducing the whole function", because
-- `create or replace` cannot patch a body in place. That works when migrations
-- land in order and each author starts from the newest version.
--
-- 101 (commission) and 103 (address disclosure) were written concurrently.
-- Both reproduced the function; 103's copy was taken from the 097+100 version,
-- before 101's `platform_commission_pct` branch existed. 103 applied last, so
-- it silently deleted that branch.
--
-- The failure mode is the quiet kind. Nothing errored. The key kept working —
-- app_settings has no per-key whitelist, so an unknown key is simply stored —
-- it just stopped being *validated*. `platform_commission_pct = 'fifteen'` or
-- `'900'` would have been accepted, and the first anyone would know is a
-- commission calculation throwing, or silently posting a 900% cut to a host's
-- ledger. Migration 101 deliberately validates this key on write precisely so
-- that cannot happen; for a while, it couldn't.
--
-- Verified before writing this: the live function had all four other branches
-- and was missing only platform_commission_pct.
--
-- ─── The fix, and the real fix ──────────────────────────────────────────────
--
-- Below is the function with ALL FIVE branches. But restoring it only resets
-- the trap — the next pair of concurrent migrations does this again.
--
-- So the branches now live in one small function per key, and the dispatcher
-- calls them. Adding a key means adding a NEW function and one `perform` line,
-- which two concurrent migrations can do without overwriting each other's
-- work: `create or replace` on different functions does not collide, and the
-- dispatcher's `perform` lines are additive rather than a whole-body rewrite.
-- Losing a branch now requires deliberately deleting a line someone else
-- added, instead of merely being unlucky about ordering.

-- ---------------------------------------------------------------------------
-- 1. One validator per key
-- ---------------------------------------------------------------------------
-- Each takes the raw text value and raises 22023 with a message meant for the
-- admin who typed it. Bodies are 097's / 100's / 101's / 103's, unchanged.

create or replace function public.fn_validate_setting_search_radius_tiers(p_value text)
returns void language plpgsql immutable set search_path to 'public' as $$
declare parts text[]; part text; n integer; prev integer := null;
begin
  parts := string_to_array(coalesce(p_value, ''), ',');
  if array_length(parts, 1) is null then
    raise exception 'search_radius_tiers_m needs at least one radius in metres'
      using errcode = '22023';
  end if;
  if array_length(parts, 1) > 6 then
    raise exception 'search_radius_tiers_m allows at most 6 tiers (got %)',
      array_length(parts, 1) using errcode = '22023';
  end if;
  foreach part in array parts loop
    if btrim(part) !~ '^[0-9]+$' then
      raise exception 'search_radius_tiers_m: "%" is not a whole number of metres',
        btrim(part) using errcode = '22023';
    end if;
    n := btrim(part)::integer;
    if n < 100 or n > 200000 then
      raise exception 'search_radius_tiers_m: % m is outside 100–200000 m', n
        using errcode = '22023';
    end if;
    -- Ascending order is load-bearing: the RPC takes the smallest tier that
    -- contains a match, so an unsorted list would pick the wrong ring.
    if prev is not null and n <= prev then
      raise exception 'search_radius_tiers_m must ascend (% came after %)', n, prev
        using errcode = '22023';
    end if;
    prev := n;
  end loop;
end;
$$;

create or replace function public.fn_validate_setting_search_scalar(p_key text, p_value text)
returns void language plpgsql immutable set search_path to 'public' as $$
declare n integer;
begin
  if btrim(coalesce(p_value, '')) !~ '^[0-9]+$' then
    raise exception '% must be a whole number', p_key using errcode = '22023';
  end if;
  n := btrim(p_value)::integer;
  if p_key = 'search_landmark_radius_m' and (n < 100 or n > 200000) then
    raise exception 'search_landmark_radius_m: % m is outside 100–200000 m', n
      using errcode = '22023';
  end if;
  if p_key = 'search_nearest_fallback_limit' and (n < 1 or n > 100) then
    raise exception 'search_nearest_fallback_limit: % is outside 1–100', n
      using errcode = '22023';
  end if;
end;
$$;

create or replace function public.fn_validate_setting_payout_channels(p_value text)
returns void language plpgsql stable set search_path to 'public' as $$
declare part text;
begin
  if coalesce(btrim(p_value), '') = '' then
    raise exception 'payout_channels_enabled cannot be empty — stop offering a channel by naming the others, not by clearing the list'
      using errcode = '22023';
  end if;
  foreach part in array string_to_array(p_value, ',') loop
    begin
      perform btrim(part)::public.payout_channel;
    exception when others then
      raise exception 'unknown payout channel "%"; valid: bkash, nagad, rocket, bank',
        btrim(part) using errcode = '22023';
    end;
  end loop;
end;
$$;

create or replace function public.fn_validate_setting_address_grace(p_value text)
returns void language plpgsql immutable set search_path to 'public' as $$
declare n integer;
begin
  if btrim(coalesce(p_value, '')) !~ '^[0-9]+$' then
    raise exception 'address_disclosure_grace_days must be a whole number of days'
      using errcode = '22023';
  end if;
  n := btrim(p_value)::integer;
  -- 0 is allowed and means "revoke at checkout". The ceiling exists because a
  -- value in the thousands is indistinguishable from the permanent disclosure
  -- migration 103 exists to remove.
  if n > 365 then
    raise exception 'address_disclosure_grace_days: % is longer than a year; use a shorter window', n
      using errcode = '22023';
  end if;
end;
$$;

-- The branch 103 deleted. Restored verbatim from 101.
create or replace function public.fn_validate_setting_commission_pct(p_value text)
returns void language plpgsql immutable set search_path to 'public' as $$
begin
  if btrim(coalesce(p_value, '')) !~ '^[0-9]{1,3}(\.[0-9]{1,2})?$' then
    raise exception 'platform_commission_pct must be a number like 15 or 12.5'
      using errcode = '22023';
  end if;
  if btrim(p_value)::numeric > 100 then
    raise exception 'platform_commission_pct: % is outside 0–100', btrim(p_value)
      using errcode = '22023';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The dispatcher
-- ---------------------------------------------------------------------------
-- Add a key by writing a validator above and one line here. A future migration
-- doing that no longer has to reproduce anyone else's work, which is what made
-- the 101/103 collision possible.
--
-- Unknown keys pass through deliberately: app_settings is a generic key/value
-- store the admin portal writes to, and rejecting unrecognised keys here would
-- turn "we added a setting in code before the migration" into a hard failure.
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
    else
      null;
  end case;
  return new;
end;
$$;

comment on function public.fn_validate_app_setting() is
  'Dispatcher for app_settings validation. Add a key by adding fn_validate_setting_<key>() and one line here — never by reproducing this body (see 104).';
