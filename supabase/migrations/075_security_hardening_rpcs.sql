-- 075_security_hardening_rpcs.sql
-- Closes IDOR / authorization gaps found in the 2026-07-27 security audit.
-- Each SECURITY DEFINER RPC below trusted a caller-supplied id (bypassing the
-- correct table RLS); they are rebound to the authenticated caller.

-- ============================================================
-- 1) HIGH — upsert_fcm_token push-notification hijack
-- The function trusted p_user_id and was EXECUTE-able by anon, so anyone with
-- the public anon key could register their own device token under any user's
-- account and receive all of that user's push notifications. Bind it to the
-- authenticated caller and drop anon/public access.
-- ============================================================
create or replace function public.upsert_fcm_token(
  p_user_id uuid,
  p_token text,
  p_device_type text default 'android',
  p_device_name text default null
) returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  insert into public.fcm_tokens (user_id, token, device_type, device_name)
  values (p_user_id, p_token, p_device_type, p_device_name)
  on conflict (user_id, token)
  do update set
    is_active = true,
    last_used_at = now(),
    updated_at = now(),
    device_type = coalesce(excluded.device_type, fcm_tokens.device_type),
    device_name = coalesce(excluded.device_name, fcm_tokens.device_name)
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.upsert_fcm_token(uuid, text, text, text) from public, anon;
grant execute on function public.upsert_fcm_token(uuid, text, text, text) to authenticated;

-- ============================================================
-- 2) MEDIUM — get_or_create_conversation was anon-callable and never checked
-- that the caller is one of the two participants, allowing conversation-row
-- spam / context tampering between arbitrary users. Require the caller to be a
-- participant and drop anon/public access.
-- ============================================================
create or replace function public.get_or_create_conversation(
  user_one uuid,
  user_two uuid,
  p_booking_id uuid default null,
  p_listing_id uuid default null
) returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  conv_id uuid;
begin
  if auth.uid() is null or auth.uid() not in (user_one, user_two) then
    raise exception 'Not authorized' using errcode = '42501';
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
$$;

revoke execute on function public.get_or_create_conversation(uuid, uuid, uuid, uuid) from public, anon;
grant execute on function public.get_or_create_conversation(uuid, uuid, uuid, uuid) to authenticated;

-- ============================================================
-- 3) LOW — redeem_coupon accepted an arbitrary booking_id and discount, letting
-- a caller write redemptions against other bookings / loop to drain a coupon.
-- Require the booking to belong to the caller, and make it idempotent per
-- booking (this also stops the client's post-booking redeem() from
-- double-counting what create_marketplace_booking already redeemed).
-- ============================================================
create or replace function public.redeem_coupon(
  p_coupon_id uuid,
  p_booking_id uuid,
  p_discount_amount numeric
) returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  c public.coupons%rowtype;
  v_uid uuid := auth.uid();
  v_booking_owner uuid;
  v_user_uses int;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;

  -- Redemptions may only be recorded for the caller's own booking.
  select tenant_id into v_booking_owner from public.bookings where id = p_booking_id;
  if v_booking_owner is null or v_booking_owner <> v_uid then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  -- One redemption per booking (idempotent no-op on repeat).
  if exists (select 1 from public.coupon_redemptions where booking_id = p_booking_id) then
    return;
  end if;

  select * into c from public.coupons where id = p_coupon_id for update;
  if not found or not c.is_active then raise exception 'Coupon unavailable'; end if;
  if c.usage_limit is not null and c.used_count >= c.usage_limit then
    raise exception 'Coupon usage limit reached';
  end if;
  if c.per_user_limit is not null then
    select count(*) into v_user_uses from public.coupon_redemptions
      where coupon_id = c.id and user_id = v_uid;
    if v_user_uses >= c.per_user_limit then raise exception 'Coupon already used'; end if;
  end if;

  insert into public.coupon_redemptions (coupon_id, user_id, booking_id, discount_amount)
    values (c.id, v_uid, p_booking_id, coalesce(p_discount_amount, 0));
  update public.coupons set used_count = used_count + 1 where id = c.id;
end;
$$;

-- ============================================================
-- 4) LOW — app_settings was world-readable (to public using true). Harmless for
-- the single benign flag it holds today, but any future sensitive key would be
-- exposed to anon by default. Gate reads on an explicit is_public flag so
-- existing public flags keep working (default true) while new sensitive keys
-- are hidden unless opted in.
-- ============================================================
alter table public.app_settings
  add column if not exists is_public boolean not null default true;

drop policy if exists "app_settings_select_all" on public.app_settings;

create policy "app_settings_select_public"
  on public.app_settings for select
  using (is_public);
