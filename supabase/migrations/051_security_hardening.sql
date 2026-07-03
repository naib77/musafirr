-- =============================================================
-- 051 — Server-side security hardening
--
-- Closes a set of holes where business rules were enforced only in
-- the Flutter client and the database trusted whatever it was sent:
--   1. Booking status/price tampering via direct UPDATE
--   2. conversation_participants SELECT policy infinite recursion (42P17)
--   3. mark_all_notifications_read / get_unread_notification_count acting
--      on any user id
--   4. apply_discount callable (and abusable) by any client
--   5. discount amount math producing negative / oversized discounts
--   6. send-push-notification callable by anyone (adds a shared secret)
-- =============================================================

-- -------------------------------------------------------------
-- 1. Booking update guard
--
-- The bookings UPDATE RLS policy only checks identity (tenant/owner/admin);
-- it cannot restrict WHICH columns or status transitions are allowed. A guest
-- could PATCH their own booking to booking_status='completed' or total_price=0.
--
-- This BEFORE UPDATE trigger enforces the real state machine:
--   * financial / identity fields are immutable after creation (non-admin)
--   * a guest (tenant, not the listing owner) may ONLY move a booking to
--     'cancelled', and only from pending/confirmed
--   * the listing owner (host) drives the rest of the lifecycle
--   * a null auth.uid() (service_role / SQL cron jobs) is trusted
-- -------------------------------------------------------------
create or replace function public.enforce_booking_update_rules()
returns trigger
language plpgsql
security definer
set search_path = public
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

drop trigger if exists trg_enforce_booking_update_rules on public.bookings;
create trigger trg_enforce_booking_update_rules
  before update on public.bookings
  for each row
  execute function public.enforce_booking_update_rules();

-- -------------------------------------------------------------
-- 2. conversation_participants — remove self-referential recursion
--
-- The original SELECT/INSERT policies queried conversation_participants
-- inside their own USING/WITH CHECK clause, which Postgres rejects with
-- 42P17 (infinite recursion). Route membership through a SECURITY DEFINER
-- helper so the check does not re-enter RLS.
-- -------------------------------------------------------------
create or replace function public.is_conversation_member(p_conversation_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = p_conversation_id
      and cp.user_id = p_user_id
      and cp.is_active = true
  );
$$;

drop policy if exists "Users can view participants in own conversations" on public.conversation_participants;
create policy "Users can view participants in own conversations"
  on public.conversation_participants
  for select
  using (public.is_conversation_member(conversation_id, auth.uid()));

drop policy if exists "Users can add participants" on public.conversation_participants;
create policy "Users can add participants"
  on public.conversation_participants
  for insert
  with check (public.is_conversation_member(conversation_id, auth.uid()));

-- -------------------------------------------------------------
-- 3. Notification RPCs must act only on the caller's own rows
-- -------------------------------------------------------------
create or replace function get_unread_notification_count(p_user_id uuid)
returns integer as $$
begin
  if auth.uid() is not null and auth.uid() <> p_user_id then
    raise exception 'Not authorized';
  end if;
  return (
    select count(*)::integer
    from notifications
    where user_id = p_user_id and status = 'unread'
  );
end;
$$ language plpgsql security definer;

create or replace function mark_all_notifications_read(p_user_id uuid)
returns integer as $$
declare
  affected_rows integer;
begin
  if auth.uid() is not null and auth.uid() <> p_user_id then
    raise exception 'Not authorized';
  end if;
  update notifications
  set status = 'read', read_at = now()
  where user_id = p_user_id and status = 'unread';
  get diagnostics affected_rows = row_count;
  return affected_rows;
end;
$$ language plpgsql security definer;

-- -------------------------------------------------------------
-- 4. apply_discount is SECURITY DEFINER with no auth / re-validation.
-- The client never calls it directly (redemption goes through the
-- validate-discount edge function under the service role). Revoke it
-- from client roles so it can only be invoked server-side.
-- -------------------------------------------------------------
-- Revoke every overload of apply_discount that actually exists (the discounts
-- feature may not be deployed on all environments, and the signature can vary),
-- so this never fails the migration when the function is absent.
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.proname = 'apply_discount' and n.nspname = 'public'
  loop
    execute format(
      'revoke execute on function %s from public, anon, authenticated', r.sig);
  end loop;
end $$;

-- -------------------------------------------------------------
-- 5. Clamp discount math so a mis-configured discount can never
-- increase the guest's price or exceed the booking total.
-- -------------------------------------------------------------
-- Only redefine when the discounts feature is actually deployed here.
do $do$
begin
  if to_regclass('public.discounts') is null then
    return;
  end if;

  execute $fn$
    create or replace function calculate_discount_amount(
      p_discount_id uuid,
      p_booking_amount decimal,
      p_nights integer
    ) returns decimal as $body$
    declare
      v_discount record;
      v_amount decimal;
    begin
      select * into v_discount from discounts where id = p_discount_id;
      if not found then
        return 0;
      end if;

      case v_discount.type
        when 'percentage' then
          v_amount := p_booking_amount * (least(greatest(v_discount.value, 0), 100) / 100);
          if v_discount.max_discount_amount is not null
             and v_amount > v_discount.max_discount_amount then
            v_amount := v_discount.max_discount_amount;
          end if;

        when 'fixed_amount' then
          v_amount := greatest(v_discount.value, 0);

        when 'free_nights' then
          if v_discount.free_nights_config is not null and p_nights > 0 then
            declare
              v_stay integer := (v_discount.free_nights_config->>'stay')::integer;
              v_pay integer := (v_discount.free_nights_config->>'pay')::integer;
              v_free_nights integer;
            begin
              if p_nights >= v_stay then
                -- Never negative: pay >= stay yields zero free nights.
                v_free_nights := greatest(v_stay - v_pay, 0);
                v_amount := v_free_nights * (p_booking_amount / p_nights);
              else
                v_amount := 0;
              end if;
            end;
          else
            v_amount := 0;
          end if;
      end case;

      -- Final safety net: a discount is in [0, booking amount].
      return least(greatest(coalesce(v_amount, 0), 0), p_booking_amount);
    end;
    $body$ language plpgsql security definer;
  $fn$;
end $do$;

-- -------------------------------------------------------------
-- 6. Gate the push edge function with a shared secret.
--
-- The delivery trigger (migration 015) currently authenticates the
-- edge-function call with the public anon key, so anyone who knows the
-- URL can invoke it and spam arbitrary users. Send a secret header that
-- only the server knows; the edge function rejects calls without it.
--
-- The secret lives in a database GUC set out-of-band (NOT in git):
--   alter database postgres set app.push_secret = '<random>';
-- and as an edge-function secret with the SAME value:
--   supabase secrets set PUSH_SHARED_SECRET='<random>'
-- -------------------------------------------------------------
create or replace function send_push_on_notification_insert()
returns trigger as $$
begin
  perform net.http_post(
    url := 'https://bojkmonskqlhuakxhzcb.supabase.co/functions/v1/send-push-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJvamttb25za3FsaHVha3hoemNiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDcwNTcwMTQsImV4cCI6MjA2MjYzMzAxNH0.gPd0QWSQ2XNjBccqEST97fqAV2HP9NMqwShTqpJlilk',
      'x-push-secret', coalesce(current_setting('app.push_secret', true), '')
    ),
    body := jsonb_build_object(
      'user_id', NEW.user_id,
      'title', NEW.title,
      'body', NEW.body,
      'data', coalesce(NEW.data, '{}'::jsonb) || jsonb_build_object(
        'type', NEW.type::text,
        'notification_id', NEW.id::text,
        'action_url', coalesce(NEW.action_url, '')
      )
    )
  );
  return NEW;
exception
  when others then
    raise warning 'Push notification error: %', SQLERRM;
    return NEW;
end;
$$ language plpgsql security definer;
