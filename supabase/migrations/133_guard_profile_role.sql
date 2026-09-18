-- =============================================
-- 133 — anyone signed in could make themselves an admin
--
-- Verified on live, rolled back, 2026-09-18. Impersonating the oldest
-- non-admin account on production:
--
--     update profiles set role = 'admin' where id = <self>;   -- succeeded
--     admin count 1 -> 2
--
-- Through PostgREST that is one PATCH with the anon key that ships inside
-- build/web plus the caller's own JWT:
--
--     PATCH /rest/v1/profiles?id=eq.<self>   {"role":"admin"}
--
-- Two things line up, and both look reasonable on their own:
--
--   * the UPDATE policy "Users can update their own profile" is
--     `using (auth.uid() = id)` with **no WITH CHECK**, so a user may set any
--     column on their own row, and
--   * `fn_guard_verification_verdicts` (the trigger that exists precisely to
--     stop a user awarding themselves a verdict) guards
--     `verification_status`, `address_verification_status`, `nid_verified`
--     and the address audit columns — and never mentions `role`.
--
-- CLAUDE.md states, in the 117 note, that "an authenticated self-`role` change
-- is stopped by `fn_guard_verification_verdicts`". That sentence is simply
-- false; it is corrected in the same commit as this migration. 117 closed the
-- *laundered* path (PATCH through the definer view `public_profiles`) and the
-- direct path was assumed safe without being driven.
--
-- The blast radius is the whole product, because `is_admin()` is what 28
-- policies key on: every booking, every payment row, every payout method,
-- every identity document in the private `documents` bucket, every listing's
-- exact address, the audit log, coupons, the SMS and notification campaigns,
-- plus UPDATE on `app_settings` and on any profile. One PATCH turns a guest
-- into all of that.
--
-- **The fix is not "non-admins may never change role", because the app
-- legitimately writes that column.** `SupabaseAuthService.becomeHost()` sets
-- `is_host`, `host_since` and `role = 'owner'` in one client-side update — the
-- "start hosting" flow. So the rule is: a non-admin may make exactly the
-- tenant -> owner move, and nothing else. `admin` is unreachable from the
-- client in either direction.
--
-- Same shape as 132: the trigger function is recreated IN FULL from the live
-- definition with one block added, because it is a chain of guards and a patch
-- that dropped one would silently stop enforcing it.
-- =============================================

create or replace function public.fn_guard_verification_verdicts()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;

  -- 133: role is a privilege, not a profile field. `admin` is never reachable
  -- from a client, and the only self-service move is starting to host.
  if new.role is distinct from old.role then
    if new.role = 'admin' then
      raise exception 'the admin role is granted by an admin, not by the user'
        using errcode = '42501', hint = 'role_change_forbidden';
    end if;
    if not (old.role = 'tenant' and new.role = 'owner') then
      raise exception 'that role change is admin-only (% -> %)', old.role, new.role
        using errcode = '42501', hint = 'role_change_forbidden';
    end if;
  end if;

  if new.address_verification_status = 'verified'
     and old.address_verification_status is distinct from 'verified' then
    raise exception 'address verification is granted by an admin visit, not by the host'
      using errcode = '42501';
  end if;

  if new.verification_status = 'verified'
     and old.verification_status is distinct from 'verified' then
    raise exception 'identity verification is granted by an admin, not by the user'
      using errcode = '42501';
  end if;

  if new.nid_verified and not coalesce(old.nid_verified, false) then
    raise exception 'nid_verified is set by an admin, not by the user'
      using errcode = '42501';
  end if;

  if new.address_verified_at is distinct from old.address_verified_at
     or new.address_verified_by is distinct from old.address_verified_by
     or new.address_visit_notes is distinct from old.address_visit_notes
     or new.address_rejection_reason is distinct from old.address_rejection_reason then
    raise exception 'address verification audit fields are admin-only'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

-- Follow-up, deliberately not here: "Users can update their own profile" still
-- has no WITH CHECK, so the trigger is the only thing standing between a
-- client and every other column on its own row. Adding
--     with check (auth.uid() = id)
-- would stop a row being reassigned to another user but would NOT have stopped
-- this, so it is a separate tidy-up rather than the fix.
