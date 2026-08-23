-- 100_payout_methods_and_disbursements.sql
--
-- Money going OUT. Until now the platform only modelled money coming in
-- (`payments`, migration 072): a guest pays, the host is owed, and the
-- Payments & payouts screen tells the host their earnings are "settled to your
-- registered account" — an account that did not exist anywhere in the system.
-- Settlement happened in someone's head, over chat.
--
-- This migration adds the two halves that were missing:
--
--   * `payout_methods`  — where a user wants to be paid. bKash / Nagad / Rocket
--                         wallets, or a bank account. Both roles need one: a
--                         host to be paid their earnings, a guest to be
--                         refunded a cancelled stay.
--   * `disbursements`   — the record that money actually went out. Entered by
--                         an admin after they send it from the bKash app or a
--                         bank transfer, so the host can see "paid" and nobody
--                         gets paid twice.
--
-- ─── The threat this schema is shaped around ────────────────────────────────
--
-- A payout method is the single highest-value target in the product. Every
-- other compromise costs a user their privacy; this one costs them their
-- money, and the classic marketplace fraud is not "steal the account" but
-- "quietly repoint the payout" — take over a host account, swap the bKash
-- number, wait for payday, and the theft is invisible until the real host
-- complains weeks later.
--
-- Three structural defences, in order of importance:
--
--   1. ACCOUNT DETAILS ARE IMMUTABLE. Not "hard to change" — impossible.
--      There is no UPDATE path, for anyone, that can alter a channel, an
--      account number, or an account holder's name. Changing where you get
--      paid means adding a new method and retiring the old one, which leaves
--      the old row intact and timestamped. A repointed payout is therefore
--      always a visible new row in an admin queue, never a silent edit.
--      This is enforced by a trigger, not by convention, and it binds
--      service_role too (see fn_guard_payout_method_immutable).
--
--   2. MONEY ONLY MOVES TO A VERIFIED METHOD. A new method lands as 'pending'
--      and record_disbursement() refuses it. An admin approves it only after
--      checking the account holder's name against the NID already on file —
--      the same human gate migration 095 put on address verification, for the
--      same reason: the credential means "a person checked", so a person must.
--
--   3. NO CLIENT WRITES AT ALL. Neither table has an INSERT/UPDATE/DELETE
--      policy. Every mutation goes through a SECURITY DEFINER RPC below that
--      re-derives the caller from auth.uid() and re-checks the rules
--      server-side, exactly as `payments` does. A hand-rolled PostgREST call
--      has nothing to aim at.
--
-- Deliberately NOT here: automatic disbursement via bKash's Instant Payout
-- (B2C) API. That needs a merchant disbursement agreement, and at ~1 booking a
-- day paying by hand is correct. `disbursements.reference` is already the right
-- shape to hold the TrxID an API would return, so wiring one in later is an
-- edge function plus a status transition, not a reshaping of this table.

-- ---------------------------------------------------------------------------
-- 1. Which channels are on offer
-- ---------------------------------------------------------------------------
-- The enum is the set of channels the code knows how to VALIDATE (each has a
-- different account-number shape). Which of them are actually offered to users
-- is an operational decision — if Rocket support lapses, or a bank partnership
-- starts, that is a Tuesday-afternoon change, not a release. So the offered set
-- lives in app_settings where an admin can edit it, per the project rule that
-- nothing a human might want to tune belongs in Dart.

do $$
begin
  if not exists (select 1 from pg_type where typname = 'payout_channel') then
    create type public.payout_channel as enum ('bkash', 'nagad', 'rocket', 'bank');
  end if;
end
$$;

-- Refuse a typo at the source rather than letting it silently disable payouts
-- for everyone — the same approach migration 097 took for the search keys.
--
-- Folded INTO `fn_validate_app_setting` rather than added as a second BEFORE
-- trigger on the same table. Two validators would both work (Postgres fires
-- BEFORE triggers alphabetically and each returns NEW), but they would give
-- this table two places to look when a setting is refused, and the next person
-- to add a key would have to guess which one to extend. The function is
-- reproduced whole because `create or replace` has no way to add a branch —
-- the same reason `fn_audit` is reproduced in section 5.
--
-- Everything above the payout branch is migration 097's, unchanged.
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

  -- ── New in 100 ────────────────────────────────────────────────────────────
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
  end if;

  return new;
end;
$$;

-- Seeded after the validator above, so the default value goes through exactly
-- the rule an admin's later edit will.
insert into public.app_settings (key, value)
values ('payout_channels_enabled', 'bkash,nagad,rocket,bank')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 2. payout_methods
-- ---------------------------------------------------------------------------

create table if not exists public.payout_methods (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  channel       public.payout_channel not null,

  -- The name the account is registered in. This is the field the admin
  -- actually verifies: it must match the NID on the profile, because a payout
  -- to an account in someone else's name is the shape both money-laundering
  -- and a hijacked-account payout take.
  account_name  text not null,

  -- MFS: an 11-digit BD mobile number, normalised to local 01XXXXXXXXX form by
  -- add_payout_method() so '+8801…', '8801…' and '01…' cannot become three
  -- different rows for one wallet.
  -- Bank: the account number, digits only.
  account_number text not null,

  -- Bank-only. Null for wallets, enforced by the check constraint below so a
  -- half-filled bank row cannot exist.
  bank_name      text,
  branch_name    text,
  -- BEFTN routing number: 9 digits. Optional — an admin can settle from the
  -- bank name and branch alone, and demanding a number people rarely know to
  -- hand would cost more payouts than it saves.
  routing_number text,

  -- Reuses the existing four-state enum rather than inventing a parallel one,
  -- for the reason 095 gives: the identity flow already means exactly these
  -- four things by these four words. 'none' is unused here — a method is
  -- 'pending' from the moment it exists.
  status public.verification_status not null default 'pending',

  -- Where payouts go when the admin does not pick explicitly. Constrained to
  -- one live row per user by the partial unique index below.
  is_default boolean not null default false,

  verified_at      timestamptz,
  verified_by      uuid references public.profiles(id),
  rejection_reason text,

  -- Soft delete. A retired method must survive, because disbursements point at
  -- it: this row is the permanent record of where a past payment actually
  -- went. Hard-deleting it would rewrite settled history.
  retired_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- A wallet is a phone number; a bank account is not, and neither carries the
  -- other's fields. Splitting these into two tables would be tidier in theory
  -- and worse in practice — every read site would need a union, to display one
  -- list.
  constraint payout_methods_shape check (
    case channel
      when 'bank' then
        account_number ~ '^[0-9]{6,20}$'
        and coalesce(btrim(bank_name), '') <> ''
        and (routing_number is null or routing_number ~ '^[0-9]{9}$')
      else
        -- BD mobile: 01, then an operator digit 3-9, then 8 more.
        account_number ~ '^01[3-9][0-9]{8}$'
        and bank_name is null
        and branch_name is null
        and routing_number is null
    end
  ),
  constraint payout_methods_account_name_present
    check (length(btrim(account_name)) >= 3),
  -- A rejection the user cannot act on is just a dead end.
  constraint payout_methods_rejection_has_reason check (
    status <> 'rejected' or coalesce(btrim(rejection_reason), '') <> ''
  ),
  -- A retired method is nobody's default; the RPCs maintain this, the
  -- constraint stops a future one from forgetting.
  constraint payout_methods_retired_not_default
    check (retired_at is null or is_default = false)
);

-- One default per user, counting only live methods.
create unique index if not exists payout_methods_one_default_per_user
  on public.payout_methods (user_id)
  where is_default and retired_at is null;

-- The same wallet added twice is a user mistake, not a second method. Scoped
-- to live rows so retiring and re-adding an account later still works — people
-- do come back to an old number.
create unique index if not exists payout_methods_no_live_duplicates
  on public.payout_methods (user_id, channel, account_number)
  where retired_at is null;

-- The admin review queue.
create index if not exists payout_methods_pending_idx
  on public.payout_methods (created_at)
  where status = 'pending' and retired_at is null;

create index if not exists payout_methods_user_live_idx
  on public.payout_methods (user_id)
  where retired_at is null;

-- Lets an admin answer "is anyone else being paid at this number?" before
-- approving. One wallet across several accounts is sometimes a family and
-- sometimes a fraud ring; the schema does not presume, it just makes the
-- question cheap to ask.
create index if not exists payout_methods_account_number_idx
  on public.payout_methods (account_number);

comment on table public.payout_methods is
  'Where a user wants to be paid (host earnings) or refunded (guest). Account details are immutable once written — change = add new + retire old (100).';
comment on column public.payout_methods.account_name is
  'Account holder name. The field the admin verifies against the NID on file; a mismatch is the signal for a hijacked or laundered payout.';
comment on column public.payout_methods.retired_at is
  'Soft delete. Never hard-delete: disbursements reference this row as the record of where money actually went.';

-- ── The immutability guard ──────────────────────────────────────────────────
-- The core defence, stated once, in the one place nothing can route around.
--
-- Note what is NOT excluded: there is no is_admin() or service_role escape
-- hatch. That is deliberate. "An admin can edit an account number" and "an
-- attacker with an admin session can edit an account number" are the same
-- sentence, and correcting a typo by adding the right method and retiring the
-- wrong one costs one extra click while removing the entire class of silent
-- repointing. The audit trail is worth more than the convenience.
create or replace function public.fn_guard_payout_method_immutable()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  if new.channel        is distinct from old.channel
     or new.user_id     is distinct from old.user_id
     or new.account_name is distinct from old.account_name
     or new.account_number is distinct from old.account_number
     or new.bank_name   is distinct from old.bank_name
     or new.branch_name is distinct from old.branch_name
     or new.routing_number is distinct from old.routing_number then
    raise exception 'payout account details are immutable — add a new method and retire this one'
      using errcode = '42501';
  end if;

  -- Verification is granted, never regained by accident: once retired, a
  -- method cannot come back to life and start receiving money again.
  if old.retired_at is not null and new.retired_at is null then
    raise exception 'a retired payout method cannot be reinstated'
      using errcode = '42501';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_payout_methods_immutable on public.payout_methods;
create trigger trg_payout_methods_immutable
  before update on public.payout_methods
  for each row execute function public.fn_guard_payout_method_immutable();

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.payout_methods enable row level security;

-- Read: your own, or an admin's. Note there is no host-reads-guest or
-- guest-reads-host path — unlike `payments`, the counterparty has no business
-- knowing where the other side banks.
drop policy if exists payout_methods_select on public.payout_methods;
create policy payout_methods_select on public.payout_methods
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- No INSERT / UPDATE / DELETE policies, by design. See the header.

-- ---------------------------------------------------------------------------
-- 3. disbursements
-- ---------------------------------------------------------------------------

create table if not exists public.disbursements (
  id uuid primary key default gen_random_uuid(),

  -- Who was paid.
  user_id uuid not null references public.profiles(id) on delete restrict,

  -- Exactly where the money went. Because payout_methods rows are immutable
  -- and never hard-deleted, this reference is a permanent, faithful record —
  -- there is no need to snapshot the account number into this table, and no
  -- risk of the history changing under a later edit.
  payout_method_id uuid not null references public.payout_methods(id) on delete restrict,

  -- The stay this settles, when there is one. Nullable because not every
  -- payout maps to a single booking: a weekly lump settlement to a host, or a
  -- goodwill refund, are both real.
  booking_id uuid references public.bookings(id) on delete restrict,

  kind text not null check (kind in ('host_payout', 'guest_refund')),

  amount   numeric not null check (amount > 0),
  currency text not null default 'BDT',

  -- 'pending' = queued but not yet sent; 'sent' = money has left; 'failed' =
  -- the transfer bounced. The admin records most rows straight as 'sent',
  -- because they type them in after sending from the bKash app.
  status text not null default 'sent'
    check (status in ('pending', 'sent', 'failed')),

  -- The bKash TrxID or bank transfer reference. The thing you quote when a
  -- host says "I never got it" — which is the entire reason this table exists.
  reference      text,
  note           text,
  failure_reason text,

  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  sent_at    timestamptz,
  updated_at timestamptz not null default now(),

  constraint disbursements_failure_has_reason check (
    status <> 'failed' or coalesce(btrim(failure_reason), '') <> ''
  )
);

-- Paying the same booking twice is the expensive mistake this table exists to
-- prevent, and a uniqueness constraint prevents it better than a careful
-- admin does. Failed attempts are excluded so a bounced transfer can be
-- retried.
create unique index if not exists disbursements_one_live_per_booking_kind
  on public.disbursements (booking_id, kind)
  where booking_id is not null and status <> 'failed';

create index if not exists disbursements_user_idx
  on public.disbursements (user_id, created_at desc);
create index if not exists disbursements_method_idx
  on public.disbursements (payout_method_id);
create index if not exists disbursements_pending_idx
  on public.disbursements (created_at)
  where status = 'pending';

comment on table public.disbursements is
  'Money paid out to a host or refunded to a guest. Recorded by an admin after sending; written only via record_disbursement() (100).';

create or replace function public.fn_touch_disbursements()
returns trigger language plpgsql set search_path to 'public' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_disbursements_touch on public.disbursements;
create trigger trg_disbursements_touch
  before update on public.disbursements
  for each row execute function public.fn_touch_disbursements();

alter table public.disbursements enable row level security;

-- The recipient can see their own payouts — that is the "you were paid ৳X on
-- the 20th" the host screen needs — and admins see everything. No client
-- writes; record_disbursement() is the only door.
drop policy if exists disbursements_select on public.disbursements;
create policy disbursements_select on public.disbursements
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- ---------------------------------------------------------------------------
-- 4. RPCs — the only write path
-- ---------------------------------------------------------------------------

-- Normalise a BD mobile number to local 01XXXXXXXXX form. '+880 1712-345678',
-- '8801712345678' and '01712345678' are one wallet, and if they can become
-- three rows then the duplicate index is decorative and an admin verifies the
-- same account three times.
create or replace function public.normalise_bd_msisdn(p_raw text)
returns text
language sql
immutable
set search_path to 'public'
as $$
  select case
    when d ~ '^8801[3-9][0-9]{8}$' then '0' || right(d, 10)
    when d ~ '^1[3-9][0-9]{8}$'    then '0' || d
    else d
  end
  from (select regexp_replace(coalesce(p_raw, ''), '[^0-9]', '', 'g') as d) s;
$$;

comment on function public.normalise_bd_msisdn(text) is
  'Collapses +880 / 880 / bare-1 mobile forms to local 01XXXXXXXXX so one wallet is one row (100).';

-- ── The user adds a method ──────────────────────────────────────────────────
create or replace function public.add_payout_method(
  p_channel        text,
  p_account_name   text,
  p_account_number text,
  p_bank_name      text default null,
  p_branch_name    text default null,
  p_routing_number text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid      uuid := auth.uid();
  v_channel  public.payout_channel;
  v_number   text;
  v_enabled  text;
  v_live     int;
  v_id       uuid;
  v_is_first boolean;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  begin
    v_channel := lower(btrim(p_channel))::public.payout_channel;
  exception when others then
    raise exception 'unknown payout channel %', p_channel using errcode = '22023';
  end;

  -- Re-check the admin's offered-channel list server-side. The app hides
  -- disabled channels, but "the client hid it" has never been a control.
  select value into v_enabled from public.app_settings
   where key = 'payout_channels_enabled';
  if v_enabled is not null
     and not (v_channel::text = any (
       select btrim(t) from unnest(string_to_array(v_enabled, ',')) t)) then
    raise exception 'the % payout channel is not currently accepted', v_channel
      using errcode = '22023';
  end if;

  if coalesce(btrim(p_account_name), '') = '' then
    raise exception 'the account holder name is required' using errcode = '22023';
  end if;

  v_number := case
    when v_channel = 'bank'
      then regexp_replace(coalesce(p_account_number, ''), '[^0-9]', '', 'g')
    else public.normalise_bd_msisdn(p_account_number)
  end;

  -- Cheap ceiling on a table an authenticated user can grow. Five is well past
  -- what anyone legitimately needs and well short of a nuisance.
  select count(*) into v_live from public.payout_methods
   where user_id = v_uid and retired_at is null;
  if v_live >= 5 then
    raise exception 'you already have the maximum of 5 payout methods — retire one first'
      using errcode = '22023';
  end if;

  if exists (
    select 1 from public.payout_methods
     where user_id = v_uid and channel = v_channel
       and account_number = v_number and retired_at is null
  ) then
    raise exception 'you have already added that account' using errcode = '23505';
  end if;

  -- The first method a user adds becomes their default, so the common case
  -- (exactly one account, ever) never needs a second decision from them.
  v_is_first := not exists (
    select 1 from public.payout_methods
     where user_id = v_uid and retired_at is null and is_default
  );

  insert into public.payout_methods (
    user_id, channel, account_name, account_number,
    bank_name, branch_name, routing_number, is_default
  ) values (
    v_uid, v_channel, btrim(p_account_name), v_number,
    case when v_channel = 'bank' then nullif(btrim(p_bank_name), '') end,
    case when v_channel = 'bank' then nullif(btrim(p_branch_name), '') end,
    case when v_channel = 'bank'
         then nullif(regexp_replace(coalesce(p_routing_number, ''), '[^0-9]', '', 'g'), '') end,
    v_is_first
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.add_payout_method(text, text, text, text, text, text) from public, anon;
grant execute on function public.add_payout_method(text, text, text, text, text, text) to authenticated;

-- ── The user picks which one is default ─────────────────────────────────────
-- Any live method may be made default, including one still pending. That is
-- intentional: a user who has added exactly one account and is waiting on
-- review should see it marked as where their money will go, and the gate that
-- actually matters — "is it verified?" — is enforced at payout time, where
-- getting it wrong costs money rather than confusion.
create or replace function public.set_default_payout_method(p_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.payout_methods
     where id = p_id and user_id = v_uid
       and retired_at is null and status <> 'rejected'
  ) then
    raise exception 'no such payout method' using errcode = '22023';
  end if;

  -- Clear first: the partial unique index permits exactly one live default,
  -- so setting before clearing would collide.
  update public.payout_methods
     set is_default = false
   where user_id = v_uid and is_default and retired_at is null and id <> p_id;

  update public.payout_methods set is_default = true where id = p_id;
end;
$$;

revoke execute on function public.set_default_payout_method(uuid) from public, anon;
grant execute on function public.set_default_payout_method(uuid) to authenticated;

-- ── The user retires one ────────────────────────────────────────────────────
create or replace function public.retire_payout_method(p_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid     uuid := auth.uid();
  v_was_def boolean;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- An owner or an admin may retire; an admin needs it to kill a method that
  -- turns out to be fraudulent without waiting for the account holder.
  select is_default into v_was_def
    from public.payout_methods
   where id = p_id and retired_at is null
     and (user_id = v_uid or public.is_admin());

  if not found then
    raise exception 'no such payout method' using errcode = '22023';
  end if;

  -- A payout already queued against this method would otherwise be sent to an
  -- account the user has just disowned.
  if exists (
    select 1 from public.disbursements
     where payout_method_id = p_id and status = 'pending'
  ) then
    raise exception 'a payout is still pending against this method — resolve it first'
      using errcode = '22023';
  end if;

  update public.payout_methods
     set retired_at = now(), is_default = false
   where id = p_id;

  -- Leave the user with a default if any live method remains, preferring a
  -- verified one so the replacement is immediately payable. Without this, a
  -- host who retires their old wallet silently has nowhere to be paid.
  if v_was_def then
    update public.payout_methods
       set is_default = true
     where id = (
       select id from public.payout_methods
        where user_id = (select user_id from public.payout_methods where id = p_id)
          and retired_at is null and status <> 'rejected'
        order by (status = 'verified') desc, created_at
        limit 1
     );
  end if;
end;
$$;

revoke execute on function public.retire_payout_method(uuid) from public, anon;
grant execute on function public.retire_payout_method(uuid) to authenticated;

-- ── The admin's verdict ─────────────────────────────────────────────────────
create or replace function public.set_payout_method_verification(
  p_id               uuid,
  p_status           public.verification_status,
  p_rejection_reason text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_admin uuid := auth.uid();
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  if p_status not in ('pending', 'verified', 'rejected') then
    raise exception 'status must be pending, verified or rejected'
      using errcode = '22023';
  end if;
  if p_status = 'rejected' and coalesce(btrim(p_rejection_reason), '') = '' then
    raise exception 'a rejection reason is required' using errcode = '22023';
  end if;

  update public.payout_methods
     set status           = p_status,
         verified_at      = case when p_status = 'verified' then now() end,
         verified_by      = case when p_status = 'verified' then v_admin end,
         rejection_reason = case when p_status = 'rejected'
                                 then btrim(p_rejection_reason) end,
         -- A rejected method must not stay the target of the next payout.
         is_default       = case when p_status = 'rejected' then false
                                 else is_default end
   where id = p_id and retired_at is null;

  if not found then
    raise exception 'no such payout method' using errcode = '22023';
  end if;
end;
$$;

revoke execute on function public.set_payout_method_verification(uuid, public.verification_status, text) from public, anon;
grant execute on function public.set_payout_method_verification(uuid, public.verification_status, text) to authenticated;

-- ── The admin records money going out ───────────────────────────────────────
create or replace function public.record_disbursement(
  p_user_id          uuid,
  p_payout_method_id uuid,
  p_amount           numeric,
  p_kind             text,
  p_booking_id       uuid default null,
  p_reference        text default null,
  p_note             text default null,
  p_status           text default 'sent'
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_admin uuid := auth.uid();
  v_id    uuid;
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  if p_kind not in ('host_payout', 'guest_refund') then
    raise exception 'kind must be host_payout or guest_refund' using errcode = '22023';
  end if;
  if p_status not in ('pending', 'sent') then
    raise exception 'a new disbursement is pending or sent' using errcode = '22023';
  end if;
  if coalesce(p_amount, 0) <= 0 then
    raise exception 'amount must be positive' using errcode = '22023';
  end if;

  -- Defence 2, at the point where it costs money: the method must belong to
  -- the recipient, be verified by a human, and still be live.
  if not exists (
    select 1 from public.payout_methods
     where id = p_payout_method_id
       and user_id = p_user_id
       and status = 'verified'
       and retired_at is null
  ) then
    raise exception 'that payout method is not a verified, live method for this user'
      using errcode = '22023';
  end if;

  -- If a booking is named, the recipient must actually be a party to it — the
  -- guest for a refund, the host for a payout. Catches the fat-finger of
  -- pasting the wrong booking id far more cheaply than a reconciliation does.
  if p_booking_id is not null then
    if p_kind = 'guest_refund' then
      if not exists (select 1 from public.bookings b
                      where b.id = p_booking_id and b.tenant_id = p_user_id) then
        raise exception 'that booking does not belong to this guest' using errcode = '22023';
      end if;
    else
      if not exists (select 1 from public.bookings b
                       join public.listings l on l.id = b.listing_id
                      where b.id = p_booking_id and l.owner_id = p_user_id) then
        raise exception 'that booking is not on this host''s listing' using errcode = '22023';
      end if;
    end if;
  end if;

  insert into public.disbursements (
    user_id, payout_method_id, booking_id, kind, amount,
    status, reference, note, created_by, sent_at
  ) values (
    p_user_id, p_payout_method_id, p_booking_id, p_kind, p_amount,
    p_status, nullif(btrim(p_reference), ''), nullif(btrim(p_note), ''),
    v_admin, case when p_status = 'sent' then now() end
  )
  returning id into v_id;

  return v_id;
exception
  when unique_violation then
    raise exception 'this booking has already been settled — check the payout history'
      using errcode = '23505';
end;
$$;

revoke execute on function public.record_disbursement(uuid, uuid, numeric, text, uuid, text, text, text) from public, anon;
grant execute on function public.record_disbursement(uuid, uuid, numeric, text, uuid, text, text, text) to authenticated;

-- ── Settling a queued payout, or marking one bounced ────────────────────────
create or replace function public.set_disbursement_status(
  p_id             uuid,
  p_status         text,
  p_reference      text default null,
  p_failure_reason text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  if p_status not in ('pending', 'sent', 'failed') then
    raise exception 'status must be pending, sent or failed' using errcode = '22023';
  end if;
  if p_status = 'failed' and coalesce(btrim(p_failure_reason), '') = '' then
    raise exception 'a failure reason is required' using errcode = '22023';
  end if;

  update public.disbursements
     set status         = p_status,
         reference      = coalesce(nullif(btrim(p_reference), ''), reference),
         failure_reason = case when p_status = 'failed'
                               then btrim(p_failure_reason) end,
         sent_at        = case when p_status = 'sent'
                               then coalesce(sent_at, now()) end
   where id = p_id;

  if not found then
    raise exception 'no such disbursement' using errcode = '22023';
  end if;
end;
$$;

revoke execute on function public.set_disbursement_status(uuid, text, text, text) from public, anon;
grant execute on function public.set_disbursement_status(uuid, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Audit
-- ---------------------------------------------------------------------------
-- Both tables are financial by definition, so they belong in the same trail
-- that already covers payments and bookings. fn_audit only knew how to pull an
-- amount off those two; teach it this one so `financial_audit` shows a figure
-- instead of a null. Additive — the existing branches are untouched.
create or replace function public.fn_audit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old      jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  v_new      jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  v_row      jsonb := coalesce(v_new, v_old);
  v_actor    uuid  := auth.uid();
  v_role     text;
  v_source   text  := coalesce(
                        nullif(current_setting('app.audit_source', true), ''),
                        case when auth.uid() is null then 'system' else 'app' end);
  v_category text  := tg_argv[0];
  v_amount   numeric;
  v_currency text;
  v_changed  text[];
begin
  if tg_op = 'UPDATE' then
    select array_agg(k)
      into v_changed
      from jsonb_object_keys(v_new) k
     where (v_new -> k) is distinct from (v_old -> k);
    if v_changed is null then
      return null;
    end if;
  end if;

  if v_actor is not null then
    select role::text into v_role from public.profiles where id = v_actor;
  end if;

  if tg_table_name = 'payments' then
    v_amount   := (v_row ->> 'amount')::numeric;
    v_currency := coalesce(v_row ->> 'currency', 'BDT');
  elsif tg_table_name = 'bookings' then
    v_amount   := (v_row ->> 'total_price')::numeric;
    v_currency := 'BDT';
  elsif tg_table_name = 'disbursements' then
    v_amount   := (v_row ->> 'amount')::numeric;
    v_currency := coalesce(v_row ->> 'currency', 'BDT');
  end if;

  insert into public.audit_log (
    table_name, record_id, action, actor_id, actor_role, source,
    category, amount, currency, changed_cols, old_data, new_data)
  values (
    tg_table_name,
    (v_row ->> 'id')::uuid,
    lower(tg_op),
    v_actor, v_role, v_source,
    v_category, v_amount, v_currency, v_changed, v_old, v_new);

  return null;
end;
$$;

-- Every payout method event: added, verified, rejected, retired. This is the
-- trail you read when a host says the money went to the wrong number.
--
-- Note that audit_log.old_data/new_data capture the whole row, so account
-- numbers land in the trail. That is intended — the point of the record is to
-- prove which account was on file at a given moment — and audit_log is
-- admin-read-only (089).
drop trigger if exists trg_audit_payout_methods_ins on public.payout_methods;
create trigger trg_audit_payout_methods_ins
  after insert on public.payout_methods
  for each row execute function public.fn_audit('financial');

drop trigger if exists trg_audit_payout_methods_upd on public.payout_methods;
create trigger trg_audit_payout_methods_upd
  after update on public.payout_methods
  for each row
  when (old.status is distinct from new.status
        or old.retired_at is distinct from new.retired_at
        or old.is_default is distinct from new.is_default)
  execute function public.fn_audit('financial');

drop trigger if exists trg_audit_disbursements_ins on public.disbursements;
create trigger trg_audit_disbursements_ins
  after insert on public.disbursements
  for each row execute function public.fn_audit('financial');

drop trigger if exists trg_audit_disbursements_upd on public.disbursements;
create trigger trg_audit_disbursements_upd
  after update on public.disbursements
  for each row
  when (old.status is distinct from new.status
        or old.amount is distinct from new.amount
        or old.reference is distinct from new.reference)
  execute function public.fn_audit('financial');

-- ---------------------------------------------------------------------------
-- 6. What the host is still owed
-- ---------------------------------------------------------------------------
-- The admin's worklist: earned stays with no live disbursement against them.
-- Deliberately a view over the existing definition of earned revenue rather
-- than a new status column on bookings — a second source of truth for "has
-- this been paid" is how the app and the ledger start disagreeing.
--
-- `suggested_amount` is the full booking total, because there is no commission
-- anywhere in this database: `bookings` has no service-fee column, and the
-- `serviceFee` field on the Dart model is never populated from a query. So the
-- honest suggestion today is "the whole thing". It is only ever a SUGGESTION —
-- record_disbursement() takes whatever amount the admin types — and when a
-- commission does land, this is the one expression that has to change.
create or replace view public.host_payouts_due
  with (security_invoker = true)
as
  select
    b.id                     as booking_id,
    l.owner_id               as host_id,
    p.full_name              as host_name,
    b.listing_title,
    b.total_price,
    b.total_price            as suggested_amount,
    b.ends_at,
    b.booking_status,
    b.payment_status,
    b.paid_at,
    (select pm.id from public.payout_methods pm
      where pm.user_id = l.owner_id and pm.retired_at is null
        and pm.status = 'verified'
      order by pm.is_default desc, pm.created_at
      limit 1)               as default_payout_method_id
  from public.bookings b
  join public.listings l on l.id = b.listing_id
  join public.profiles p on p.id = l.owner_id
  -- Mirrors Booking.isEarnedRevenue exactly (lib/models/booking.dart): never a
  -- cancelled, rejected or still-pending request, and then either the stay
  -- completed or the guest's money actually arrived.
 where b.booking_status not in ('cancelled', 'rejected', 'pending')
   and (b.booking_status = 'completed' or b.payment_status = 'paid')
   and not exists (
     select 1 from public.disbursements d
      where d.booking_id = b.id
        and d.kind = 'host_payout'
        and d.status <> 'failed'
   );

comment on view public.host_payouts_due is
  'Earned stays with no live host_payout recorded. security_invoker, so RLS decides who sees what: admins everything, a host only their own (100).';
