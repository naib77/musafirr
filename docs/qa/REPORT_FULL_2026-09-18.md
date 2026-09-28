# Full functional QA — host, guest, reservation, concurrency, notifications, interface

Written for: the Musafir owner and whoever runs QA.

Scope asked for: everything a host can do, everything a guest can do, the whole
reservation cycle under realistic conditions including several guests competing
for one slot, notifications, error paths, and the user experience. This is a
separate report from `docs/qa/REPORT_2026-09-18.md`, which covered payments,
the build and the database mirror.

Where it ran: the local mirror of live (`tool/local_db_from_live.sh`), the app
served against it, and — for the two findings that had to be certain — the live
database inside transactions that were rolled back. **Nothing was applied to
live in this round.** Live still has one admin and 44 profiles, checked after.

## 1. Score

| Suite | Result |
| --- | --- |
| Role capability matrix, 61 checks | 57 pass, 4 genuine failures |
| Reservation lifecycle, 8 steps | 8 pass, notification correct at every step |
| Concurrency, 4 racers × 6 runs plus 2, 3 and 8 racers | exactly one booking survived **every time**, 0 double bookings |
| Interface at 1440 / 1000 / 390 px | renders, no sideways scroll, 1 console error |
| Accessibility labels | 8 of 38 semantic nodes carry a label |
| New findings | 1 S1, 1 S2, 6 S3 |

## 2. The S1: anyone signed in can make themselves an admin

**Verified on the live database, inside a rolled-back transaction.**
Impersonating the oldest non-admin account on production:

```
update profiles set role = 'admin' where id = <self>;   -- succeeded
role   owner -> admin
admins 1 -> 2
```

Through the public API that is one request, with the anonymous key that ships
inside `build/web` plus the user's own login token:

```
PATCH /rest/v1/profiles?id=eq.<self>    {"role":"admin"}
```

Two things line up, each reasonable alone. The update policy "Users can update
their own profile" is `using (auth.uid() = id)` with **no WITH CHECK**, so a
user may set any column on their own row. And
`fn_guard_verification_verdicts` — the trigger whose entire job is stopping a
user awarding themselves a verdict — guards identity verification, address
verification, the NID flag and the address audit columns, and **never mentions
`role`**.

`CLAUDE.md` states, in the migration 117 note, that "an authenticated
self-`role` change is stopped by `fn_guard_verification_verdicts`". That
sentence is false. Migration 117 closed the *laundered* path (writing through
the `public_profiles` view) and the direct path was assumed safe without ever
being driven. The sentence is corrected in the same commit as this report.

**What the admin role unlocks.** `is_admin()` is what 28 policies key on:
every booking, every payment row, every payout method, every identity document
in the private `documents` bucket, every listing's exact address, the audit
log, coupons, the SMS and notification campaigns, plus UPDATE on
`app_settings` and on any profile. One request turns a guest into all of that.

**Fix written and verified, not applied.**
`supabase/migrations/133_guard_profile_role.sql` recreates the trigger in full
with a role clause. It is not a blanket ban, because the app legitimately
writes that column: `SupabaseAuthService.becomeHost()` sets `is_host`,
`host_since` and `role = 'owner'` in one client update. So the rule is that a
non-admin may make exactly the `tenant -> owner` move and nothing else, and
`admin` is unreachable from a client in either direction.

`supabase/tests/133_guard_profile_role_test.sql` is seven rows run against
live, rolled back:

| | Without 133 | With 133 |
| --- | --- | --- |
| 1 user makes themselves admin | **FAIL** (role became admin) | PASS (refused, hint `role_change_forbidden`) |
| 2 demote then promote | **FAIL** (role became admin) | PASS |
| 3 a tenant still becomes a host | PASS | PASS |
| 4 name and bio still self-service | PASS | PASS |
| 5 an admin can still grant roles | PASS | PASS |
| 6 service role still writes roles | PASS | PASS |
| 7 self-approving identity still refused | PASS | PASS |

Applying it to live is a real outward-facing action and needs your word.

## 3. What a host can do, measured

Every write below was measured by **effect**, not by whether it threw. That
distinction is the reason the first draft of this matrix was wrong: under row
level security an UPDATE whose rows are filtered out matches nothing and
raises nothing, so "no exception" reads as success while the database in fact
refused. Each row now probes a value before and after and reports CHANGED,
NO-OP or REFUSED.

| Host can | Result |
| --- | --- |
| Publish a listing when verified | allowed |
| Publish while unverified | refused |
| Publish under another owner's id | refused |
| Edit own listing | changed |
| Edit another host's listing | no-op (invisible to them) |
| Delete another host's listing | no-op |
| Block dates on own listing | allowed |
| Block dates on another's listing | refused |
| Check a guest in on own listing | changed |
| Change a booking on another host's listing | no-op |
| Confirm cash on own listing's booking | allowed |
| Confirm cash on a stranger's booking | refused |
| Mark a booking paid by a direct write | refused (migration 132) |
| Add a payout method | allowed |
| Read another host's payout methods | 0 rows |
| Make another user's payout method the default | refused |
| Retire another user's payout method | refused |
| Insert a payout row directly | refused, no policy exists |
| Self-verify own payout method | no-op |
| Edit own name and bio | changed |
| Edit another user's profile | no-op |
| **Promote self to admin** | **changed — see section 2** |
| Self-approve own identity | refused |
| Upload a listing image | allowed |
| **Overwrite another host's listing image** | **changed — see section 5** |
| Delete another host's listing image | refused, by storage's own protect trigger |

## 4. What a guest can do, measured

| Guest can | Result |
| --- | --- |
| Browse listings while signed out | 3 active listings |
| Read the profiles table while signed out | refused outright, no grant |
| Read host names through `public_profiles` | allowed, by design |
| Book while unverified | refused |
| Book while verified | allowed |
| **Book their own listing** | **allowed — see section 5** |
| Book more guests than the listing holds | refused |
| Book a reversed window | refused |
| **Book a slot entirely in the past** | **allowed — see section 5** |
| Book an inactive listing | refused |
| Cancel own booking | changed |
| Cancel a stranger's booking | no-op |
| Accept own booking, playing host | refused |
| Read a stranger's booking | 0 rows |
| Read a stranger's payment | 0 rows |
| Read own payment | 1 row |
| Mark own booking paid by direct write | refused (migration 132) |
| Read the exact address of a listing never booked | 0 rows |
| Upload own avatar named with own id | allowed |
| Upload an avatar named as another user | refused |
| Upload own identity document | allowed |
| Read another user's identity document | 0 rows |
| Read an identity document while signed out | 0 rows |
| Admin reads an identity document | 1 row, by design |
| Review own completed booking | allowed |
| Review a booking that is not theirs | refused |
| Add a favourite | allowed |
| Read another user's favourites | 0 rows |
| Insert a notification for another user | refused |
| Read another user's notifications | 0 rows |

## 5. The four genuine capability failures

**N2 (S2). Any signed-in user can overwrite any listing image.** The storage
policy `listing_images_authenticated_update` is
`using (bucket_id = 'listing-images')` with no owner clause, so a host can
replace a competitor's photos with anything, and so can a guest. Measured:
the object's metadata changed from none to `{"hacked": true}` under another
host's identity. Deleting is refused, but only because Supabase's own
`protect_objects_delete` trigger intervenes, not because of our policy —
overwriting achieves the same defacement. Fix: add an ownership clause tying
the object's path to the listing's owner, the way the avatars policy ties a
filename to `auth.uid()`.

**N3 (S3). Any signed-in user can upload into the public listing-images
bucket.** `listing_images_authenticated_insert` checks only the bucket name.
A guest who hosts nothing can fill a public bucket with arbitrary images up to
5 MB each. Storage cost and content risk, with no rate limit in front of it.

**N4 (S3). A host can book their own listing.**
`create_marketplace_booking` never compares the listing's owner to
`auth.uid()`. Measured allowed. A host can post earnings to themselves by
paying themselves, and a listing can be blocked out by its own owner through
the booking path rather than the availability path built for it. This was
noted in the earlier payment report and is confirmed here.

**N5 (S3). A booking can be created entirely in the past.** There is no
past-date guard in the RPC. Measured: a booking starting ten days ago was
accepted and returned an id. Past slots are always "free", so availability
never objects. The calendar hides past dates, which is the "the form is not
enforcement" pattern this codebase has been bitten by repeatedly. It also
interacts with the auto-complete sweep, which will mark such a booking
complete immediately.

## 6. Several guests competing for one slot

This is the scenario asked for, driven for real: separate database
connections, each with its own guest identity, all released at one shared
wall-clock instant, all asking for the same one-hour slot on the same listing.

**The safety result is clean. Exactly one booking survived every single run.**

| Racers | Runs | Bookings that survived |
| --- | --- | --- |
| 2 | 1 | 1 |
| 3 | 1 | 1 |
| 4 | 7 | 1 every time |
| 8 | 2 | 1 every time |

The `bookings_no_overlap` exclusion constraint is doing the work, exactly as
CLAUDE.md says it must: the RPC's own "is this slot free" check is
check-then-insert and loses races by construction, and it did lose them here.

**N6 (S3). What the losers are told is wrong at three or more racers.** With
two guests the loser gets SQLSTATE `23P01`, which
`createMarketplaceBooking` translates into "This time slot was just booked by
someone else". With three or more, the losers frequently get `40P01`,
deadlock detected, raised from inside the exclusion-constraint check itself:

```
ERROR:  deadlock detected
CONTEXT: while checking exclusion constraint on tuple (1,25) in relation "bookings"
```

The client handles `23P01` only; everything else falls through to a rethrow
and a generic failure banner. So under the load this feature is designed for —
a popular slot — most losing guests see an unexplained error rather than the
sentence written for them. It is not random: across six four-racer runs, two
runs had all three losers deadlock.

Fix: treat `40P01` and `40001` as retryable in `createMarketplaceBooking`.
One retry lands cleanly on `23P01` and produces the right message. Mapping
them straight to the conflict message would also work and is simpler.

## 7. The reservation cycle end to end, with notifications

One booking walked from request to review, recording both statuses and, at
each step, which notifications that step alone raised.

| Step | Actor | Booking state after | Who was told |
| --- | --- | --- | --- |
| 1 Request a 2-hour stay | guest | pending / unpaid | host: New Booking Request |
| 2 Accept | host | confirmed / unpaid | guest: Booking Confirmed |
| 3 Choose cash, confirm receipt | guest then host | confirmed / paid | guest: Cash payment confirmed |
| 4 Check in | host | active / paid | guest: Enjoy Your Stay |
| 5 Mark service complete | host | completed / paid | guest: How Was Your Stay, and the host |
| 6 Earning posted | system | 1 ledger row | — |
| 7 Both sides review | both | 2 reviews, 0 revealed | — |
| 8 A stranger reads those reviews | stranger | 0 visible | — |

Eight of eight pass. **Every transition notifies the right party.** The one
gap in notifications remains the online payment path reported earlier: the
settlement function inserts a type that is not in the enum, the error is
swallowed, and nobody is told. Cash notifies correctly, which is why the gap
was invisible.

A trap worth recording, because it made an earlier draft of this test report a
working feature as broken: notifications default `created_at` to `now()`,
which is **transaction** time and identical for every row inside one test, so
a `clock_timestamp()` watermark matches nothing and every step reads as
"NOBODY". The test tracks notification ids instead.

**Correction to a standing note.** There is a live commission model:
`platform_commission_pct = 15` in `app_settings`, and
`fn_post_booking_ledger` posts it. On live the ledger already holds
`booking_online` totalling 11,305, `booking_cash` totalling -46.50 (the
commission a host owes on cash they collected directly), payouts and
reversals. The memory note saying Musafir has no commission model is stale and
has been corrected.

## 8. Interface and experience

The app was served against the local mirror and loaded at three widths.

| Width | Renders | Sideways scroll | Console |
| --- | --- | --- | --- |
| 1440 desktop | yes | none | one 401 |
| 1000 tablet | yes | none | one 401 |
| 390 phone | yes | none | one 401 |

Desktop shows the brand, the Where / When / Who pill with the rose search
button, Filters, the account menu, and the curated rows. Phone shows the
compact search bar, the same rows as horizontal carousels, and the
**two-item signed-out bottom bar** (Explore, Log in) that CLAUDE.md describes.
Both match their intent. No layout overflow at any width.

**N7 (S3). Almost nothing is labelled for a screen reader.** Flutter builds
its semantics tree only when assistive technology asks. After enabling it, 38
nodes exist and **8 carry a label** — the two section headings and the six
listing cards. The search pill's three segments, the Filters button, the
search button, the voice button, the wishlist hearts, the account menu and the
bottom navigation all have a role but no name. Two consequences: a screen
reader user hears "button" with no idea what it does, and the end-to-end test
strategy in `docs/QA_PLAN.md` section 4.5, which selects controls by
accessibility label, cannot address most of the interface as it stands. This
is the cheapest high-value UX fix on the list: a `Semantics(label: …)` per
control, and the E2E suite becomes possible at the same time.

**N8 (S4). Signed-out visitors trigger a failing request on every launch.**
`DeviceSessionWatcher.checkNow()` runs at startup and on every resume without
checking for a session, so `touch_device` is called with no user and the
database refuses it — the function is granted to `authenticated` only.
Confirmed on live: `touch_device` carries no `anon` grant. The error is caught
and fails open, so nothing breaks, but every visitor makes a wasted round trip
that lands as a red 401 in the browser console and will land in error tracking
the moment Sentry is added. Fix: return early when there is no session.

## 9. Findings, ranked

| # | Sev | Finding | State |
| --- | --- | --- | --- |
| N1 | S1 | Any signed-in user can make themselves admin | **closed** — migration 133, applied 2026-09-19 |
| N2 | S2 | Any signed-in user can overwrite any listing image | **closed** — migration 134, applied 2026-09-19 |
| N3 | S3 | Any signed-in user can upload into the public listing-images bucket | **closed** — migration 134, applied 2026-09-19 |
| N4 | S3 | A host can book their own listing | **closed** — migration 135, applied 2026-09-19 |
| N5 | S3 | A booking can be created entirely in the past | **closed** — migration 135, applied 2026-09-19 |
| N6 | S3 | Concurrent losers get a deadlock error the client cannot explain | fixed in the client, tested |
| N7 | S3 | 8 of 38 controls carry an accessibility label | fixed for six control families, tested |
| N8 | S4 | Signed-out visitors trigger a 401 on every launch | fixed |

**Every row above was fixed on 2026-09-19 — see
[FIXES_2026-09-19.md](FIXES_2026-09-19.md).** All six migrations are applied
to live and were re-verified there, rolled back, against the applied state.
The client-side fixes (N6, N7, N8) do not reach users until `build/web` is
rebuilt and committed.

Carried from the payments report and still open: online payments notify
nobody (S2), the admin refund switch matches zero rows (S2), payment attempts
are uncapped per booking (S3), a risky payment settles like a clean one (S3).

## 10. What this round proved is working

Worth stating plainly, because a findings list reads as if nothing works:

- Cross-user isolation holds everywhere it was tested except the two storage
  policies named above. Bookings, payments, payout methods, notifications,
  favourites, identity documents and profile fields are all invisible to
  strangers, by policy, not by the app.
- Identity verification genuinely gates publishing and booking, from the
  database.
- Migration 132 holds in both directions: neither guest nor host can stamp a
  booking paid, while the cash and gateway paths still settle.
- The booking state machine refuses every wrong actor: a guest cannot accept,
  a host cannot touch another host's reservations, a stranger cannot cancel.
- Under genuine contention no slot was ever double-booked.
- Every lifecycle transition notifies the right person.
- Reviews stay double-blind until revealed.

## 11. Files

New: `supabase/migrations/133_guard_profile_role.sql`,
`supabase/tests/133_guard_profile_role_test.sql`,
`supabase/tests/qa_role_capability_matrix_test.sql`,
`supabase/tests/qa_reservation_lifecycle_test.sql`, this report and its HTML
companion. Extended: `tool/dump_live_baseline.py` now mirrors storage buckets
and policies, `supabase/baseline/qa_seed.sql` gained eight racer accounts and
an unreachable-phone account. Nothing committed.
