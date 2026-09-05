-- Migration 113: let a signed-out visitor actually read what browsing needs.
--
-- Prerequisite for making Explore public. search_listings has been granted
-- `to anon, authenticated` at every revision since 062, whose header argued it
-- was safe because "it only ever returns is_active listings, which are already
-- world-readable". True of listings -- and false of the amenity catalogue it
-- reads on the way, because the function is SECURITY INVOKER: the grant only
-- buys the right to CALL it, and every relation inside is re-checked as anon.
--
-- Measured against live, in a rolled-back transaction, before this migration:
--
--                                    anon   authenticated
--   select count(*) from facilities     0              22
--   search_listings(p_amenities =>
--                   array['Wi-Fi'])     0               5
--   amenity chips on the first card     0               7
--
-- So a public Explore on the pre-113 database shows a feed with no amenity
-- chips anywhere, and **any** search with an amenity ticked returns zero
-- results rather than degrading. Both silently: nothing errors, the inner join
-- just collapses.
--
-- READ THIS BEFORE ADDING A GRANT HERE. Only the first section below is a real
-- fix. On a Supabase project, ALTER DEFAULT PRIVILEGES on schema `public`
-- grants anon and authenticated at CREATE time, and the `revoke all ... from
-- public` this repo writes after a SECURITY DEFINER function strips only the
-- PUBLIC pseudo-role -- it does not touch that explicit anon grant. So anon
-- already holds EXECUTE on every function here, and SELECT on every table,
-- whatever the migrations say. Confirmed by reading pg_proc.proacl and
-- pg_class.relacl on live.
--
-- The corollary is the thing to remember: **an RLS policy is the only one of
-- the two that actually gates anon.** Default privileges hand out the grant;
-- nothing hands out a policy. `facilities` was broken because of a policy, and
-- that is why it was the only one broken.

-- ---------------------------------------------------------------------------
-- 1. facilities -- the amenity catalogue. THE ACTUAL FIX.
-- ---------------------------------------------------------------------------

-- 059 created this policy and its header already made the argument for a
-- blanket read -- "The catalog is non-sensitive reference data, so a blanket
-- read is correct" -- while predicting this exact failure: "Any join to
-- facilities (explore feed, listing detail) returns no amenity names". It then
-- scoped it `to authenticated`, which was the whole audience at the time. It no
-- longer is.
--
-- 22 rows of names like 'Wi-Fi' and 'Balcony'. There is nothing here to leak,
-- and listing_facilities -- the table saying which listing has which -- has
-- been `to public using (true)` all along, so anon could already read the join
-- rows and only ever lacked the labels for them.
drop policy if exists "facilities_read_authenticated" on public.facilities;
drop policy if exists "facilities_read_public" on public.facilities;
create policy "facilities_read_public"
on public.facilities
for select
to public
using (true);

comment on table public.facilities is
  'Amenity catalogue. World-readable reference data (113) -- browsing is public '
  'and search_listings is SECURITY INVOKER, so an authenticated-only policy '
  'silently emptied every amenity chip and zeroed every amenity filter.';

-- ---------------------------------------------------------------------------
-- 2. Two grants that are already true on live, made explicit.
-- ---------------------------------------------------------------------------

-- Neither of these changes live behaviour today -- anon holds both already, by
-- default privilege rather than by intent. They are written down so the repo
-- stops depending on that accident: a future `revoke all on schema public from
-- anon` (the standard hardening step) would silently take both away, and
-- neither failure is one you would enjoy debugging.

-- search_listings LEFT JOINs this view. A missing privilege on a view is a hard
-- 42501 that aborts the whole query, so losing it turns the public feed into a
-- blank page with an error -- not a feed without stars. 016 granted it to
-- `authenticated` only.
grant select on public.listing_ratings to anon;

-- Worth knowing before treating this as "just ratings": the view has no
-- security_invoker, so it runs with its owner's rights and bypasses `reviews`
-- RLS -- 023 dropped its is_revealed filter on purpose. Anon therefore learns
-- aggregate scores that reviews_select_revealed withholds row by row. That is
-- pre-existing and identical to what every signed-in user already sees; it is
-- called out so nobody reads this grant as narrower than it is.

-- 110 calls this the reader guests use, because "Guests need this to be told
-- WHY a date is unavailable rather than just being refused at checkout", then
-- granted it `to authenticated` when a logged-in user was the only kind there
-- was. It is SECURITY DEFINER and returns two timestamps per range with the
-- host's private `note` withheld -- strictly less than is_booking_available,
-- which 112 opened to anon on the reasoning that it discloses "the same fact
-- any booking calendar publishes". A public listing page that cannot grey out
-- blocked dates would walk the visitor into the login wall to discover them,
-- which is the funnel this whole change exists to fix.
grant execute on function public.listing_blocked_ranges(uuid) to anon;
