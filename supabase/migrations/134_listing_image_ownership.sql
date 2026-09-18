-- =============================================
-- 134 — the listing-images bucket had no owner
--
-- Measured 2026-09-18 on the local mirror, with real storage policies copied
-- from live: a second host overwrote another host's photo (the object's
-- metadata went from none to `{"hacked": true}`), and a guest who hosts
-- nothing uploaded into the bucket. Both are one HTTP request with the anon
-- key that ships inside build/web plus any signed-in session.
--
-- All three write policies were `bucket_id = 'listing-images'` and nothing
-- else:
--
--     listing_images_authenticated_insert   with check (bucket_id = …)
--     listing_images_authenticated_update   using      (bucket_id = …)
--     listing_images_authenticated_delete   using      (bucket_id = …)
--
-- so "may this person write here" was answered by *which bucket it is*. The
-- `avatars` policies next to them get it right — they tie the file name to
-- `auth.uid()` — and `documents` scopes reads to the owner's folder. This
-- bucket was the odd one out, and it is the public one.
--
-- Deleting happened to be refused in the measurement, but by Supabase's own
-- `protect_objects_delete` trigger rather than by our policy. Do not read
-- that as the hole being narrower than it is: overwriting achieves the same
-- defacement, and a trigger we do not own is not a control we can rely on.
--
-- ## Why `owner`, not the path
--
-- The obvious clause — "the first folder must be a listing you own" — does
-- not work, and the reason is worth keeping. `CreateListingScreen` uploads
-- the photos BEFORE the listing row exists, under a synthetic folder
-- (`listing_<millis>`, create_listing_screen.dart); only `EditListingScreen`
-- uses the real uuid. On live, 42 objects: **12** sit under a listing uuid
-- and 30 do not. A path-based policy would refuse every first publish.
--
-- `storage.objects.owner` is stamped by Storage with the uploader's uid and
-- is populated on all 42. So the rule is "the object is yours", which needs
-- no path convention and cannot be spoofed by choosing a folder name.
-- `owner_id` (text) is the newer column; both are checked because which one
-- Storage populates depends on its version, and a mirror that populates only
-- one must not lock a host out of their own photos.
--
-- ## Why the INSERT gate is "may you publish at all"
--
-- There is no listing to belong to at upload time (see above), so the only
-- honest question left is whether this account is a host. That predicate
-- already exists — it is the `listings` INSERT policy, `owners_insert_own
-- _listings`: role in (owner, admin) AND verification_status = 'verified'.
-- Writing it out a second time here would be two copies of one rule, and the
-- copy in a storage policy is the one nobody would remember to update. So it
-- moves into `public.can_publish_listings()` and BOTH policies call it.
--
-- **Plus anyone who already owns a listing, which is not the same set.** Live
-- has 4 listings belonging to 2 accounts that would fail that predicate
-- today: they predate 114, which is INSERT-time only and deliberately left
-- existing rows alone. Those two can still EDIT their listings — the UPDATE
-- policy on `listings` has no verification clause — so gating uploads on
-- publishing rights alone would let them change everything about a listing
-- except its photos, and the error would arrive from Storage with no
-- explanation attached. N3 is about a guest who hosts nothing; it is not
-- about them.
-- =============================================

-- The one implementation of "this account may publish listings".
--
-- SECURITY DEFINER because it reads `profiles`, which is behind RLS: an
-- INVOKER function would answer "no" for anyone whose own profile row the
-- calling context cannot see, and storage policies run as `authenticated`.
-- It takes no parameter — a caller-supplied identity on a definer function is
-- exactly the hole 116 exists to close (see CLAUDE.md).
create or replace function public.can_publish_listings()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role in ('owner', 'admin')
      and p.verification_status = 'verified'
  );
$$;

-- Who may put a file in the public listing-images bucket.
--
-- Deliberately looser than `can_publish_listings()` and deliberately not
-- inlined into the policy: the storage policy is the one place where the
-- looser rule is right, and a reader of either function should be able to see
-- which question it answers.
create or replace function public.can_upload_listing_image()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select public.can_publish_listings()
      or exists (select 1 from public.listings l where l.owner_id = auth.uid());
$$;

comment on function public.can_upload_listing_image() is
  'Whether the caller may upload into the public listing-images bucket: '
  'anyone who may publish, plus anyone who already owns a listing (134).';

comment on function public.can_publish_listings() is
  'Whether the caller may publish a listing: a verified owner or an admin. '
  'Called from the listings INSERT policy and the listing-images storage '
  'INSERT policy so the two cannot drift (134).';

-- Recreated so the rule has one home. The predicate is byte-for-byte the
-- behaviour of the policy this replaces; only where it is written changes.
drop policy if exists owners_insert_own_listings on public.listings;
create policy owners_insert_own_listings on public.listings
  as permissive for insert to authenticated
  with check (owner_id = auth.uid() and public.can_publish_listings());

-- ---------------------------------------------------------------- storage
-- Reads stay wide open: the bucket is public and every listing card on the
-- site loads from it, signed out included.
drop policy if exists listing_images_authenticated_insert on storage.objects;
drop policy if exists listing_images_authenticated_update on storage.objects;
drop policy if exists listing_images_authenticated_delete on storage.objects;

-- The new names too. The local mirror applies the baseline and the forward
-- migrations REPEATEDLY until the failure count stops shrinking (see
-- tool/local_db_from_live.sh), so a `create policy` that cannot be re-run is
-- a failure that never clears and hides the ones that matter.
drop policy if exists listing_images_publisher_insert on storage.objects;
drop policy if exists listing_images_owner_update on storage.objects;
drop policy if exists listing_images_owner_delete on storage.objects;

create policy listing_images_publisher_insert on storage.objects
  as permissive for insert to authenticated
  with check (
    bucket_id = 'listing-images'
    and public.can_upload_listing_image()
  );

create policy listing_images_owner_update on storage.objects
  as permissive for update to authenticated
  using (
    bucket_id = 'listing-images'
    and (owner = auth.uid() or owner_id = auth.uid()::text or public.is_admin())
  )
  with check (
    bucket_id = 'listing-images'
    and (owner = auth.uid() or owner_id = auth.uid()::text or public.is_admin())
  );

create policy listing_images_owner_delete on storage.objects
  as permissive for delete to authenticated
  using (
    bucket_id = 'listing-images'
    and (owner = auth.uid() or owner_id = auth.uid()::text or public.is_admin())
  );
