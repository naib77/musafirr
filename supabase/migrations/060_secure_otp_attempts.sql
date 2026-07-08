-- 060 — Lock down otp_attempts (HIGH severity fix)
--
-- The live otp_attempts table was readable AND writable by anon:
--   otp_attempts_select  USING (true)          -> anon could read every row
--   otp_attempts_insert  WITH CHECK (true)
--   otp_attempts_update  USING (true) CHECK (true)
-- OTP verification is done in-memory by the client (OtpService._otpStore); the
-- table is only a write-only audit trail. The real risk is the SELECT: OTPs are
-- 4 digits hashed with unsalted SHA-256, so any anon client could read the hash
-- and brute-force it offline in microseconds -> account takeover. Anon also had
-- free INSERT/UPDATE (audit-trail tampering / row spam).
--
-- Fix: no client ever needs to read the table, and its writes are three fixed
-- shapes. Move those writes behind SECURITY DEFINER RPCs and revoke all direct
-- client access. The RPCs run as owner (bypass RLS) and never return otp_hash.

-- ---- write RPCs -------------------------------------------------------------
create or replace function public.otp_log_send(
  p_phone text, p_otp_hash text, p_expires_at timestamptz)
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  insert into public.otp_attempts (phone, otp_hash, expires_at)
  values (p_phone, p_otp_hash, p_expires_at)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.otp_log_attempts(p_id uuid, p_attempts integer)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.otp_attempts set attempts = p_attempts where id = p_id;
end $$;

create or replace function public.otp_log_verified(p_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.otp_attempts
  set verified_at = now(), is_used = true
  where id = p_id;
end $$;

-- OTP happens pre-authentication, so anon must be able to call these.
revoke execute on function public.otp_log_send(text, text, timestamptz) from public;
revoke execute on function public.otp_log_attempts(uuid, integer) from public;
revoke execute on function public.otp_log_verified(uuid) from public;
grant execute on function public.otp_log_send(text, text, timestamptz) to anon, authenticated;
grant execute on function public.otp_log_attempts(uuid, integer) to anon, authenticated;
grant execute on function public.otp_log_verified(uuid) to anon, authenticated;

-- ---- remove all direct client access to the table --------------------------
drop policy if exists "otp_attempts_select" on public.otp_attempts;
drop policy if exists "otp_attempts_insert" on public.otp_attempts;
drop policy if exists "otp_attempts_update" on public.otp_attempts;
revoke all on public.otp_attempts from anon, authenticated;
-- RLS stays enabled with zero policies: table is now reachable only via the
-- SECURITY DEFINER RPCs above and the service_role.
