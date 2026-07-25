-- 069_coupons.sql
--
-- Simple coupon-code discounts: admins create codes (percentage or flat amount),
-- guests redeem them at checkout. Distinct from the older (unwired) discounts
-- engine in 004 — this is the minimal, actually-integrated coupon path.
--
-- Security model: guests never read the `coupons` table (would let them
-- enumerate/guess codes). They call the SECURITY DEFINER `validate_coupon()` and
-- `redeem_coupon()` functions, which do the authoritative math and limit checks.
-- Only admins (is_admin()) can create/list/edit coupons directly.

create table if not exists public.coupons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  discount_type text not null check (discount_type in ('percentage', 'flat')),
  discount_value numeric not null check (discount_value >= 0),
  max_discount_amount numeric,           -- cap for percentage coupons (null = no cap)
  min_booking_amount numeric not null default 0,
  usage_limit int,                       -- total redemptions allowed (null = unlimited)
  used_count int not null default 0,
  per_user_limit int default 1,          -- redemptions per user (null = unlimited)
  is_active boolean not null default true,
  starts_at timestamptz,
  expires_at timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.coupon_redemptions (
  id uuid primary key default gen_random_uuid(),
  coupon_id uuid not null references public.coupons(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  booking_id uuid references public.bookings(id) on delete set null,
  discount_amount numeric not null default 0,
  redeemed_at timestamptz not null default now()
);
create index if not exists coupon_redemptions_coupon_user_idx
  on public.coupon_redemptions (coupon_id, user_id);

-- Record of the coupon applied to a booking.
alter table public.bookings add column if not exists coupon_code text;
alter table public.bookings add column if not exists discount_amount numeric not null default 0;

-- Codes are stored/compared upper-cased.
create or replace function public.coupons_normalize_code()
  returns trigger language plpgsql as $$
begin
  new.code := upper(trim(new.code));
  return new;
end;
$$;
drop trigger if exists coupons_normalize_code_trg on public.coupons;
create trigger coupons_normalize_code_trg
  before insert or update on public.coupons
  for each row execute function public.coupons_normalize_code();

alter table public.coupons enable row level security;
alter table public.coupon_redemptions enable row level security;

drop policy if exists coupons_admin_all on public.coupons;
create policy coupons_admin_all on public.coupons
  for all to authenticated using (is_admin()) with check (is_admin());

drop policy if exists coupon_redemptions_select on public.coupon_redemptions;
create policy coupon_redemptions_select on public.coupon_redemptions
  for select to authenticated using (user_id = auth.uid() or is_admin());

-- Validate a coupon for the current user against a pre-discount amount.
-- Returns a JSON verdict, including the authoritative discount amount.
create or replace function public.validate_coupon(p_code text, p_amount numeric)
  returns jsonb language plpgsql security definer set search_path = public as $$
declare
  c public.coupons%rowtype;
  v_uid uuid := auth.uid();
  v_user_uses int;
  v_discount numeric;
begin
  if v_uid is null then
    return jsonb_build_object('valid', false, 'message', 'Please sign in to use a coupon');
  end if;

  select * into c from public.coupons where code = upper(trim(p_code));
  if not found then
    return jsonb_build_object('valid', false, 'message', 'Coupon not found');
  end if;
  if not c.is_active then
    return jsonb_build_object('valid', false, 'message', 'This coupon is no longer active');
  end if;
  if c.starts_at is not null and now() < c.starts_at then
    return jsonb_build_object('valid', false, 'message', 'This coupon is not active yet');
  end if;
  if c.expires_at is not null and now() > c.expires_at then
    return jsonb_build_object('valid', false, 'message', 'This coupon has expired');
  end if;
  if c.usage_limit is not null and c.used_count >= c.usage_limit then
    return jsonb_build_object('valid', false, 'message', 'This coupon has reached its usage limit');
  end if;
  if p_amount < c.min_booking_amount then
    return jsonb_build_object('valid', false, 'message',
      'Minimum booking amount for this coupon is ' || c.min_booking_amount::text);
  end if;
  if c.per_user_limit is not null then
    select count(*) into v_user_uses from public.coupon_redemptions
      where coupon_id = c.id and user_id = v_uid;
    if v_user_uses >= c.per_user_limit then
      return jsonb_build_object('valid', false, 'message', 'You have already used this coupon');
    end if;
  end if;

  if c.discount_type = 'percentage' then
    v_discount := round(p_amount * c.discount_value / 100.0, 2);
    if c.max_discount_amount is not null and v_discount > c.max_discount_amount then
      v_discount := c.max_discount_amount;
    end if;
  else
    v_discount := c.discount_value;
  end if;
  if v_discount > p_amount then v_discount := p_amount; end if;

  return jsonb_build_object(
    'valid', true,
    'coupon_id', c.id,
    'code', c.code,
    'discount_type', c.discount_type,
    'discount_value', c.discount_value,
    'discount_amount', v_discount,
    'final_amount', p_amount - v_discount,
    'message', 'Coupon applied'
  );
end;
$$;
grant execute on function public.validate_coupon(text, numeric) to authenticated;

-- Atomically record a redemption and bump used_count, re-checking limits.
-- Call after a booking is created. Raises on limit violations.
create or replace function public.redeem_coupon(
  p_coupon_id uuid, p_booking_id uuid, p_discount_amount numeric)
  returns void language plpgsql security definer set search_path = public as $$
declare
  c public.coupons%rowtype;
  v_uid uuid := auth.uid();
  v_user_uses int;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
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
grant execute on function public.redeem_coupon(uuid, uuid, numeric) to authenticated;
