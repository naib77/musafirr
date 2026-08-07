-- 085_payment_method_choice.sql
-- Guest chooses a payment method at the pay step (after the host accepts):
--   • 'online' — pay now via SSLCommerz (existing flow), or
--   • 'cash'   — "hand cash": pay the host directly; the host later confirms
--                receipt with mark_cash_payment() (migration 076).
--
-- Whether the 'cash' option is offered at all is an app-wide switch an admin
-- flips from the admin portal: the app_settings key `cash_payment_enabled`.
--
-- This migration:
--   1. Seeds the `cash_payment_enabled` setting (default: enabled).
--   2. Lets an admin write app_settings from the portal (RLS INSERT/UPDATE).
--   3. Adds bookings.payment_method to record the guest's choice.
--   4. Adds set_booking_payment_method() — the guest-only RPC that records it,
--      re-checking the admin toggle server-side (never trust the client).

-- ── 1. Seed the admin toggle ────────────────────────────────────────────────
-- Enabled by default (cash was already a supported settlement path). Flip off
-- from the admin portal, or with:
--   update public.app_settings set value = 'false' where key = 'cash_payment_enabled';
insert into public.app_settings (key, value)
values ('cash_payment_enabled', 'true')
on conflict (key) do nothing;

-- ── 2. Admin write access to app_settings ───────────────────────────────────
-- Reads stay public (the app loads settings at startup — policy from 075).
-- Writes are admin-only so the portal (which acts as the signed-in admin under
-- RLS) can toggle settings without needing the service_role key.
drop policy if exists "app_settings_admin_insert" on public.app_settings;
create policy "app_settings_admin_insert"
  on public.app_settings for insert
  to authenticated
  with check (
    exists (select 1 from public.profiles p
            where p.id = auth.uid() and p.role = 'admin')
  );

drop policy if exists "app_settings_admin_update" on public.app_settings;
create policy "app_settings_admin_update"
  on public.app_settings for update
  to authenticated
  using (
    exists (select 1 from public.profiles p
            where p.id = auth.uid() and p.role = 'admin')
  )
  with check (
    exists (select 1 from public.profiles p
            where p.id = auth.uid() and p.role = 'admin')
  );

-- ── 3. Record the guest's chosen method on the booking ──────────────────────
-- Null = not chosen yet (legacy / online-by-default). 'cash' tells the host to
-- expect a hand-cash payment and confirm it once received.
alter table public.bookings
  add column if not exists payment_method text
  check (payment_method in ('online', 'cash'));

-- ── 4. Guest-only RPC to set the method ─────────────────────────────────────
-- Only the booking's own guest may set it, only while the stay is accepted and
-- unpaid, and 'cash' is rejected unless the admin toggle is on. This is the
-- authoritative gate — the app also hides the option, but the server re-checks.
create or replace function public.set_booking_payment_method(
  p_booking_id uuid,
  p_method text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_tenant uuid;
  v_pay_status text;
  v_status text;
  v_cash_enabled boolean;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;

  if p_method not in ('online', 'cash') then
    raise exception 'Invalid payment method: %', p_method using errcode = '22023';
  end if;

  select tenant_id, payment_status, booking_status
    into v_tenant, v_pay_status, v_status
    from public.bookings where id = p_booking_id;
  if v_tenant is null then raise exception 'Booking not found'; end if;

  -- Only the guest who owns the booking may choose its payment method.
  if v_tenant <> v_uid then
    raise exception 'Only the guest can choose the payment method'
      using errcode = '42501';
  end if;

  -- Nothing to choose once it's already settled.
  if v_pay_status = 'paid' then
    raise exception 'This booking is already paid' using errcode = '42501';
  end if;

  -- Payment is only arranged after the host accepts and before completion.
  if v_status not in ('confirmed', 'active') then
    raise exception 'Payment can only be arranged after the host accepts'
      using errcode = '42501';
  end if;

  -- 'cash' requires the admin toggle. Defence in depth: the client hides the
  -- option, but never trust the client.
  if p_method = 'cash' then
    select lower(coalesce(value, '')) = 'true' into v_cash_enabled
      from public.app_settings where key = 'cash_payment_enabled';
    if not coalesce(v_cash_enabled, false) then
      raise exception 'Cash payment is not available' using errcode = '42501';
    end if;
  end if;

  update public.bookings set payment_method = p_method where id = p_booking_id;
end;
$$;

revoke execute on function public.set_booking_payment_method(uuid, text) from public, anon;
grant execute on function public.set_booking_payment_method(uuid, text) to authenticated;
