-- Verification for 116_revoke_internal_function_grants.sql.
--
-- Asserts the EXECUTE matrix: internal functions unreachable by the two roles
-- PostgREST can hand a request to, service_role still able to run them, and the
-- public browse surface untouched.
--
-- Pure catalog reads -- nothing here mutates, so it needs no transaction
-- wrapper, though running it inside one you roll back is harmless:
--
--   \i supabase/tests/116_internal_function_grants_test.sql
--
-- Or against live through the Management API SQL endpoint. No psql
-- metacommands, so it runs either way.
--
-- Expected: every row PASS. Before 116, all fourteen BLOCKED rows and both
-- SIGNED_IN rows were `anon => true` -- measured on live.
--
-- The OTP rows are the ones that matter. otp_log_send with anon EXECUTE is an
-- account-takeover primitive: unsalted SHA-256 hashes plus verify-otp's
-- `order by created_at desc limit 1` means an anon-inserted row outranks the
-- code that was actually texted. See the migration for the full chain.

-- Matched by name, not signature, and EVERY overload must agree. Two reasons:
-- pg_get_function_identity_arguments spells arguments with their parameter
-- names ("p_id uuid"), so a types-only signature silently matches nothing and
-- the whole table reports MISSING FUNCTION -- a green-looking red. And an
-- overload carrying a stray grant is just as much of a hole as the base
-- function, so "all overloads" is the rule we actually want asserted.
with expected(fname, anon_ok, auth_ok, svc_ok, why) as (values
  -- name                                    anon   auth   svc
  ('otp_log_send',                          false, false, true, 'takeover primitive'),
  ('otp_log_attempts',                      false, false, true, 'defeats rate limit'),
  ('otp_log_verified',                      false, false, true, 'marks codes used'),
  ('cleanup_old_otps',                      false, false, true, 'deletes OTP rows'),
  ('auto_complete_elapsed_bookings',        false, false, true, 'cron: completes stays'),
  ('auto_reveal_old_reviews',               false, false, true, 'cron: breaks double-blind'),
  ('expire_stale_bookings',                 false, false, true, 'cron: cancels bookings'),
  ('capture_monthly_leaderboard_snapshot',  false, false, true, 'cron: writes snapshots'),
  ('migrate_conversation_participants',     false, false, true, 'one-off backfill'),
  ('send_pre_checkin_messages',             false, false, true, 'mass messaging'),
  ('send_review_reminders',                 false, false, true, 'mass messaging'),
  ('send_checkout_for_booking',             false, false, true, 'arbitrary booking id'),
  ('send_booking_contacts',                 false, false, true, 'leaks both phone numbers'),
  ('get_conversation_participants',         false, false, true, 'any conversation'),
  -- Signed-in only: real app call site / referenced by an RLS policy.
  ('get_unread_count',                      false,  true, true, 'app calls it as authenticated'),
  ('is_conversation_member',                false,  true, true, 'used by conversation_participants policies'),
  -- Public browse surface: anon MUST keep these. Three are called from inside
  -- policy expressions, where a missing grant raises instead of filtering.
  ('is_booking_available',                   true,  true, true, '112 grants anon on purpose'),
  ('listing_blocked_ranges',                 true,  true, true, '110: guests read blocked dates'),
  ('get_host_leaderboard',                   true,  true, true, 'public leaderboard'),
  ('is_admin',                               true,  true, true, 'used in policy expressions'),
  -- Guards itself internally, so the grant is not the control.
  ('admin_expire_bookings',                  true,  true, true, 'raises: only service_role')
), actual as (
  select e.*,
         count(p.oid) as overloads,
         bool_and(has_function_privilege('anon',          p.oid,'EXECUTE') = e.anon_ok
              and has_function_privilege('authenticated', p.oid,'EXECUTE') = e.auth_ok
              and has_function_privilege('service_role',  p.oid,'EXECUTE') = e.svc_ok) as all_match,
         string_agg(distinct
           'anon=' || has_function_privilege('anon',          p.oid,'EXECUTE') ||
           ' auth='|| has_function_privilege('authenticated', p.oid,'EXECUTE') ||
           ' svc=' || has_function_privilege('service_role',  p.oid,'EXECUTE'), '; ') as got
    from expected e
    left join pg_proc p
      on p.pronamespace = 'public'::regnamespace and p.proname = e.fname
   group by e.fname, e.anon_ok, e.auth_ok, e.svc_ok, e.why
)
select fname as function,
       case when overloads = 0 then 'FAIL missing function'
            when all_match   then 'PASS'
            else 'FAIL got ' || got end as result,
       case when anon_ok then 'PUBLIC' else 'BLOCKED' end as intent,
       overloads,
       why
  from actual
 order by anon_ok, fname;
