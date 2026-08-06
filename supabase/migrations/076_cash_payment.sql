-- 076_cash_payment.sql
-- Host-confirmed cash ("hand cash") payment. SSLCommerz can't process cash, so
-- the HOST — the person who physically received the money — confirms it. This
-- records an auditable cash payment row and flips bookings.payment_status='paid'
-- so "mark service complete" unlocks, mirroring the online settlement path.
-- Guest cannot self-confirm (fraud): the RPC checks the caller owns the listing.

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

  update public.bookings set payment_status = 'paid' where id = p_booking_id;

  -- Let the guest see the confirmation live (reliable notifications channel).
  insert into public.notifications (user_id, type, title, body, action_url)
  values (
    v_tenant, 'paymentReceived', 'Cash payment confirmed',
    'The host confirmed your cash payment for ' || coalesce(v_title, 'your booking') || '.',
    '/trips'
  );
end;
$$;

revoke execute on function public.mark_cash_payment(uuid) from public, anon;
grant execute on function public.mark_cash_payment(uuid) to authenticated;
