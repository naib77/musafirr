-- =============================================
-- 132 — a guest or a host could mark their own booking paid
--
-- Verified on live, rolled back, 2026-09-17. Impersonating the tenant of a
-- real `completed, unpaid` booking:
--
--     update bookings set payment_status = 'paid' where id = <mine>;
--
-- succeeded. So did the same as the listing's owner. Through PostgREST that is
-- one PATCH with the anon key that ships in build/web plus the user's own JWT.
--
-- Three things line up to allow it, and each one on its own looks fine:
--
--   * `authenticated` holds column UPDATE on `bookings.payment_status` (and on
--     `payment_method` and `paid_at`) — the table-wide grant from 001.
--   * both UPDATE policies admit the caller: "Users can cancel their own
--     bookings" is `auth.uid() = tenant_id` with no WITH CHECK, and "Hosts can
--     update bookings for their listings" admits the owner.
--   * `enforce_booking_update_rules` (051, 098) freezes tenant, listing, price
--     and dates for non-admins and gates *booking_status* transitions. It never
--     mentions `payment_status`.
--
-- What the write does downstream is why this is S1 rather than cosmetic:
-- `trg_post_booking_ledger` (101) posts the host's earning on the transition
-- to `paid`, so the host is owed a payout for money that never moved, and
-- Service complete — which refuses while unpaid — unlocks.
--
-- The client never writes these columns legitimately. Online settlement is
-- `sslcommerz-ipn` under the service role (auth.uid() is null, the trigger's
-- first branch). Cash is `mark_cash_payment` (076) and the method choice is
-- `set_booking_payment_method` (086), both SECURITY DEFINER. `paid_at` is set
-- by `set_booking_paid_at`, a trigger. The only JWT-bearing writer is the admin
-- console's refund switch (`markBookingRefunded`, a direct table update as an
-- admin user), and admins are exempt from this trigger by design.
--
-- **Why a trigger guard and not a column REVOKE.** A revoke would be the
-- cleaner control and is the eventual shape, but the admin console writes
-- `payment_status` with the admin's own JWT (role `authenticated`), so the
-- revoke lands there first and breaks refunds until the console moves that
-- write to an RPC or the service-role client. That is a change in another
-- repo with a manual deploy; this migration has to be safe to apply alone.
--
-- **How the guard tells a client apart from an RPC.** The definer functions
-- above update these columns *with* auth.uid() set — the host confirming cash
-- is a real signed-in user — so "non-admin changed payment_status" would block
-- them too. `current_user` cannot tell them apart either: this trigger is
-- itself SECURITY DEFINER, so inside it `current_user` is always `postgres`
-- (the first draft of this migration used it and the guard never fired —
-- verified rolled back, rows 1–3 still "update accepted"). So the two RPCs
-- raise a transaction-local flag, `musafir.settlement_write`, immediately
-- around their own update, and the trigger lets a settlement change through
-- only while it is set. `set_config(..., true)` is local to the transaction,
-- and PostgREST runs each request in its own, so the flag cannot leak from
-- one request to the next; a client has no way to set it — PostgREST only
-- materialises GUCs under `request.*`, and `set_config` is not exposed as an
-- RPC. The two RPCs are recreated in full below for the same reason the
-- trigger is.
--
-- The CASE-recreation rule from CLAUDE.md applies: the function is rewritten
-- in full below, from the live definition (098's version), with one new block.
-- =============================================

create or replace function public.enforce_booking_update_rules()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_is_owner boolean;
  v_is_admin boolean;
  v_is_tenant boolean;
begin
  -- Server-side (service_role / cron) has no auth context; trust it.
  if v_uid is null then
    return new;
  end if;

  select exists (
    select 1 from public.profiles p where p.id = v_uid and p.role = 'admin'
  ) into v_is_admin;
  if v_is_admin then
    return new;
  end if;

  -- Financial / identity fields never change after creation for non-admins.
  if new.tenant_id  is distinct from old.tenant_id
     or new.listing_id  is distinct from old.listing_id
     or new.total_price is distinct from old.total_price
     or new.starts_at   is distinct from old.starts_at
     or new.ends_at     is distinct from old.ends_at then
    raise exception
      'Booking amount, dates and parties cannot be modified after creation';
  end if;

  -- 132: settlement columns are written only by the service role, by admins,
  -- or by the SECURITY DEFINER payment RPCs — never by a client's own table
  -- write. The RPCs announce themselves with a transaction-local flag; see
  -- the header for why neither current_user nor auth.uid() can do this.
  if (new.payment_status is distinct from old.payment_status
      or new.payment_method is distinct from old.payment_method
      or new.paid_at        is distinct from old.paid_at)
     and coalesce(current_setting('musafir.settlement_write', true), '') <> '1' then
    raise exception
      'Payment status is set by the payment gateway or the host''s cash confirmation, not directly'
      using errcode = '42501', hint = 'payment_columns_protected';
  end if;

  select exists (
    select 1 from public.listings l
    where l.id = new.listing_id and l.owner_id = v_uid
  ) into v_is_owner;
  v_is_tenant := (new.tenant_id = v_uid);

  -- Guest: cancellation only.
  if v_is_tenant and not v_is_owner then
    if new.booking_status is distinct from old.booking_status then
      if new.booking_status <> 'cancelled' then
        raise exception
          'Guests may only cancel a booking (attempted % -> %)',
          old.booking_status, new.booking_status;
      end if;
      if old.booking_status not in ('pending', 'confirmed') then
        raise exception 'Cannot cancel a booking in % state', old.booking_status;
      end if;
    end if;
    return new;
  end if;

  -- Host (listing owner) drives accept/reject/check-in/complete/cancel.
  if v_is_owner then
    return new;
  end if;

  -- Not tenant, owner, or admin — RLS should already have blocked this.
  raise exception 'Not authorized to update this booking';
end;
$$;

-- ---------------------------------------------------------------------------
-- The two client-reachable writers of settlement columns, recreated in full
-- from their live definitions (086 and 076) with the flag raised around the
-- one statement that needs it and lowered straight after, so nothing else in
-- the same transaction inherits the permission.
-- ---------------------------------------------------------------------------

create or replace function public.set_booking_payment_method(p_booking_id uuid, p_method text)
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

  -- 132: this is a settlement-column write from a real auth.uid(); tell the
  -- bookings trigger it is ours.
  perform set_config('musafir.settlement_write', '1', true);
  update public.bookings set payment_method = p_method where id = p_booking_id;
  perform set_config('musafir.settlement_write', '0', true);
end;
$$;

create or replace function public.mark_cash_payment(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_tenant uuid;
  v_listing uuid;
  v_total numeric;
  v_pay_status text;
  v_owner uuid;
  v_title text;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;

  select tenant_id, listing_id, total_price, payment_status
    into v_tenant, v_listing, v_total, v_pay_status
    from public.bookings where id = p_booking_id;
  if v_tenant is null then raise exception 'Booking not found'; end if;

  select owner_id, title into v_owner, v_title
    from public.listings where id = v_listing;
  if v_owner is null or v_owner <> v_uid then
    raise exception 'Only the host can confirm a cash payment' using errcode = '42501';
  end if;

  -- Idempotent: already settled (online or a prior cash confirm) → no-op.
  if v_pay_status = 'paid' then return; end if;

  insert into public.payments (
    booking_id, user_id, tran_id, amount, currency, status,
    card_type, validated_at, gateway_response
  ) values (
    p_booking_id, v_tenant, 'CASH-' || p_booking_id::text,
    coalesce(v_total, 0), 'BDT', 'paid',
    'cash', now(), jsonb_build_object('method', 'cash', 'confirmed_by', v_uid)
  )
  on conflict (tran_id) do nothing;

  -- 132: see set_booking_payment_method.
  perform set_config('musafir.settlement_write', '1', true);
  update public.bookings set payment_status = 'paid' where id = p_booking_id;
  perform set_config('musafir.settlement_write', '0', true);

  -- Let the guest see the confirmation live (reliable notifications channel).
  insert into public.notifications (user_id, type, title, body, action_url)
  values (
    v_tenant, 'payment_received', 'Cash payment confirmed',
    'The host confirmed your cash payment for ' || coalesce(v_title, 'your booking') || '.',
    '/trips'
  );
end;
$$;

-- Both keep the grants they had (postgres, authenticated, service_role);
-- CREATE OR REPLACE preserves the ACL.

-- Follow-up, deliberately not here: once `markBookingRefunded` in
-- ../musafir-admin writes through the service-role client or an admin_* RPC,
-- add
--     revoke update (payment_status, payment_method, paid_at)
--       on public.bookings from anon, authenticated;
-- so the grant is gone as well as guarded. Rows 4–6 in
-- supabase/tests/132_guard_payment_columns_test.sql is written to keep
-- passing either way.
