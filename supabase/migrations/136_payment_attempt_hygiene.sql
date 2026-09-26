-- =============================================
-- 136 — payment attempts pile up, and a risky payment settles like a clean one
--
-- Two findings from the payments QA round of 2026-09-18.
--
-- **F4.** `sslcommerz-init` writes a `payments` row before it calls the
-- gateway and nothing ever closes that row. Six rapid taps made six more
-- rows for one booking. Live carries 27 `initiated` rows worth 52,420 taka
-- from July and August that will sit there forever, so "how much have we
-- taken" cannot be answered by looking at the table, and the console's
-- "Gateway attempts" count is noise.
--
-- **F11.** SSLCommerz sets `risk_level = 1` with a `risk_title` when its own
-- fraud screen fires on an otherwise VALID transaction; its guidance is to
-- hold such a payment for review before delivering the service. The IPN
-- stored both fields and then marked the payment paid anyway, which unlocks
-- Service complete and posts the host's earning immediately.
--
-- This migration is the database half of both: two new terminal-ish states
-- for a payment, a sweep that reaches the first one, and the two admin RPCs
-- that resolve the second. The function halves ship with the same commit
-- (`supabase/functions/sslcommerz-init`, `sslcommerz-ipn`).
--
-- Note the direction of the damage, which is the opposite of 128's:
-- abandoning an attempt is recoverable (the guest taps Pay again and gets a
-- fresh session), so the sweep may act on its own. *Releasing* a held
-- payment moves money into the ledger and cannot be undone from the app, so
-- that one is admin-only and never automatic.
-- =============================================

-- ------------------------------------------------- the two new states
--
-- `abandoned` — an `initiated` row the guest never came back to.
-- `pending_review` — validated and paid for, but the gateway flagged it;
--                    the money is real, the service is NOT unlocked.
--
-- Recreated rather than patched: a CHECK is replaced wholesale, and the list
-- is the whole rule.
alter table public.payments drop constraint if exists payments_status_check;
alter table public.payments add constraint payments_status_check
  check (status in ('initiated', 'paid', 'failed', 'cancelled',
                    'abandoned', 'pending_review'));

comment on column public.payments.status is
  'initiated → the gateway session was created; paid → validated and '
  'settled; pending_review → validated but risk-flagged, held for an admin '
  '(136); failed / cancelled → the gateway said so; abandoned → initiated '
  'and never returned to, closed by expire_stale_payment_attempts (136).';

-- ------------------------------------------------- the sweep (F4)
--
-- 60 minutes, hardcoded, unlike `booking_accept_window_hours` (119). That one
-- is a setting because a host argued about it and the number is visible to
-- guests as a countdown. This one is invisible: it only decides when a dead
-- row stops being called `initiated`, and an admin has no reason to have an
-- opinion. An SSLCommerz session expires long before an hour is out.
--
-- It never touches `paid`, `pending_review` or the booking. A guest who
-- pays after the sweep runs still settles: the IPN looks the row up by
-- `tran_id` and its `status <> 'paid'` guard is unaffected by `abandoned`.
create or replace function public.expire_stale_payment_attempts()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_count integer;
begin
  update public.payments
     set status = 'abandoned',
         updated_at = now()
   where status = 'initiated'
     and created_at < now() - interval '60 minutes';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- PostgREST publishes everything in `public` at /rest/v1/rpc/<name>, and
-- ALTER DEFAULT PRIVILEGES has already granted anon and authenticated
-- EXECUTE on this the moment it was created (see CLAUDE.md on 116). All
-- three have to go or the grant survives through whichever is left.
revoke all on function public.expire_stale_payment_attempts() from public;
revoke all on function public.expire_stale_payment_attempts() from anon;
revoke all on function public.expire_stale_payment_attempts() from authenticated;

-- Every 15 minutes, matching `expire-stale-bookings`. An hour-long window
-- swept hourly expires somewhere between one and two hours, which is the
-- mistake 119 records.
select cron.unschedule('expire-stale-payment-attempts')
where exists (select 1 from cron.job where jobname = 'expire-stale-payment-attempts');

select cron.schedule(
  'expire-stale-payment-attempts',
  '*/15 * * * *',
  $cron$select public.expire_stale_payment_attempts();$cron$
);

-- ------------------------------------------------- resolving a held payment (F11)
--
-- Both are `admin_*`, so both carry the guard every other `admin_*` function
-- in this schema carries: service_role only. The console reaches them with
-- `createServiceClient()`; an admin's own JWT is deliberately not enough,
-- because releasing a payment is the one action here that moves money.
create or replace function public.admin_release_payment(p_payment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_payment public.payments%rowtype;
begin
  perform public.fn_require_service_role();

  select * into v_payment from public.payments where id = p_payment_id for update;
  if not found then
    raise exception 'Payment not found' using errcode = 'P0002';
  end if;
  if v_payment.status <> 'pending_review' then
    raise exception 'Only a payment held for review can be released (status is %)',
      v_payment.status using errcode = '22023';
  end if;

  update public.payments
     set status = 'paid', updated_at = now()
   where id = p_payment_id;

  -- The same announcement the two payment RPCs make (132). Without it
  -- `enforce_booking_update_rules` refuses this write, exactly as it should:
  -- a SECURITY DEFINER function still runs with the caller's `auth.uid()`.
  perform set_config('musafir.settlement_write', '1', true);
  update public.bookings
     set payment_status = 'paid',
         paid_at = coalesce(paid_at, now())
   where id = v_payment.booking_id;
  perform set_config('musafir.settlement_write', '0', true);

  return jsonb_build_object('payment_id', p_payment_id,
                            'booking_id', v_payment.booking_id,
                            'status', 'paid');
end;
$$;

create or replace function public.admin_reject_payment(p_payment_id uuid,
                                                       p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_payment public.payments%rowtype;
begin
  perform public.fn_require_service_role();

  select * into v_payment from public.payments where id = p_payment_id for update;
  if not found then
    raise exception 'Payment not found' using errcode = 'P0002';
  end if;
  if v_payment.status <> 'pending_review' then
    raise exception 'Only a payment held for review can be rejected (status is %)',
      v_payment.status using errcode = '22023';
  end if;

  -- `failed` rather than a new `rejected`: from the guest's and the host's
  -- point of view this payment did not happen, and every screen that already
  -- knows how to render a failed attempt renders this one correctly. The
  -- reason is kept in the gateway blob, which is where the risk fields
  -- that caused the hold already live.
  update public.payments
     set status = 'failed',
         gateway_response = coalesce(gateway_response, '{}'::jsonb)
           || jsonb_build_object('musafir_review',
                jsonb_build_object('decision', 'rejected',
                                   'reason', p_reason,
                                   'at', now())),
         updated_at = now()
   where id = p_payment_id;

  return jsonb_build_object('payment_id', p_payment_id, 'status', 'failed');
end;
$$;

revoke all on function public.admin_release_payment(uuid) from public;
revoke all on function public.admin_release_payment(uuid) from anon;
revoke all on function public.admin_release_payment(uuid) from authenticated;
revoke all on function public.admin_reject_payment(uuid, text) from public;
revoke all on function public.admin_reject_payment(uuid, text) from anon;
revoke all on function public.admin_reject_payment(uuid, text) from authenticated;
