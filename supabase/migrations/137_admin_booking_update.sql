-- =============================================
-- 137 — the console's refund switch matched no rows
--
-- `bookings` carries five policies and not one of them admits an admin for
-- UPDATE: a host for their listing, a guest for their own row, and three
-- SELECTs. So `markBookingRefunded` in ../musafir-admin — which PATCHes with
-- the signed-in admin's JWT — got `[]` back from PostgREST, and the action's
-- "no rows changed" branch reported *"Only a paid booking can be marked
-- refunded"* however paid the booking was. Reproduced locally against the
-- seeded admin.
--
-- Note what that means about the failure mode: PostgREST does not refuse an
-- UPDATE whose rows RLS filtered out. It succeeds, changes nothing, and
-- returns an empty set — which is why this has been broken for as long as
-- the screen has existed without anyone seeing an error. It is the same trap
-- the QA capability matrix had to be rewritten around: measure the effect,
-- never the exception.
--
-- The fix is the policy, not a service-role client in the console. Admins
-- already hold UPDATE on `listings` (`listings_admin_update`) and on
-- `profiles` and `app_settings` by exactly this shape, and
-- `enforce_booking_update_rules` already returns `new` unconditionally for
-- an admin — the whole state machine, the frozen-money block and 132's
-- settlement guard are all written on the assumption that an admin can write
-- this table. This restores the assumption the rest of the schema makes.
--
-- Refunding is still a bookkeeping flip, not a money movement: 101's trigger
-- posts the reversing ledger entry, and the guest's actual money goes back
-- through a `guest_refund` disbursement on the Payouts screen.
--
-- CLAUDE.md's 132 note says to fix this in the console and then revoke the
-- payment columns. That is superseded: with the trigger as the one guard and
-- admins exempt inside it, a column revoke would have to exempt them too and
-- there is no way to write "except admins" in a GRANT.
-- =============================================

drop policy if exists bookings_admin_update on public.bookings;
create policy bookings_admin_update on public.bookings
  as permissive for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());
