-- 101_commission_ledger.sql
--
-- The commission, made real. Until now the platform's cut existed only as a
-- hardcoded estimate in the admin console (COMMISSION_RATE = 0.1 in
-- src/lib/reports.ts, with a comment admitting there is no commission table).
-- Migration 100 modelled money going OUT (disbursements); this one models what
-- is OWED, in both directions:
--
--   * Guest pays ONLINE  → the platform holds the money and owes the host
--                          everything but the commission.
--   * Guest pays CASH    → the host holds the money and owes the platform
--                          the commission.
--
-- One table answers both: `host_ledger_entries`, a signed, append-only journal
-- from the HOST's point of view. Positive = platform owes host, negative =
-- host owes platform. A host's balance is sum(amount); the admin console's
-- "collective journal" is the same table unfiltered.
--
-- Why one signed column and not a debit/credit account tree: the platform side
-- of every event is already recorded (payments 072, disbursements 100,
-- audit_log 089). The only unanswered question is each host's position, which
-- a flat signed journal answers with no reconciliation surface — the same
-- shape `disbursements` already chose.
--
-- Design decisions (user-confirmed):
--   * Commission base is the NET the guest actually paid. bookings.total_price
--     IS that net — create_marketplace_booking (070) stores
--     greatest(gross − discount, 0), and both settle paths charge exactly it.
--     Never subtract discount_amount again.
--   * The percent lives in app_settings ('platform_commission_pct', seeded 15)
--     and is SNAPSHOTTED onto each entry at posting time. Changing the setting
--     changes future bookings only; the append-only guard makes rewriting
--     history impossible rather than merely discouraged.
--   * Settlement is lump-sum against the running balance, not per booking.
--     Payouts arrive in the ledger automatically from `disbursements` (so
--     "did we send money" and "what does the host owe" cannot drift apart);
--     cash collections and manual adjustments come in through one admin RPC.
--   * A refund (payment_status 'paid' → 'refunded') posts a reversing entry.
--
-- Posting is done by AFTER triggers on bookings/disbursements, SECURITY
-- DEFINER, because every settle path already converges on
-- bookings.payment_status (cash: mark_cash_payment 076; online: the
-- sslcommerz-ipn edge function 072) — exactly the event 079 already triggers
-- on for paid_at. No edge function or app change is needed.

-- ---------------------------------------------------------------------------
-- 1. The setting
-- ---------------------------------------------------------------------------
-- Folded into fn_validate_app_setting for the reason 100 gives: one validator,
-- one place to look when a setting is refused. Reproduced whole because
-- `create or replace` cannot add a branch. Everything above the commission
-- branch is 097's + 100's, unchanged.
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

  -- ── New in 101 ────────────────────────────────────────────────────────────
  elsif new.key = 'platform_commission_pct' then
    if btrim(coalesce(new.value, '')) !~ '^[0-9]{1,3}(\.[0-9]{1,2})?$' then
      raise exception 'platform_commission_pct must be a number like 15 or 12.5'
        using errcode = '22023';
    end if;
    if btrim(new.value)::numeric > 100 then
      raise exception 'platform_commission_pct: % is outside 0–100', btrim(new.value)
        using errcode = '22023';
    end if;
  end if;

  return new;
end;
$$;

-- Seeded after the validator, so the default goes through exactly the rule an
-- admin's later edit will.
insert into public.app_settings (key, value)
values ('platform_commission_pct', '15')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 2. host_ledger_entries
-- ---------------------------------------------------------------------------

create table if not exists public.host_ledger_entries (
  id              uuid primary key default gen_random_uuid(),

  -- Snapshotted at posting time, never re-derived from listings.owner_id at
  -- read time: the console can transfer a listing between hosts, and settled
  -- history must not migrate with it.
  host_id         uuid not null references public.profiles(id) on delete restrict,

  -- What the entry settles. Booking-derived entries carry booking_id; payout
  -- entries carry disbursement_id; manual entries carry neither.
  booking_id      uuid references public.bookings(id) on delete restrict,
  disbursement_id uuid references public.disbursements(id) on delete restrict,

  entry_type text not null check (entry_type in (
    'booking_online',           -- guest paid the platform: +(net − commission)
    'booking_cash',             -- guest paid the host:     −commission
    'booking_refund_reversal',  -- negation of the booking's earning entry
    'payout',                   -- disbursement sent to the host: −amount
    'payout_reversal',          -- that disbursement later bounced: +amount
    'collection',               -- host handed the platform its commission: +amount
    'adjustment')),             -- admin correction, signed, note required

  -- Signed, from the HOST's perspective. Positive = platform owes host.
  amount numeric(12,2) not null check (amount <> 0),

  -- The arithmetic behind booking-derived rows, frozen at posting time.
  booking_net         numeric(12,2),  -- bookings.total_price when it was posted
  commission_rate_pct numeric(5,2),
  commission_amount   numeric(12,2),  -- negated on the reversal row

  currency   text not null default 'BDT',
  reference  text,  -- collection TrxID / receipt number
  note       text,
  created_by uuid references public.profiles(id),  -- null = posted by trigger
  created_at timestamptz not null default now(),

  -- Each entry type has exactly one legal shape; a row that drifts from it is
  -- a bug, so refuse it at the source.
  constraint host_ledger_shape check (
    case entry_type
      when 'booking_online'          then booking_id is not null
                                          and booking_net is not null
                                          and commission_rate_pct is not null
                                          and commission_amount is not null
                                          and amount > 0
      when 'booking_cash'            then booking_id is not null
                                          and booking_net is not null
                                          and commission_rate_pct is not null
                                          and commission_amount is not null
                                          and amount < 0
      when 'booking_refund_reversal' then booking_id is not null
      when 'payout'                  then disbursement_id is not null and amount < 0
      when 'payout_reversal'         then disbursement_id is not null and amount > 0
      when 'collection'              then amount > 0 and created_by is not null
      when 'adjustment'              then coalesce(btrim(note), '') <> ''
                                          and created_by is not null
    end
  )
);

-- The double-post defences. These indexes, not application care, are what
-- make the posting triggers and the backfill idempotent under races.
create unique index if not exists host_ledger_one_earning_per_booking
  on public.host_ledger_entries (booking_id)
  where entry_type in ('booking_online', 'booking_cash');

create unique index if not exists host_ledger_one_reversal_per_booking
  on public.host_ledger_entries (booking_id)
  where entry_type = 'booking_refund_reversal';

create unique index if not exists host_ledger_one_per_disbursement
  on public.host_ledger_entries (disbursement_id, entry_type)
  where disbursement_id is not null;

-- The console's read patterns: a host's journal newest-first, a booking's
-- money panel, the collective journal filtered by type.
create index if not exists host_ledger_host_idx
  on public.host_ledger_entries (host_id, created_at desc);
create index if not exists host_ledger_booking_idx
  on public.host_ledger_entries (booking_id);
create index if not exists host_ledger_type_idx
  on public.host_ledger_entries (entry_type);

comment on table public.host_ledger_entries is
  'Signed journal of what the platform owes each host (positive) or is owed by them (negative). Append-only; posted by triggers on bookings/disbursements, plus record_host_ledger_entry() for collections and adjustments (101).';
comment on column public.host_ledger_entries.commission_rate_pct is
  'platform_commission_pct at the moment the booking settled. History keeps the rate it was charged; the setting only shapes the future.';

-- ── Append-only guard ────────────────────────────────────────────────────────
-- Same posture as fn_audit_immutable (089) and the payout-method guard (100):
-- no is_admin() or service_role escape hatch, because "an admin can edit a
-- ledger entry" and "an attacker with an admin session can edit a ledger
-- entry" are the same sentence. A wrong entry is corrected by a new
-- adjustment entry, which leaves the mistake visible.
create or replace function public.fn_host_ledger_immutable()
returns trigger
language plpgsql
as $$
begin
  raise exception 'ledger entries are append-only — post an adjustment instead'
    using errcode = '42501';
end;
$$;

drop trigger if exists trg_host_ledger_immutable on public.host_ledger_entries;
create trigger trg_host_ledger_immutable
  before update or delete on public.host_ledger_entries
  for each row execute function public.fn_host_ledger_immutable();

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.host_ledger_entries enable row level security;

-- A host may read their own journal (the mobile app's future balance screen);
-- admins read everything. No client write policies — the triggers below are
-- SECURITY DEFINER and the RPC is the only manual door, exactly as 100 does.
drop policy if exists host_ledger_select on public.host_ledger_entries;
create policy host_ledger_select on public.host_ledger_entries
  for select to authenticated
  using (host_id = auth.uid() or public.is_admin());

revoke insert, update, delete on public.host_ledger_entries from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Posting trigger — bookings
-- ---------------------------------------------------------------------------
-- AFTER, not BEFORE: 079's BEFORE trigger must have stamped paid_at first, and
-- this function must never be able to mangle the booking row itself.
-- SECURITY DEFINER so the insert clears the ledger's default-deny RLS no
-- matter which role flipped the status (service-role IPN, the SECURITY
-- DEFINER mark_cash_payment, or an admin session).
create or replace function public.fn_post_booking_ledger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_host   uuid;
  v_pct    numeric;
  v_net    numeric;
  v_comm   numeric;
  v_method text;
begin
  -- ── Became paid ────────────────────────────────────────────────────────────
  if new.payment_status = 'paid'
     and (tg_op = 'INSERT' or old.payment_status is distinct from 'paid') then

    select l.owner_id into v_host from public.listings l where l.id = new.listing_id;
    -- An orphaned listing is a data bug, but raising here would abort the
    -- guest's settlement inside the IPN. Skip; the booking page will show the
    -- missing entry.
    if v_host is null then return null; end if;

    v_pct  := coalesce(
      (select nullif(btrim(value), '')::numeric
         from public.app_settings
        where key = 'platform_commission_pct'),
      15);
    v_net  := coalesce(new.total_price, 0);
    v_comm := round(v_net * v_pct / 100.0, 2);

    -- The guest's recorded choice (086) is authoritative; older rows fall back
    -- to the settled payments row (mark_cash_payment writes card_type 'cash'
    -- BEFORE flipping the status, so it is visible here); default online.
    v_method := coalesce(
      new.payment_method,
      (select case when p.card_type = 'cash' then 'cash' else 'online' end
         from public.payments p
        where p.booking_id = new.id and p.status = 'paid'
        order by coalesce(p.validated_at, p.created_at)
        limit 1),
      'online');

    if v_method = 'cash' then
      -- Host already holds the guest's money; they owe the platform its cut.
      if v_comm > 0 then
        insert into public.host_ledger_entries
          (host_id, booking_id, entry_type, amount,
           booking_net, commission_rate_pct, commission_amount)
        select v_host, new.id, 'booking_cash', -v_comm, v_net, v_pct, v_comm
         where not exists (
           select 1 from public.host_ledger_entries e
            where e.booking_id = new.id
              and e.entry_type in ('booking_online', 'booking_cash'));
      end if;
    else
      -- Platform holds the guest's money; it owes the host the rest.
      if v_net - v_comm > 0 then
        insert into public.host_ledger_entries
          (host_id, booking_id, entry_type, amount,
           booking_net, commission_rate_pct, commission_amount)
        select v_host, new.id, 'booking_online', v_net - v_comm, v_net, v_pct, v_comm
         where not exists (
           select 1 from public.host_ledger_entries e
            where e.booking_id = new.id
              and e.entry_type in ('booking_online', 'booking_cash'));
      end if;
    end if;
  end if;

  -- ── Paid → refunded: negate whatever was posted ────────────────────────────
  if tg_op = 'UPDATE'
     and new.payment_status = 'refunded'
     and old.payment_status = 'paid' then
    insert into public.host_ledger_entries
      (host_id, booking_id, entry_type, amount,
       booking_net, commission_rate_pct, commission_amount)
    select e.host_id, e.booking_id, 'booking_refund_reversal',
           -e.amount, e.booking_net, e.commission_rate_pct, -e.commission_amount
      from public.host_ledger_entries e
     where e.booking_id = new.id
       and e.entry_type in ('booking_online', 'booking_cash')
       and not exists (
         select 1 from public.host_ledger_entries r
          where r.booking_id = new.id
            and r.entry_type = 'booking_refund_reversal');
  end if;

  return null;
end;
$$;

drop trigger if exists trg_post_booking_ledger on public.bookings;
create trigger trg_post_booking_ledger
  after insert or update of payment_status on public.bookings
  for each row execute function public.fn_post_booking_ledger();

-- ---------------------------------------------------------------------------
-- 4. Posting trigger — disbursements
-- ---------------------------------------------------------------------------
-- Payouts feed the ledger automatically, so recording a disbursement (the
-- existing record_disbursement flow, untouched) is the ONLY act of paying a
-- host — there is no second "also post it to the ledger" step to forget.
-- Posted on 'sent', not 'pending': money moves the ledger only when it has
-- actually left. guest_refund disbursements post nothing — platform→guest
-- money never touches the host's balance; the host side of a refund is the
-- booking reversal above.
create or replace function public.fn_post_disbursement_ledger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.kind <> 'host_payout' then
    return null;
  end if;

  if new.status = 'sent'
     and (tg_op = 'INSERT' or old.status is distinct from 'sent') then
    insert into public.host_ledger_entries
      (host_id, disbursement_id, booking_id, entry_type, amount, reference, note)
    select new.user_id, new.id, new.booking_id, 'payout', -new.amount,
           new.reference, new.note
     where not exists (
       select 1 from public.host_ledger_entries e
        where e.disbursement_id = new.id and e.entry_type = 'payout');
  end if;

  if tg_op = 'UPDATE' and new.status = 'failed' and old.status = 'sent' then
    insert into public.host_ledger_entries
      (host_id, disbursement_id, booking_id, entry_type, amount, note)
    select new.user_id, new.id, new.booking_id, 'payout_reversal', new.amount,
           new.failure_reason
     where exists (
       select 1 from public.host_ledger_entries e
        where e.disbursement_id = new.id and e.entry_type = 'payout')
       and not exists (
         select 1 from public.host_ledger_entries e
          where e.disbursement_id = new.id and e.entry_type = 'payout_reversal');
  end if;

  return null;
end;
$$;

drop trigger if exists trg_post_disbursement_ledger on public.disbursements;
create trigger trg_post_disbursement_ledger
  after insert or update of status on public.disbursements
  for each row execute function public.fn_post_disbursement_ledger();

-- A failed or sent disbursement cannot quietly change its mind: the ledger's
-- one-entry-per-(disbursement, type) index means a same-row resurrection would
-- desynchronise the two tables. Money that bounces is retried as a NEW
-- disbursement — the same "new row, never a silent edit" rule payout methods
-- follow. Allowed transitions: pending→sent, pending→failed, sent→failed.
create or replace function public.fn_guard_disbursement_transitions()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  if old.status is distinct from new.status then
    if not ((old.status = 'pending' and new.status in ('sent', 'failed'))
            or (old.status = 'sent' and new.status = 'failed')) then
      raise exception 'a % disbursement cannot become % — record a new disbursement instead',
        old.status, new.status using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_disbursements_transitions on public.disbursements;
create trigger trg_disbursements_transitions
  before update of status on public.disbursements
  for each row execute function public.fn_guard_disbursement_transitions();

-- ---------------------------------------------------------------------------
-- 5. The manual door — collections and adjustments
-- ---------------------------------------------------------------------------
-- Payouts do NOT come through here (they flow from record_disbursement via the
-- trigger above). This RPC records the other direction — a host handing the
-- platform its commission on cash bookings — and signed corrections.
create or replace function public.record_host_ledger_entry(
  p_host_id    uuid,
  p_entry_type text,
  p_amount     numeric,
  p_note       text default null,
  p_reference  text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_admin  uuid := auth.uid();
  v_amount numeric := round(coalesce(p_amount, 0), 2);
  v_id     uuid;
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  if p_entry_type not in ('collection', 'adjustment') then
    raise exception 'entry type must be collection or adjustment — payouts are recorded as disbursements'
      using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_host_id) then
    raise exception 'no such user' using errcode = '22023';
  end if;
  if p_entry_type = 'collection' and v_amount <= 0 then
    raise exception 'a collection must be a positive amount' using errcode = '22023';
  end if;
  if p_entry_type = 'adjustment' and v_amount = 0 then
    raise exception 'an adjustment cannot be zero' using errcode = '22023';
  end if;
  if p_entry_type = 'adjustment' and coalesce(btrim(p_note), '') = '' then
    raise exception 'an adjustment needs a note explaining it' using errcode = '22023';
  end if;

  insert into public.host_ledger_entries
    (host_id, entry_type, amount, reference, note, created_by)
  values
    (p_host_id, p_entry_type, v_amount,
     nullif(btrim(p_reference), ''), nullif(btrim(p_note), ''), v_admin)
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.record_host_ledger_entry(uuid, text, numeric, text, text) from public, anon;
grant execute on function public.record_host_ledger_entry(uuid, text, numeric, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Audit
-- ---------------------------------------------------------------------------
-- Teach fn_audit to pull an amount off ledger rows, so financial_audit shows a
-- figure. Reproduced whole (the 100 convention); existing branches untouched.
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
  -- ── New in 101 ────────────────────────────────────────────────────────────
  elsif tg_table_name = 'host_ledger_entries' then
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

-- Insert only: the table is append-only, there is nothing else to audit.
drop trigger if exists trg_audit_host_ledger_ins on public.host_ledger_entries;
create trigger trg_audit_host_ledger_ins
  after insert on public.host_ledger_entries
  for each row execute function public.fn_audit('financial');

-- ---------------------------------------------------------------------------
-- 7. Views for the console
-- ---------------------------------------------------------------------------

-- Each host's position on one row. security_invoker + the select policy means
-- a host aggregates only their own entries; admins see everyone.
create or replace view public.host_balances
  with (security_invoker = true)
as
  select
    e.host_id,
    p.full_name,
    p.mobile,
    p.avatar_url,
    sum(e.amount)     as balance,
    sum(e.commission_amount) filter (where e.entry_type in
      ('booking_online', 'booking_cash', 'booking_refund_reversal'))
                      as commission_earned,
    count(*)          as entry_count,
    max(e.created_at) as last_entry_at
  from public.host_ledger_entries e
  join public.profiles p on p.id = e.host_id
 group by e.host_id, p.full_name, p.mobile, p.avatar_url;

comment on view public.host_balances is
  'One row per host with ledger activity: balance (positive = platform owes host), commission earned, entry count. security_invoker, so RLS scopes it (101).';

-- host_payouts_due, reproduced whole from 100 with the two changes its own
-- header comment promised once a commission existed:
--   * suggested_amount is now the host's actual share — the posted ledger
--     entry when there is one, else an estimate at the current rate;
--   * cash-settled bookings no longer appear as "due" (the host already holds
--     that money; what remains is the platform's receivable, which the
--     Accounting page shows as a negative balance).
--
-- DROP + CREATE, not create-or-replace: the live view's suggested_amount
-- inherited numeric(10,2) from bookings.total_price, the new expression types
-- as bare numeric, and or-replace refuses to change a view column's type
-- (42P16). Dropping a view loses nothing, and the explicit cast below pins
-- the column so the next edit doesn't hit the same wall.
drop view if exists public.host_payouts_due;
create view public.host_payouts_due
  with (security_invoker = true)
as
  select
    b.id                     as booking_id,
    l.owner_id               as host_id,
    p.full_name              as host_name,
    b.listing_title,
    b.total_price,
    coalesce(
      (select e.amount from public.host_ledger_entries e
        where e.booking_id = b.id and e.entry_type = 'booking_online'),
      b.total_price - round(b.total_price * coalesce(
        (select nullif(btrim(s.value), '')::numeric
           from public.app_settings s
          where s.key = 'platform_commission_pct'),
        15) / 100.0, 2)
    )::numeric(12,2)         as suggested_amount,
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
   and coalesce(b.payment_method, 'online') <> 'cash'
   and not exists (
     select 1 from public.host_ledger_entries e
      where e.booking_id = b.id
        and e.entry_type = 'booking_cash'
   )
   and not exists (
     select 1 from public.disbursements d
      where d.booking_id = b.id
        and d.kind = 'host_payout'
        and d.status <> 'failed'
   );

comment on view public.host_payouts_due is
  'Earned stays with no live host_payout recorded, excluding cash-settled ones. suggested_amount is net of commission since 101. security_invoker (100).';

-- ---------------------------------------------------------------------------
-- 8. Backfill
-- ---------------------------------------------------------------------------
-- Every historically paid booking gets its earning entry at 15% (the rate the
-- console has been ESTIMATING at 10% was never charged to anyone — these
-- entries are the first real record, so they take the launch rate), dated at
-- paid_at so month-by-month reports stay honest. Idempotent: the not-exists
-- guard plus the unique index make a re-run a no-op.
insert into public.host_ledger_entries
  (host_id, booking_id, entry_type, amount,
   booking_net, commission_rate_pct, commission_amount, created_at)
select
  l.owner_id,
  b.id,
  case when coalesce(b.payment_method, m.method, 'online') = 'cash'
       then 'booking_cash' else 'booking_online' end,
  case when coalesce(b.payment_method, m.method, 'online') = 'cash'
       then -round(b.total_price * 0.15, 2)
       else b.total_price - round(b.total_price * 0.15, 2) end,
  b.total_price,
  15.00,
  round(b.total_price * 0.15, 2),
  coalesce(b.paid_at, b.completed_at, b.created_at)
from public.bookings b
join public.listings l on l.id = b.listing_id
left join lateral (
  select case when p.card_type = 'cash' then 'cash' else 'online' end as method
    from public.payments p
   where p.booking_id = b.id and p.status = 'paid'
   order by coalesce(p.validated_at, p.created_at)
   limit 1
) m on true
where b.payment_status = 'paid'
  and b.total_price > 0
  -- The same skip rules the trigger applies: a cash booking with a
  -- zero-rounding commission has nothing to owe, an online one posts as long
  -- as the host's share is positive.
  and case when coalesce(b.payment_method, m.method, 'online') = 'cash'
       then round(b.total_price * 0.15, 2) > 0
       else b.total_price - round(b.total_price * 0.15, 2) > 0 end
  and not exists (
    select 1 from public.host_ledger_entries e
     where e.booking_id = b.id
       and e.entry_type in ('booking_online', 'booking_cash'));

-- Payouts already sent under 100 join the ledger too, so a host's balance
-- reflects money that has genuinely left.
insert into public.host_ledger_entries
  (host_id, disbursement_id, booking_id, entry_type, amount,
   reference, note, created_at)
select d.user_id, d.id, d.booking_id, 'payout', -d.amount,
       d.reference, d.note, coalesce(d.sent_at, d.created_at)
  from public.disbursements d
 where d.kind = 'host_payout'
   and d.status = 'sent'
   and not exists (
     select 1 from public.host_ledger_entries e
      where e.disbursement_id = d.id and e.entry_type = 'payout');
