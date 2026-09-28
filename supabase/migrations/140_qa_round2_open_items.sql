-- =============================================
-- 140 — the second QA round's open items (2026-09-19)
--
-- Section 5 of docs/qa/REPORT_ROUND2_2026-09-19.md listed what 138 left
-- open. This closes the four that are database work:
--
--   1. A refund POLICY (scenario 20 only alerted; nothing decided how much
--      goes back). Two settings, a pure function, a stamp on the booking, and
--      the ledger reversal scaled to it.
--   2. A no-show OUTCOME (24). 139 added the label; this teaches the state
--      machine, the notifier and the refund policy about it.
--   3. Account SUSPENSION (53). Two columns, two service-role RPCs, and a
--      guard on every write path a suspended account could still reach with
--      a token it already holds.
--   4. A RATE-LIMIT counter for the four Google/Gemini edge functions (56),
--      which accept the anon key that ships in the bundle and were metered by
--      nothing but Google's invoice.
--
-- Requires 139 to be COMMITTED first — `no_show` is used below.
--
-- supabase/tests/139_140_open_items_test.sql goes red with this reverted.
-- =============================================


-- ============================================================ 1. refund policy
--
-- The rule, in one sentence a guest can be told: cancel early and you get
-- everything back; cancel late and you get part of it; cancel after
-- check-in time, or do not turn up, and you get nothing; if the HOST cancels
-- you always get everything back. "Early" and "part" are admin settings so
-- the business can move them without a release:
--
--   refund_full_window_hours  (default 48)  cancelling at least this many
--                                           hours before check-in refunds 100%
--   refund_late_pct           (default 50)  cancelling inside that window,
--                                           but before check-in, refunds this
--
-- Both validated on write like every other key (fn_validate_app_setting is a
-- CASE and is recreated in full — an arm dropped by a partial patch silently
-- stops validating that key).

create or replace function public.fn_validate_setting_refund_window_hours(p_value text)
returns void
language plpgsql
immutable
set search_path to 'public'
as $$
declare n integer;
begin
  if btrim(coalesce(p_value, '')) !~ '^[0-9]+$' then
    raise exception 'refund_full_window_hours must be a whole number of hours'
      using errcode = '22023';
  end if;
  n := btrim(p_value)::integer;
  -- 0 is a real policy ("full refund right up to check-in"); 720 hours is
  -- thirty days, past which the window is longer than most stays are booked
  -- ahead and every cancellation would be a partial one.
  if n > 720 then
    raise exception 'refund_full_window_hours: % is more than 720 hours (30 days)', n
      using errcode = '22023';
  end if;
end;
$$;

create or replace function public.fn_validate_setting_refund_late_pct(p_value text)
returns void
language plpgsql
immutable
set search_path to 'public'
as $$
declare n integer;
begin
  if btrim(coalesce(p_value, '')) !~ '^[0-9]+$' then
    raise exception 'refund_late_pct must be a whole-number percentage'
      using errcode = '22023';
  end if;
  n := btrim(p_value)::integer;
  if n > 100 then
    raise exception 'refund_late_pct: % is more than 100', n using errcode = '22023';
  end if;
end;
$$;

create or replace function public.fn_validate_app_setting()
returns trigger
language plpgsql
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
    when 'active_theme' then
      perform public.fn_validate_setting_active_theme(new.value);
    when 'booking_accept_window_hours' then
      perform public.fn_validate_setting_booking_accept_hours(new.value);
    when 'android_min_version_code' then
      perform public.fn_validate_setting_android_min_version_code(new.value);
    when 'max_devices_per_user' then
      perform public.fn_validate_setting_max_devices(new.value);
    when 'sms_bulk_max_recipients' then
      perform public.fn_validate_setting_sms_max_recipients(new.value);
    when 'notification_bulk_max_recipients' then
      perform public.fn_validate_setting_notification_max_recipients(new.value);
    when 'refund_full_window_hours' then
      perform public.fn_validate_setting_refund_window_hours(new.value);
    when 'refund_late_pct' then
      perform public.fn_validate_setting_refund_late_pct(new.value);
    else
      null;
  end case;
  return new;
end;
$$;

insert into public.app_settings (key, value)
values ('refund_full_window_hours', '48'), ('refund_late_pct', '50')
on conflict (key) do nothing;

-- What the policy decided, stamped on the booking the moment it closes so the
-- admin's alert, the guest's notification, the console and the ledger all
-- quote one number. Written only by the trigger below (enforce_booking_update_
-- rules freezes both for a client).
alter table public.bookings
  add column if not exists refund_pct    integer
    check (refund_pct is null or refund_pct between 0 and 100),
  add column if not exists refund_amount numeric
    check (refund_amount is null or refund_amount >= 0);

-- Pure over its arguments plus the two settings: what percentage of a paid
-- booking goes back to the guest when it ends as p_status at p_at.
--
-- The settings are read with the same regex the validator uses and fall back
-- to the defaults, because rows predate guards and a policy function that
-- raises inside a cancellation is a cancellation that cannot happen.
create or replace function public.fn_refund_policy_pct(
  p_status       public.booking_status,
  p_cancelled_by uuid,
  p_tenant_id    uuid,
  p_starts_at    timestamptz,
  p_at           timestamptz default now()
) returns integer
language plpgsql
stable
set search_path to 'public'
as $$
declare
  v_window_hours integer;
  v_late_pct     integer;
  v_raw          text;
begin
  -- A guest who did not turn up is the late-cancellation rule taken to its
  -- end: nothing back. Same answer as cancelling after check-in time.
  if p_status = 'no_show' then
    return 0;
  end if;
  if p_status <> 'cancelled' then
    return null;
  end if;

  -- Anyone but the guest cancelling (the host, an admin, a sweep) means the
  -- guest is owed everything: they did not choose this.
  if p_cancelled_by is null or p_cancelled_by is distinct from p_tenant_id then
    return 100;
  end if;

  select value into v_raw from public.app_settings where key = 'refund_full_window_hours';
  v_window_hours := case when btrim(coalesce(v_raw, '')) ~ '^[0-9]+$'
                         then btrim(v_raw)::integer else 48 end;
  select value into v_raw from public.app_settings where key = 'refund_late_pct';
  v_late_pct := case when btrim(coalesce(v_raw, '')) ~ '^[0-9]+$'
                     then least(btrim(v_raw)::integer, 100) else 50 end;

  if p_at >= p_starts_at then
    return 0;
  end if;
  if p_starts_at - p_at >= make_interval(hours => v_window_hours) then
    return 100;
  end if;
  return v_late_pct;
end;
$$;
revoke all on function public.fn_refund_policy_pct(public.booking_status, uuid, uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.fn_refund_policy_pct(public.booking_status, uuid, uuid, timestamptz, timestamptz) to authenticated;

-- BEFORE the row closes: stamp the policy's answer. Only a PAID booking has
-- anything to refund; an unpaid one is left null so nothing downstream reads
-- "0% of nothing" as a decision.
--
-- Trigger order matters and is by name: trg_enforce_booking_update_rules
-- ("trg_e") fires before this ("trg_s"), so it sees refund_* exactly as the
-- client sent them and can refuse a client that tried to write them; this
-- then fills them in.
create or replace function public.fn_stamp_refund_policy()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_pct integer;
begin
  if new.booking_status in ('cancelled', 'no_show')
     and old.booking_status not in ('cancelled', 'no_show')
     and new.payment_status = 'paid' then
    v_pct := public.fn_refund_policy_pct(
      new.booking_status,
      -- enforce_booking_update_rules has already stamped cancelled_by for a
      -- caller who omitted it; a no-show carries no canceller.
      new.cancelled_by, new.tenant_id, new.starts_at, now());
    new.refund_pct    := v_pct;
    new.refund_amount := round(coalesce(new.total_price, 0) * v_pct / 100.0, 2);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_stamp_refund_policy on public.bookings;
create trigger trg_stamp_refund_policy
  before update of booking_status on public.bookings
  for each row execute function public.fn_stamp_refund_policy();

-- 138's alert, now quoting the policy. Admins are told only when money is
-- actually owed; the guest is always told what was decided, including "no
-- refund", because a silent zero reads as a forgotten refund.
create or replace function public.fn_alert_paid_cancellation()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_title  text;
  v_admin  uuid;
  v_amount text;
  v_total  text;
  v_by     text;
  v_policy text;
begin
  if not (new.booking_status in ('cancelled', 'no_show')
          and old.booking_status not in ('cancelled', 'no_show')
          and new.payment_status = 'paid') then
    return null;
  end if;

  v_title  := coalesce(new.listing_title,
                       (select l.title from public.listings l where l.id = new.listing_id),
                       'a booking');
  v_total  := trim(to_char(coalesce(new.total_price, 0), 'FM999999990.00'));
  v_amount := trim(to_char(coalesce(new.refund_amount, 0), 'FM999999990.00'));
  v_by     := case when new.booking_status = 'no_show' then 'The host reported a no-show on'
                   when new.cancelled_by = new.tenant_id then 'The guest cancelled'
                   else 'The host cancelled' end;
  v_policy := case coalesce(new.refund_pct, 100)
                when 100 then 'full refund'
                when 0 then 'no refund'
                else new.refund_pct || '% refund' end;

  if coalesce(new.refund_amount, 0) > 0 then
    for v_admin in select p.id from public.profiles p where p.role = 'admin' loop
      insert into public.notifications (user_id, type, title, body, priority, action_url, data)
      values (
        v_admin, 'system_alert', 'Refund due: ৳' || v_amount,
        format('%s a paid booking at %s (৳%s). Policy: %s — refund ৳%s from Payouts and mark the booking refunded.',
               v_by, v_title, v_total, v_policy, v_amount),
        'high', '/bookings/' || new.id,
        jsonb_build_object('booking_id', new.id, 'reason', 'paid_cancellation',
                           'amount', new.total_price, 'refund_amount', new.refund_amount,
                           'refund_pct', new.refund_pct, 'cancelled_by', new.cancelled_by)
      );
    end loop;
  end if;

  if new.tenant_id is not null then
    insert into public.notifications (user_id, type, title, body, priority, action_url, data)
    values (
      new.tenant_id, 'system_alert',
      case when coalesce(new.refund_amount, 0) > 0 then 'Your refund is being arranged'
           else 'No refund for this booking' end,
      case when coalesce(new.refund_amount, 0) > 0 then
        format('Your booking at %s was %s after you paid ৳%s. Under the cancellation policy you get ৳%s back (%s). Our team will refund you and be in touch.',
               v_title,
               case when new.booking_status = 'no_show' then 'marked as a no-show' else 'cancelled' end,
               v_total, v_amount, v_policy)
      else
        format('Your booking at %s was %s after you paid ৳%s. Under the cancellation policy no refund is due (%s).',
               v_title,
               case when new.booking_status = 'no_show' then 'marked as a no-show' else 'cancelled' end,
               v_total,
               case when new.booking_status = 'no_show' then 'you did not check in'
                    else 'cancelled after check-in time' end)
      end,
      'high', '/trips/' || new.id,
      jsonb_build_object('booking_id', new.id, 'reason', 'paid_cancellation',
                         'amount', new.total_price, 'refund_amount', new.refund_amount,
                         'refund_pct', new.refund_pct)
    );
  end if;
  return null;
end $$;

-- The ledger reversal follows the policy. "Mark refunded" used to negate the
-- host's whole earning whatever went back to the guest, so a 50% refund left
-- the platform holding half the money and the host holding none of it. The
-- reversal is now refund_pct of the original entry; a 0% refund posts nothing
-- (the CHECK forbids a zero-amount row anyway).
create or replace function public.fn_post_booking_ledger()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_host   uuid;
  v_pct    numeric;
  v_net    numeric;
  v_comm   numeric;
  v_method text;
  v_share  numeric;
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

  -- ── Paid → refunded: reverse the refunded share of whatever was posted ────
  if tg_op = 'UPDATE'
     and new.payment_status = 'refunded'
     and old.payment_status = 'paid' then
    -- null = a refund marked on a booking that closed before 140 stamped
    -- anything, or one refunded by hand while still open: whole thing back,
    -- which is what the reversal always did.
    v_share := coalesce(new.refund_pct, 100) / 100.0;
    if v_share > 0 then
      insert into public.host_ledger_entries
        (host_id, booking_id, entry_type, amount,
         booking_net, commission_rate_pct, commission_amount, note)
      select e.host_id, e.booking_id, 'booking_refund_reversal',
             -round(e.amount * v_share, 2), e.booking_net, e.commission_rate_pct,
             -round(e.commission_amount * v_share, 2),
             case when v_share < 1 then format('%s%% refund under policy', new.refund_pct) end
        from public.host_ledger_entries e
       where e.booking_id = new.id
         and e.entry_type in ('booking_online', 'booking_cash')
         and round(e.amount * v_share, 2) <> 0
         and not exists (
           select 1 from public.host_ledger_entries r
            where r.booking_id = new.id
              and r.entry_type = 'booking_refund_reversal');
    end if;
  end if;

  return null;
end;
$$;


-- ============================================================ 2. no-show
--
-- 139 added the label. Here it becomes a move the host can make and
-- everything else learns what it means.

-- The state machine (138), with two additions:
--   confirmed -> no_show   host only, and only once check-in time has passed.
--                          Reporting a no-show before the guest was due is
--                          the host cancelling with the guest's deposit, so it
--                          is refused with its own hint.
--   no_show is terminal.
-- And 140's own columns join the frozen list: refund_pct / refund_amount are
-- the trigger's to write.
--
-- Plus the suspension check (section 3): a suspended host cannot accept,
-- reject or otherwise move a booking with a token they still hold.
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

  -- 140: a suspended account keeps its access token for up to an hour after
  -- its sessions are deleted. Nothing it does in that hour lands.
  if public.fn_is_suspended(v_uid) then
    raise exception 'This account is suspended'
      using errcode = '42501', hint = 'account_suspended';
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

  -- 138: and neither does anything else create_marketplace_booking decided.
  -- guest_count is the capacity the host agreed to; unit_count and
  -- pricing_unit are what total_price was computed from; the coupon columns
  -- are what the ledger and the coupon's usage count rest on; the listing_*
  -- and tenant_name copies are what the OTHER party's screens display.
  -- 140: refund_pct / refund_amount are the policy's answer, not an input.
  if new.guest_count       is distinct from old.guest_count
     or new.unit_count        is distinct from old.unit_count
     or new.pricing_unit      is distinct from old.pricing_unit
     or new.coupon_code       is distinct from old.coupon_code
     or new.discount_amount   is distinct from old.discount_amount
     or new.listing_title     is distinct from old.listing_title
     or new.listing_image_url is distinct from old.listing_image_url
     or new.listing_city      is distinct from old.listing_city
     or new.tenant_name       is distinct from old.tenant_name
     or new.created_at        is distinct from old.created_at
     or new.refund_pct        is distinct from old.refund_pct
     or new.refund_amount     is distinct from old.refund_amount then
    raise exception
      'Booking details are fixed once the request is made'
      using errcode = '42501', hint = 'booking_columns_protected';
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

  -- 138: whoever cancels is the one recorded as cancelling. The lifecycle
  -- notification decides "cancelled by guest" vs "cancelled by host" from this
  -- column, and both the trips screen and the reservations screen print it.
  -- A caller may only ever name themselves; a caller who cancels without
  -- naming anyone is stamped, so the plain-update path notifies the other
  -- party like every other path does.
  if new.cancelled_by is distinct from old.cancelled_by
     and new.cancelled_by is distinct from v_uid then
    raise exception 'cancelled_by must be the account doing the cancelling'
      using errcode = '42501', hint = 'cancelled_by_forged';
  end if;
  if new.booking_status = 'cancelled' and old.booking_status <> 'cancelled' then
    new.cancelled_by := coalesce(new.cancelled_by, v_uid);
    new.cancelled_at := coalesce(new.cancelled_at, now());
  end if;

  select exists (
    select 1 from public.listings l
    where l.id = new.listing_id and l.owner_id = v_uid
  ) into v_is_owner;
  v_is_tenant := (new.tenant_id = v_uid);

  -- Guest: cancellation only, and none of the host's lifecycle fields.
  if v_is_tenant and not v_is_owner then
    if new.host_message      is distinct from old.host_message
       or new.rejection_reason is distinct from old.rejection_reason
       or new.confirmed_at     is distinct from old.confirmed_at
       or new.actual_check_in  is distinct from old.actual_check_in
       or new.completed_at     is distinct from old.completed_at then
      raise exception 'Only the host writes the host''s side of a booking'
        using errcode = '42501', hint = 'host_columns_protected';
    end if;
    if new.booking_status is distinct from old.booking_status then
      if new.booking_status <> 'cancelled' then
        raise exception
          'Guests may only cancel a booking (attempted % -> %)',
          old.booking_status, new.booking_status
          using errcode = '42501', hint = 'booking_transition_forbidden';
      end if;
      if old.booking_status not in ('pending', 'confirmed') then
        raise exception 'Cannot cancel a booking in % state', old.booking_status
          using errcode = '42501', hint = 'booking_transition_forbidden';
      end if;
    end if;
    return new;
  end if;

  -- Host (listing owner) drives accept/reject/check-in/complete/cancel/no-show
  -- — forwards only. This is BookingLifecycleService's table, now enforced:
  --   pending   -> confirmed | rejected | cancelled
  --   confirmed -> active | completed | cancelled | no_show
  --   active    -> completed | cancelled
  -- completed, rejected, cancelled and no_show are terminal. A host who needs
  -- to undo a wrong tap asks the guest to book again; a host who could re-open
  -- a cancelled booking could re-block a guest's calendar and re-post the
  -- earning the guest already walked away from. `confirmed -> completed` stays
  -- allowed because auto_complete_elapsed_bookings takes exactly that step for
  -- a guest who never tapped check-in, and a host finalising by hand is the
  -- same fact.
  if v_is_owner then
    if new.booking_status is distinct from old.booking_status then
      if old.booking_status = 'confirmed' and new.booking_status = 'no_show' then
        if now() < old.starts_at then
          raise exception 'A no-show can only be reported after check-in time (%)',
            old.starts_at
            using errcode = '42501', hint = 'no_show_too_early';
        end if;
      elsif not (
           (old.booking_status = 'pending'
              and new.booking_status in ('confirmed', 'rejected', 'cancelled'))
        or (old.booking_status = 'confirmed'
              and new.booking_status in ('active', 'completed', 'cancelled'))
        or (old.booking_status = 'active'
              and new.booking_status in ('completed', 'cancelled'))
      ) then
        raise exception 'A booking cannot go from % to %',
          old.booking_status, new.booking_status
          using errcode = '42501', hint = 'booking_transition_forbidden';
      end if;
    end if;
    return new;
  end if;

  -- Not tenant, owner, or admin — RLS should already have blocked this.
  raise exception 'Not authorized to update this booking';
end;
$$;

-- The lifecycle notifier learns the new transition. Everything else in it is
-- unchanged; it is recreated in full because it is one CASE.
create or replace function public.notify_on_booking_lifecycle()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
DECLARE
    listing_record RECORD;
    guest_record RECORD;
    notification_title text;
    notification_body text;
    notification_type text;
    notification_priority text;
    target_user_id uuid;
    action_url text;
BEGIN
    SELECT l.title, l.owner_id INTO listing_record
    FROM public.listings l
    WHERE l.id = NEW.listing_id;

    SELECT p.full_name INTO guest_record
    FROM public.profiles p
    WHERE p.id = NEW.tenant_id;

    CASE
        WHEN TG_OP = 'INSERT' AND NEW.booking_status = 'pending' THEN
            notification_title := 'New Booking Request';
            notification_body := format('%s wants to book %s',
                COALESCE(guest_record.full_name, 'A guest'),
                COALESCE(listing_record.title, 'your property'));
            notification_type := 'booking_request';
            notification_priority := 'high';
            target_user_id := listing_record.owner_id;
            action_url := '/host/reservations/' || NEW.id;

        WHEN TG_OP = 'UPDATE' AND OLD.booking_status = 'pending' AND NEW.booking_status = 'confirmed' THEN
            notification_title := 'Booking Confirmed!';
            notification_body := format('Your booking at %s has been confirmed',
                COALESCE(listing_record.title, 'the property'));
            notification_type := 'booking_confirmed';
            notification_priority := 'high';
            target_user_id := NEW.tenant_id;
            action_url := '/trips/' || NEW.id;

        WHEN TG_OP = 'UPDATE' AND OLD.booking_status = 'pending' AND NEW.booking_status = 'rejected' THEN
            notification_title := 'Booking Declined';
            notification_body := CASE
                WHEN NEW.rejection_reason IS NOT NULL THEN
                    format('Your booking was declined: %s', NEW.rejection_reason)
                ELSE
                    format('Your booking at %s was declined', COALESCE(listing_record.title, 'the property'))
            END;
            notification_type := 'booking_rejected';
            notification_priority := 'normal';
            target_user_id := NEW.tenant_id;
            action_url := '/trips/' || NEW.id;

        WHEN TG_OP = 'UPDATE' AND OLD.booking_status = 'confirmed' AND NEW.booking_status = 'active' THEN
            notification_title := 'Enjoy Your Stay!';
            notification_body := format('You are now checked in at %s',
                COALESCE(listing_record.title, 'the property'));
            notification_type := 'checked_in';
            notification_priority := 'normal';
            target_user_id := NEW.tenant_id;
            action_url := '/trips/' || NEW.id;

        WHEN TG_OP = 'UPDATE' AND OLD.booking_status = 'active' AND NEW.booking_status = 'completed' THEN
            notification_title := 'How Was Your Stay?';
            notification_body := format('Your stay at %s is complete. Leave a review!',
                COALESCE(listing_record.title, 'the property'));
            notification_type := 'review_prompt';
            notification_priority := 'normal';
            target_user_id := NEW.tenant_id;
            action_url := '/review/' || NEW.id || '/guest';

            INSERT INTO public.notifications (
                user_id, type, title, body, priority, action_url, data
            ) VALUES (
                target_user_id,
                notification_type::notification_type,
                notification_title,
                notification_body,
                notification_priority::notification_priority,
                action_url,
                jsonb_build_object(
                    'booking_id', NEW.id,
                    'listing_id', NEW.listing_id,
                    'listing_title', listing_record.title
                )
            );

            notification_title := 'Leave a Guest Review';
            notification_body := format('Your guest %s has checked out. Leave a review!',
                COALESCE(guest_record.full_name, 'your guest'));
            target_user_id := listing_record.owner_id;
            action_url := '/review/' || NEW.id || '/host';

        -- 140: the host reported that the guest never arrived. The guest is
        -- told in plain words; there is no review window and (see the refund
        -- policy) nothing comes back, which fn_alert_paid_cancellation says
        -- separately when the booking was paid.
        WHEN TG_OP = 'UPDATE' AND OLD.booking_status = 'confirmed' AND NEW.booking_status = 'no_show' THEN
            notification_title := 'Marked as a no-show';
            notification_body := format('The host reported that you did not arrive for your booking at %s. If that is wrong, reply to the host from Messages.',
                COALESCE(listing_record.title, 'the property'));
            notification_type := 'booking_cancelled';
            notification_priority := 'high';
            target_user_id := NEW.tenant_id;
            action_url := '/trips/' || NEW.id;

        WHEN TG_OP = 'UPDATE' AND NEW.booking_status = 'cancelled' AND NEW.cancelled_by = NEW.tenant_id THEN
            notification_title := 'Booking Cancelled';
            notification_body := format('%s cancelled their booking at %s',
                COALESCE(guest_record.full_name, 'A guest'),
                COALESCE(listing_record.title, 'your property'));
            notification_type := 'booking_cancelled';
            notification_priority := 'high';
            target_user_id := listing_record.owner_id;
            action_url := '/host/reservations/' || NEW.id;

        WHEN TG_OP = 'UPDATE' AND NEW.booking_status = 'cancelled' AND NEW.cancelled_by != NEW.tenant_id THEN
            notification_title := 'Booking Cancelled by Host';
            notification_body := format('Your booking at %s was cancelled by the host',
                COALESCE(listing_record.title, 'the property'));
            notification_type := 'booking_cancelled';
            notification_priority := 'high';
            target_user_id := NEW.tenant_id;
            action_url := '/trips/' || NEW.id;

        ELSE
            RETURN NEW;
    END CASE;

    INSERT INTO public.notifications (
        user_id, type, title, body, priority, action_url, data
    ) VALUES (
        target_user_id,
        notification_type::notification_type,
        notification_title,
        notification_body,
        notification_priority::notification_priority,
        action_url,
        jsonb_build_object(
            'booking_id', NEW.id,
            'listing_id', NEW.listing_id,
            'tenant_id', NEW.tenant_id,
            'listing_title', listing_record.title,
            'guest_name', guest_record.full_name,
            'check_in', NEW.starts_at,
            'check_out', NEW.ends_at,
            'total_price', NEW.total_price
        )
    );

    RETURN NEW;
END;
$$;


-- ============================================================ 3. suspension
--
-- Until now the console could hide a fraudulent account's listings and change
-- its role, and the account kept logging in, messaging and booking. This is
-- the missing verb. Three parts, and only the last one is enforcement:
--
--   * two columns on profiles (plus who did it), frozen for the account itself
--   * `admin_suspend_user`, which also DELETES the account's auth sessions —
--     the same move revoke_device makes, for the same reason: revoked_at is
--     bookkeeping a client can ignore, a deleted refresh token is not
--   * a guard on every write path a still-valid access token could reach in
--     the hour before it expires: bookings (RPC and trigger), conversations,
--     messages, listings, reviews, and the login itself (verify-otp)
--
-- A suspended host's listings are hidden and remembered, so lifting the
-- suspension puts back exactly the ones it took down and no others.

alter table public.profiles
  add column if not exists suspended_at     timestamptz,
  add column if not exists suspended_reason text,
  add column if not exists suspended_by     uuid references public.profiles(id) on delete set null;

alter table public.listings
  add column if not exists suspended_hidden boolean not null default false;

create or replace function public.fn_is_suspended(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select p_user_id is not null and exists (
    select 1 from public.profiles p where p.id = p_user_id and p.suspended_at is not null
  );
$$;
-- Called from SECURITY DEFINER triggers and RPCs only; a client learns it is
-- suspended from the refusal, or from its own profile row.
revoke all on function public.fn_is_suspended(uuid) from public, anon, authenticated;

-- The account cannot un-suspend itself through its own profile row. Same
-- shape as fn_guard_verification_verdicts (133): the profiles UPDATE policy
-- has no WITH CHECK, so a trigger is the only guard on any column.
create or replace function public.fn_guard_suspension_columns()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if new.suspended_at     is distinct from old.suspended_at
     or new.suspended_reason is distinct from old.suspended_reason
     or new.suspended_by     is distinct from old.suspended_by then
    raise exception 'suspension is set by an admin, not by the account'
      using errcode = '42501', hint = 'suspension_columns_protected';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_suspension_columns on public.profiles;
create trigger trg_guard_suspension_columns
  before update on public.profiles
  for each row execute function public.fn_guard_suspension_columns();

-- One trigger function for every table a suspended account might still write.
-- Automated writers (null uid) and admins pass; everyone else is checked.
create or replace function public.fn_refuse_suspended_writer()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is not null
     and public.fn_is_suspended(v_uid)
     and not public.is_admin(v_uid) then
    raise exception 'This account is suspended'
      using errcode = '42501', hint = 'account_suspended';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_refuse_suspended_writer on public.messages;
create trigger trg_refuse_suspended_writer
  before insert or update on public.messages
  for each row execute function public.fn_refuse_suspended_writer();

drop trigger if exists trg_refuse_suspended_writer on public.conversations;
create trigger trg_refuse_suspended_writer
  before insert or update on public.conversations
  for each row execute function public.fn_refuse_suspended_writer();

drop trigger if exists trg_refuse_suspended_writer on public.listings;
create trigger trg_refuse_suspended_writer
  before insert or update on public.listings
  for each row execute function public.fn_refuse_suspended_writer();

drop trigger if exists trg_refuse_suspended_writer on public.reviews;
create trigger trg_refuse_suspended_writer
  before insert or update on public.reviews
  for each row execute function public.fn_refuse_suspended_writer();

-- bookings UPDATE is covered inside enforce_booking_update_rules (above);
-- bookings INSERT only happens through create_marketplace_booking (071), which
-- checks both parties below.

-- The booking RPC: neither a suspended guest nor a suspended host's listing.
-- Patched by textual replacement of the 138 block-check, so the rest of the
-- 260-line function is untouched.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.create_marketplace_booking'::regproc) into v_def;
  if position('account_suspended' in v_def) = 0 then
    v_def := replace(v_def,
      $old$  if public.fn_users_blocked(v_uid, v_listing.owner_id) then$old$,
      $new$  -- 140: a suspended account keeps its access token for up to an hour.
  if public.fn_is_suspended(v_uid) then
    raise exception 'This account is suspended'
      using errcode = '42501', hint = 'account_suspended';
  end if;
  -- And a suspended host's listings are hidden, but a deep link or a stale
  -- client can still name one.
  if public.fn_is_suspended(v_listing.owner_id) then
    raise exception 'This listing is no longer available' using errcode = '22023';
  end if;

  if public.fn_users_blocked(v_uid, v_listing.owner_id) then$new$);
    if position('account_suspended' in v_def) = 0 then
      raise exception '140: create_marketplace_booking did not contain the 138 block check to patch';
    end if;
    execute v_def;
  end if;
end $$;

-- The thread RPC: a real caller who is suspended, or who is trying to reach a
-- suspended account, gets no thread. Automated senders (null uid) still do —
-- a checkout message to a guest whose host was suspended mid-stay is still
-- owed to the guest.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.get_or_create_conversation'::regproc) into v_def;
  if position('account_suspended' in v_def) = 0 then
    v_def := replace(v_def,
      $old$  if auth.uid() is not null and public.fn_users_blocked(user_one, user_two) then$old$,
      $new$  if auth.uid() is not null
     and (public.fn_is_suspended(user_one) or public.fn_is_suspended(user_two)) then
    raise exception 'This account is suspended'
      using errcode = '42501', hint = 'account_suspended';
  end if;

  if auth.uid() is not null and public.fn_users_blocked(user_one, user_two) then$new$);
    if position('account_suspended' in v_def) = 0 then
      raise exception '140: get_or_create_conversation did not contain the 138 block check to patch';
    end if;
    execute v_def;
  end if;
end $$;

-- The session watcher asks touch_device on every resume. A suspended
-- account is told "revoked" so the app signs itself out at once, rather than
-- showing a working screen whose every write fails for the next hour.
create or replace function public.touch_device(p_device_id text)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'auth'
as $$
declare
  v_user uuid := auth.uid();
  v_revoked timestamptz;
  v_found boolean;
begin
  if v_user is null then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  if public.fn_is_suspended(v_user) then
    return true;
  end if;

  update public.user_devices
     set last_seen_at = now(),
         last_ip = coalesce(inet_client_addr(), last_ip)
   where user_id = v_user
     and device_id = p_device_id
     and revoked_at is null
  returning revoked_at into v_revoked;

  get diagnostics v_found = row_count;

  -- An unknown device id is not "revoked": it is a device that has never
  -- registered, or one whose row was cascaded away with a deleted account.
  -- Answering true would sign out a perfectly good session.
  if not v_found then
    return exists (
      select 1 from public.user_devices
       where user_id = v_user
         and device_id = p_device_id
         and revoked_at is not null
    );
  end if;

  return false;
end;
$$;

-- Service-role only, like every admin_*: an admin's own JWT is deliberately
-- not enough to end another person's access to their account.
create or replace function public.admin_suspend_user(
  p_user_id uuid,
  p_reason  text,
  p_actor   uuid default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'auth'
as $$
declare
  v_role     text;
  v_already  timestamptz;
  v_sessions integer := 0;
  v_listings integer := 0;
  v_declined integer := 0;
  v_own      integer := 0;
begin
  perform public.fn_require_service_role();

  select role, suspended_at into v_role, v_already
    from public.profiles where id = p_user_id for update;
  if v_role is null then
    raise exception 'User not found' using errcode = 'P0002';
  end if;
  -- An admin is suspended by taking the role away first; doing both in one
  -- move from a text box is how a console loses its last admin.
  if v_role = 'admin' then
    raise exception 'Change this account''s role before suspending it'
      using errcode = '42501';
  end if;
  if v_already is not null then
    return jsonb_build_object('already_suspended', true, 'suspended_at', v_already);
  end if;
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'A reason is required' using errcode = '22023';
  end if;

  update public.profiles
     set suspended_at = now(), suspended_reason = btrim(p_reason), suspended_by = p_actor
   where id = p_user_id;

  -- The enforcement. postgres holds DELETE on auth.sessions (124, proven by
  -- doing it); every device dies at its next token refresh.
  delete from auth.sessions where user_id = p_user_id;
  get diagnostics v_sessions = row_count;

  -- No more pushes to a phone that can no longer act on them.
  update public.fcm_tokens set is_active = false
   where user_id = p_user_id and is_active;

  -- A suspended host's live listings come down, and are marked so
  -- admin_unsuspend_user can put back exactly these.
  update public.listings
     set is_active = false, suspended_hidden = true
   where owner_id = p_user_id and is_active;
  get diagnostics v_listings = row_count;

  -- Requests waiting on this host would otherwise sit until the sweep expires
  -- them; the guests are told now, through the normal "declined" path.
  update public.bookings b
     set booking_status = 'rejected',
         rejection_reason = 'The host''s account is no longer active'
   where b.booking_status = 'pending'
     and exists (select 1 from public.listings l
                  where l.id = b.listing_id and l.owner_id = p_user_id);
  get diagnostics v_declined = row_count;

  -- And this account's own open requests as a guest are withdrawn. Named as
  -- the guest's own cancellation so the host is told the way they would be
  -- for any other withdrawn request.
  update public.bookings
     set booking_status = 'cancelled', cancelled_by = p_user_id, cancelled_at = now()
   where tenant_id = p_user_id and booking_status = 'pending';
  get diagnostics v_own = row_count;

  return jsonb_build_object(
    'suspended_at', now(),
    'sessions_ended', v_sessions,
    'listings_hidden', v_listings,
    'requests_declined', v_declined,
    'own_requests_withdrawn', v_own);
end;
$$;
revoke all on function public.admin_suspend_user(uuid, text, uuid) from public, anon, authenticated;

create or replace function public.admin_unsuspend_user(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_already timestamptz;
  v_listings integer := 0;
begin
  perform public.fn_require_service_role();

  select suspended_at into v_already
    from public.profiles where id = p_user_id for update;
  if not found then
    raise exception 'User not found' using errcode = 'P0002';
  end if;
  if v_already is null then
    return jsonb_build_object('was_suspended', false);
  end if;

  update public.profiles
     set suspended_at = null, suspended_reason = null, suspended_by = null
   where id = p_user_id;

  update public.listings
     set is_active = true, suspended_hidden = false
   where owner_id = p_user_id and suspended_hidden;
  get diagnostics v_listings = row_count;

  return jsonb_build_object('was_suspended', true, 'listings_restored', v_listings);
end;
$$;
revoke all on function public.admin_unsuspend_user(uuid) from public, anon, authenticated;


-- ============================================================ 4. rate limits
--
-- geocode, places-search, google-directions and voice-parse run behind
-- verify_jwt, which accepts the anon key compiled into build/web. None of
-- them checked for a user, and signed-out search legitimately needs
-- places-search, so the fix is a counter, not a login gate. The counter lives
-- here rather than in the function's memory because there are many edge
-- runtimes and one database.
--
-- Fixed windows: the bucket is (key, window start), and the key is the
-- caller's user id when signed in and their IP when not. A hit past the limit
-- is still counted, so a client that keeps hammering keeps getting 429.

create table if not exists public.edge_rate_limits (
  bucket       text        not null,
  window_start timestamptz not null,
  hits         integer     not null default 0,
  primary key (bucket, window_start)
);
alter table public.edge_rate_limits enable row level security;
-- No policies: only the service role (which bypasses RLS) ever touches it.
revoke all on table public.edge_rate_limits from public, anon, authenticated;

create or replace function public.fn_rate_limit_hit(
  p_bucket         text,
  p_limit          integer,
  p_window_seconds integer
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_start timestamptz;
  v_hits  integer;
begin
  perform public.fn_require_service_role();
  if p_limit < 1 or p_window_seconds < 1 or coalesce(btrim(p_bucket), '') = '' then
    raise exception 'fn_rate_limit_hit: bad arguments' using errcode = '22023';
  end if;

  v_start := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);

  insert into public.edge_rate_limits (bucket, window_start, hits)
  values (p_bucket, v_start, 1)
  on conflict (bucket, window_start) do update set hits = edge_rate_limits.hits + 1
  returning hits into v_hits;

  return jsonb_build_object(
    'allowed', v_hits <= p_limit,
    'hits', v_hits,
    'limit', p_limit,
    'retry_after_seconds',
      greatest(1, ceil(extract(epoch from (v_start + make_interval(secs => p_window_seconds) - now())))::integer));
end;
$$;
revoke all on function public.fn_rate_limit_hit(text, integer, integer) from public, anon, authenticated;

-- Windows are a minute wide; anything older than a day is noise.
create or replace function public.reap_edge_rate_limits()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare n integer;
begin
  delete from public.edge_rate_limits where window_start < now() - interval '1 day';
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.reap_edge_rate_limits() from public, anon, authenticated;

do $$
begin
  perform cron.schedule(
    'reap-edge-rate-limits',
    '41 3 * * *',
    'SELECT public.reap_edge_rate_limits()'
  );
exception when others then
  raise notice 'pg_cron not available; reap_edge_rate_limits must be run manually';
end $$;
