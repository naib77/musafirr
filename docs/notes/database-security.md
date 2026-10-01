# Database: security definer functions, views and self-service rows

Moved verbatim from `CLAUDE.md` on 2026-10-01 to keep that file small.
The short rule for each section is still in `CLAUDE.md`; the reasoning is here.

### A SECURITY DEFINER function is public unless you say otherwise

Same root cause as the note above, one level down: `ALTER DEFAULT PRIVILEGES`
grants `anon` and `authenticated` EXECUTE on **every function created in
`public`**, and PostgREST publishes anything in `public` at
`/rest/v1/rpc/<name>`. So a `SECURITY DEFINER` function is a public,
unauthenticated endpoint running as `postgres` from the moment it is created,
and the only thing standing between it and the internet is a check you wrote
inside its body.

116 found fourteen with no such check. The worst was **`otp_log_send`**, and it
was full account takeover:

- it inserts into `otp_attempts` with a **caller-supplied** `otp_hash`,
- `hashOtp` (`supabase/functions/_shared/otp.ts`) is unsalted, unpeppered
  SHA-256 of the code, so the hash for `1234` is a public constant,
- `verify-otp` picks its row with `order by created_at desc limit 1`, so a row
  inserted just now **outranks the code that was actually texted**.

Three requests with the anon key that ships in the bundle — `otp_log_send`,
`verify-otp`, redeem the token — and you hold anyone's session, admin included.
Verified live to step one (HTTP 200 + row id, for a nonexistent phone, row
deleted immediately); the chain was not completed. This is not the master-OTP
risk in the QA section — that needs the number allowlisted; this needed nothing.

Two rules follow, and 116 is the worked example:

- **Revoke from `public` AND `anon` AND `authenticated`.** Nearly every one of
  these carried both a PUBLIC `=X/postgres` and an explicit `anon=X/postgres`.
  Dropping either alone leaves EXECUTE intact through the other — 115's lesson
  exactly inverted.
- **The grant is not the control if the body already guards.** `admin_*`
  raise `Only service_role can execute this function` and were left alone;
  functions checking `auth.uid()` likewise. Don't revoke blind: three
  (`is_admin`, `can_see_listing_address`, `get_listing_owner`) are called from
  inside RLS policy expressions, where a role lacking EXECUTE gets an **error
  instead of an empty result**, and `is_conversation_member` is the same for
  `authenticated`. Check `pg_policy` before touching a grant.

Safe to revoke the OTP four because the live login path never calls them: both
OTP edge functions build their client with `SUPABASE_SERVICE_ROLE_KEY` and hit
`otp_attempts` through PostgREST directly. The Dart callers in
`lib/services/otp_service.dart` sit behind
`OtpState._useSupabase => SupabaseConfig.isConfigured`, true in every shipped
build, so that branch is the mock path. Login was **not** driven to test this —
see the QA section on why automating a login can send a real SMS.

Still open after 116, in rough priority order: **20 `SECURITY DEFINER`
functions with a mutable `search_path`** (a schema-shadowing escalation vector,
mechanical to fix with `alter function … set search_path`), and
`get_unread_count` / `is_conversation_member` never checking that `p_user_id`
is the caller, so one signed-in user can still read another's counts.

### A SECURITY DEFINER *view* can be written through, as postgres

The three `security_definer_view` advisor ERRORs looked cosmetic and one was a
full **anon → admin escalation** (117). A view with neither `security_invoker=on`
nor an owner clause runs as its OWNER — `postgres` — for reads *and writes*, and
a single-table view is auto-updatable, so PostgREST accepts a PATCH on it and
the write lands on the base table **as postgres, outside RLS and before any
guard trigger**. `public_profiles` is `select <safe columns> from profiles`, so:

```
PATCH /rest/v1/public_profiles?id=eq.<host>  {"role":"admin"}   →  204
```

with the bundled anon key promoted any account to admin. The definer view launders the actor into `postgres` and slips
RLS entirely.

**This note used to claim the direct path was safe, and it was wrong.** It
said an authenticated self-`role` change is stopped by
`fn_guard_verification_verdicts`. That function guards identity verification,
address verification, `nid_verified` and the address audit columns, and never
mentioned `role`; the direct path was assumed safe without being driven.
Proved otherwise on live 2026-09-18 (rolled back): one PATCH on your own
profile row set `role` to `admin`. See 133 below. Fix
was to **revoke INSERT/UPDATE/DELETE on the view**; reads run as postgres either
way, so nothing broke.

Two rules from it:

- **A definer view over an RLS table is a write hole unless you revoke writes
  on the view.** Auto-updatability is silent — nothing in the view definition
  says "writable".
- **`security_invoker=on` is the lint's fix but not always yours.**
  `listing_ratings`/`guest_ratings` are aggregates (not updatable), and flipping
  them to invoker cleared the lint *and* fixed a real leak — as definer they
  averaged in **unrevealed** reviews (`reviews_select_revealed` is `to public`,
  so reading as the caller drops them; live count went 37→36). But flipping
  **`public_profiles`** to invoker would read as the caller: an anon caller sees
  zero rows and every host name in the app vanishes. Making it work again needs
  a `to public using(true)` SELECT policy on `profiles`, and anon holds column
  SELECT on all 31 columns (mobile, nid, email included — only RLS hides them),
  so that policy would leak PII instantly. **`public_profiles` stays a definer
  view on purpose; its lint (0010) does not clear**, same category as
  `spatial_ref_sys`'s 0013 (see 115). 117 also revoked anon's now-purposeless
  direct grants on `profiles` (it reads through the definer view, never the
  table) so those PII column grants stop being one careless policy away from a
  leak.

The rule itself is *not* reimplemented — search calls `is_booking_available`,
same as the booking form. `searchDateWindowFor`
(`lib/services/search/search_date_window.dart`) is the only place that decides
whether a search has a usable window, and it has tests.

The client omits `p_check_in`/`p_check_out` **entirely** when there is no
window rather than sending nulls, so the deploy order between `build/web` and
this migration does not matter: PostgREST picks the overload by the keys
present, so a null key would still demand the 19-argument function and, against
a pre-112 database, resolve to nothing and empty out every search.

`searchListings` (synchronous, cache-local, `supabase_musafir_repository.dart`)
has **no callers** and cannot see blocks at all — they are not in the listing
cache. `search_listings_by_location` is likewise dead in both the app and the
admin portal. Neither is a live discovery path; do not add one without giving it
the same date filter.

### Settlement columns are written by RPCs, and the trigger knows them by a flag (132, applied 2026-09-18)

Until 132, a guest or a host could `PATCH /rest/v1/bookings?id=eq.<own>`
with `{"payment_status":"paid"}` and it landed — verified live, rolled back.
`authenticated` holds column UPDATE, both UPDATE policies admit them, and
`enforce_booking_update_rules` (051/098) froze price and dates but never
`payment_status`. The ledger trigger then posts the host an earning for
money that never moved. Same class as 116 and 117: nothing in the client
writes the column, so nobody looked at who *could*.

- **The guard is on `payment_status`, `payment_method` and `paid_at`, for
  anyone with an `auth.uid()` who is not an admin.** The IPN function is
  service role (uid null) and passes; `mark_cash_payment` and
  `set_booking_payment_method` are SECURITY DEFINER but run *with* the
  caller's uid, so they announce themselves with
  `set_config('musafir.settlement_write','1',true)` around their one update
  and reset it after. A new writer of these columns must do the same; the
  test row for it goes red otherwise.
- **`current_user` cannot do this job, and the first draft tried.** The
  trigger is itself SECURITY DEFINER, so inside it `current_user` is always
  `postgres`, whoever is writing. The guard never fired and the rolled-back
  test still said "update accepted" on all three rows. A transaction-local
  GUC is the only thing the caller can hand across a definer boundary that a
  PostgREST client cannot forge (it only materialises `request.*`).
- **It is a trigger, not a `REVOKE` on the columns**, because the admin
  console's refund switch writes `payment_status` with the admin's own JWT.
  That switch matched zero rows until **137** gave `bookings` an admin UPDATE
  policy — see below. The revoke this note used to propose is now off the
  table for good: with admins exempt *inside* the trigger, a column revoke
  would have to exempt them too, and there is no way to write "except admins"
  in a GRANT.
- **In a rolled-back impersonation test, clear the claims when you drop
  the role.** `set_config('role','postgres')` alone leaves `request.jwt.claims`
  set, `auth.uid()` stays non-null, and the guard correctly refuses even
  `postgres`. Every block in `supabase/tests/132_*` ends with both.
- **The Management API's `/database/query` returns `[]` for the repo's
  standard `select n, case when ok then 'PASS' else 'FAIL' end …` result
  line.** `select * from t_result order by n` comes back fine. The files keep
  the standard line (psql is unaffected); when driving a test through the
  API, swap the last select.

### A profile row is self-service, so every privilege on it needs a guard (133, applied 2026-09-19)

`role` lives on `profiles`, the UPDATE policy is `using (auth.uid() = id)`
with **no WITH CHECK**, and the only thing between a client and any other
column on its own row is `fn_guard_verification_verdicts`. Until 133 that
trigger did not mention `role`, so:

```
PATCH /rest/v1/profiles?id=eq.<self>   {"role":"admin"}   ->  204
```

made anyone an admin, and `is_admin()` is what **28 policies** key on: every
booking, payment, payout method, identity document, exact address, the audit
log, coupons, the campaigns, plus UPDATE on `app_settings` and on any profile.
Same class as 116, 117 and 132 — nothing in the client writes the column, so
nobody asked who *could*.

- **The fix is not a blanket ban, because the app writes `role` itself.**
  `SupabaseAuthService.becomeHost()` sets `is_host`, `host_since` and
  `role = 'owner'` in one client-side update. So 133 permits exactly
  `tenant -> owner` for a non-admin and refuses everything else; `admin` is
  unreachable from a client in either direction. Test row 3 is that flow and
  goes red on the obvious over-strict fix.
- **Measure the effect, not the exception, when testing RLS.** An UPDATE whose
  rows RLS filters out matches nothing and raises nothing, so "no error" reads
  as success while the database in fact refused. The first draft of
  `qa_role_capability_matrix_test.sql` reported four false alarms for exactly
  this reason; it probes a value before and after now.
- **Clear `request.jwt.claims` whenever you drop back to `postgres`** in a
  test. A stale `sub` leaves `auth.uid()` non-null and the guards correctly
  refuse even `postgres`, which reads as the fix being broken.

Still open after 133: the profiles UPDATE policy has no WITH CHECK at all, so
the trigger remains the only guard on every other column of your own row.

### A bucket name is not an access rule (134, applied 2026-09-19)

`listing-images` granted INSERT, UPDATE and DELETE to **any** authenticated
user with only `bucket_id = 'listing-images'` as the check — "may this person
write here" answered by *which bucket it is*. Measured 2026-09-18: a second
host overwrote another host's image, and a guest who hosts nothing uploaded
into the bucket. `avatars` next door ties the filename to `auth.uid()` and
`documents` scopes reads to the owner's folder; this was the odd one out, and
it is the public one.

134 rewrites all three. Four things in it are worth keeping:

- **Ownership is `storage.objects.owner`, not the path.** The obvious clause —
  "the first folder must be a listing you own" — refuses every first publish:
  `CreateListingScreen` uploads photos BEFORE the listing row exists, under a
  synthetic `listing_<millis>` folder, and only `EditListingScreen` uses the
  real uuid. On live, 12 of 42 objects sit under a listing uuid. `owner` is
  stamped by Storage and populated on all 42. `owner_id` (text) is checked
  too, because which of the two Storage fills depends on its version.
- **The INSERT gate is deliberately LOOSER than the publish gate.** Publishing
  is `can_publish_listings()` — verified owner or admin, the predicate the
  `listings` INSERT policy already used, now called from both so they cannot
  drift. Uploading is `can_upload_listing_image()`, which is that **or you
  already own a listing**: live has 4 listings belonging to 2 accounts that
  predate 114 and could not publish today, and they can still edit those
  listings, so the strict gate would have let them change everything except
  the photos.
- **DELETE cannot be tested through SQL.** Supabase's statement-level
  `protect_objects_delete` refuses every direct `DELETE` on `storage.objects`,
  so the Storage API is the only door and the policy is asserted from
  `pg_policies` instead. That trigger is also the only reason deletion looked
  safe before 134 — a control we do not own is not a control.
- Reads stay `to public`. The bucket is public and every listing card on the
  site loads from it, signed out included.

`supabase/tests/134_137_qa_fixes_test.sql` is 27 rows; three of them go red
with the old policies put back, which is the negative control.

### An admin has to be able to write the table the admin screens write (137, applied 2026-09-19)

`bookings` carried five policies and none admitted an admin for UPDATE, so the
console's "Mark refunded" PATCHed with the admin's JWT, matched nothing, and
reported *"Only a paid booking can be marked refunded"* however paid the
booking was — since the screen shipped.

**The failure mode is the lesson, not the policy.** PostgREST does not refuse
an UPDATE whose rows RLS filtered out: it succeeds, changes nothing, and
returns `[]`. Nothing errors, nothing logs, and the feature is simply inert.
The same trap made the first draft of the QA capability matrix report four
false passes. **Measure the effect, never the exception.**
