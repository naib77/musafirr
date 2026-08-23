-- 103_address_disclosure_expires.sql
--
-- The exact-address disclosure was permanent. Fixing that.
--
-- Migration 093 moved a listing's door-level address into
-- `public.listing_addresses` behind `can_see_listing_address()`, which admits
-- the owner, an admin, or a guest with a booking in
-- ('confirmed','active','completed'). The exclusions were reasoned about
-- carefully — pending is not enough, a rejected or cancelled booking is "not a
-- standing invitation" — but nothing ever reconsidered `completed`.
--
-- `completed` never expires. So one finished stay disclosed that host's front
-- door to that guest **forever**: not only in their trip history, where it
-- belongs, but on the live listing page, every time they browsed it again.
--
-- Reported as: a guest opens a listing they stayed at months ago, starts a new
-- reservation, and sees "3344, b3, Dhaka, Bangladesh, banani, Dhaka" while that
-- new request is still pending — before this host has agreed to anything.
--
-- Verified against the live rule before changing it (all statuses synthesised
-- for one guest on one listing, each measured through can_see_listing_address):
--
--     area only       no booking at all
--     area only       only a pending booking
--     EXACT ADDRESS   only a confirmed booking
--     EXACT ADDRESS   only a active booking
--     EXACT ADDRESS   only a completed booking
--     area only       only a rejected booking
--     area only       only a cancelled booking
--     EXACT ADDRESS   completed 90d ago + NEW pending      <-- the report
--
-- So this was not a leak and not a client bug: the gate did exactly what it
-- said, and what it said was too generous. `tool/verify_address_privacy.sh`
-- reproduces that table and is the regression check for this migration.
--
-- ─── The rule now ───────────────────────────────────────────────────────────
--
--   confirmed / active   → disclosed. A live entitlement: the host has agreed
--                          and the guest needs to find the door.
--   completed            → disclosed only while the stay is RECENT. A guest who
--                          checked out yesterday still needs the address for a
--                          receipt, a lost item, or the safety screen; a guest
--                          who checked out in May does not, and by then the
--                          listing page is just a shop window again.
--   everything else      → area only.
--
-- Why a grace window rather than revoking at checkout: `completed` is also what
-- an in-progress stay becomes the moment a host marks it done, sometimes while
-- the guest is still standing in the flat. Cutting disclosure at that instant
-- would take the address away from `safety_screen.dart` — the screen whose
-- entire job is reading a real street address to an emergency dispatcher —
-- at the worst imaginable moment.
--
-- Note what this deliberately does NOT do: it does not try to scope disclosure
-- to a *particular* booking. A guest with any live entitlement to a listing
-- sees that listing's address, which is the honest model — they are about to
-- stand at that door. The bug was duration, not granularity.

-- ---------------------------------------------------------------------------
-- 1. How long a finished stay keeps the address
-- ---------------------------------------------------------------------------
-- A privacy window is exactly the kind of number an operator wants to change
-- without a release — shorten it after a complaint, lengthen it if support
-- keeps re-sending addresses to recent guests — so it lives in app_settings
-- with the rest of the tunables rather than being frozen into a function body.
insert into public.app_settings (key, value)
values ('address_disclosure_grace_days', '7')
on conflict (key) do nothing;

-- Validated on write, like the search keys (097) and the payout channels (100):
-- a typo here silently changes who can see host addresses, which is the last
-- setting that should fail quietly. Reproduced whole because `create or
-- replace` cannot add a branch.
create or replace function public.fn_validate_app_setting()
returns trigger
language plpgsql
as $$
declare
  parts text[];
  part  text;
  n     integer;
  prev  integer := null;
begin
  if new.key = 'search_radius_tiers_m' then
    parts := string_to_array(coalesce(new.value, ''), ',');
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

  elsif new.key in ('search_landmark_radius_m', 'search_nearest_fallback_limit') then
    if btrim(coalesce(new.value, '')) !~ '^[0-9]+$' then
      raise exception '% must be a whole number', new.key using errcode = '22023';
    end if;
    n := btrim(new.value)::integer;
    if new.key = 'search_landmark_radius_m' and (n < 100 or n > 200000) then
      raise exception 'search_landmark_radius_m: % m is outside 100–200000 m', n
        using errcode = '22023';
    end if;
    if new.key = 'search_nearest_fallback_limit' and (n < 1 or n > 100) then
      raise exception 'search_nearest_fallback_limit: % is outside 1–100', n
        using errcode = '22023';
    end if;

  elsif new.key = 'payout_channels_enabled' then
    if coalesce(btrim(new.value), '') = '' then
      raise exception 'payout_channels_enabled cannot be empty — stop offering a channel by naming the others, not by clearing the list'
        using errcode = '22023';
    end if;
    foreach part in array string_to_array(new.value, ',') loop
      begin
        perform btrim(part)::public.payout_channel;
      exception when others then
        raise exception 'unknown payout channel "%"; valid: bkash, nagad, rocket, bank',
          btrim(part) using errcode = '22023';
      end;
    end loop;

  -- ── New in 103 ────────────────────────────────────────────────────────────
  elsif new.key = 'address_disclosure_grace_days' then
    if btrim(coalesce(new.value, '')) !~ '^[0-9]+$' then
      raise exception 'address_disclosure_grace_days must be a whole number of days'
        using errcode = '22023';
    end if;
    n := btrim(new.value)::integer;
    -- 0 is allowed and means "revoke at checkout". The ceiling exists because
    -- a value in the thousands is indistinguishable from the permanent
    -- disclosure this migration exists to remove.
    if n > 365 then
      raise exception 'address_disclosure_grace_days: % is longer than a year; use a shorter window', n
        using errcode = '22023';
    end if;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The gate
-- ---------------------------------------------------------------------------
create or replace function public.can_see_listing_address(p_listing_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select
    -- Admins run the safety/verification queues and need the real address.
    public.is_admin()
    -- The host knows their own address.
    or exists (
      select 1 from public.listings l
      where l.id = p_listing_id and l.owner_id = auth.uid()
    )
    -- A guest with a LIVE entitlement. `pending` is excluded on purpose: asking
    -- to stay somewhere must not be enough to learn where it is. `rejected` and
    -- `cancelled` are excluded too — an acceptance that fell through is not a
    -- standing invitation.
    --
    -- `completed` is time-boxed (103). It used to be unbounded, which meant one
    -- finished stay disclosed the host's door to that guest permanently, on
    -- every later visit to the listing page. The window is measured from
    -- `ends_at` — when the guest was last entitled to be there — rather than
    -- from `completed_at`, so a host who marks a stay done weeks late cannot
    -- extend a stranger's access by being slow with their paperwork.
    or exists (
      select 1 from public.bookings b
      where b.listing_id = p_listing_id
        and b.tenant_id = auth.uid()
        and (
          b.booking_status in ('confirmed', 'active')
          or (
            b.booking_status = 'completed'
            and b.ends_at > now() - make_interval(days =>
                  coalesce(
                    (select nullif(btrim(value), '')::int
                       from public.app_settings
                      where key = 'address_disclosure_grace_days'),
                    7))
          )
        )
    );
$$;

comment on function public.can_see_listing_address(uuid) is
  'Who may read a listing''s exact address: the owner, an admin, a guest with a confirmed/active booking, or one whose stay finished within address_disclosure_grace_days (093, time-boxed in 103).';

-- The gate now filters completed bookings by `ends_at`, so the lookup wants
-- both columns. Without this it is a scan of the guest''s bookings per row.
create index if not exists bookings_tenant_listing_status_idx
  on public.bookings (tenant_id, listing_id, booking_status, ends_at);
