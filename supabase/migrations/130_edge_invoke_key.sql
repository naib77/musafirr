-- =============================================
-- 130 — stop hardcoding the key that lets the database call an edge function
--
-- **Push notifications had been silently dead.** Every insert into
-- `notifications` fires `send_push_on_notification_insert`, which POSTs to the
-- `send-push-notification` function with an `Authorization` bearer written as a
-- literal in migration 018. That key was later rotated, and the literal was not.
-- Since then the platform gateway has rejected every one of those calls:
--
--     HTTP 401 {"code":"UNAUTHORIZED_LEGACY_JWT","message":"Invalid JWT"}
--
-- Proven rather than inferred: the same request sent with the key baked into
-- the trigger is refused by the GATEWAY, while the project's current anon key
-- gets through it and is then answered by the function's own guard. 28 such
-- failures are sitting in `net._http_response` from one bulk campaign alone.
--
-- Nothing surfaced it, and that is the point. The trigger wraps its own body in
-- `exception when others` and `net.http_post` is fire-and-forget, so a total
-- outage of push looks exactly like a quiet week — the in-app inbox kept
-- filling correctly the whole time.
--
-- The fix is not "paste the new key in". A literal credential in a function
-- body has no way to be rotated with the thing it mirrors, so it is guaranteed
-- to go stale again the next time somebody rolls a key. It moves to
-- `app_secrets`, where `push_secret` already lives, and BOTH callers read the
-- same row — so there is one place to update and no second copy to drift.
--
-- Trade-off, stated because it is real: if that row is deleted, push stops.
-- That is strictly better than today, where push stops on its own and the only
-- way to notice is to go looking in pg_net. A missing row is also fixable with
-- an INSERT rather than a migration.
-- =============================================

-- Seeded by COPYING the value already proven good — `sms_worker_auth` was set
-- from the current anon key when 128 shipped and is what makes the SMS sweep
-- return 200 where push returns 401. No key material is typed into this file.
insert into public.app_secrets (key, value)
select 'edge_invoke_key', value
  from public.app_secrets
 where key = 'sms_worker_auth'
on conflict (key) do update set value = excluded.value, updated_at = now();

-- ---------------------------------------------------------------------------
-- The push trigger. Body is 018's, plus 129's suppress_push guard, with the
-- one literal replaced by a lookup.
-- ---------------------------------------------------------------------------
create or replace function public.send_push_on_notification_insert()
returns trigger
language plpgsql
security definer
as $$
declare
  v_auth text;
begin
  -- 129: a recipient whose preferences say in-app only still gets the row.
  if coalesce(new.data ->> 'suppress_push', '') = 'true' then
    return new;
  end if;

  select value into v_auth from public.app_secrets where key = 'edge_invoke_key';

  -- Loud, because the silent version of this cost the app every push it should
  -- have sent. A warning cannot fail the insert — the notification must still
  -- reach the in-app inbox whatever the delivery layer is doing.
  if coalesce(v_auth, '') = '' then
    raise warning 'push not sent: app_secrets.edge_invoke_key is missing or empty';
    return new;
  end if;

  perform net.http_post(
    url := 'https://bojkmonskqlhuakxhzcb.supabase.co/functions/v1/send-push-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_auth,
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
-- The SMS sweep reads the same row, so there is one key rather than two that
-- can disagree. 128's reasoning for needing BOTH headers is unchanged: the
-- bearer satisfies the gateway and proves nothing, the worker secret is the
-- real authentication.
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
  select value into v_auth   from public.app_secrets where key = 'edge_invoke_key';

  if coalesce(v_url,'') = '' or coalesce(v_secret,'') = '' or coalesce(v_auth,'') = '' then
    return 0;
  end if;

  for v_row in
    select c.id
      from public.sms_campaigns c
     where c.status in ('queued', 'sending')
       and exists (select 1 from public.sms_recipients r
                    where r.campaign_id = c.id and r.status = 'pending')
  loop
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

-- One key, one row. Leaving the old name behind would be a second copy free to
-- drift, which is the whole bug this migration exists to close.
delete from public.app_secrets where key = 'sms_worker_auth';

comment on function public.send_push_on_notification_insert() is
  'Delivers every push in the app. The edge-function bearer comes from '
  'app_secrets.edge_invoke_key — NEVER hardcode it: the literal in 018 was '
  'rotated out and push failed silently until 130.';
