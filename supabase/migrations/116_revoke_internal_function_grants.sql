-- 116: take EXECUTE away from the API roles on functions that were never meant
-- to be callable from a browser.
--
-- Found while working through the Security Advisor after 115. The advisor
-- reports 124 `{anon,authenticated}_security_definer_function_executable`
-- findings; most are by design (see the keep-list at the bottom). These are
-- not, and one of them is an account takeover.
--
-- ── The critical one: otp_log_send ────────────────────────────────────────
--
-- SECURITY DEFINER, no caller check, EXECUTE held by anon, and it inserts a
-- row into otp_attempts with a *caller-supplied* hash:
--
--     insert into public.otp_attempts (phone, otp_hash, expires_at)
--     values (p_phone, p_otp_hash, p_expires_at)
--
-- `hashOtp` in supabase/functions/_shared/otp.ts is an unsalted, unpeppered
-- SHA-256 of the code itself, so the hash for any code is a public constant.
-- And verify-otp picks its row with
--
--     .order("created_at", { ascending: false }).limit(1)
--
-- so a row inserted just now WINS over the genuine code that was actually
-- texted. The whole chain, with nothing but the anon key that ships inside the
-- web bundle:
--
--   1. compute sha256("1234")
--   2. POST /rest/v1/rpc/otp_log_send  {victim phone, that hash, future expiry}
--   3. POST /functions/v1/verify-otp   {victim phone, "1234"}
--   4. verify-otp matches, calls admin.generateLink, returns a token_hash
--   5. redeem it -> authenticated session as the victim
--
-- Step 2 was verified against live and answered HTTP 200 with a row id (the
-- row was for a nonexistent phone and was deleted immediately; the chain was
-- NOT completed). Any account, including an admin's. No SMS, no guessing, and
-- unrelated to the master-OTP allowlist in CLAUDE.md — that at least needs the
-- number to be allowlisted, this needs nothing.
--
-- otp_log_attempts is the same shape and defeats the rate limit on its own: it
-- sets otp_attempts.attempts to any value the caller likes, so OTP_MAX_ATTEMPTS
-- never trips and a 4-digit code (keyspace 10,000) is brute-forceable.
--
-- Safe to revoke because the live login path does not use these. Both OTP edge
-- functions build their client with SUPABASE_SERVICE_ROLE_KEY and reach
-- otp_attempts through PostgREST directly, calling none of these RPCs. The
-- callers in lib/services/otp_service.dart sit behind
-- `OtpState._useSupabase => SupabaseConfig.isConfigured`, which is true in
-- every shipped build, so that branch is the mock path and cannot run in
-- production. service_role keeps EXECUTE regardless.
--
-- ── The rest: scheduled jobs with no caller ──────────────────────────────
--
-- These are cron/maintenance functions that transition business state, and
-- anyone on the internet could fire them:
--
--   auto_complete_elapsed_bookings   completes stays -> earnings/payout state
--   expire_stale_bookings            cancels pending bookings
--   auto_reveal_old_reviews          breaks the double-blind window early
--   send_pre_checkin_messages        mass-sends guest messages
--   send_review_reminders            mass-sends guest messages
--   send_checkout_for_booking        messages for an ARBITRARY booking id
--   send_booking_contacts            posts BOTH parties' phone numbers into
--                                    the conversation for an arbitrary booking
--   capture_monthly_leaderboard_snapshot / migrate_conversation_participants
--                                    re-runnable writes, one a one-off backfill
--
-- The `admin_*` trio is deliberately NOT here: admin_expire_bookings,
-- admin_auto_complete_bookings and admin_reveal_reviews each raise
-- "Only service_role can execute this function" internally, which was
-- confirmed live (P0001 as anon). They defend themselves; these do not.
--
-- get_conversation_participants takes a conversation id and checks nothing, so
-- it lists the members of any conversation to anyone.
--
-- ── Revoking from anon is not enough on its own ──────────────────────────
--
-- Every one of these carries BOTH an explicit `anon=X/postgres` (Supabase's
-- ALTER DEFAULT PRIVILEGES on schema public grants it at CREATE time) and, for
-- most, a PUBLIC `=X/postgres`. Dropping one leaves the other, and anon still
-- holds EXECUTE through whichever survived. This is 115's lesson inverted:
-- there, `revoke ... from public` left the anon grant standing; here, revoking
-- anon would leave PUBLIC standing. Both halves are load-bearing.
--
-- These grants were made BY postgres, so unlike 115's spatial_ref_sys the
-- revoke actually takes effect. Check proacl afterwards anyway.

-- ── OTP internals: no API role has any business here ─────────────────────
revoke execute on function
  public.otp_log_send(text, text, timestamp with time zone),
  public.otp_log_attempts(uuid, integer),
  public.otp_log_verified(uuid),
  public.cleanup_old_otps()
from public, anon, authenticated;

-- ── Scheduled jobs and internal message senders ─────────────────────────
revoke execute on function
  public.auto_complete_elapsed_bookings(),
  public.auto_reveal_old_reviews(),
  public.expire_stale_bookings(),
  public.capture_monthly_leaderboard_snapshot(),
  public.migrate_conversation_participants(),
  public.send_pre_checkin_messages(),
  public.send_review_reminders(),
  public.send_checkout_for_booking(uuid),
  public.send_booking_contacts(uuid),
  public.get_conversation_participants(uuid)
from public, anon, authenticated;

-- ── Signed-in only, not public ──────────────────────────────────────────
-- These two keep `authenticated` on purpose and lose only anon/PUBLIC:
--   get_unread_count       is called by the app (supabase_messaging_service,
--                          supabase_conversation_repository)
--   is_conversation_member is referenced by two RLS policies on
--                          conversation_participants, and a role whose policy
--                          calls a function it cannot execute gets an error
--                          instead of an empty result
-- Neither checks that p_user_id is the caller, so a signed-in user can still
-- read another's unread count. That is a function-body fix, not a grant fix,
-- and is deliberately left for its own migration rather than rewritten blind.
revoke execute on function
  public.get_unread_count(uuid, uuid),
  public.is_conversation_member(uuid, uuid)
from public, anon;

-- ── Deliberately untouched ──────────────────────────────────────────────
-- anon must keep EXECUTE on these; they are the public browse surface, and
-- three of them are called from inside RLS policies, where a missing grant
-- raises rather than filtering:
--
--   is_booking_available      granted to anon on purpose by 112 (dated search)
--   listing_blocked_ranges    110; how a guest reads a host's blocked dates
--   get_host_leaderboard / get_host_rank / host_leaderboard_ranked
--                             the public leaderboard
--   is_admin / can_see_listing_address / get_listing_owner
--                             used in policy expressions
--   create_marketplace_booking, redeem_coupon, validate_coupon,
--   mark_all_notifications_read, get_unread_notification_count,
--   get_booking_contacts, send_booking_accept_messages
--                             all check auth.uid() themselves, so a signed-out
--                             caller already fails inside them
