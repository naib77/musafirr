-- 117: the three security_definer_view ERRORs from the advisor, plus the
-- privilege escalation that hid behind one of them.
--
-- A view with neither `security_invoker=on` nor an owner override runs as its
-- OWNER (postgres here), so it reads AND writes the base table with the owner's
-- privileges, ignoring the querying user's RLS. The advisor flags all three of
-- ours. Two are a clean fix; the third turned out to be critical.
--
-- ── public_profiles was an anon -> admin escalation ───────────────────────
--
-- public_profiles is `select <15 non-PII columns> from profiles`. A simple
-- single-table view is AUTO-UPDATABLE, so PostgREST accepts INSERT/UPDATE/
-- DELETE on it -- and because the view is definer, those writes hit `profiles`
-- as postgres, bypassing every SELECT/UPDATE policy on it. Proven on live:
--
--   set local role anon;
--   update public.public_profiles set role='admin' where id=<a host>;
--   -- role: owner -> admin
--
-- and over HTTPS with the bundled anon key, `PATCH /rest/v1/public_profiles`
-- answered 204. Any visitor could make any account -- their own or anyone's --
-- an admin. The direct path is NOT vulnerable: `update profiles` as anon hits
-- RLS (auth.uid() is null) and matches no row, and an authenticated user
-- editing their own row is stopped from changing `role` by the
-- fn_guard_verification_verdicts trigger. The view slipped both because it
-- launders the actor into postgres, before the trigger runs and outside RLS.
--
-- Fix: strip the write privileges. The view exists to be READ; nothing legit
-- ever wrote through it. Reads are untouched (they run as postgres either way),
-- verified: anon still reads all 40 rows after the revoke.
--
-- It stays a SECURITY DEFINER view on purpose, so its advisor lint (0010) does
-- NOT clear -- accepted, for the same shape of reason spatial_ref_sys's 0013
-- cannot (see 115). public_profiles is the whole point of 061: profiles is
-- RLS-locked to own-row + admin so its PII (mobile, nid, email, address) is
-- private, and this view is the ONE surface exposing the safe columns to
-- everyone. Flipping it to security_invoker would run the read as the caller;
-- an anon caller then sees zero rows and every host name in the app vanishes.
-- Making that work again would need a `to public using(true)` SELECT policy on
-- profiles -- and anon holds column SELECT on all 31 columns (only RLS hides
-- them, confirmed: a direct anon select returns []), so that policy would leak
-- every phone number and NID the instant it existed. The definer view is
-- load-bearing; the danger was the write path, and that is now closed.
--
-- ── listing_ratings / guest_ratings: invoker is the real fix ──────────────
--
-- These are aggregates (GROUP BY), so NOT auto-updatable -- no write hole. But
-- as definer views they aggregate `reviews` as postgres, which sees every row.
-- reviews' own SELECT policy is `reviews_select_revealed to public using
-- (is_revealed = true)`, so reading as the caller yields only revealed reviews.
-- listing_ratings never filtered is_revealed itself, so the definer view was
-- averaging in UNREVEALED reviews -- a double-blind leak. Flipping to
-- security_invoker both clears the lint and fixes that: verified on live, the
-- listing_ratings review count drops 37 -> 36 (one unrevealed review leaves)
-- and anon still reads all 8 rows; guest_ratings already filtered is_revealed,
-- so it is unchanged at 6 rows / 13 reviews. anon keeps EXECUTE-equivalent read
-- because reviews is granted to it and the revealed policy is `to public`.

alter view public.listing_ratings set (security_invoker = on);
alter view public.guest_ratings   set (security_invoker = on);

-- Close the escalation. The view keeps SELECT for everyone; only writes go.
revoke insert, update, delete on public.public_profiles
  from anon, authenticated, public;

-- Defense in depth, unrelated to the view mechanics: anon holds table-level
-- SELECT/INSERT/UPDATE on all 31 columns of profiles, PII included, held back
-- only by RLS. anon never touches the table directly -- it reads through this
-- view (definer, so it needs no table grant) and never writes -- so the grants
-- are pure attack surface waiting for a careless future policy. No anon-facing
-- invoker function reads the profiles table either (search_listings joins the
-- view), so removing them changes nothing that works today. authenticated is
-- left alone: it legitimately reads and writes its OWN row, which RLS scopes.
revoke all on public.profiles from anon;
