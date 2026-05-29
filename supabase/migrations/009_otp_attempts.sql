-- OTP attempts table for tracking and auditing OTP verifications
-- Stores hashed OTPs (never plaintext) with automatic cleanup

create table public.otp_attempts (
  id uuid primary key default gen_random_uuid(),
  phone text not null,
  otp_hash text not null,  -- SHA-256 hash, never plaintext
  created_at timestamptz not null default timezone('utc', now()),
  expires_at timestamptz not null,
  verified_at timestamptz,  -- null until verified
  attempts int not null default 0,
  is_used boolean not null default false
);

-- Index for quick lookups by phone and active OTPs
create index otp_attempts_phone_idx on public.otp_attempts (phone);
create index otp_attempts_expires_at_idx on public.otp_attempts (expires_at);

-- Function to clean up old OTP records
-- Keeps table small by removing:
-- 1. Verified OTPs older than 24 hours (for audit trail)
-- 2. Expired unverified OTPs older than 24 hours
-- 3. Any record older than 7 days regardless of status
create or replace function public.cleanup_old_otps()
returns integer
language plpgsql
security definer
as $$
declare
  deleted_count integer;
begin
  with deleted as (
    delete from public.otp_attempts
    where
      -- Remove verified OTPs after 24 hours
      (verified_at is not null and verified_at < now() - interval '24 hours')
      -- Remove expired unverified OTPs after 24 hours
      or (verified_at is null and expires_at < now() - interval '24 hours')
      -- Hard limit: remove anything older than 7 days
      or created_at < now() - interval '7 days'
    returning 1
  )
  select count(*) into deleted_count from deleted;

  return deleted_count;
end;
$$;

-- Schedule cleanup to run periodically (call this from a cron job or edge function)
-- Example: SELECT public.cleanup_old_otps();

-- RLS policies for otp_attempts
-- This table should only be accessed by service role (backend)
-- No direct client access for security
alter table public.otp_attempts enable row level security;

-- No policies = no direct client access (only service role can access)
-- If you need client access for specific cases, add policies here

comment on table public.otp_attempts is 'Stores hashed OTPs for verification and audit. Auto-cleaned after 24h-7d.';
comment on column public.otp_attempts.otp_hash is 'SHA-256 hash of OTP. Never store plaintext OTPs.';
comment on column public.otp_attempts.is_used is 'Prevents OTP reuse after successful verification.';
