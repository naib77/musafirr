-- 089_audit_log.sql
-- Phase 1 of the audit trail: an append-only, DB-level log of financial and
-- admin/sensitive changes, populated by triggers (NOT app code) so every write
-- path — the Flutter app, the admin portal, SECURITY DEFINER RPCs
-- (mark_cash_payment, set_booking_payment_method, …), and the SSLCommerz IPN
-- edge function — is captured uniformly and can't be bypassed.
--
-- Covered in Phase 1:
--   payments        (INSERT + status/settlement UPDATE)   → financial
--   bookings        (INSERT + money/status/method UPDATE)  → financial
--   app_settings    (INSERT/UPDATE — e.g. cash toggle)     → admin
--   owner_documents (verification decision UPDATE)         → verification
--   profiles        (role / is_host escalation UPDATE)     → auth
--
-- Immutability: RLS makes it admin-read-only with NO client write path (trigger
-- inserts run as the SECURITY DEFINER function owner, bypassing RLS); a guard
-- trigger blocks UPDATE/DELETE outright. Retention/purge (a later phase) runs
-- as a superuser with `set session_replication_role = 'replica'` to bypass the
-- guard.

-- ── 1. The log table ─────────────────────────────────────────────────────────
create table if not exists public.audit_log (
  id           bigint generated always as identity primary key,
  occurred_at  timestamptz not null default now(),
  table_name   text        not null,
  record_id    uuid,
  action       text        not null,          -- insert | update | delete
  actor_id     uuid,                           -- auth.uid() of the writer, if any
  actor_role   text,                           -- app_role of the actor (admin/owner/tenant)
  source       text        not null default 'app', -- app | admin | rpc | gateway | system
  category     text        not null,           -- financial | admin | verification | auth | …
  amount       numeric,                         -- denormalized for financial reporting
  currency     text,
  changed_cols text[],                          -- columns that changed (UPDATE only)
  old_data     jsonb,
  new_data     jsonb,
  note         text
);

create index if not exists idx_audit_log_occurred      on public.audit_log (occurred_at desc);
create index if not exists idx_audit_log_table_record  on public.audit_log (table_name, record_id);
create index if not exists idx_audit_log_actor         on public.audit_log (actor_id);
create index if not exists idx_audit_log_category_time on public.audit_log (category, occurred_at desc);

comment on table public.audit_log is
  'Append-only audit trail (financial + admin/sensitive changes). Admin-read-only; written only by trigger fn public.fn_audit.';

-- ── 2. RLS: admin-read-only, no client write path ───────────────────────────
alter table public.audit_log enable row level security;

drop policy if exists "audit_log_admin_select" on public.audit_log;
create policy "audit_log_admin_select"
  on public.audit_log for select
  to authenticated
  using (
    exists (select 1 from public.profiles p
            where p.id = auth.uid() and p.role = 'admin')
  );

-- No INSERT/UPDATE/DELETE policies → default-deny for every client role.
revoke insert, update, delete on public.audit_log from anon, authenticated;

-- ── 3. Immutability guard ────────────────────────────────────────────────────
create or replace function public.fn_audit_immutable()
returns trigger
language plpgsql
as $$
begin
  raise exception 'audit_log is append-only (% blocked)', tg_op
    using errcode = '42501';
end;
$$;

drop trigger if exists trg_audit_immutable on public.audit_log;
create trigger trg_audit_immutable
  before update or delete on public.audit_log
  for each row execute function public.fn_audit_immutable();

-- ── 4. The generic capture function ──────────────────────────────────────────
-- SECURITY DEFINER so its INSERT into audit_log bypasses the table's deny-all
-- RLS. Category is passed as the trigger argument; amount/currency are pulled
-- from the row for financial tables.
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
    -- Nothing we care about actually changed → skip the row.
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

  return null; -- AFTER trigger; return value ignored
end;
$$;

-- ── 5. Attach triggers to the Phase-1 tables ─────────────────────────────────
-- payments: every insert, and settlement-relevant updates.
drop trigger if exists trg_audit_payments_ins on public.payments;
create trigger trg_audit_payments_ins
  after insert on public.payments
  for each row execute function public.fn_audit('financial');

drop trigger if exists trg_audit_payments_upd on public.payments;
create trigger trg_audit_payments_upd
  after update on public.payments
  for each row
  when (old.status is distinct from new.status
        or old.validated_at is distinct from new.validated_at)
  execute function public.fn_audit('financial');

-- bookings: creation (captures initial price/terms) + money/status/method changes.
drop trigger if exists trg_audit_bookings_ins on public.bookings;
create trigger trg_audit_bookings_ins
  after insert on public.bookings
  for each row execute function public.fn_audit('financial');

drop trigger if exists trg_audit_bookings_upd on public.bookings;
create trigger trg_audit_bookings_upd
  after update on public.bookings
  for each row
  when (old.payment_status  is distinct from new.payment_status
        or old.payment_method is distinct from new.payment_method
        or old.booking_status is distinct from new.booking_status
        or old.total_price    is distinct from new.total_price)
  execute function public.fn_audit('financial');

-- app_settings: any admin config change (e.g. cash_payment_enabled).
drop trigger if exists trg_audit_app_settings on public.app_settings;
create trigger trg_audit_app_settings
  after insert or update on public.app_settings
  for each row execute function public.fn_audit('admin');

-- owner_documents: verification approve/reject decisions.
drop trigger if exists trg_audit_owner_documents_upd on public.owner_documents;
create trigger trg_audit_owner_documents_upd
  after update on public.owner_documents
  for each row
  when (old.verified_at      is distinct from new.verified_at
        or old.verified_by      is distinct from new.verified_by
        or old.rejection_reason is distinct from new.rejection_reason)
  execute function public.fn_audit('verification');

-- profiles: privilege escalation (role / host status).
drop trigger if exists trg_audit_profiles_upd on public.profiles;
create trigger trg_audit_profiles_upd
  after update on public.profiles
  for each row
  when (old.role is distinct from new.role
        or old.is_host is distinct from new.is_host)
  execute function public.fn_audit('auth');

-- ── 6. Finance convenience view (admin-only via security_invoker + RLS) ──────
create or replace view public.financial_audit
  with (security_invoker = true)
as
  select id, occurred_at, table_name, record_id, action,
         actor_id, actor_role, source, amount, currency, changed_cols
    from public.audit_log
   where category = 'financial';
