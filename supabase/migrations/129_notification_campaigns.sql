-- =============================================
-- 129 — bulk in-app / push notifications from the admin console
--
-- The notification sibling of 128. Deliberately NOT the same machinery, because
-- the problem is not the same shape:
--
--   • **Delivery already exists.** `on_notification_send_push` fires a push for
--     every row inserted into `notifications`, so a campaign is one
--     `insert … select`, not a queue drained by a worker. No claim step, no
--     cron sweep, no provider to be refused by.
--   • **It is free.** No per-message cost, so the ceiling exists to stop a
--     mistake reaching everyone, not to stop a bill.
--   • **`user_id` is the key, not a phone.** There is nothing to canonicalise
--     and nothing to deduplicate across spellings — a primary key does that.
--     All 44 accounts are reachable here, where only 38 have a usable number.
--   • **A user with no push token still gets the notification.** The row is the
--     product; the push is one way of announcing it. The console says how many
--     of each, rather than pretending the two numbers are one.
--
-- ---------------------------------------------------------------------------
-- What this fixes on the way past, and what it deliberately does not
--
-- `notification_preferences` has existed all along — `global_enabled`, quiet
-- hours, and per-category `enabled` / `channels` — and `send-push-notification`
-- **references none of it**. `NotificationPreferences.shouldDeliver` in
-- lib/models/notification_preferences.dart is a client-side read, and the push
-- goes out regardless. That is the "the booking form checks it" pattern again,
-- one level down.
--
-- This migration honours those preferences for BULK campaigns only, at the
-- point the rows are created. It does **not** change what happens to a booking
-- confirmation or a new-message alert: retrofitting the whole notification
-- system is a bigger change than this, and doing it silently inside a feature
-- about marketing blasts would be the wrong place to find out it broke.
--
-- The distinction that makes that defensible: a booking alert is something the
-- user asked for by using the app. A bulk campaign is the exact thing those
-- preference toggles were built to refuse.
-- =============================================

-- ---------------------------------------------------------------------------
-- Which preference category a notification type belongs to.
--
-- The SQL twin of `NotificationType.category` in lib/models/notification.dart.
-- Every value of the enum must map to something: `category_preferences` is
-- keyed by these strings, so a type that mapped to null would silently ignore
-- the user's setting rather than fail.
--
-- **The two enums have already drifted.** `notification_type` in the database
-- carries `booking_rejected`, `checked_in` and `review_prompt`, which the Dart
-- enum does not have at all — so its `switch` never had to consider them. They
-- are mapped here by meaning. A test asserts that EVERY label of the live enum
-- resolves, so the next value added fails loudly instead of quietly opting its
-- recipients out of their own preferences.
-- ---------------------------------------------------------------------------
create or replace function public.fn_notification_category(p_type public.notification_type)
returns text
language sql
immutable
set search_path = public
as $$
  select case p_type
    when 'booking_request'    then 'booking'
    when 'booking_confirmed'  then 'booking'
    when 'booking_cancelled'  then 'booking'
    when 'booking_reminder'   then 'booking'
    when 'booking_rejected'   then 'booking'
    when 'check_in_reminder'  then 'booking'
    when 'check_out_reminder' then 'booking'
    when 'checked_in'         then 'booking'
    when 'payment_received'   then 'payment'
    when 'payment_failed'     then 'payment'
    when 'refund_processed'   then 'payment'
    when 'review_received'    then 'review'
    when 'review_reminder'    then 'review'
    when 'review_prompt'      then 'review'
    when 'promotion_available' then 'promotion'
    when 'discount_expiring'  then 'promotion'
    when 'referral_reward'    then 'promotion'
    when 'new_message'        then 'message'
    when 'message_read'       then 'message'
    when 'system_alert'       then 'system'
    when 'account_update'     then 'system'
    when 'security_alert'     then 'system'
  end;
$$;

-- Not SECURITY DEFINER and it leaks nothing — the mapping is a constant, and
-- the same one is compiled into build/web. Revoked anyway: PostgREST publishes
-- everything in `public`, and a reachable endpoint nobody calls is exactly the
-- class of thing 116 had to go round cleaning up. Callers here are all
-- SECURITY DEFINER functions running as postgres.
revoke all on function public.fn_notification_category(public.notification_type)
  from public, anon, authenticated;

comment on function public.fn_notification_category(public.notification_type) is
  'Twin of NotificationType.category in lib/models/notification.dart. Must '
  'cover every enum label — 129 s test fails if a new one is added without a '
  'mapping, because an unmapped type silently ignores user preferences.';

-- ---------------------------------------------------------------------------
-- The campaign record.
-- ---------------------------------------------------------------------------
create table if not exists public.notification_campaigns (
  id               uuid primary key default gen_random_uuid(),
  title            text not null,
  body             text not null,
  type             public.notification_type not null default 'system_alert',
  priority         public.notification_priority not null default 'normal',
  action_url       text,
  audience         jsonb not null default '{}'::jsonb,
  created_by       uuid references public.profiles(id) on delete set null,
  -- Three different numbers, kept apart on purpose: how many rows were
  -- created, how many of those also fired a push, and how many people were
  -- left out because their own settings said so.
  total_recipients integer not null default 0,
  pushed_count     integer not null default 0,
  skipped_count    integer not null default 0,
  created_at       timestamptz not null default now(),
  sent_at          timestamptz
);

create index if not exists idx_notification_campaigns_created
  on public.notification_campaigns (created_at desc);

-- Lets a campaign be looked at after the fact, and is what the counts are
-- recomputed from. Nullable: every notification the app itself raises has no
-- campaign, which is the overwhelming majority of the 787 rows already there.
alter table public.notifications
  add column if not exists campaign_id uuid
    references public.notification_campaigns(id) on delete set null;

create index if not exists idx_notifications_campaign
  on public.notifications (campaign_id)
  where campaign_id is not null;

alter table public.notification_campaigns enable row level security;

drop policy if exists notification_campaigns_admin_read on public.notification_campaigns;
create policy notification_campaigns_admin_read on public.notification_campaigns
  for select to authenticated
  using (public.is_admin(auth.uid()));

-- ---------------------------------------------------------------------------
-- Suppressing the push without suppressing the notification.
--
-- A user whose preferences say the promotion category is `inApp` only still
-- wants the notification — they just do not want their phone to buzz. The
-- trigger had no way to express that, because it pushes on every insert.
--
-- **Additive by construction**: the key is absent from all 787 existing rows
-- (checked, not assumed) and nothing else writes it, so every notification the
-- app already raises behaves exactly as before. That is the whole reason this
-- is a data flag rather than a rewrite of the trigger's logic — a trigger that
-- started consulting preferences for ALL notifications would change booking and
-- message delivery as a side effect of a marketing feature.
-- ---------------------------------------------------------------------------
create or replace function public.send_push_on_notification_insert()
returns trigger
language plpgsql
security definer
as $$
begin
  -- The one new line. Everything below is 018's body, unchanged.
  if coalesce(new.data ->> 'suppress_push', '') = 'true' then
    return new;
  end if;

  perform net.http_post(
    url := 'https://bojkmonskqlhuakxhzcb.supabase.co/functions/v1/send-push-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      -- Unchanged from 018's live body, character for character. This trigger
      -- delivers every push in the app; the only edit this migration makes to
      -- it is the suppress_push guard above. Re-pointing this header at
      -- app_secrets would mean a deleted row silently kills ALL push.
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJvamttb25za3FsaHVha3hoemNiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDcwNTcwMTQsImV4cCI6MjA2MjYzMzAxNH0.gPd0QWSQ2XNjBccqEST97fqAV2HP9NMqwShTqpJlilk',
      'x-push-secret',
      coalesce((select value from public.app_secrets where key = 'push_secret'), '')
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
$$;

-- ---------------------------------------------------------------------------
-- The ceiling. Same fail-closed reasoning as `sms_bulk_max_recipients` (128) —
-- 0 DISABLES bulk notifications, it does not mean unlimited. Seeded higher than
-- the SMS cap because these cost nothing; the limit is against a mistake
-- reaching everyone, not against a bill.
-- ---------------------------------------------------------------------------
insert into public.app_settings (key, value, is_public)
values ('notification_bulk_max_recipients', '2000', false)
on conflict (key) do nothing;

create or replace function public.fn_validate_setting_notification_max_recipients(p_value text)
returns void
language plpgsql
as $$
begin
  if p_value !~ '^[0-9]{1,6}$' then
    raise exception 'notification_bulk_max_recipients must be a whole number (0 disables bulk notifications)'
      using errcode = '22023';
  end if;
  if p_value::integer > 100000 then
    raise exception 'notification_bulk_max_recipients cannot exceed 100000'
      using errcode = '22023';
  end if;
end;
$$;

-- Recreated IN FULL. It is a CASE; a patch that drops an arm silently stops
-- validating that key.
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
    else
      null;
  end case;
  return new;
end;
$$;

create or replace function public.notification_bulk_max_recipients()
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v text;
begin
  select value into v from public.app_settings
   where key = 'notification_bulk_max_recipients';
  if v is null or v !~ '^[0-9]{1,6}$' then
    return 2000;
  end if;
  return least(v::integer, 100000);
end;
$$;

revoke all on function public.notification_bulk_max_recipients() from public, anon;
grant execute on function public.notification_bulk_max_recipients()
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Who a campaign would reach, and what each of them would actually get.
--
-- **`notification_preferences` is LEFT joined, and that is load-bearing.** Only
-- ONE of 44 accounts has a row; an inner join would quietly reduce every
-- campaign to a single recipient. An absent row means the app's defaults —
-- enabled, both channels — exactly as `getForCategory` returns
-- `const CategoryPreferences()` for a missing key.
--
-- Three separate answers per person, because they are three different facts:
--   • `delivers`     — do they get the notification at all?
--   • `push_allowed` — should it also buzz their phone?
--   • `has_token`    — could it, even if allowed? (29 of 44 have one.)
-- ---------------------------------------------------------------------------
create or replace function public.admin_notify_audience(
  p_filters jsonb default '{}'::jsonb,
  p_type    public.notification_type default 'system_alert',
  p_priority public.notification_priority default 'normal'
)
returns table (
  user_id      uuid,
  full_name    text,
  role         text,
  delivers     boolean,
  push_allowed boolean,
  has_token    boolean,
  skip_reason  text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cat text := public.fn_notification_category(p_type);
  -- Bangladesh-only product, and `quiet_hours_start/end` are `time` with no
  -- zone, so there is nothing else they could sensibly mean.
  v_local time := (now() at time zone 'Asia/Dhaka')::time;
begin
  perform public.fn_require_service_role();

  return query
  with candidate as (
    select p.id,
           p.full_name,
           p.role::text as role,
           p.is_host,
           p.verification_status::text as verification_status,
           p.created_at,
           coalesce(np.global_enabled, true) as global_enabled,
           coalesce((np.category_preferences -> v_cat ->> 'enabled')::boolean, true)
             as category_enabled,
           -- Absent channels key -> app default, which includes push.
           coalesce(np.category_preferences -> v_cat -> 'channels' ? 'push', true)
             as push_channel,
           coalesce(np.quiet_hours_enabled, false) as quiet_on,
           coalesce(np.quiet_hours_allow_urgent, true) as quiet_allows_urgent,
           np.quiet_hours_start,
           np.quiet_hours_end,
           exists (select 1 from public.fcm_tokens f
                    where f.user_id = p.id and f.is_active) as has_token
      from public.profiles p
      left join public.notification_preferences np on np.user_id = p.id
  ),
  scoped as (
    select c.*,
           -- The default window is 22:00–07:00, which CROSSES MIDNIGHT — so
           -- a plain BETWEEN is wrong for exactly the case that matters and
           -- would leave the small-hours push it exists to prevent.
           (c.quiet_on and (
              case when c.quiet_hours_start <= c.quiet_hours_end
                   then v_local between c.quiet_hours_start and c.quiet_hours_end
                   else v_local >= c.quiet_hours_start or v_local <= c.quiet_hours_end
              end))
             and not (p_priority = 'urgent' and c.quiet_allows_urgent) as in_quiet_hours
      from candidate c
     where (p_filters ->> 'role' is null or c.role = p_filters ->> 'role')
       and (p_filters ->> 'is_host' is null
            or c.is_host = (p_filters ->> 'is_host')::boolean)
       and (p_filters ->> 'verification_status' is null
            or c.verification_status = p_filters ->> 'verification_status')
       and (p_filters ->> 'joined_from' is null
            or c.created_at >= (p_filters ->> 'joined_from')::timestamptz)
       and (p_filters ->> 'joined_to' is null
            or c.created_at <= (p_filters ->> 'joined_to')::timestamptz)
       and (p_filters -> 'user_ids' is null
            or c.id = any (select (jsonb_array_elements_text(p_filters -> 'user_ids'))::uuid))
  )
  select s.id,
         s.full_name,
         s.role,
         (s.global_enabled and s.category_enabled) as delivers,
         (s.global_enabled and s.category_enabled and s.push_channel
            and s.has_token and not s.in_quiet_hours) as push_allowed,
         s.has_token,
         case
           when not s.global_enabled  then 'notifications turned off'
           when not s.category_enabled then v_cat || ' notifications turned off'
           when not s.push_channel    then 'in-app only, by their choice'
           when s.in_quiet_hours      then 'quiet hours — in-app only'
           when not s.has_token       then 'no device registered — in-app only'
           else null
         end as skip_reason
    from scoped s
   order by s.full_name nulls last, s.id;
end;
$$;

revoke all on function public.admin_notify_audience(jsonb, public.notification_type, public.notification_priority)
  from public, anon, authenticated;
grant execute on function public.admin_notify_audience(jsonb, public.notification_type, public.notification_priority)
  to service_role;

-- ---------------------------------------------------------------------------
-- Sending.
--
-- **One statement, one transaction, no queue.** Everything the SMS version
-- needs a worker and a cron sweep for is unnecessary here: the rows either all
-- land or none do, and the push is the existing trigger's job. There is no
-- partway state to recover from, which is why there is no `status` column on a
-- notification campaign and no retry.
--
-- The duplicate protection the SMS side gets from a unique index comes free —
-- `admin_notify_audience` selects from `profiles`, so one row per account is
-- guaranteed by its primary key. Calling this twice sends twice, exactly as
-- pressing send twice should; it is the confirmation step in the console that
-- guards against that, not the database.
-- ---------------------------------------------------------------------------
create or replace function public.admin_send_bulk_notification(
  p_title      text,
  p_body       text,
  p_type       public.notification_type,
  p_priority   public.notification_priority,
  p_action_url text,
  p_filters    jsonb,
  p_created_by uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_campaign uuid;
  v_max      integer := public.notification_bulk_max_recipients();
  v_total    integer;
  v_pushed   integer;
  v_skipped  integer;
begin
  perform public.fn_require_service_role();

  if coalesce(trim(p_title), '') = '' then
    raise exception 'A notification needs a title' using errcode = '22023';
  end if;
  if coalesce(trim(p_body), '') = '' then
    raise exception 'A notification needs a message' using errcode = '22023';
  end if;

  -- Hold the audience still for the whole call. Reading it twice — once to
  -- count, once to insert — could answer differently if somebody changed their
  -- preferences in between, and the admin confirmed the first number.
  --
  -- Dropped first, not just `on commit drop`. Every raise below happens AFTER
  -- the table exists, so a caught exception leaves it behind and the next call
  -- in the SAME transaction dies with "relation already exists" — invisible in
  -- production, where each call is its own transaction, and immediate in any
  -- test that exercises a refusal and then a success.
  drop table if exists t_audience;
  create temp table t_audience on commit drop as
    select * from public.admin_notify_audience(p_filters, p_type, p_priority);

  select count(*) filter (where delivers),
         count(*) filter (where push_allowed),
         count(*) filter (where not delivers)
    into v_total, v_pushed, v_skipped
    from t_audience;

  if v_total = 0 then
    raise exception 'Nobody in this audience would receive it' using errcode = '22023';
  end if;
  if v_max = 0 then
    raise exception 'Bulk notifications are disabled (notification_bulk_max_recipients is 0)'
      using errcode = '22023';
  end if;
  -- Refused, never truncated: sending to the first 2000 of 3000 would leave the
  -- admin believing everyone was reached.
  if v_total > v_max then
    raise exception 'This campaign has % recipients, above the current limit of %',
      v_total, v_max using errcode = '22023';
  end if;

  insert into public.notification_campaigns
    (title, body, type, priority, action_url, audience, created_by,
     total_recipients, pushed_count, skipped_count, sent_at)
  values
    (trim(p_title), p_body, p_type, p_priority, nullif(trim(coalesce(p_action_url,'')), ''),
     coalesce(p_filters, '{}'::jsonb), p_created_by,
     v_total, v_pushed, v_skipped, now())
  returning id into v_campaign;

  -- `suppress_push` is set per recipient, so one campaign can buzz the phones
  -- of people who allow it while still reaching the in-app inbox of those who
  -- asked for in-app only. Row-level, because the preference is.
  insert into public.notifications
    (user_id, type, title, body, priority, action_url, campaign_id, data)
  select a.user_id,
         p_type,
         trim(p_title),
         p_body,
         p_priority,
         nullif(trim(coalesce(p_action_url,'')), ''),
         v_campaign,
         jsonb_build_object(
           'campaign_id', v_campaign::text,
           'suppress_push', (not a.push_allowed)
         )
    from t_audience a
   where a.delivers;

  drop table if exists t_audience;

  return jsonb_build_object(
    'campaign_id', v_campaign,
    'total', v_total,
    'pushed', v_pushed,
    'skipped', v_skipped
  );
end;
$$;

revoke all on function public.admin_send_bulk_notification(
  text, text, public.notification_type, public.notification_priority, text, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.admin_send_bulk_notification(
  text, text, public.notification_type, public.notification_priority, text, jsonb, uuid)
  to service_role;

comment on table public.notification_campaigns is
  'One bulk notification send. Unlike sms_campaigns there is no queue: delivery '
  'is the existing on_notification_send_push trigger, so the whole campaign is '
  'one insert. See docs/BULK_SMS.md and 129 for why the two differ.';
