-- 102_payouts_due_requires_posted_earning.sql
--
-- Close the trap 101 left open. `host_payouts_due` still admitted a stay that
-- was completed but never PAID (inherited from 100, where it mirrored the
-- app's isEarnedRevenue definition and the list was purely informational).
-- Now that recording a payout writes the host ledger, that inclusion is a
-- footgun with a real casualty: an admin paid a host ৳85 for a completed,
-- unpaid ৳100 stay — money the platform never held — and the ledger dutifully
-- reported the host ৳100 in debt.
--
-- The rule becomes: a booking is due for payout exactly when its
-- 'booking_online' earning entry exists on the ledger. That single condition
-- subsumes the old ones —
--   * unpaid stays post no entry, so they cannot appear;
--   * cash stays post 'booking_cash', not 'booking_online', so the platform
--     never appears to owe money the host is already holding;
--   * and the suggestion stops being an estimate: it is the exact host share
--     the trigger froze at payment time, at the rate then in force.
-- The booking_status filter stays: a cancelled-after-payment stay should be
-- resolved as a refund, not silently offered as a payout.
drop view if exists public.host_payouts_due;
create view public.host_payouts_due
  with (security_invoker = true)
as
  select
    b.id                     as booking_id,
    e.host_id                as host_id,
    p.full_name              as host_name,
    b.listing_title,
    b.total_price,
    e.amount::numeric(12,2)  as suggested_amount,
    b.ends_at,
    b.booking_status,
    b.payment_status,
    b.paid_at,
    (select pm.id from public.payout_methods pm
      where pm.user_id = e.host_id and pm.retired_at is null
        and pm.status = 'verified'
      order by pm.is_default desc, pm.created_at
      limit 1)               as default_payout_method_id
  from public.bookings b
  -- The earning entry IS the definition of "the platform owes this host for
  -- this stay" — ledger and worklist cannot disagree, because they are the
  -- same row. host_id comes from the entry, not listings.owner_id: the entry
  -- snapshotted who earned the money at payment time, so a listing
  -- transferred afterwards still pays the person who hosted the stay.
  join public.host_ledger_entries e
    on e.booking_id = b.id and e.entry_type = 'booking_online'
  join public.profiles p on p.id = e.host_id
 where b.booking_status not in ('cancelled', 'rejected', 'pending')
   and not exists (
     select 1 from public.host_ledger_entries r
      where r.booking_id = b.id
        and r.entry_type = 'booking_refund_reversal'
   )
   and not exists (
     select 1 from public.disbursements d
      where d.booking_id = b.id
        and d.kind = 'host_payout'
        and d.status <> 'failed'
   );

comment on view public.host_payouts_due is
  'Online-paid stays whose ledger earning has no live host_payout against it. suggested_amount is the posted entry — the exact share frozen at payment time. security_invoker (102).';
