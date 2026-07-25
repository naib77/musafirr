-- 072: SSLCommerz payments.
--
-- Guest pays after the host accepts (booking = 'confirmed'). Payment is recorded
-- here and mirrored onto bookings.payment_status; the host can only mark a
-- booking 'completed' once payment_status = 'paid' (enforced in the app + the
-- lifecycle, and the amount is validated server-side in the sslcommerz-ipn
-- Edge Function against SSLCommerz's Validation API).
--
-- Writes to `payments` happen ONLY from the Edge Functions (service role, which
-- bypasses RLS). There is intentionally no INSERT/UPDATE policy for clients.

create table if not exists public.payments (
  id               uuid primary key default gen_random_uuid(),
  booking_id       uuid not null references public.bookings(id) on delete cascade,
  user_id          uuid not null references auth.users(id) on delete cascade,
  tran_id          text not null unique,
  amount           numeric not null,
  currency         text not null default 'BDT',
  status           text not null default 'initiated'
                     check (status in ('initiated', 'paid', 'failed', 'cancelled')),
  val_id           text,
  card_type        text,
  bank_tran_id     text,
  gateway_response jsonb,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index if not exists payments_booking_id_idx on public.payments(booking_id);
create index if not exists payments_user_id_idx on public.payments(user_id);

-- Mirror flag on bookings so lists/gates don't need a join.
alter table public.bookings
  add column if not exists payment_status text not null default 'unpaid'
    check (payment_status in ('unpaid', 'paid', 'refunded'));

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.payments enable row level security;

-- Read: the paying guest, the listing's host, or an admin. No client writes.
drop policy if exists payments_select on public.payments;
create policy payments_select on public.payments
  for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.bookings b
      join public.listings l on l.id = b.listing_id
      where b.id = payments.booking_id and l.owner_id = auth.uid()
    )
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'admin'
    )
  );

-- keep updated_at fresh
create or replace function public.touch_payments_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists payments_touch_updated_at on public.payments;
create trigger payments_touch_updated_at
  before update on public.payments
  for each row execute function public.touch_payments_updated_at();

comment on table public.payments is
  'SSLCommerz payment attempts. Written only by the sslcommerz-init / sslcommerz-ipn Edge Functions (service role). bookings.payment_status mirrors the successful payment.';
