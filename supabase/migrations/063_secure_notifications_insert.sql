-- 063 — Remove the spoofable client INSERT policy on notifications (MEDIUM)
--
-- `notifications_insert_service` was `with check (true)`, so any client could
-- insert notification rows for ANY user_id (phishing / spam into other users'
-- notification feeds). All real notifications are created by SECURITY DEFINER
-- triggers (booking lifecycle, messaging, etc.) which bypass RLS, and the
-- client's NotificationService.createNotification has no callers. So no
-- legitimate client insert exists — drop the policy.
--
-- RLS stays enabled; with no INSERT policy, clients cannot insert, while the
-- SECURITY DEFINER trigger functions continue to insert unaffected.

drop policy if exists "notifications_insert_service" on public.notifications;
revoke insert on public.notifications from anon, authenticated;
