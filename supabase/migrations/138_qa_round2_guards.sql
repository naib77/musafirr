-- =============================================
-- 138 — what the second QA round found (2026-09-19)
--
-- Sixty scenarios were driven against the local mirror as 80 guests,
-- 50 hosts and one admin would drive the app; twenty-eight failed, and
-- docs/qa/REPORT_ROUND2_2026-09-19.md is the record. This file closes
-- everything that lives in the database.
-- Each section names the scenario that found it. Every fix below is pinned by
-- supabase/tests/138_qa_round2_test.sql, which goes red with this file
-- reverted.
--
-- The recurring lesson is the one CLAUDE.md already states four times over:
-- "the client checks it" is not a rule. Every hole here was a rule that
-- existed only in Dart — the booking state machine, the block list, the
-- review reveal, the conversation membership, the listing's star rating.
-- =============================================


-- ============================================================ helpers

-- Are these two people separated by a block, in either direction?
-- SECURITY DEFINER because user_blocks' SELECT policy only shows a row to the
-- two people on it, and the callers below ask on behalf of one of them from
-- inside a trigger. Revoked from every client role: "did X block Y" is not a
-- question a stranger gets to ask.
create or replace function public.fn_users_blocked(p_a uuid, p_b uuid)
returns boolean
language sql stable security definer
set search_path to 'public'
as $$
  select p_a is not null and p_b is not null and exists (
    select 1 from public.user_blocks ub
    where (ub.blocker_id = p_a and ub.blocked_id = p_b)
       or (ub.blocker_id = p_b and ub.blocked_id = p_a)
  );
$$;
revoke all on function public.fn_users_blocked(uuid, uuid) from public, anon, authenticated;

-- The phone number an account actually logged in with: verify-otp mints the
-- identity `phone.<number>@musaafir.app`, so the number is in auth.users and
-- cannot be edited from the app. profiles.mobile CAN be (measured: a guest
-- set it to a host's number and took the host's name), and it was what
-- get_booking_contacts and the "📞 Contact details" message handed to the
-- other party. Same derivation admin_sms_audience (128) already uses.
-- Null for an email-only account (the console admins), so callers fall back.
create or replace function public.fn_identity_phone(p_user_id uuid)
returns text
language sql stable security definer
set search_path to 'public', 'auth'
as $$
  select public.fn_canonical_bd_phone(
           substring(u.email from '^phone\.([0-9]+)@musaafir\.app$'))
  from auth.users u
  where u.id = p_user_id;
$$;
revoke all on function public.fn_identity_phone(uuid) from public, anon, authenticated;


-- ============================================================ bookings
-- Scenarios 14–19, 23, 31. The host side of enforce_booking_update_rules was
-- `if v_is_owner then return new; end if;` — the whole state machine lived in
-- BookingLifecycleService (Dart). Measured: a host set a guest-cancelled
-- booking back to confirmed (the accept-after-cancel race does this by
-- accident: the guest's cancel and the host's accept are two PATCHes and the
-- last one wins), moved a booking confirmed -> completed skipping check-in,
-- and a guest rewrote guest_count to 50, the listing title to anything, the
-- discount to 9999, and set cancelled_by to the HOST's id — at which point the
-- lifecycle trigger told the guest "Cancelled by host" and told the host
-- nothing at all. A plain `{booking_status: cancelled}` from the guest (the
-- repository's fallback path) also notified nobody, because the notification
-- CASE keys on cancelled_by and it was null.
create or replace function public.enforce_booking_update_rules()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
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

  -- 138: and neither does anything else create_marketplace_booking decided.
  -- guest_count is the capacity the host agreed to; unit_count and
  -- pricing_unit are what total_price was computed from; the coupon columns
  -- are what the ledger and the coupon's usage count rest on; the listing_*
  -- and tenant_name copies are what the OTHER party's screens display.
  if new.guest_count       is distinct from old.guest_count
     or new.unit_count        is distinct from old.unit_count
     or new.pricing_unit      is distinct from old.pricing_unit
     or new.coupon_code       is distinct from old.coupon_code
     or new.discount_amount   is distinct from old.discount_amount
     or new.listing_title     is distinct from old.listing_title
     or new.listing_image_url is distinct from old.listing_image_url
     or new.listing_city      is distinct from old.listing_city
     or new.tenant_name       is distinct from old.tenant_name
     or new.created_at        is distinct from old.created_at then
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
          old.booking_status, new.booking_status;
      end if;
      if old.booking_status not in ('pending', 'confirmed') then
        raise exception 'Cannot cancel a booking in % state', old.booking_status;
      end if;
    end if;
    return new;
  end if;

  -- Host (listing owner) drives accept/reject/check-in/complete/cancel —
  -- forwards only. This is BookingLifecycleService's table, now enforced:
  --   pending   -> confirmed | rejected | cancelled
  --   confirmed -> active | completed | cancelled
  --   active    -> completed | cancelled
  -- completed, rejected and cancelled are terminal. A host who needs to undo
  -- a wrong tap asks the guest to book again; a host who could re-open a
  -- cancelled booking could re-block a guest's calendar and re-post the
  -- earning the guest already walked away from. `confirmed -> completed` stays
  -- allowed because auto_complete_elapsed_bookings takes exactly that step for
  -- a guest who never tapped check-in, and a host finalising by hand is the
  -- same fact.
  if v_is_owner then
    if new.booking_status is distinct from old.booking_status then
      if not (
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
$function$;

-- Scenario 20. A host who cancels a PAID booking (or a guest who cancels one
-- the host already accepted and they already paid) leaves ৳ sitting on the
-- platform's side with the host's earning still posted in the ledger and
-- nobody told. There is no automatic refund — the money goes back through a
-- guest_refund disbursement on the console's Payouts screen — so the least
-- the database can do is put it on someone's desk: every admin gets an
-- alert, and the guest is told what happens next rather than seeing a "Paid"
-- pill on a cancelled trip and wondering.
create or replace function public.fn_alert_paid_cancellation()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_title text;
  v_admin uuid;
begin
  if not (new.booking_status = 'cancelled'
          and old.booking_status <> 'cancelled'
          and new.payment_status = 'paid') then
    return null;
  end if;

  v_title := coalesce(new.listing_title,
                      (select l.title from public.listings l where l.id = new.listing_id),
                      'a booking');

  for v_admin in select p.id from public.profiles p where p.role = 'admin' loop
    insert into public.notifications (user_id, type, title, body, priority, action_url, data)
    values (
      v_admin, 'system_alert', 'Refund due',
      format('%s cancelled a paid booking at %s (৳%s). Arrange the guest''s refund from Payouts and mark the booking refunded.',
             case when new.cancelled_by = new.tenant_id then 'The guest' else 'The host' end,
             v_title, trim(to_char(new.total_price, 'FM999999990.00'))),
      'high', '/bookings/' || new.id,
      jsonb_build_object('booking_id', new.id, 'reason', 'paid_cancellation',
                         'amount', new.total_price, 'cancelled_by', new.cancelled_by)
    );
  end loop;

  if new.tenant_id is not null then
    insert into public.notifications (user_id, type, title, body, priority, action_url, data)
    values (
      new.tenant_id, 'system_alert', 'Your refund is being arranged',
      format('Your booking at %s was cancelled after you paid ৳%s. Our team will refund you and be in touch.',
             v_title, trim(to_char(new.total_price, 'FM999999990.00'))),
      'high', '/trips/' || new.id,
      jsonb_build_object('booking_id', new.id, 'reason', 'paid_cancellation',
                         'amount', new.total_price)
    );
  end if;
  return null;
end $$;
revoke all on function public.fn_alert_paid_cancellation() from public, anon, authenticated;

drop trigger if exists trg_alert_paid_cancellation on public.bookings;
create trigger trg_alert_paid_cancellation
  after update of booking_status on public.bookings
  for each row execute function public.fn_alert_paid_cancellation();

-- Scenario 12. A blocked guest could still book the host who blocked them.
CREATE OR REPLACE FUNCTION public.create_marketplace_booking(p_listing_id uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_pricing_unit text, p_guest_count integer, p_tenant_name text DEFAULT NULL::text, p_coupon_code text DEFAULT NULL::text, p_listing_image_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid        uuid := auth.uid();
  v_listing    public.listings%rowtype;
  v_rate       numeric;
  v_qty        int;
  v_min        int;
  v_max        int;
  v_unit_word  text;
  v_gross      numeric;
  v_discount   numeric := 0;
  v_coupon_id  uuid;
  v_total      numeric;
  v_res        jsonb;
  v_booking    public.bookings%rowtype;
begin
  if v_uid is null then
    raise exception 'You must be signed in to book' using errcode = '42501';
  end if;

  -- Identity verification (114). Until now this lived ONLY in the Flutter
  -- client -- IdentityGate.ensure, called from the Reserve button -- and this
  -- function never looked at it. Live has 8 bookings from guests whose
  -- verification_status is 'none', so that gate demonstrably leaked even
  -- before Explore went public; a public browse page makes the RPC reachable
  -- by anyone holding the publishable anon key.
  --
  -- Reads the column directly rather than trusting a client claim. 095's
  -- trg_guard_verification_verdicts already stops a non-admin awarding
  -- themselves 'verified', so this check cannot be defeated by a PostgREST
  -- write to one's own profile -- the two halves only work together.
  --
  -- The hint is how the client tells this apart from an availability
  -- conflict. Never match on the message prose: that is the mistake
  -- bookingConflictTypeFrom was rewritten to stop making.
  if (select verification_status from public.profiles where id = v_uid)
     is distinct from 'verified' then
    raise exception 'Your identity must be verified before you can book'
      using errcode = '42501', hint = 'identity_unverified';
  end if;

  -- Reserved interval must be forward-in-time.
  if p_ends_at is null or p_starts_at is null or p_ends_at <= p_starts_at then
    raise exception 'Invalid booking dates' using errcode = '22023';
  end if;

  -- 135: and it must not be in the past. Measured: a stay starting ten days
  -- ago was accepted and returned an id. Past slots are always "free", so the
  -- availability checks below never object, and `expire_stale_bookings` /
  -- the auto-complete sweep then walk the row straight to completed — which
  -- is a review prompt and a ledger entry for a stay nobody had.
  --
  -- The calendar already hides past dates. That is the "the booking form
  -- checks it" pattern this codebase has been bitten by four times: the form
  -- is skippable and the RPC is a public endpoint.
  --
  -- One hour of slack rather than a hard `>= now()`, because a guest booking
  -- a turf for *this* hour is the normal case for hourly listings, the
  -- client's clock is its own, and `now()` here is transaction time. The
  -- guard exists to stop last month, not to police the last minute.
  if p_starts_at < now() - interval '1 hour' then
    raise exception 'Choose a start time in the future'
      using errcode = '22023', hint = 'starts_in_past';
  end if;

  -- Load the listing. Must exist and be active.
  select * into v_listing from public.listings where id = p_listing_id;
  if not found then
    raise exception 'Listing not found' using errcode = 'P0002';
  end if;
  if not coalesce(v_listing.is_active, true) then
    raise exception 'This listing is no longer available' using errcode = '22023';
  end if;

  -- 135: a host must not book their own listing. Nothing checked this, and
  -- live already holds one such booking. Two things go wrong when it is
  -- allowed: the ledger posts the owner an earning against money that only
  -- moved between their own two pockets (or did not move at all, on the cash
  -- path), and a host can black out their own calendar through the booking
  -- path instead of listing_availability_blocks (110), which is the feature
  -- built for exactly that and the only one the host's own UI can undo.
  if v_listing.owner_id = v_uid then
    raise exception 'You cannot book your own listing'
      using errcode = '42501', hint = 'self_booking';
  end if;

  -- 138: a block is a wall, not a filter. `user_blocks` (SAFETY.md) only ever
  -- hid the other party's listings and threads in the CLIENT; measured
  -- 2026-09-19, a guest a host had blocked booked that host's listing and
  -- opened a conversation with them without a hitch. Either direction counts:
  -- a host who blocked a guest does not want their money, and a guest who
  -- blocked a host does not want to stay there.
  if public.fn_users_blocked(v_uid, v_listing.owner_id) then
    raise exception 'You cannot book this listing'
      using errcode = '42501', hint = 'blocked';
  end if;

  -- The host-wide Away switch (038). Only ever a search filter before this, so
  -- a guest who already had the page open could book straight past it.
  if not coalesce(v_listing.host_available, true) then
    raise exception 'This host isn''t accepting new bookings right now'
      using errcode = '22023';
  end if;

  -- Guest count within the listing's capacity.
  if p_guest_count is null or p_guest_count < 1 then
    raise exception 'At least one guest is required' using errcode = '22023';
  end if;
  if v_listing.max_guests is not null and p_guest_count > v_listing.max_guests then
    raise exception 'This place hosts up to % guests', v_listing.max_guests
      using errcode = '22023';
  end if;

  -- Server-side rate + quantity. Quantity is derived from the reserved interval
  -- so the client can't understate it; hour/day are exact epoch multiples,
  -- month is a calendar diff (monthly stays are booked whole-month, same day).
  -- The per-plan duration limits (055) are read here too, so the unit, the
  -- quantity and the bounds they are compared against always come from the same
  -- branch and cannot drift apart.
  case p_pricing_unit
    when 'hour' then
      v_rate := v_listing.hourly_rate;
      v_qty  := round(extract(epoch from (p_ends_at - p_starts_at)) / 3600.0);
      v_min  := v_listing.min_hours;
      v_max  := v_listing.max_hours;
      v_unit_word := 'hour';
    when 'day' then
      v_rate := v_listing.daily_rate;
      v_qty  := round(extract(epoch from (p_ends_at - p_starts_at)) / 86400.0);
      v_min  := v_listing.min_nights;
      v_max  := v_listing.max_nights;
      -- 'night', not 'day' — matches the word the booking form uses, so the
      -- guest doesn't get two different names for one number.
      v_unit_word := 'night';
    when 'month' then
      v_rate := v_listing.monthly_rate;
      v_qty  := (extract(year from p_ends_at) - extract(year from p_starts_at))::int * 12
              + (extract(month from p_ends_at) - extract(month from p_starts_at))::int;
      v_min  := v_listing.min_months;
      v_max  := v_listing.max_months;
      v_unit_word := 'month';
    else
      raise exception 'Unsupported booking type: %', p_pricing_unit using errcode = '22023';
  end case;

  if v_rate is null then
    raise exception 'This listing is not available for % bookings', p_pricing_unit
      using errcode = '22023';
  end if;
  if v_qty is null or v_qty < 1 then
    raise exception 'Booking must be at least one %', p_pricing_unit using errcode = '22023';
  end if;

  -- The host's per-plan minimum/maximum (055). `coalesce(v_min, 1)` mirrors
  -- BookingLimits.minFor's `?? 1` in lib/models/listing.dart — if those two ever
  -- disagree, the form and the server disagree about the floor and the guest
  -- gets refused for something the UI let them pick.
  if v_qty < coalesce(v_min, 1) then
    raise exception 'Minimum booking is % %', coalesce(v_min, 1),
      v_unit_word || case when coalesce(v_min, 1) = 1 then '' else 's' end
      using errcode = '22023';
  end if;
  if v_max is not null and v_qty > v_max then
    raise exception 'Maximum booking is % %', v_max,
      v_unit_word || case when v_max = 1 then '' else 's' end
      using errcode = '22023';
  end if;

  v_gross := round(v_rate * v_qty, 2);

  -- Conflict checks (authoritative backstop for the client's pre-flight checks;
  -- also catches races). Blocking statuses match BookingStatus.isActive. The
  -- `hint` is what the Dart layer reads to choose between the two guest-facing
  -- sentences; it used to grep this message for the words 'already have a
  -- booking', which meant rewording the line below silently changed the UI.
  if exists (
    select 1 from public.bookings b
    where b.listing_id = p_listing_id
      and b.booking_status in ('pending', 'confirmed', 'active')
      and p_starts_at < b.ends_at
      and b.starts_at < p_ends_at
  ) then
    raise exception 'This time slot is already booked'
      using errcode = '23P01', hint = 'listing_overlap';
  end if;

  -- Same user can't hold two overlapping bookings. Now backed by
  -- bookings_no_tenant_overlap, so losing the race here fails at COMMIT rather
  -- than slipping through.
  if exists (
    select 1 from public.bookings b
    where b.tenant_id = v_uid
      and b.booking_status in ('pending', 'confirmed', 'active')
      and p_starts_at < b.ends_at
      and b.starts_at < p_ends_at
  ) then
    raise exception 'You already have a booking during this time'
      using errcode = '23P01', hint = 'tenant_overlap';
  end if;

  -- Host-declared blocked dates (110). A block is not a bookings row, so no
  -- single exclusion constraint can cover both tables; a host blocking dates in
  -- the same millisecond a guest commits can lose this check. That window is
  -- accepted deliberately — the cost is one booking the host declines by hand,
  -- and the alternative (storing blocks AS bookings rows under a sentinel
  -- status) would drag them through earnings, commission, payouts and the host
  -- reservations list.
  if exists (
    select 1 from public.listing_availability_blocks blk
    where blk.listing_id = p_listing_id
      and tstzrange(blk.starts_at, blk.ends_at, '[)')
          && tstzrange(p_starts_at, p_ends_at, '[)')
  ) then
    raise exception 'The host has blocked these dates' using errcode = '22023';
  end if;

  -- Coupon (optional). Reuse the authoritative validator against the SERVER
  -- gross, so the discount can't be inflated against a fake amount either.
  if p_coupon_code is not null and length(trim(p_coupon_code)) > 0 then
    v_res := public.validate_coupon(p_coupon_code, v_gross);
    if (v_res->>'valid')::boolean is not true then
      raise exception '%', coalesce(v_res->>'message', 'Invalid coupon')
        using errcode = '22023';
    end if;
    v_discount  := coalesce((v_res->>'discount_amount')::numeric, 0);
    v_coupon_id := (v_res->>'coupon_id')::uuid;
  end if;

  v_total := greatest(v_gross - v_discount, 0);

  insert into public.bookings (
    listing_id, tenant_id, tenant_name,
    starts_at, ends_at, pricing_unit, unit_count,
    total_price, guest_count, booking_status,
    listing_title, listing_image_url, listing_city,
    coupon_code, discount_amount
  ) values (
    p_listing_id, v_uid, coalesce(p_tenant_name, ''),
    p_starts_at, p_ends_at, p_pricing_unit::pricing_unit, v_qty,
    v_total, p_guest_count, 'pending',
    v_listing.title, p_listing_image_url, v_listing.city,
    case when v_coupon_id is not null then upper(trim(p_coupon_code)) end,
    case when v_coupon_id is not null then v_discount else 0 end
  ) returning * into v_booking;

  -- Record redemption + bump usage atomically. If limits were exhausted between
  -- validate and here, redeem_coupon raises and the whole booking rolls back.
  if v_coupon_id is not null then
    perform public.redeem_coupon(v_coupon_id, v_booking.id, v_discount);
  end if;

  return to_jsonb(v_booking);
end;
$function$

;


-- ============================================================ messaging
-- Scenario 8. `conversations` has an UPDATE policy with no WITH CHECK and no
-- trigger, so either participant could rewrite participant_one_id /
-- participant_two_id. Measured: a guest swapped the host out for a stranger,
-- and the stranger read the host's messages; the host lost the thread. The
-- pair is the identity of a conversation (uniq_conversation_per_pair); it
-- does not change. Admins are exempt for the day a support merge needs it.
create or replace function public.fn_freeze_conversation_participants()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if new.participant_one_id is distinct from old.participant_one_id
     or new.participant_two_id is distinct from old.participant_two_id then
    raise exception 'The two people in a conversation cannot be changed'
      using errcode = '42501', hint = 'participants_frozen';
  end if;
  return new;
end $$;
revoke all on function public.fn_freeze_conversation_participants() from public, anon, authenticated;

drop trigger if exists trg_freeze_conversation_participants on public.conversations;
create trigger trg_freeze_conversation_participants
  before update on public.conversations
  for each row execute function public.fn_freeze_conversation_participants();

-- Scenarios 10–11. A block hid the thread on the blocker's phone and nothing
-- else: the blocked person kept sending, every message still raised a
-- notification and a push on the blocker's phone, and when the app's other
-- block affordance (conversation status = blocked) was used, the other side
-- flipped it back to active with one PATCH and carried on. The rule belongs
-- here, on the write.
create or replace function public.fn_messages_block_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_other uuid;
begin
  -- Automated sends (pre-check-in, checkout, map, contacts) run with no uid
  -- on a booking that exists; they are the host's own words to their guest
  -- and must be delivered regardless.
  if auth.uid() is null then
    return new;
  end if;
  select case when c.participant_one_id = new.sender_id
              then c.participant_two_id else c.participant_one_id end
    into v_other
    from public.conversations c where c.id = new.conversation_id;
  if public.fn_users_blocked(new.sender_id, v_other) then
    raise exception 'You cannot message this user'
      using errcode = '42501', hint = 'blocked';
  end if;
  return new;
end $$;
revoke all on function public.fn_messages_block_guard() from public, anon, authenticated;

drop trigger if exists trg_messages_block_guard on public.messages;
create trigger trg_messages_block_guard
  before insert on public.messages
  for each row execute function public.fn_messages_block_guard();

CREATE OR REPLACE FUNCTION public.get_or_create_conversation(user_one uuid, user_two uuid, p_booking_id uuid DEFAULT NULL::uuid, p_listing_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  conv_id uuid;
begin
  -- Enforce participant membership ONLY for a real authenticated user. A NULL
  -- auth.uid() means a trusted SECURITY DEFINER / cron caller (anon has no
  -- EXECUTE grant, so it can never reach here unauthenticated).
  if auth.uid() is not null and auth.uid() not in (user_one, user_two) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  -- 138: same wall as create_marketplace_booking. Only for a real caller —
  -- the cron-driven automated messages (pre-check-in, checkout) run with a
  -- null uid on a booking that already exists and must still be delivered.
  if auth.uid() is not null and public.fn_users_blocked(user_one, user_two) then
    raise exception 'You cannot message this user'
      using errcode = '42501', hint = 'blocked';
  end if;

  select id into conv_id from public.conversations
  where least(participant_one_id, participant_two_id) = least(user_one, user_two)
    and greatest(participant_one_id, participant_two_id) = greatest(user_one, user_two)
  limit 1;

  if conv_id is null then
    insert into public.conversations (participant_one_id, participant_two_id, booking_id, listing_id)
    values (user_one, user_two, p_booking_id, p_listing_id)
    returning id into conv_id;
  elsif p_booking_id is not null or p_listing_id is not null then
    -- The single thread follows the latest booking/listing context.
    update public.conversations
    set booking_id = coalesce(p_booking_id, booking_id),
        listing_id = coalesce(p_listing_id, listing_id),
        status = 'active',
        updated_at = now()
    where id = conv_id;
  end if;

  return conv_id;
end;
$function$

;

-- Scenario 9. typing_indicators and read_cursors were "own rows only", with
-- no requirement to be IN the conversation. A stranger who learned a
-- conversation id could make "… is typing" appear in it. Membership is read
-- straight off conversations (its RLS already answers "am I in it"), not via
-- is_conversation_member, which reads conversation_participants — a table
-- nothing populates.
drop policy if exists "Users can manage own typing" on public.typing_indicators;
create policy "Users can manage own typing" on public.typing_indicators
  as permissive for all to public
  using (auth.uid() = user_id
         and exists (select 1 from public.conversations c
                      where c.id = typing_indicators.conversation_id
                        and auth.uid() in (c.participant_one_id, c.participant_two_id)))
  with check (auth.uid() = user_id
         and exists (select 1 from public.conversations c
                      where c.id = typing_indicators.conversation_id
                        and auth.uid() in (c.participant_one_id, c.participant_two_id)));

drop policy if exists "Users can manage own read cursors" on public.read_cursors;
create policy "Users can manage own read cursors" on public.read_cursors
  as permissive for all to public
  using (auth.uid() = user_id
         and exists (select 1 from public.conversations c
                      where c.id = read_cursors.conversation_id
                        and auth.uid() in (c.participant_one_id, c.participant_two_id)))
  with check (auth.uid() = user_id
         and exists (select 1 from public.conversations c
                      where c.id = read_cursors.conversation_id
                        and auth.uid() in (c.participant_one_id, c.participant_two_id)));

-- Scenario 40. The contact card handed the other party profiles.mobile, a
-- column its owner can type anything into.
CREATE OR REPLACE FUNCTION public.get_booking_contacts(p_booking_id uuid)
 RETURNS TABLE(guest_name text, guest_phone text, host_name text, host_phone text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_tenant UUID;
    v_host UUID;
    v_status TEXT;
begin
    select b.tenant_id, l.owner_id, b.booking_status::text
    into v_tenant, v_host, v_status
    from public.bookings b
    join public.listings l on l.id = b.listing_id
    where b.id = p_booking_id;

    if v_tenant is null then return; end if;

    -- Only the two participants may read contacts.
    if auth.uid() is null or auth.uid() not in (v_tenant, v_host) then
        raise exception 'Not authorized';
    end if;

    -- Contacts are revealed only once the booking is locked in.
    if v_status not in ('confirmed', 'active', 'completed') then
        return;
    end if;

    return query
    select coalesce(b.tenant_name, gp.full_name, 'Guest'),
           coalesce(public.fn_identity_phone(gp.id), gp.mobile),
           coalesce(hp.full_name, 'Host'),
           coalesce(public.fn_identity_phone(hp.id), hp.mobile)
    from public.bookings b
    join public.listings l on l.id = b.listing_id
    left join public.profiles gp on gp.id = b.tenant_id
    left join public.profiles hp on hp.id = l.owner_id
    where b.id = p_booking_id;
end;
$function$

;

CREATE OR REPLACE FUNCTION public.send_booking_contacts(p_booking_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    rec RECORD;
    v_conv_id UUID;
    v_lang TEXT;
    v_header TEXT;
    v_msg TEXT;
begin
    select b.id as booking_id, b.tenant_id, b.listing_id,
           coalesce(b.tenant_name, gp.full_name, 'Guest') as guest_name,
           coalesce(public.fn_identity_phone(gp.id), gp.mobile) as guest_phone,
           l.owner_id as host_id,
           coalesce(hp.full_name, 'Host') as host_name,
           coalesce(public.fn_identity_phone(hp.id), hp.mobile) as host_phone,
           coalesce(hp.message_language, gp.message_language, 'en') as lang
    into rec
    from public.bookings b
    join public.listings l on l.id = b.listing_id
    left join public.profiles gp on gp.id = b.tenant_id
    left join public.profiles hp on hp.id = l.owner_id
    where b.id = p_booking_id
      and b.booking_status = 'confirmed'
      and b.tenant_id is not null;

    if not found then return; end if;

    -- Deliver only once per booking.
    if exists (select 1 from public.scheduled_message_sends s
               where s.booking_id = rec.booking_id and s.trigger = 'contacts') then
        return;
    end if;

    v_lang := rec.lang;
    v_header := case when v_lang = 'bn' then '📞 যোগাযোগের তথ্য' else '📞 Contact details' end;
    v_msg := v_header;

    if nullif(trim(rec.guest_phone), '') is not null then
        v_msg := v_msg || E'\n'
            || (case when v_lang = 'bn' then 'অতিথি: ' else 'Guest: ' end)
            || rec.guest_name || ' — ' || trim(rec.guest_phone);
    end if;
    if nullif(trim(rec.host_phone), '') is not null then
        v_msg := v_msg || E'\n'
            || (case when v_lang = 'bn' then 'হোস্ট: ' else 'Host: ' end)
            || rec.host_name || ' — ' || trim(rec.host_phone);
    end if;

    v_conv_id := public.get_or_create_conversation(
        rec.tenant_id, rec.host_id, rec.booking_id, rec.listing_id);

    -- Only post if at least one phone was present.
    if v_msg <> v_header then
        insert into public.messages (conversation_id, sender_id, content, content_type)
        values (v_conv_id, rec.host_id, v_msg, 'text');
    end if;

    insert into public.scheduled_message_sends (booking_id, trigger)
    values (rec.booking_id, 'contacts');
end;
$function$

;


-- ============================================================ reviews
-- Scenario 25. The double-blind reveal never worked for the second reviewer.
-- check_and_reveal_reviews is SECURITY INVOKER, so the UPDATE it runs to flip
-- BOTH reviews to revealed runs as the person who just posted the second
-- review — and reviews_update_own lets them touch only their own row. The
-- other party's review matched nothing and stayed hidden until the 14-day
-- sweep. Measured: guest and host both reviewed booking …0001; both rows
-- still is_revealed = false. Live has 3 hidden reviews on 3 bookings and no
-- pair yet, so nobody has seen this in production — it would have appeared
-- with the first pair.
create or replace function public.check_and_reveal_reviews()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    other_review_exists boolean;
begin
    select exists (
        select 1 from public.reviews
        where booking_id = new.booking_id
          and review_type != new.review_type
          and is_revealed = false
    ) into other_review_exists;

    if other_review_exists then
        update public.reviews
        set is_revealed = true, revealed_at = timezone('utc', now())
        where booking_id = new.booking_id and is_revealed = false;
    end if;

    return new;
end;
$function$;

-- Scenarios 26–27. listings.rating / review_count were never recomputed —
-- update_listing_rating() existed, averaged a column reviews does not have,
-- and was attached to nothing. The explore card reads listings.rating, so a
-- host's stars were whatever the row was created with, forever. And the same
-- host could PATCH rating = 5, review_count = 999, is_superhost = true on
-- their own listing, because the owner UPDATE policy has no column list.
-- Measured, both.
--
-- The recompute is SECURITY DEFINER and announces itself with a
-- transaction-local flag (132's pattern) so the freeze trigger below lets it
-- through; everyone else who is not an admin is refused. Only REVEALED
-- guest_to_host reviews count — a hidden review is one the other party has
-- not seen and could still be answered, and listing_ratings (117) already
-- draws the same line.
drop trigger if exists trg_update_listing_rating on public.reviews;
drop function if exists public.update_listing_rating();

create or replace function public.fn_refresh_listing_rating()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_listing uuid;
begin
  v_listing := case when tg_op = 'DELETE' then old.listing_id else new.listing_id end;
  if v_listing is null then return null; end if;
  perform set_config('musafir.rating_write', '1', true);
  update public.listings l
     set rating = (select round(avg(r.overall_rating), 2) from public.reviews r
                    where r.listing_id = v_listing and r.review_type = 'guest_to_host'
                      and r.is_revealed),
         review_count = (select count(*) from public.reviews r
                          where r.listing_id = v_listing and r.review_type = 'guest_to_host'
                            and r.is_revealed)
   where l.id = v_listing;
  perform set_config('musafir.rating_write', '0', true);
  return null;
end $$;
revoke all on function public.fn_refresh_listing_rating() from public, anon, authenticated;

drop trigger if exists trg_refresh_listing_rating on public.reviews;
create trigger trg_refresh_listing_rating
  after insert or update or delete on public.reviews
  for each row execute function public.fn_refresh_listing_rating();

create or replace function public.fn_freeze_listing_reputation()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth.uid() is null or public.is_admin()
     or coalesce(current_setting('musafir.rating_write', true), '') = '1' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    -- A new listing starts with no reputation, whatever the client sent.
    new.rating := null;
    new.review_count := 0;
    new.is_superhost := false;
    return new;
  end if;
  if new.rating       is distinct from old.rating
     or new.review_count is distinct from old.review_count
     or new.is_superhost is distinct from old.is_superhost then
    raise exception 'A listing''s rating and badges come from reviews, not from its owner'
      using errcode = '42501', hint = 'reputation_columns_protected';
  end if;
  return new;
end $$;
revoke all on function public.fn_freeze_listing_reputation() from public, anon, authenticated;

drop trigger if exists trg_freeze_listing_reputation on public.listings;
create trigger trg_freeze_listing_reputation
  before insert or update on public.listings
  for each row execute function public.fn_freeze_listing_reputation();

-- Bring every listing's stored stars in line with its revealed reviews once.
-- On live this changes rows whose rating was seeded or stale; that IS the
-- correction.
update public.listings l
   set rating = agg.avg_rating,
       review_count = agg.n
  from (
    select li.id,
           (select round(avg(r.overall_rating), 2) from public.reviews r
             where r.listing_id = li.id and r.review_type = 'guest_to_host' and r.is_revealed) as avg_rating,
           (select count(*) from public.reviews r
             where r.listing_id = li.id and r.review_type = 'guest_to_host' and r.is_revealed) as n
      from public.listings li
  ) agg
 where agg.id = l.id
   and (l.rating is distinct from agg.avg_rating or l.review_count is distinct from agg.n);

-- Scenario 28. Review reminders fire from a daily job (10:00) but looked for
-- bookings completed in a ONE-HOUR window three and seven days earlier
-- (completed_at between now-3d-1h and now-3d) — so only a stay that
-- completed between 09:00 and 10:00 ever got one; the other 23/24 never did.
-- Measured: two bookings completed 3d5h and 3d30m ago, one reminder pair.
-- The window is the whole day now, and a reminder is skipped when that
-- booking already has one for that day, so a re-run cannot double up.
create or replace function public.send_review_reminders()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    reminder_count integer := 0;
    booking_record record;
    listing_record record;
    v_day text;
begin
    for booking_record in
        select b.*, case when (b.completed_at at time zone 'Asia/Dhaka')::date
                              = ((now() - interval '3 days') at time zone 'Asia/Dhaka')::date
                         then '3' else '7' end as which
        from public.bookings b
        where b.booking_status = 'completed'
          and b.completed_at is not null
          and (b.completed_at at time zone 'Asia/Dhaka')::date in (
                ((now() - interval '3 days') at time zone 'Asia/Dhaka')::date,
                ((now() - interval '7 days') at time zone 'Asia/Dhaka')::date)
    loop
        v_day := booking_record.which;

        select l.title, l.owner_id into listing_record
        from public.listings l
        where l.id = booking_record.listing_id;

        if booking_record.tenant_id is not null
           and not exists (select 1 from public.reviews r
                            where r.booking_id = booking_record.id
                              and r.review_type = 'guest_to_host')
           and not exists (select 1 from public.notifications n
                            where n.user_id = booking_record.tenant_id
                              and n.type = 'review_reminder'
                              and n.data ->> 'booking_id' = booking_record.id::text
                              and n.data ->> 'day' = v_day) then
            insert into public.notifications (user_id, type, title, body, priority, action_url, data)
            values (
                booking_record.tenant_id, 'review_reminder',
                'Don''t Forget to Review!',
                format('Share your experience at %s. Your review helps other travelers!',
                    coalesce(listing_record.title, 'your recent stay')),
                'normal', '/review/' || booking_record.id || '/guest',
                jsonb_build_object('booking_id', booking_record.id,
                                   'listing_id', booking_record.listing_id,
                                   'reminder_type', 'guest', 'day', v_day)
            );
            reminder_count := reminder_count + 1;
        end if;

        if listing_record.owner_id is not null
           and not exists (select 1 from public.reviews r
                            where r.booking_id = booking_record.id
                              and r.review_type = 'host_to_guest')
           and not exists (select 1 from public.notifications n
                            where n.user_id = listing_record.owner_id
                              and n.type = 'review_reminder'
                              and n.data ->> 'booking_id' = booking_record.id::text
                              and n.data ->> 'day' = v_day) then
            insert into public.notifications (user_id, type, title, body, priority, action_url, data)
            values (
                listing_record.owner_id, 'review_reminder',
                'Review Your Guest',
                format('Don''t forget to review your guest from %s. Your feedback helps the community!',
                    coalesce(listing_record.title, 'your property')),
                'normal', '/review/' || booking_record.id || '/host',
                jsonb_build_object('booking_id', booking_record.id,
                                   'listing_id', booking_record.listing_id,
                                   'reminder_type', 'host', 'day', v_day)
            );
            reminder_count := reminder_count + 1;
        end if;
    end loop;

    if reminder_count > 0 then
        raise notice 'Sent % review reminders', reminder_count;
    end if;
    return reminder_count;
end;
$function$;


-- ============================================================ identity
-- Scenario 33. A rejected applicant who re-uploads never re-enters the queue.
-- set_verification_pending only moved 'none' -> 'pending', and only on
-- INSERT — but a re-upload of the same document type is an UPSERT on
-- (user_id, document_type), i.e. an UPDATE, so the trigger did not even fire.
-- The app papers over this by writing 'pending' itself after the upload; a
-- rule the client has to remember is not a rule.
create or replace function public.set_verification_pending()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if exists (select 1 from public.owner_documents
              where user_id = new.user_id and document_type = 'nid_front')
     and exists (select 1 from public.owner_documents
                  where user_id = new.user_id and document_type = 'nid_back') then
    update public.profiles
       set verification_status = 'pending'
     where id = new.user_id
       and verification_status in ('none', 'rejected');
  end if;
  return new;
end;
$function$;

drop trigger if exists on_document_uploaded on public.owner_documents;
create trigger on_document_uploaded
  after insert or update of file_path on public.owner_documents
  for each row execute function public.set_verification_pending();


-- ============================================================ coupons
-- Scenario 36. redeem_coupon took the discount as a PARAMETER and only checked
-- that the booking was the caller's. A guest called it on a booking made with
-- no coupon at all, with p_discount_amount = 99999: a redemption row for
-- ৳99,999 appeared and the coupon's single use was burnt, while the booking
-- kept its real price. A limited promo could be exhausted by one account with
-- one request per booking. The booking row already says which coupon (if
-- any) create_marketplace_booking applied and for how much; that is the only
-- redemption there is.
create or replace function public.redeem_coupon(p_coupon_id uuid, p_booking_id uuid, p_discount_amount numeric)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  c public.coupons%rowtype;
  v_uid uuid := auth.uid();
  v_booking public.bookings%rowtype;
  v_user_uses int;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;

  select * into v_booking from public.bookings where id = p_booking_id;
  if v_booking.tenant_id is null or v_booking.tenant_id <> v_uid then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  -- One redemption per booking (idempotent no-op on repeat).
  if exists (select 1 from public.coupon_redemptions where booking_id = p_booking_id) then
    return;
  end if;

  select * into c from public.coupons where id = p_coupon_id for update;
  if not found or not c.is_active then raise exception 'Coupon unavailable'; end if;

  -- 138: the booking must actually carry this coupon. The parameter is kept
  -- for the existing signature but the amount recorded is the booking's own.
  if v_booking.coupon_code is distinct from c.code then
    raise exception 'This booking was not made with that coupon'
      using errcode = '42501', hint = 'coupon_not_on_booking';
  end if;

  if c.usage_limit is not null and c.used_count >= c.usage_limit then
    raise exception 'Coupon usage limit reached';
  end if;
  if c.per_user_limit is not null then
    select count(*) into v_user_uses from public.coupon_redemptions
      where coupon_id = c.id and user_id = v_uid;
    if v_user_uses >= c.per_user_limit then raise exception 'Coupon already used'; end if;
  end if;

  insert into public.coupon_redemptions (coupon_id, user_id, booking_id, discount_amount)
    values (c.id, v_uid, p_booking_id, coalesce(v_booking.discount_amount, 0));
  update public.coupons set used_count = used_count + 1 where id = c.id;
end;
$function$;
revoke all on function public.redeem_coupon(uuid, uuid, numeric) from public, anon;


-- ============================================================ messages: dates
-- Scenario 29. The host's automated pre-check-in and checkout messages
-- rendered dates with to_char() on a timestamptz, i.e. in the database's
-- UTC. A stay booked from midnight Dhaka time on 1 October is 18:00 UTC on
-- 30 September, so the guest was told "check-in on Wednesday, September 30".
-- Every daily and monthly booking the app makes starts at local midnight, so
-- this was every one of them. Bangladesh has one time zone and no DST, so the
-- zone is a constant here rather than a setting.
CREATE OR REPLACE FUNCTION public.send_precheckin_for_booking(p_booking_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    rec RECORD;
    v_content TEXT;
    v_enabled BOOLEAN;
    v_lead_days INTEGER;
    v_conv_id UUID;
    v_rendered TEXT;
    v_nights INTEGER;
    v_units INTEGER;
    v_duration TEXT;
    v_address TEXT;
    v_access TEXT;
    v_lang TEXT;
    v_default_en TEXT;
    v_default_bn TEXT;
    v_ci_date TEXT;
    v_co_date TEXT;
BEGIN
    SELECT b.id AS booking_id, b.tenant_id, b.tenant_name, b.guest_count,
           b.starts_at, b.ends_at, b.pricing_unit,
           COALESCE(b.listing_title, l.title) AS listing_title,
           b.listing_id, l.address AS listing_address, l.city AS listing_city,
           l.owner_id AS host_id,
           COALESCE(p.full_name, 'Your host') AS host_name,
           COALESCE(p.message_language, 'en') AS message_language,
           cd.directions AS ci_directions, cd.wifi_name AS ci_wifi_name,
           cd.wifi_password AS ci_wifi_password, cd.access_code AS ci_access_code
    INTO rec
    FROM public.bookings b
    JOIN public.listings l ON l.id = b.listing_id
    LEFT JOIN public.profiles p ON p.id = l.owner_id
    LEFT JOIN public.listing_checkin_details cd ON cd.listing_id = b.listing_id
    WHERE b.id = p_booking_id AND b.booking_status = 'confirmed'
      AND b.tenant_id IS NOT NULL;

    IF NOT FOUND THEN RETURN; END IF;

    -- Already delivered for this booking?
    IF EXISTS (SELECT 1 FROM public.scheduled_message_sends s
               WHERE s.booking_id = rec.booking_id AND s.trigger = 'check_in') THEN
        RETURN;
    END IF;

    v_lang := rec.message_language;

    -- Keep in sync with MessageTemplate.defaultContentFor(checkIn, en).
    v_default_en := E'Hi {{guest_name}},\n\n' ||
        E'Thanks again for booking at {{listing_title}}!\n\n' ||
        'Please find the details below for a smooth and seamless ' ||
        E'check-in on {{check_in_date}}.\n\n' ||
        E'Address:\n{{listing_address}}\n\n' ||
        'I am sharing the exact map location below so you can find ' ||
        'the place easily. Please let me know your expected arrival ' ||
        'time, and feel free to reach out if you have any questions ' ||
        E'before your stay.\n\n' ||
        'I hope you will have an enjoyable stay at ' ||
        E'{{listing_title}}!\n\n' ||
        E'Thanks,\n{{host_name}}';

    -- Keep in sync with MessageTemplate.defaultContentFor(checkIn, bn).
    v_default_bn := E'হ্যালো {{guest_name}},\n\n' ||
        E'{{listing_title}}-এ বুকিং করার জন্য আবারও ধন্যবাদ!\n\n' ||
        '{{check_in_date}} তারিখে সহজ ও ঝামেলাহীন চেক-ইনের জন্য নিচের ' ||
        E'তথ্যগুলো দেখুন।\n\n' ||
        E'ঠিকানা:\n{{listing_address}}\n\n' ||
        'জায়গাটি সহজে খুঁজে পেতে আমি নিচে সঠিক ম্যাপ লোকেশন শেয়ার করছি। ' ||
        'অনুগ্রহ করে আপনার সম্ভাব্য আগমনের সময় জানাবেন, এবং থাকার আগে ' ||
        E'কোনো প্রশ্ন থাকলে নির্দ্বিধায় যোগাযোগ করবেন।\n\n' ||
        E'আশা করি {{listing_title}}-এ আপনার থাকা আনন্দদায়ক হবে!\n\n' ||
        E'ধন্যবাদ,\n{{host_name}}';

    SELECT t.content, t.enabled, t.lead_days
    INTO v_content, v_enabled, v_lead_days
    FROM public.message_templates t
    WHERE t.host_id = rec.host_id AND t.trigger = 'check_in';

    IF NOT FOUND THEN
        v_enabled := TRUE;
        v_lead_days := 2;
        v_content := CASE WHEN v_lang = 'bn' THEN v_default_bn ELSE v_default_en END;
    ELSIF v_content = v_default_en OR v_content = v_default_bn THEN
        v_content := CASE WHEN v_lang = 'bn' THEN v_default_bn ELSE v_default_en END;
    END IF;

    IF NOT v_enabled THEN RETURN; END IF;
    -- Not yet within the near-check-in window — the cron will pick it up later.
    IF rec.starts_at > NOW() + make_interval(days => v_lead_days) THEN RETURN; END IF;

    v_conv_id := public.get_or_create_conversation(
        rec.tenant_id, rec.host_id, rec.booking_id, rec.listing_id);

    v_nights := GREATEST(1, ((rec.ends_at at time zone 'Asia/Dhaka')::date - (rec.starts_at at time zone 'Asia/Dhaka')::date));
    IF rec.pricing_unit::text = 'hour' THEN
        v_units := GREATEST(1, FLOOR(EXTRACT(EPOCH FROM (rec.ends_at - rec.starts_at)) / 3600)::int);
        v_duration := v_units || CASE WHEN v_lang = 'bn' THEN ' ঘণ্টা'
                                      WHEN v_units = 1 THEN ' hour' ELSE ' hours' END;
    ELSIF rec.pricing_unit::text = 'month' THEN
        v_units := GREATEST(1, ROUND(((rec.ends_at at time zone 'Asia/Dhaka')::date - (rec.starts_at at time zone 'Asia/Dhaka')::date) / 30.0)::int);
        v_duration := v_units || CASE WHEN v_lang = 'bn' THEN ' মাস'
                                      WHEN v_units = 1 THEN ' month' ELSE ' months' END;
    ELSE
        v_duration := v_nights || CASE WHEN v_lang = 'bn' THEN ' রাত'
                                       WHEN v_nights = 1 THEN ' night' ELSE ' nights' END;
    END IF;

    v_address := NULLIF(TRIM(BOTH ', ' FROM
        COALESCE(rec.listing_address, '') ||
        CASE WHEN rec.listing_city IS NOT NULL
                  AND (rec.listing_address IS NULL
                       OR rec.listing_address NOT ILIKE '%' || rec.listing_city || '%')
             THEN ', ' || rec.listing_city ELSE '' END), '');

    v_ci_date := to_char(rec.starts_at at time zone 'Asia/Dhaka', 'FMDay, FMMonth FMDD');
    v_co_date := to_char(rec.ends_at at time zone 'Asia/Dhaka', 'FMDay, FMMonth FMDD');
    IF v_lang = 'bn' THEN
        v_ci_date := public._localize_date_bn(v_ci_date);
        v_co_date := public._localize_date_bn(v_co_date);
    END IF;

    v_rendered := v_content;
    v_rendered := replace(v_rendered, '{{guest_name}}',
        COALESCE(rec.tenant_name, CASE WHEN v_lang = 'bn' THEN 'অতিথি' ELSE 'Guest' END));
    v_rendered := replace(v_rendered, '{{listing_title}}',
        COALESCE(rec.listing_title, CASE WHEN v_lang = 'bn' THEN 'আপনার থাকার জায়গা' ELSE 'your stay' END));
    v_rendered := replace(v_rendered, '{{listing_address}}',
        COALESCE(v_address, rec.listing_title, CASE WHEN v_lang = 'bn' THEN 'লিস্টিং' ELSE 'the listing' END));
    v_rendered := replace(v_rendered, '{{check_in_date}}', v_ci_date);
    v_rendered := replace(v_rendered, '{{check_out_date}}', v_co_date);
    v_rendered := replace(v_rendered, '{{duration}}', v_duration);
    v_rendered := replace(v_rendered, '{{nights}}', v_nights::text);
    v_rendered := replace(v_rendered, '{{guest_count}}', COALESCE(rec.guest_count, 1)::text);
    v_rendered := replace(v_rendered, '{{host_name}}', rec.host_name);
    v_rendered := replace(v_rendered, '{{directions}}', COALESCE(rec.ci_directions, ''));
    v_rendered := replace(v_rendered, '{{wifi_name}}', COALESCE(rec.ci_wifi_name, ''));
    v_rendered := replace(v_rendered, '{{wifi_password}}', COALESCE(rec.ci_wifi_password, ''));
    v_rendered := replace(v_rendered, '{{access_code}}', COALESCE(rec.ci_access_code, ''));

    INSERT INTO public.messages (conversation_id, sender_id, content, content_type)
    VALUES (v_conv_id, rec.host_id, v_rendered, 'text');

    v_access := '';
    IF NULLIF(TRIM(rec.ci_directions), '') IS NOT NULL THEN
        v_access := v_access ||
            CASE WHEN v_lang = 'bn' THEN E'\n\n📍 দিকনির্দেশনা:\n' ELSE E'\n\n📍 Directions:\n' END
            || TRIM(rec.ci_directions);
    END IF;
    IF NULLIF(TRIM(rec.ci_wifi_name), '') IS NOT NULL THEN
        v_access := v_access ||
            CASE WHEN v_lang = 'bn' THEN E'\n\n📶 ওয়াই-ফাই: ' ELSE E'\n\n📶 Wi-Fi: ' END
            || TRIM(rec.ci_wifi_name)
            || CASE WHEN NULLIF(TRIM(rec.ci_wifi_password), '') IS NOT NULL
                    THEN (CASE WHEN v_lang = 'bn' THEN E'\nপাসওয়ার্ড: ' ELSE E'\nPassword: ' END)
                         || TRIM(rec.ci_wifi_password) ELSE '' END;
    END IF;
    IF NULLIF(TRIM(rec.ci_access_code), '') IS NOT NULL THEN
        v_access := v_access ||
            CASE WHEN v_lang = 'bn' THEN E'\n\n🔑 দরজা / অ্যাক্সেস কোড: ' ELSE E'\n\n🔑 Door / access code: ' END
            || TRIM(rec.ci_access_code);
    END IF;

    IF v_access <> '' THEN
        INSERT INTO public.messages (conversation_id, sender_id, content, content_type)
        VALUES (v_conv_id, rec.host_id,
                (CASE WHEN v_lang = 'bn' THEN 'চেক-ইন বিবরণ' ELSE 'Check-in details' END)
                || v_access, 'text');
    END IF;

    INSERT INTO public.scheduled_message_sends (booking_id, trigger)
    VALUES (rec.booking_id, 'check_in');
END;
$function$

;

CREATE OR REPLACE FUNCTION public.send_checkout_for_booking(p_booking_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    rec RECORD;
    v_content TEXT;
    v_enabled BOOLEAN;
    v_conv_id UUID;
    v_rendered TEXT;
    v_nights INTEGER;
    v_units INTEGER;
    v_duration TEXT;
    v_lang TEXT;
    v_default_en TEXT;
    v_default_bn TEXT;
    v_ci_date TEXT;
    v_co_date TEXT;
BEGIN
    SELECT b.id AS booking_id, b.tenant_id, b.tenant_name, b.guest_count,
           b.starts_at, b.ends_at, b.pricing_unit,
           COALESCE(b.listing_title, l.title) AS listing_title,
           b.listing_id, l.owner_id AS host_id,
           COALESCE(p.full_name, 'Your host') AS host_name,
           COALESCE(p.message_language, 'en') AS message_language
    INTO rec
    FROM public.bookings b
    JOIN public.listings l ON l.id = b.listing_id
    LEFT JOIN public.profiles p ON p.id = l.owner_id
    WHERE b.id = p_booking_id AND b.tenant_id IS NOT NULL;

    IF NOT FOUND THEN RETURN; END IF;

    -- Deliver once per booking.
    IF EXISTS (SELECT 1 FROM public.scheduled_message_sends s
               WHERE s.booking_id = rec.booking_id AND s.trigger = 'check_out') THEN
        RETURN;
    END IF;

    v_lang := rec.message_language;

    -- Keep in sync with MessageTemplate.defaultContentFor(checkOut, en).
    v_default_en := E'Hi {{guest_name}},\n\n' ||
        'Thanks for staying at {{listing_title}} — I hope you enjoyed ' ||
        E'your visit! You are welcome back anytime.\n\n' ||
        E'Safe travels!\n\n' ||
        E'Thanks,\n{{host_name}}';
    -- Keep in sync with MessageTemplate.defaultContentFor(checkOut, bn).
    v_default_bn := E'হ্যালো {{guest_name}},\n\n' ||
        '{{listing_title}}-এ থাকার জন্য ধন্যবাদ — আশা করি আপনার সময়টা ' ||
        E'ভালো কেটেছে! আপনি যেকোনো সময় আবার স্বাগত।\n\n' ||
        E'শুভ যাত্রা!\n\n' ||
        E'ধন্যবাদ,\n{{host_name}}';

    SELECT t.content, t.enabled
    INTO v_content, v_enabled
    FROM public.message_templates t
    WHERE t.host_id = rec.host_id AND t.trigger = 'check_out';

    IF NOT FOUND THEN
        v_enabled := TRUE;
        v_content := CASE WHEN v_lang = 'bn' THEN v_default_bn ELSE v_default_en END;
    ELSIF v_content = v_default_en OR v_content = v_default_bn THEN
        -- Host stored an un-customized default; render it in their language.
        v_content := CASE WHEN v_lang = 'bn' THEN v_default_bn ELSE v_default_en END;
    END IF;

    IF NOT v_enabled THEN RETURN; END IF;

    v_conv_id := public.get_or_create_conversation(
        rec.tenant_id, rec.host_id, rec.booking_id, rec.listing_id);

    v_nights := GREATEST(1, ((rec.ends_at at time zone 'Asia/Dhaka')::date - (rec.starts_at at time zone 'Asia/Dhaka')::date));
    IF rec.pricing_unit::text = 'hour' THEN
        v_units := GREATEST(1, FLOOR(EXTRACT(EPOCH FROM (rec.ends_at - rec.starts_at)) / 3600)::int);
        v_duration := v_units || CASE WHEN v_lang = 'bn' THEN ' ঘণ্টা'
                                      WHEN v_units = 1 THEN ' hour' ELSE ' hours' END;
    ELSIF rec.pricing_unit::text = 'month' THEN
        v_units := GREATEST(1, ROUND(((rec.ends_at at time zone 'Asia/Dhaka')::date - (rec.starts_at at time zone 'Asia/Dhaka')::date) / 30.0)::int);
        v_duration := v_units || CASE WHEN v_lang = 'bn' THEN ' মাস'
                                      WHEN v_units = 1 THEN ' month' ELSE ' months' END;
    ELSE
        v_duration := v_nights || CASE WHEN v_lang = 'bn' THEN ' রাত'
                                       WHEN v_nights = 1 THEN ' night' ELSE ' nights' END;
    END IF;

    v_ci_date := to_char(rec.starts_at at time zone 'Asia/Dhaka', 'FMDay, FMMonth FMDD');
    v_co_date := to_char(rec.ends_at at time zone 'Asia/Dhaka', 'FMDay, FMMonth FMDD');
    IF v_lang = 'bn' THEN
        v_ci_date := public._localize_date_bn(v_ci_date);
        v_co_date := public._localize_date_bn(v_co_date);
    END IF;

    v_rendered := v_content;
    v_rendered := replace(v_rendered, '{{guest_name}}',
        COALESCE(rec.tenant_name, CASE WHEN v_lang = 'bn' THEN 'অতিথি' ELSE 'Guest' END));
    v_rendered := replace(v_rendered, '{{listing_title}}',
        COALESCE(rec.listing_title, CASE WHEN v_lang = 'bn' THEN 'আপনার থাকার জায়গা' ELSE 'your stay' END));
    v_rendered := replace(v_rendered, '{{check_in_date}}', v_ci_date);
    v_rendered := replace(v_rendered, '{{check_out_date}}', v_co_date);
    v_rendered := replace(v_rendered, '{{duration}}', v_duration);
    v_rendered := replace(v_rendered, '{{nights}}', v_nights::text);
    v_rendered := replace(v_rendered, '{{guest_count}}', COALESCE(rec.guest_count, 1)::text);
    v_rendered := replace(v_rendered, '{{host_name}}', rec.host_name);

    INSERT INTO public.messages (conversation_id, sender_id, content, content_type)
    VALUES (v_conv_id, rec.host_id, v_rendered, 'text');

    INSERT INTO public.scheduled_message_sends (booking_id, trigger)
    VALUES (rec.booking_id, 'check_out');
END;
$function$

;


-- ============================================================ hidden listings
-- Scenario 39. A host hides a listing (is_active = false) while a guest holds
-- a confirmed booking on it. The guest's trip is still there — the booking
-- row is theirs — but the listing behind it is not: the SELECT policy is
-- "active, or mine", so "View listing" from the trip, the address gate's
-- listing lookup and the wishlist card all come back empty for the one
-- person who most needs them. A guest who has ever booked a place may keep
-- reading it, hidden or not; hiding is about new guests finding it.
--
-- Through a definer helper, not an inline EXISTS on bookings: bookings'
-- own "hosts can view bookings for their listings" policy reads listings,
-- so a listings policy that reads bookings is a cycle and Postgres refuses
-- the whole query with "infinite recursion detected in policy" — measured,
-- first draft. The helper reads bookings as postgres (no policy applies) and
-- answers only "does the CALLER hold a booking here", so granting it to
-- authenticated leaks nothing. It must be granted: a role without EXECUTE
-- on a function a policy calls gets an error, not an empty result (116).
create or replace function public.fn_caller_booked_listing(p_listing_id uuid)
returns boolean
language sql stable security definer
set search_path to 'public'
as $$
  select auth.uid() is not null and exists (
    select 1 from public.bookings b
    where b.listing_id = p_listing_id and b.tenant_id = auth.uid()
  );
$$;
revoke all on function public.fn_caller_booked_listing(uuid) from public, anon;
grant execute on function public.fn_caller_booked_listing(uuid) to authenticated;

drop policy if exists listings_select_booked_guest on public.listings;
create policy listings_select_booked_guest on public.listings
  as permissive for select to authenticated
  using (public.fn_caller_booked_listing(id));


-- ============================================================ held payments
-- Scenario 41, the other half. sslcommerz-ipn now holds a payment that lands
-- on a booking no longer open (cancelled, rejected, expired) instead of
-- marking the booking paid. The console resolves a hold with
-- admin_release_payment, which marks the BOOKING paid — and checked only the
-- payment's status, so an admin who pressed Release on such a hold would
-- have paid a cancelled stay and posted the host an earning for it. Release
-- now refuses unless the booking is confirmed or active; the admin's only
-- move on a closed booking is Reject + refund, which is what the IPN's
-- notification tells them.
create or replace function public.admin_release_payment(p_payment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_payment public.payments%rowtype;
  v_booking_status text;
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

  select booking_status::text into v_booking_status
    from public.bookings where id = v_payment.booking_id;
  if v_booking_status is null or v_booking_status not in ('confirmed', 'active') then
    raise exception 'This booking is % — the payment can only be rejected and refunded, not released',
      coalesce(v_booking_status, 'gone')
      using errcode = '22023', hint = 'booking_not_open';
  end if;

  update public.payments
     set status = 'paid', updated_at = now()
   where id = p_payment_id;

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
$function$;


-- ============================================================ realtime
-- Scenario 44. The app subscribes to postgres_changes on `bookings` so a host
-- sees a new request and a guest sees the acceptance without pulling to
-- refresh. On live, the supabase_realtime publication carried conversations,
-- messages, notifications and typing_indicators — and not bookings. The
-- subscription connected, reported active, and never received a row; only
-- the notification row arrived. Idempotent: adds only what is missing, and
-- re-asserts the four live already has so a fresh mirror gets them too.
do $$
declare t text;
begin
  foreach t in array array['bookings', 'conversations', 'messages',
                           'notifications', 'typing_indicators'] loop
    if not exists (select 1 from pg_publication_tables
                    where pubname = 'supabase_realtime'
                      and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;


-- ============================================================ storage
-- Scenario 45. chat-attachments — public, 10 MB, and NO mime allowlist, unlike
-- the other three buckets. Measured: a guest uploaded a 9 MB blob labelled
-- image/png and a text/html "Musafir login" page; Storage served the page as
-- text/plain, so it does not render, but the bucket still accepts an .apk or
-- .exe that the chat then offers the other party as a downloadable file. The
-- chat sends photos and documents: images, PDF and the office formats.
-- (Text, audio and video were never offered by the picker.)
update storage.buckets
   set allowed_mime_types = array[
         'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic',
         'application/pdf',
         'application/msword',
         'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
         'application/vnd.ms-excel',
         'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
         'text/plain']
 where id = 'chat-attachments';

-- And a participant could not delete their own attachment on a Storage that
-- stamps owner_id rather than owner (the local mirror is one; 134 met the
-- same split on listing-images).
drop policy if exists chat_attachments_owner_delete on storage.objects;
create policy chat_attachments_owner_delete on storage.objects
  as permissive for delete to authenticated
  using (bucket_id = 'chat-attachments'
         and (owner = auth.uid() or owner_id = auth.uid()::text or public.is_admin()));
