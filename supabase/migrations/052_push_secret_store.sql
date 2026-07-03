-- =============================================================
-- 052 — Store the push shared secret in a locked-down table
--
-- Managed Supabase does not allow `ALTER DATABASE ... SET` (superuser only),
-- so the push secret cannot live in a GUC (current_setting('app.push_secret')).
-- Instead keep it in a table that NO client role can read — only the
-- SECURITY DEFINER delivery trigger (which bypasses RLS) and the dashboard
-- SQL editor (postgres/service_role) can touch it. The secret value itself is
-- inserted out-of-band via the SQL editor, so it never lands in git.
-- =============================================================

create table if not exists public.app_secrets (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.app_secrets enable row level security;

-- No SELECT/INSERT/UPDATE/DELETE policies are defined, so anon/authenticated
-- clients get zero access. Revoke the default grants for good measure.
revoke all on public.app_secrets from anon;
revoke all on public.app_secrets from authenticated;

-- Read the push secret from the table instead of a database GUC.
create or replace function send_push_on_notification_insert()
returns trigger as $$
begin
  perform net.http_post(
    url := 'https://bojkmonskqlhuakxhzcb.supabase.co/functions/v1/send-push-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
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
$$ language plpgsql security definer;
