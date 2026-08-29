-- Migration 099: let admins read and edit any listing.
--
-- Every policy on the four listing tables is written for the host, and none of
-- them has an admin rule:
--
--   listings                  select: is_active = true OR auth.uid() = owner_id
--                             update/insert/delete: auth.uid() = owner_id
--   listing_addresses         insert/update/delete: the listing's owner
--                             (select is fine — can_see_listing_address()
--                              already returns true for is_admin())
--   listing_checkin_details   ALL: the listing's owner
--   listing_facilities        ALL: the listing's owner
--
-- The rest of the schema does not work this way: `profiles` has
-- `admins_update_any_profile`, and `coupons`, `app_settings`, `reports` and
-- `owner_documents` all carry an is_admin() policy. Listings were simply
-- missed.
--
-- The effect on the admin console was total, because the one admin account
-- owns no listings: every save returned "Nothing was updated" (Postgres
-- answers a denied UPDATE with zero rows, not an error), other hosts' hidden
-- listings were invisible, and their check-in details could not even be read.
--
-- Insert and delete stay owner-only on purpose. The console never creates or
-- destroys a listing — it edits, publishes, hides and transfers ownership —
-- and a policy that is not needed is a policy that cannot be misused.

-- ── listings ───────────────────────────────────────────────────────────────

-- Additive: policies are OR-ed, so the host's own rule is untouched. This adds
-- the inactive listings the existing select policy hides from everyone but
-- their owner.
drop policy if exists listings_admin_select on public.listings;
create policy listings_admin_select
  on public.listings for select
  using (public.is_admin());

drop policy if exists listings_admin_update on public.listings;
create policy listings_admin_update
  on public.listings for update
  using (public.is_admin())
  with check (public.is_admin());

-- ── listing_addresses ──────────────────────────────────────────────────────

drop policy if exists listing_addresses_admin_insert on public.listing_addresses;
create policy listing_addresses_admin_insert
  on public.listing_addresses for insert
  with check (public.is_admin());

drop policy if exists listing_addresses_admin_update on public.listing_addresses;
create policy listing_addresses_admin_update
  on public.listing_addresses for update
  using (public.is_admin())
  with check (public.is_admin());

-- ── listing_checkin_details ────────────────────────────────────────────────

-- Select included: the owner-only ALL policy is the reason an admin opening
-- someone else's listing sees an empty check-in block rather than the wifi and
-- access code the guest will be given.
drop policy if exists listing_checkin_details_admin_all on public.listing_checkin_details;
create policy listing_checkin_details_admin_all
  on public.listing_checkin_details for all
  using (public.is_admin())
  with check (public.is_admin());

-- ── listing_facilities ─────────────────────────────────────────────────────

-- Select is already public; this is for the delete-then-insert rewrite the
-- console does when an admin changes the facility set.
drop policy if exists listing_facilities_admin_all on public.listing_facilities;
create policy listing_facilities_admin_all
  on public.listing_facilities for all
  using (public.is_admin())
  with check (public.is_admin());
