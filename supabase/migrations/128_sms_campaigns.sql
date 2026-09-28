-- =============================================
-- 128 — bulk SMS from the admin console
--
-- The console can already reach every user; what it could not do was speak to
-- them. This adds a campaign (one message) and a recipient queue (one row per
-- number), sent by the `send-bulk-sms` edge function.
--
-- **Why a queue and not a loop.** The single rule this feature has to obey is
-- that nobody is ever texted twice. A loop inside one request cannot promise
-- that: it has no record of how far it got, so a timeout halfway through leaves
-- the admin with no way to finish except to start again, over the top of the
-- people already reached. The queue makes the promise structural — one row per
-- recipient, a unique index on (campaign, phone), and a claim step that is a
-- separate transaction from the send.
--
-- **Claim before send, deliberately.** `admin_claim_sms_batch` flips a row to
-- 'sending' and commits BEFORE the provider is called. A crash in the gap
-- therefore loses that message rather than repeating it, and the row is left in
-- 'sending' where nothing will pick it up again without an admin explicitly
-- retrying it. That is the right way round: an unsent marketing message costs
-- nothing, and a duplicate costs money and trust. Do not "fix" this into
-- mark-after-send.
--
-- **This is not the OTP path.** `send-otp` sends one message to one person who
-- just asked for it. Everything here is unsolicited and goes out over
-- GENNET_SID=IOBYTESNONMASK, a non-masked route — hence the suppression list,
-- the hard ceiling, and the fact that a campaign has to be started as a
-- separate act from being composed.
-- =============================================

-- ---------------------------------------------------------------------------
-- Canonical BD mobile, in SQL.
--
-- This is the twin of `normalizePhone` in supabase/functions/_shared/otp.ts and
-- `canonicalBdPhone` in lib/services/auth/phone_number.dart — but it differs
-- from both in one deliberate way, and the difference is the whole point of it
-- existing.
--
-- Those two are ROUTERS: they must pass unrecognised input through unchanged so
-- that a mistyped login fails cleanly against a nonexistent account. This one is
-- a GATE: it returns null for anything that is not an assigned BD mobile, and
-- the caller drops the row.
--
-- That matters because `profiles.mobile` is not clean. On live today one row
-- holds the literal string 'pending_382e2a8a-1199-415e-a974-9e1da6ca0647' and
-- another holds '+880 1233293542', where 123 is not an assigned operator
-- prefix. A router would hand both to the SMS provider.
-- ---------------------------------------------------------------------------
create or replace function public.fn_canonical_bd_phone(p_raw text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  n text;
begin
  if p_raw is null then
    return null;
  end if;

  n := regexp_replace(p_raw, '[[:space:]()\-]', '', 'g');

  if left(n, 4) = '+880' then
    n := '0' || substr(n, 5);
  elsif left(n, 3) = '880' then
    n := '0' || substr(n, 4);
  elsif left(n, 1) = '+' then
    n := substr(n, 2);
  end if;

  -- The bare-10-digit case the login screen invites, because it renders "+880"
  -- as a decorative prefix. See otp.ts for the four accounts this cost.
  if n ~ '^1[3-9][0-9]{8}$' then
    n := '0' || n;
  end if;

  -- The gate. 013-019 are the assigned prefixes; anything else is not a number
  -- we are willing to pay to send to.
  if n !~ '^01[3-9][0-9]{8}$' then
    return null;
  end if;

  return n;
end;
$$;

comment on function public.fn_canonical_bd_phone(text) is
  'Canonical 01XXXXXXXXX, or NULL when the input is not an assigned BD mobile. '
  'Unlike normalizePhone in otp.ts this REFUSES junk rather than passing it '
  'through — it gates spending, not routing.';

-- GenNet wants 8801XXXXXXXXX.
create or replace function public.fn_msisdn(p_canonical text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_canonical is null then null
    else '880' || substr(p_canonical, 2)
  end;
$$;

-- ---------------------------------------------------------------------------
-- Message length, for the cost estimate the compose screen shows.
--
-- A deliberately CONSERVATIVE approximation: anything outside printable ASCII
-- is treated as UCS-2. The real GSM-7 alphabet also carries a handful of
-- accented letters, so a message using only those is over-estimated by one
-- tier. Over-estimating is the safe direction — a Bangla message is 70
-- characters per segment against English's 160, so under-estimating would
-- silently quote a campaign at a third of its price.
--
-- The provider's own count is authoritative for billing. This is for the
-- admin's benefit before they commit, not an invoice.
-- ---------------------------------------------------------------------------
create or replace function public.fn_sms_encoding(p_text text)
returns text
language sql
immutable
set search_path = public
as $$
  select case when coalesce(p_text, '') ~ '^[ -~\r\n]*$' then 'gsm7' else 'ucs2' end;
$$;

create or replace function public.fn_sms_segments(p_text text)
returns integer
language plpgsql
immutable
set search_path = public
as $$
declare
  v_len integer := length(coalesce(p_text, ''));
  v_gsm boolean := public.fn_sms_encoding(p_text) = 'gsm7';
  v_single integer;
  v_multi integer;
begin
  if v_len = 0 then
    return 0;
  end if;

  v_single := case when v_gsm then 160 else 70 end;
  -- Concatenated parts give up header room, which is why this is not simply
  -- ceil(len / single) — a 161-character GSM-7 message is two 153s, not 160+1.
  v_multi  := case when v_gsm then 153 else 67 end;

  if v_len <= v_single then
    return 1;
  end if;
  return ceil(v_len::numeric / v_multi)::integer;
end;
$$;

-- ---------------------------------------------------------------------------
-- Merge fields.
--
-- "Formatting" in an SMS is not bold or colour — the channel has none. It is
-- personalisation, so the body carries {{name}} / {{first_name}} and each
-- recipient's rendered text is STORED on their row rather than re-derived at
-- send time. Two reasons: the preview is then exactly what goes out, and the
-- campaign remains auditable after the fact even if the account is renamed.
--
-- An unknown placeholder is left alone rather than blanked, so a typo shows up
-- in the preview as "{{nmae}}" instead of vanishing silently.
-- ---------------------------------------------------------------------------
create or replace function public.fn_render_sms_body(p_body text, p_name text)
returns text
language sql
immutable
set search_path = public
as $$
  select replace(
           replace(coalesce(p_body, ''), '{{name}}', coalesce(nullif(trim(p_name), ''), 'there')),
           '{{first_name}}',
           coalesce(nullif(split_part(trim(coalesce(p_name, '')), ' ', 1), ''), 'there')
         );
$$;

-- ---------------------------------------------------------------------------
-- Suppression list — keyed on the PHONE, not on the profile.
--
-- A profiles.sms_opt_out column cannot hold the case that matters most here: a
-- number uploaded by CSV has no account, so there would be nowhere to record
-- that its owner asked to stop. Keying on the canonical number covers both, and
-- leaves exactly one place to look before spending money on a message.
-- ---------------------------------------------------------------------------
create table if not exists public.sms_suppressions (
  phone       text primary key,
  reason      text,
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  constraint sms_suppressions_phone_canonical
    check (phone ~ '^01[3-9][0-9]{8}$')
);

alter table public.sms_suppressions enable row level security;

-- Read-only to admins; every write goes through a definer function, so there is
-- no policy that admits an INSERT. Same shape as listing_availability_blocks.
drop policy if exists sms_suppressions_admin_read on public.sms_suppressions;
create policy sms_suppressions_admin_read on public.sms_suppressions
  for select to authenticated
  using (public.is_admin(auth.uid()));

-- ---------------------------------------------------------------------------
-- The campaign, and its recipients.
-- ---------------------------------------------------------------------------
create table if not exists public.sms_campaigns (
  id                uuid primary key default gen_random_uuid(),
  title             text not null,
  body              text not null,
  -- 'promotional' honours the suppression list; 'transactional' does not, and
  -- is for things like a service interruption notice that a user cannot
  -- meaningfully opt out of. It is NOT a way round the list for marketing.
  kind              text not null default 'promotional'
                      check (kind in ('promotional', 'transactional')),
  status            text not null default 'draft'
                      check (status in ('draft','queued','sending','sent','cancelled','failed')),
  -- What the admin selected, kept so a campaign can be explained later.
  audience          jsonb not null default '{}'::jsonb,
  created_by        uuid references public.profiles(id) on delete set null,
  total_recipients  integer not null default 0,
  sent_count        integer not null default 0,
  failed_count      integer not null default 0,
  encoding          text not null default 'gsm7',
  segments_each     integer not null default 1,
  created_at        timestamptz not null default now(),
  started_at        timestamptz,
  finished_at       timestamptz,
  error             text
);

create index if not exists idx_sms_campaigns_status
  on public.sms_campaigns (status, created_at desc);

create table if not exists public.sms_recipients (
  id              uuid primary key default gen_random_uuid(),
  campaign_id     uuid not null references public.sms_campaigns(id) on delete cascade,
  phone           text not null,
  msisdn          text not null,
  -- Null for a number that came from a CSV and matches no account.
  user_id         uuid references public.profiles(id) on delete set null,
  name            text,
  body_rendered   text not null,
  status          text not null default 'pending'
                    check (status in ('pending','sending','sent','failed','skipped')),
  skip_reason     text,
  attempts        integer not null default 0,
  provider_status text,
  provider_ref    text,
  error           text,
  claimed_at      timestamptz,
  sent_at         timestamptz,
  created_at      timestamptz not null default now()
);

-- **This index is the no-duplicates rule.** Not the compose form, which an
-- admin can drive twice, and not the audience query, which can overlap a CSV
-- upload. Adding the same number to one campaign twice is refused by the
-- database whatever the caller believes.
create unique index if not exists sms_recipients_campaign_phone
  on public.sms_recipients (campaign_id, phone);

-- The claim query's covering index: pending rows of one campaign, in order.
create index if not exists idx_sms_recipients_pending
  on public.sms_recipients (campaign_id, created_at, id)
  where status = 'pending';

alter table public.sms_campaigns  enable row level security;
alter table public.sms_recipients enable row level security;

drop policy if exists sms_campaigns_admin_read on public.sms_campaigns;
create policy sms_campaigns_admin_read on public.sms_campaigns
  for select to authenticated
  using (public.is_admin(auth.uid()));

drop policy if exists sms_recipients_admin_read on public.sms_recipients;
create policy sms_recipients_admin_read on public.sms_recipients
  for select to authenticated
  using (public.is_admin(auth.uid()));

-- No INSERT, UPDATE or DELETE policy on either table, deliberately. Every write
-- is a SECURITY DEFINER function with a service_role guard, so "who may send an
-- SMS" is one question answered in one place rather than a policy expression
-- that has to stay right as columns are added.

-- ---------------------------------------------------------------------------
-- The ceiling, as an admin setting.
--
-- **0 means DISABLED here, not unlimited — the opposite of
-- `max_devices_per_user` (125) and `android_min_version_code` (122), and the
-- inversion is on purpose.** Those two fail open because the harm they can do is
-- to lock a user out of an app they can only get back into via a real SMS. This
-- one fails CLOSED because the harm it can do is to spend money and text
-- thousands of people, and neither is retractable. There is no "unlimited"
-- value; a campaign larger than the ceiling is refused, not truncated.
--
-- Whoever copies this next: check which direction the damage runs before
-- copying the 0-means-no-limit idiom across.
-- ---------------------------------------------------------------------------
insert into public.app_settings (key, value, is_public)
values ('sms_bulk_max_recipients', '500', false)
on conflict (key) do nothing;

create or replace function public.fn_validate_setting_sms_max_recipients(p_value text)
returns void
language plpgsql
as $$
begin
  if p_value !~ '^[0-9]{1,6}$' then
    raise exception 'sms_bulk_max_recipients must be a whole number of recipients (0 disables bulk SMS)'
      using errcode = '22023';
  end if;
  if p_value::integer > 100000 then
    raise exception 'sms_bulk_max_recipients cannot exceed 100000'
      using errcode = '22023';
  end if;
end;
$$;

-- Recreated IN FULL, as CLAUDE.md requires: this is a CASE, so a patch that
-- drops an arm silently stops validating that key.
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
    else
      null;
  end case;
  return new;
end;
$$;

-- Read-side re-guard. Rows predate guards, and a malformed value must not be
-- able to raise inside the send path. Falls back to the seeded 500 rather than
-- to "no limit", because there is no no-limit here.
create or replace function public.sms_bulk_max_recipients()
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v text;
begin
  select value into v from public.app_settings where key = 'sms_bulk_max_recipients';
  if v is null or v !~ '^[0-9]{1,6}$' then
    return 500;
  end if;
  return least(v::integer, 100000);
end;
$$;

revoke all on function public.sms_bulk_max_recipients() from public, anon;
grant execute on function public.sms_bulk_max_recipients() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Writing a campaign. Every one of these carries the service_role guard that
-- every admin_* function in this schema carries — PostgREST publishes anything
-- in `public`, so the guard is the control and the grant is only a second lock.
-- ---------------------------------------------------------------------------
create or replace function public.fn_require_service_role()
returns void
language plpgsql
stable
set search_path = public
as $$
begin
  if current_setting('request.jwt.claims', true)::jsonb ->> 'role'
     is distinct from 'service_role' then
    raise exception 'Only service_role can execute this function'
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.fn_require_service_role() from public, anon, authenticated;

create or replace function public.admin_create_sms_campaign(
  p_title      text,
  p_body       text,
  p_kind       text,
  p_audience   jsonb,
  p_created_by uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  perform public.fn_require_service_role();

  if coalesce(trim(p_title), '') = '' then
    raise exception 'A campaign needs a title' using errcode = '22023';
  end if;
  if coalesce(trim(p_body), '') = '' then
    raise exception 'A campaign needs a message' using errcode = '22023';
  end if;
  if p_kind not in ('promotional', 'transactional') then
    raise exception 'Invalid campaign kind: %', p_kind using errcode = '22023';
  end if;

  insert into public.sms_campaigns (title, body, kind, audience, created_by,
                                    encoding, segments_each)
  values (trim(p_title), p_body, p_kind, coalesce(p_audience, '{}'::jsonb), p_created_by,
          public.fn_sms_encoding(p_body), public.fn_sms_segments(p_body))
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.admin_create_sms_campaign(text, text, text, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.admin_create_sms_campaign(text, text, text, jsonb, uuid)
  to service_role;

-- ---------------------------------------------------------------------------
-- Adding recipients.
--
-- Takes rows of {phone, name, user_id} and returns a per-reason count, so the
-- console can tell the admin exactly what it dropped and why rather than
-- quietly sending to fewer people than they picked. That report is the point:
-- "you selected 44, we will text 39" is information the admin needs BEFORE
-- committing, and it is the only place the dirty `profiles.mobile` data
-- becomes visible.
-- ---------------------------------------------------------------------------
create or replace function public.admin_add_sms_recipients(
  p_campaign_id uuid,
  p_rows        jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_campaign   public.sms_campaigns;
  v_row        jsonb;
  v_phone      text;
  v_name       text;
  v_user       uuid;
  v_added      integer := 0;
  v_invalid    integer := 0;
  v_duplicate  integer := 0;
  v_suppressed integer := 0;
  v_inserted   integer;
begin
  perform public.fn_require_service_role();

  select * into v_campaign from public.sms_campaigns where id = p_campaign_id;
  if not found then
    raise exception 'No such campaign' using errcode = '22023';
  end if;
  -- Recipients may only be added while the campaign has not gone out. Adding to
  -- a sending campaign would make the total a moving target and the admin's
  -- confirmed count a lie.
  if v_campaign.status <> 'draft' then
    raise exception 'Campaign is already %, recipients cannot be changed', v_campaign.status
      using errcode = '22023';
  end if;

  for v_row in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  loop
    v_phone := public.fn_canonical_bd_phone(v_row ->> 'phone');
    v_name  := nullif(trim(coalesce(v_row ->> 'name', '')), '');
    begin
      v_user := nullif(v_row ->> 'user_id', '')::uuid;
    exception when others then
      v_user := null;
    end;

    if v_phone is null then
      v_invalid := v_invalid + 1;
      continue;
    end if;

    -- A promotional campaign never reaches the suppression list. A
    -- transactional one may, and that is the only difference between them.
    if v_campaign.kind = 'promotional'
       and exists (select 1 from public.sms_suppressions s where s.phone = v_phone) then
      v_suppressed := v_suppressed + 1;
      continue;
    end if;

    insert into public.sms_recipients
      (campaign_id, phone, msisdn, user_id, name, body_rendered)
    values
      (p_campaign_id, v_phone, public.fn_msisdn(v_phone), v_user, v_name,
       public.fn_render_sms_body(v_campaign.body, v_name))
    on conflict (campaign_id, phone) do nothing;

    get diagnostics v_inserted = row_count;
    if v_inserted = 1 then
      v_added := v_added + 1;
    else
      -- The unique index caught it. This is the count that makes the four
      -- duplicated numbers on live visible instead of silently doubled.
      v_duplicate := v_duplicate + 1;
    end if;
  end loop;

  update public.sms_campaigns
     set total_recipients = (select count(*) from public.sms_recipients
                              where campaign_id = p_campaign_id)
   where id = p_campaign_id;

  return jsonb_build_object(
    'added', v_added,
    'invalid', v_invalid,
    'duplicate', v_duplicate,
    'suppressed', v_suppressed,
    'total', (select count(*) from public.sms_recipients where campaign_id = p_campaign_id)
  );
end;
$$;

revoke all on function public.admin_add_sms_recipients(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.admin_add_sms_recipients(uuid, jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- Starting a campaign — the moment it becomes irreversible.
--
-- Separate from composing it on purpose. Everything up to here is editable and
-- costs nothing; this is the one call that makes messages go out, so it is the
-- one place the ceiling is checked and the one thing the console asks the admin
-- to confirm by typing the recipient count.
-- ---------------------------------------------------------------------------
create or replace function public.admin_start_sms_campaign(p_campaign_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_campaign public.sms_campaigns;
  v_pending  integer;
  v_max      integer := public.sms_bulk_max_recipients();
begin
  perform public.fn_require_service_role();

  select * into v_campaign from public.sms_campaigns where id = p_campaign_id for update;
  if not found then
    raise exception 'No such campaign' using errcode = '22023';
  end if;
  -- Idempotent by status, so a double-submitted form cannot start one twice.
  if v_campaign.status <> 'draft' then
    raise exception 'Campaign is already %', v_campaign.status using errcode = '22023';
  end if;

  select count(*) into v_pending
    from public.sms_recipients where campaign_id = p_campaign_id and status = 'pending';

  if v_pending = 0 then
    raise exception 'This campaign has no recipients to send to' using errcode = '22023';
  end if;

  -- Refused, never truncated. Silently sending to the first 500 of 900 would
  -- leave the admin believing 900 were reached.
  if v_max = 0 then
    raise exception 'Bulk SMS is disabled (sms_bulk_max_recipients is 0)'
      using errcode = '22023';
  end if;
  if v_pending > v_max then
    raise exception 'This campaign has % recipients, above the current limit of %',
      v_pending, v_max using errcode = '22023';
  end if;

  update public.sms_campaigns
     set status = 'queued', started_at = now(), total_recipients = v_pending
   where id = p_campaign_id;

  return jsonb_build_object('queued', v_pending);
end;
$$;

revoke all on function public.admin_start_sms_campaign(uuid) from public, anon, authenticated;
grant execute on function public.admin_start_sms_campaign(uuid) to service_role;

-- Stops anything not yet sent. Rows already 'sent' are untouched — they are
-- gone, and a cancel that pretended otherwise would be a lie in the report.
create or replace function public.admin_cancel_sms_campaign(p_campaign_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stopped integer;
begin
  perform public.fn_require_service_role();

  update public.sms_recipients
     set status = 'skipped', skip_reason = 'campaign cancelled'
   where campaign_id = p_campaign_id and status = 'pending';
  get diagnostics v_stopped = row_count;

  update public.sms_campaigns
     set status = 'cancelled', finished_at = now()
   where id = p_campaign_id and status in ('draft', 'queued', 'sending');

  return jsonb_build_object('stopped', v_stopped);
end;
$$;

revoke all on function public.admin_cancel_sms_campaign(uuid) from public, anon, authenticated;
grant execute on function public.admin_cancel_sms_campaign(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- The worker's two calls: claim a batch, then report each result.
--
-- `for update skip locked` is what lets the cron sweep and an admin-triggered
-- run overlap safely — the second one takes the rows the first did not, instead
-- of blocking on them or, far worse, sending them again.
-- ---------------------------------------------------------------------------
create or replace function public.admin_claim_sms_batch(
  p_campaign_id uuid,
  p_limit       integer default 50
)
returns table (id uuid, msisdn text, body_rendered text)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.fn_require_service_role();

  update public.sms_campaigns
     set status = 'sending'
   where sms_campaigns.id = p_campaign_id and status = 'queued';

  return query
  update public.sms_recipients r
     set status = 'sending',
         claimed_at = now(),
         attempts = r.attempts + 1
   where r.id in (
     select c.id
       from public.sms_recipients c
      where c.campaign_id = p_campaign_id
        and c.status = 'pending'
      order by c.created_at, c.id
      limit greatest(1, least(coalesce(p_limit, 50), 200))
      for update skip locked
   )
  returning r.id, r.msisdn, r.body_rendered;
end;
$$;

revoke all on function public.admin_claim_sms_batch(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.admin_claim_sms_batch(uuid, integer) to service_role;

create or replace function public.admin_mark_sms_result(
  p_recipient_id    uuid,
  p_ok              boolean,
  p_provider_status text default null,
  p_provider_ref    text default null,
  p_error           text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_campaign uuid;
begin
  perform public.fn_require_service_role();

  update public.sms_recipients
     set status = case when p_ok then 'sent' else 'failed' end,
         sent_at = case when p_ok then now() else sent_at end,
         provider_status = p_provider_status,
         provider_ref = p_provider_ref,
         error = case when p_ok then null else p_error end
   where id = p_recipient_id
     and status = 'sending'
  returning campaign_id into v_campaign;

  if v_campaign is null then
    return;
  end if;

  -- Counters are recomputed rather than incremented, so a retried or
  -- hand-corrected row cannot drift them away from the recipient rows they
  -- summarise.
  update public.sms_campaigns c
     set sent_count   = s.sent,
         failed_count = s.failed,
         status = case
                    when c.status = 'cancelled' then 'cancelled'
                    when s.outstanding = 0 and s.sent = 0 then 'failed'
                    when s.outstanding = 0 then 'sent'
                    else c.status
                  end,
         finished_at = case when s.outstanding = 0 then now() else c.finished_at end
    from (
      select count(*) filter (where status = 'sent')                 as sent,
             count(*) filter (where status = 'failed')               as failed,
             count(*) filter (where status in ('pending','sending')) as outstanding
        from public.sms_recipients where campaign_id = v_campaign
    ) s
   where c.id = v_campaign;
end;
$$;

revoke all on function public.admin_mark_sms_result(uuid, boolean, text, text, text)
  from public, anon, authenticated;
grant execute on function public.admin_mark_sms_result(uuid, boolean, text, text, text)
  to service_role;

-- Retry is explicit, and only ever for rows the provider REFUSED. A row stuck
-- in 'sending' is deliberately not included: it may already have gone out, and
-- this feature's one promise is that nobody is texted twice.
create or replace function public.admin_retry_sms_failures(p_campaign_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  perform public.fn_require_service_role();

  update public.sms_recipients
     set status = 'pending', error = null, provider_status = null
   where campaign_id = p_campaign_id and status = 'failed';
  get diagnostics v_count = row_count;

  if v_count > 0 then
    update public.sms_campaigns
       set status = 'queued', finished_at = null
     where id = p_campaign_id;
  end if;

  return v_count;
end;
$$;

revoke all on function public.admin_retry_sms_failures(uuid) from public, anon, authenticated;
grant execute on function public.admin_retry_sms_failures(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Suppression.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_sms_suppression(
  p_phone   text,
  p_opt_out boolean,
  p_reason  text default null,
  p_actor   uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.fn_canonical_bd_phone(p_phone);
begin
  perform public.fn_require_service_role();

  if v_phone is null then
    raise exception 'Not a valid Bangladeshi mobile number: %', p_phone
      using errcode = '22023';
  end if;

  if p_opt_out then
    insert into public.sms_suppressions (phone, reason, created_by)
    values (v_phone, p_reason, p_actor)
    on conflict (phone) do update set reason = excluded.reason;
  else
    delete from public.sms_suppressions where phone = v_phone;
  end if;

  return p_opt_out;
end;
$$;

revoke all on function public.admin_set_sms_suppression(text, boolean, text, uuid)
  from public, anon, authenticated;
grant execute on function public.admin_set_sms_suppression(text, boolean, text, uuid)
  to service_role;

-- ---------------------------------------------------------------------------
-- Who a campaign would reach.
--
-- The console calls this to count and to preview before anything is created, so
-- the number the admin confirms is produced by the same code that later builds
-- the queue.
--
-- **The phone comes from the auth identity first, `profiles.mobile` second.**
-- The identity is the number that actually received an OTP, so it is known
-- deliverable; `mobile` is typed and displayed and, on live today, holds one
-- placeholder string and one number with an unassigned prefix. Where both
-- exist they normally canonicalise to the same thing — the identity just wins
-- the cases where they do not.
--
-- `distinct on (phone)` is the second half of the deduplication. The unique
-- index catches whatever gets past this; this is what makes the count honest
-- before the admin commits.
-- ---------------------------------------------------------------------------
create or replace function public.admin_sms_audience(p_filters jsonb default '{}'::jsonb)
returns table (
  user_id      uuid,
  full_name    text,
  phone        text,
  suppressed   boolean
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  perform public.fn_require_service_role();

  return query
  select distinct on (c.phone)
         c.id,
         c.full_name,
         c.phone,
         exists (select 1 from public.sms_suppressions s where s.phone = c.phone)
    from (
      select p.id,
             p.full_name,
             coalesce(
               public.fn_canonical_bd_phone(
                 substring(u.email from '^phone\.([0-9]+)@musaafir\.app$')),
               public.fn_canonical_bd_phone(p.mobile)
             ) as phone,
             p.role::text as role,
             p.is_host,
             p.verification_status::text as verification_status,
             p.created_at
        from public.profiles p
        left join auth.users u on u.id = p.id
    ) c
   where c.phone is not null
     and (p_filters ->> 'role' is null
          or c.role = p_filters ->> 'role')
     and (p_filters ->> 'is_host' is null
          or c.is_host = (p_filters ->> 'is_host')::boolean)
     and (p_filters ->> 'verification_status' is null
          or c.verification_status = p_filters ->> 'verification_status')
     and (p_filters ->> 'joined_from' is null
          or c.created_at >= (p_filters ->> 'joined_from')::timestamptz)
     and (p_filters ->> 'joined_to' is null
          or c.created_at <= (p_filters ->> 'joined_to')::timestamptz)
     -- An explicit list of ids, for "select some users" rather than a filter.
     and (p_filters -> 'user_ids' is null
          or c.id = any (select (jsonb_array_elements_text(p_filters -> 'user_ids'))::uuid))
   -- Ties between two accounts sharing a number resolve to the older one, so
   -- repeating the same query gives the same answer.
   order by c.phone, c.created_at, c.id;
end;
$$;

revoke all on function public.admin_sms_audience(jsonb) from public, anon, authenticated;
grant execute on function public.admin_sms_audience(jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- The sweep.
--
-- The console invokes the worker directly when an admin presses Send, which is
-- what makes it feel immediate. This is the half that makes it reliable: a
-- campaign whose worker died mid-batch has pending rows and nothing scheduled
-- to look at them again, and without this it would sit half-sent until somebody
-- noticed.
--
-- Same shape as DeviceSessionWatcher — the direct call is promptness, the
-- periodic one is the guarantee. Every minute rather than 126's daily, because
-- the thing it is recovering is a campaign an admin is watching.
-- ---------------------------------------------------------------------------
create or replace function public.sweep_sms_campaigns()
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url    text;
  v_secret text;
  v_auth   text;
  v_row    record;
  v_count  integer := 0;
begin
  select value into v_url    from public.app_secrets where key = 'sms_worker_url';
  select value into v_secret from public.app_secrets where key = 'sms_worker_secret';
  select value into v_auth   from public.app_secrets where key = 'sms_worker_auth';

  -- Unconfigured is a no-op, not an error: this runs every minute and a cron
  -- job that raises is a job that stops running.
  if coalesce(v_url, '') = '' or coalesce(v_secret, '') = ''
     or coalesce(v_auth, '') = '' then
    return 0;
  end if;

  for v_row in
    select c.id
      from public.sms_campaigns c
     where c.status in ('queued', 'sending')
       and exists (select 1 from public.sms_recipients r
                    where r.campaign_id = c.id and r.status = 'pending')
  loop
    -- **BOTH headers are required, and they do different jobs.**
    --
    -- The Authorization bearer satisfies the edge-function GATEWAY, which
    -- rejects a request with no auth header before any of our code runs
    -- (`UNAUTHORIZED_NO_AUTH_HEADER`, verified against live). It is the
    -- project's anon key — public, since it ships inside build/web — so it
    -- proves nothing about the caller.
    --
    -- `x-sms-worker-secret` is therefore the real authentication, checked in
    -- constant time inside the function. Sending only the first would let
    -- anyone holding the public key drive this endpoint; sending only the
    -- second gets a silent 401 from the gateway every minute and the sweep —
    -- the half that GUARANTEES a campaign finishes — never runs at all.
    --
    -- `send_push_on_notification_insert` has the same pair for the same reason.
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_auth,
        'x-sms-worker-secret', v_secret
      ),
      body := jsonb_build_object('campaignId', v_row.id)
    );
    v_count := v_count + 1;
  end loop;

  return v_count;
exception when others then
  raise warning 'sweep_sms_campaigns failed: %', sqlerrm;
  return 0;
end;
$$;

revoke all on function public.sweep_sms_campaigns() from public, anon, authenticated;

-- Guarded, the same way 126 guards its schedule: pg_cron may not be installed
-- on a plain Postgres, and a migration that dies there is a migration that
-- cannot be applied anywhere else.
do $$
begin
  perform cron.unschedule('sweep-sms-campaigns');
exception when others then
  null;
end $$;

do $$
begin
  perform cron.schedule(
    'sweep-sms-campaigns',
    '* * * * *',
    $cron$select public.sweep_sms_campaigns();$cron$
  );
exception when others then
  raise notice 'pg_cron not available; sweep-sms-campaigns not scheduled: %', sqlerrm;
end $$;

comment on table public.sms_campaigns is
  'One bulk SMS send. Composed as draft, made irreversible by '
  'admin_start_sms_campaign. See docs/BULK_SMS.md.';
comment on table public.sms_recipients is
  'One row per number per campaign. The unique index on (campaign_id, phone) '
  'is what makes a duplicate send impossible; claim-before-send is what makes '
  'a crash lose a message rather than repeat one.';
