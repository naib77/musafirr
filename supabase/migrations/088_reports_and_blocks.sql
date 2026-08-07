-- 088: safety P1 — user reports and user blocks.
--
-- reports: "report this listing / user / booking" from the app. Reporters see
-- their own reports; admins (is_admin(), from 075) triage everything — the
-- admin portal reads this table directly as its safety queue.
--
-- user_blocks: guest/host-initiated blocks. v1 enforcement is client-side
-- (blocked users' listings and conversations are hidden by the app); rows
-- are readable by both sides' clients so each app can filter. Server-side
-- message enforcement can be layered on later without a schema change.

create table if not exists public.reports (
  id               uuid primary key default gen_random_uuid(),
  reporter_id      uuid not null references public.profiles(id) on delete cascade,
  reported_user_id uuid references public.profiles(id) on delete set null,
  listing_id       uuid references public.listings(id) on delete set null,
  booking_id       uuid references public.bookings(id) on delete set null,
  category         text not null check (category in
                     ('safety', 'fraud', 'inappropriate', 'listing_issue', 'other')),
  details          text,
  status           text not null default 'open' check (status in
                     ('open', 'reviewing', 'resolved', 'dismissed')),
  resolution_note  text,
  created_at       timestamptz not null default now(),
  resolved_at      timestamptz,
  resolved_by      uuid references public.profiles(id) on delete set null
);

create index if not exists idx_reports_status on public.reports (status, created_at desc);
create index if not exists idx_reports_reported_user on public.reports (reported_user_id);

alter table public.reports enable row level security;

drop policy if exists "reports_insert_own" on public.reports;
create policy "reports_insert_own"
  on public.reports for insert to authenticated
  with check (reporter_id = auth.uid());

drop policy if exists "reports_select_own_or_admin" on public.reports;
create policy "reports_select_own_or_admin"
  on public.reports for select to authenticated
  using (reporter_id = auth.uid() or public.is_admin());

drop policy if exists "reports_admin_update" on public.reports;
create policy "reports_admin_update"
  on public.reports for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create table if not exists public.user_blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

alter table public.user_blocks enable row level security;

drop policy if exists "user_blocks_insert_own" on public.user_blocks;
create policy "user_blocks_insert_own"
  on public.user_blocks for insert to authenticated
  with check (blocker_id = auth.uid());

drop policy if exists "user_blocks_delete_own" on public.user_blocks;
create policy "user_blocks_delete_own"
  on public.user_blocks for delete to authenticated
  using (blocker_id = auth.uid());

-- Both sides can see the row: the blocker's app hides the blocked user's
-- content; the blocked side's app can hide the blocker's listings/chat too.
drop policy if exists "user_blocks_select_involved" on public.user_blocks;
create policy "user_blocks_select_involved"
  on public.user_blocks for select to authenticated
  using (blocker_id = auth.uid() or blocked_id = auth.uid() or public.is_admin());
