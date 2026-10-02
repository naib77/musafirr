# Database: booking, availability and search rules

Moved verbatim from `CLAUDE.md` on 2026-10-01 to keep that file small.
The short rule for each section is still in `CLAUDE.md`; the reasoning is here.

## Availability rules belong in the database, not the booking form

Migration 070 moved the *price* server-side because the client was deciding it.
It left every other booking rule in Dart, and each one turned out to be
unenforced. Migrations 110–111 close that; the pattern is worth remembering,
because **"the booking form checks it" is not enforcement** — the form is
skippable, and the RPC is a public endpoint.

What 111 fixed, and what to check before adding a rule:

- **`host_available` (038) was never enforced at booking time.** That
  migration's own comment claims it is "enforced at the Reserve step". It was
  not — it was only ever a search/browse filter, so a guest with the listing
  already open, deep-linked, or reached from wishlist/trips booked an away host
  fine. Do not trust that comment; it predates the fix.
- **Per-plan min/max duration (055) was form-only.** `BookingLimits.minFor`'s
  `?? 1` and the RPC's `coalesce(v_min, 1)` are now two implementations of one
  rule. A test in `booking_limits_test.dart` pins the default so they can't
  drift; if you change one, change both.
- **`is_booking_available` was `SECURITY INVOKER`.** `bookings` has RLS and no
  policy admits another guest's row, so the function the client calls
  "server-authoritative" returned **true for slots that were already taken**.
  The guest was told the dates were free and only found out at checkout. It is
  `SECURITY DEFINER` now. Any function that has to see across users needs the
  same, and the Dart-side comment claiming a plain RPC "sees ALL bookings" was
  simply wrong.

Two exclusion constraints are the real backstop, not the RPC's `if exists`
guards — those are check-then-insert and lose races by construction:
`bookings_no_overlap` (078, per listing) and `bookings_no_tenant_overlap` (111,
per guest). Both raise `23P01`.

**Never tell the two conflicts apart by their message text.** That is what the
repository used to do (`contains('already have a booking')`), matching English
written in a SQL file — rewording a migration silently showed guests the wrong
message. Both raises now carry a `hint` (`listing_overlap` / `tenant_overlap`)
and `bookingConflictTypeFrom` reads it, with the constraint name and then the
legacy prose as ordered fallbacks. It has tests; keep them passing.

Host date blocks live in `listing_availability_blocks` (110). Writes go through
`block_listing_dates` / `unblock_listing_dates` — the table has **no** INSERT
policy, deliberately, so the "are these dates already booked?" check can't be
skipped by writing through PostgREST. The host's `note` is private, which is
why the SELECT policy is owner-scoped and guests read
`listing_blocked_ranges()` instead. Every range in the schema is half-open
`'[)'`: a block ending when a stay begins does not collide.

There is deliberately **no** constraint spanning blocks and bookings — a block
is not a `bookings` row. A host blocking dates in the same millisecond a guest
commits can lose; the cost is one booking to decline by hand, and the
alternative (blocks as `bookings` rows under a sentinel status) would drag them
through earnings, commission, payouts and the reservations list.

### Search filters on dates through `is_booking_available`, not its own copy

`search_listings` took no date until 112, so a guest searching 10-15 September
was shown listings blocked for exactly those days and listings already booked
solid — then refused at Reserve. `SearchFilters` had carried `checkIn`/`checkOut`
all along; the client simply never sent them.

A block hides a listing **only from searches whose dates overlap it**. Do not
"fix" this into hiding the listing outright: one blocked weekend would then cost
the host every other booking, which is the problem 110 was built to solve, and
`host_available` (038) plus `is_active` already exist for stepping out entirely.
An undated search — including the default explore feed, which is
`searchListingsFromDb(const SearchFilters())` — filters on nothing.

Three things about it that are easy to undo by accident:

- **The predicate lives in the `base` CTE, not the outer `where`.** `chosen`
  (the smallest radius tier holding a match) reads `base`, so a blocked listing
  must not be allowed to win a tier and then be filtered out of it — a dated
  tiered search would answer with an **empty ring**. Verified: moving the
  predicate outward turns one scenario from two results into zero.
- **It is a `case`, not an `or` chain.** Postgres does not promise
  left-to-right `or` evaluation, and a reversed window reaches
  `tstzrange(lower > upper)`, which aborts the whole search with `22000`.
  `searchDateWindowFor` drops such a window client-side too, but a public RPC
  cannot lean on that.
- **112 grants `is_booking_available` to `anon`** because `search_listings` is
  `SECURITY INVOKER` and open to `anon`, and 111 had granted it to
  `authenticated` only. On a *plain* Postgres that grant is load-bearing —
  without it a not-signed-in dated search dies with `42501` and the client's
  `catch` renders it as "no results". On **this** database it is not: see the
  default-privileges note below. Keep it anyway; it stops the repo depending on
  an accident.

**Do not reason about anon access from the migrations alone.** Supabase's
`ALTER DEFAULT PRIVILEGES` on schema `public` grants `anon` and `authenticated`
at CREATE time, and the `revoke all ... from public` this repo writes after a
`SECURITY DEFINER` function strips only the PUBLIC pseudo-role — it leaves that
explicit anon grant untouched. Verified on live via `pg_proc.proacl` /
`pg_class.relacl`: anon already holds EXECUTE on `is_booking_available` and
`listing_blocked_ranges`, and SELECT on `listing_ratings`, in flat
contradiction of what 110/111/016 appear to say.

So **an RLS policy is the only one of the two that actually gates `anon`.**
Default privileges hand out the grant; nothing hands out a policy. That is why
`facilities` was the single thing broken for signed-out visitors (113) — it was
a `to authenticated` *policy*, not a missing grant. When you need to know what a
visitor can read, impersonate one (`begin; set local role anon; …; rollback;`)
rather than reading the SQL.

### PostGIS lives in `public`, and its tables are not ours to fix

001 runs `create extension if not exists postgis` with no schema, so PostGIS's
reference tables land in the schema PostgREST exposes, carrying the extension's
own grants: `anon=arwdDxtm` on `spatial_ref_sys` — INSERT, UPDATE, DELETE **and
TRUNCATE**, not just read. Verified, not inferred: `DELETE
/rest/v1/spatial_ref_sys` with the compiled-in anon key answered **204**. An
emptied table is a full search outage, because geography operations resolve
their spheroid through it and every one of them then raises `Cannot find SRID
(4326)` — `search_listings`, the radius tiers, the landmark ring, the geog
trigger, the default explore feed.

115 closes it, and the shape of that migration is the lesson. Three obvious
fixes are all refused here — the table is owned by `supabase_admin`, and our
`postgres` is neither a superuser nor a member of it:

| Attempt | Result |
| --- | --- |
| `enable row level security` | `42501: must be owner` — the linter's own advice |
| `owner to postgres` | `42501: must be owner` |
| `alter extension postgis set schema` | refused; postgis is `extrelocatable = false` |

**The `revoke` is the dangerous one: it is permitted, reports success, and does
nothing.** A non-owner may only revoke grants it made itself, and these were
made by `supabase_admin`, so `relacl` comes back byte-identical. A migration
built on it applies green and records itself as done with the hole untouched.
`postgres` holds `t` (TRIGGER) and nothing else useful, so the guard is a
trigger — **two** of them, because TRUNCATE does not fire row-level triggers
and a row-only guard loses the table to a one-word statement. Reads stay open
deliberately: search runs as `anon` and needs them.

So when a Supabase lint names a table you did not create, check who owns it
before writing the fix — and check `relacl` *after* applying it, because
"succeeded" is not evidence.

### Party capacity is sub-caps under a total, and pets default to deny

118 gave `listings` four nullable columns — `max_adults`, `max_children`,
`max_infants`, `max_pets` — and `search_listings` four matching arguments. Three
things about the model are easy to get wrong later:

- **They sit beneath `max_guests`, they do not replace it.** The total is still
  the backstop, still what `create_marketplace_booking` enforces, and still the
  only number a booking carries. They are deliberately **not** constrained to be
  `<= max_guests` and do not have to sum to it: "up to 4 people, at most 2
  adults, at most 3 children" is a coherent thing for a host to mean, and every
  obvious constraint forbids it. `PartyLimits.clampedTo` trims a *counted* cap
  when the host lowers the total, because a sub-cap above the total can never
  bind — it does not touch infants or pets, which the total never gated.
- **`null` means "no separate limit", not zero.** That is what makes the
  migration invisible to the listings that already existed: a null column drops
  out of the predicate entirely. Zero is a different, stated rule ("no
  children"), and the two must never be collapsed — `supabase/tests/118…`
  rows 02b/06/06b are the pair that pins it. It is also why the host control is
  a stepper whose floor is **"Any"** rather than an `int` stepper beside a
  switch: a host has to be able to take a cap back *off*, and `PartyLimits`
  therefore needs explicit `clear*` flags where `SearchFilters.copyWith` reads
  null as "unchanged".
- **Pets are the exception and default to deny.** Unlike the other three they
  already had a switch — `pets_allowed` (053), `not null default false` — so
  silence means no, and `max_pets` is only consulted for a host who said yes.
  Searching with an animal must not surface a place that never agreed to one.
  Nothing ties the toggle and the number together, so a host switching pets off
  needs no cleanup: the predicate reads the toggle first and never reaches the
  number. `partyLimitsSentence` does the same, or a listing page would advertise
  a pet limit for a place that no longer takes pets.

**The four RPC keys are omitted unless the guest actually narrowed**
(`searchPartyParams`), for exactly the reason 112 omits `p_check_in`: PostgREST
picks the overload by the keys *present*, so sending them against a database
without 118 demands a function that does not exist, and
`searchListingsFromDb`'s catch turns every search on the site into "no results".
`build/web` always lags a migration, so that window is real.

The split still stops at search. A stay found as "2 adults, 1 child, 1 infant,
1 pet" is booked as **3 guests** — bookings carry one number, and carrying the
breakdown through means a bookings migration plus the booking sheet, the price
breakdown and the host's reservation list.

### Turf is a listing type, and adding an enum value is a two-file migration

120 added `turf` to `listing_type`; 121 gave it three nullable columns
(`turf_sport`, `turf_format`, `turf_surface`) and seven amenity rows. A turf is
a sports ground rented by the hour.

**They are two files because Postgres refuses to let a new enum label be used
in the transaction that added it** — `55P04: unsafe use of new value "turf"`.
That has two consequences that bite immediately:

- 121's check constraint names `'turf'`, so running the pair together fails.
  Apply 120, **commit**, then 121.
- **The rolled-back-transaction check this repo verifies every migration with
  does not work here.** A turf fixture needs the label committed, so
  `supabase/tests/120_121_turf_test.sql` runs *after* both are applied, not
  around them. Do not assume that safety net is under you for an enum change.
- And it is **not reversible**: Postgres has no `ALTER TYPE … DROP VALUE`.
  Removing `turf` means recreating the type and every dependent column.

**Almost nothing else had to change, and that is the point.** Hourly booking
already existed in full — `pricing_unit` carries `hour`, `listings` carries
`hourly_rate`/`min_hours`/`max_hours`, `create_marketplace_booking` takes an
arbitrary range, and `bookings_no_overlap` (078) is a *range* exclusion, so
16:00–17:00 and 18:00–19:00 on one listing already coexisted. Rows 07–09 of the
test pin exactly that, including a real overlap still being refused so the
first two cannot pass for the wrong reason. `search_listings` needed no change
either: it selects `to_jsonb(listings_row)`, so new columns flow through.

Four things worth keeping:

- **`max_guests` is the capacity column for a turf too.** It is the same
  question — how many people fit — and a turf just calls the answer "players".
  That is why 121 added no capacity column, and why the party predicate in
  `search_listings` needed no second branch. `scopeFieldsToType` deliberately
  does not touch it.
- **The deploy-order trap from 112/118 does NOT apply in the read direction.**
  `search_listings` filters with `l.listing_type::text = any(p_property_types)`
  — it casts the *column* to text, never the input array to the enum — so a
  build sending `'turf'` to a database without 120 matches nothing rather than
  raising `22P02`. Only the write path (a host publishing) needs the migration
  first, which is the safe direction. Do not "fix" this by omitting the key.
- **`scopeFieldsToType` is the only place that drops the other type's
  answers, and it is load-bearing.** A host can choose turf, state the sport,
  go back and switch to room — the answers are still in form state, and
  `listings_turf_fields_only_on_turf` refuses the whole write with `23514`. It
  also zeroes bedrooms/beds/bathrooms for a turf (the model defaults them to 1,
  and the card would print "1 bedroom" under a football pitch) and forces
  `petsAllowed` off, because that column gates the entire pet branch of the
  search predicate. Create and Edit are separate save paths and had two copies
  of this rule on the first pass; one function now, with tests.
- **`FacilityCatalog.ownerSelectable` is deduplicated by name, and must stay
  that way.** The turf amenity set reuses Parking, Drinking Water, First Aid
  Kit, CCTV Security and Security Guard, and both save paths filter that flat
  list by the selected *names* — so a plain concatenation yields Parking twice,
  reaches `listing_facilities` as two identical rows, and is refused by its
  `(listing_id, facility_id)` unique index with `23505`. The entire save fails
  because the host ticked a shared amenity. A test pins it, and a second test
  pins that the two shapes genuinely overlap, or the first proves nothing.

The host wizard is a **list** of steps derived from the type
(`_WizardStep`), not a fixed count of eight, and `_canProceed` switches on the
step's *identity* rather than its index — the two shapes put photos at 7 and 6,
so an index-based rule would have let a turf publish with no photos. Sport,
format and surface render through the shared
[`TurfDetailsFields`](lib/widgets/host/turf_details_fields.dart), for the same
reason `GuestPartyFields` is shared: the wire values are pinned by check
constraints, and two copies drift into one screen offering a sport the other
refuses.

Every palette gained a `turf` colour and it is a **new dark green token, not
the existing `green` accent** — `_CategoryBadge` paints the type's name in
white on it, so it is held to 4.5:1 like every other text-bearing token, and
`green` (#10B981) is 2.54:1. The palette test now checks all six pairs for
distinctness and all four for white-text contrast.

**What is still missing, and it is the thing that makes turf good rather than
merely possible:** the hourly picker is guess-and-check. A guest picks a date,
a start time and a duration, and `is_booking_available` answers yes/no for
exactly that window — nothing shows which slots are already taken. That is
tolerable for a stay booked hourly now and then and poor for a ground where
every booking is a slot. There is also no opening-hours concept, so nothing
stops a 3am booking; that would be a column plus a check inside
`create_marketplace_booking`, since the form is not enforcement.

### The booking RPC is the only booking rule there is (135, applied 2026-09-19)

`create_marketplace_booking` is the single writer of a `bookings` row — 071
locked direct INSERT — so anything it does not check is not checked. Two
things it did not:

- **A host could book their own listing.** Measured allowed; live already
  holds one. The ledger then posts the owner an earning against money that
  moved between their own two pockets, and a host can black out their own
  calendar through the booking path instead of `listing_availability_blocks`
  (110), which is the feature built for it and the only one their own UI can
  undo.
- **A booking could be entirely in the past.** A stay starting ten days ago
  was accepted and returned an id. Past slots are always free, so the
  availability checks never object, and the auto-complete sweep then walks the
  row straight to completed — a review prompt and a ledger entry for a stay
  nobody had.

Both refuse at INSERT time only, the choice 114 made for identity; the live
rows are left alone. The past-date guard allows **one hour** of slack rather
than a hard `>= now()`, because booking a turf for *this* hour is the normal
case for an hourly listing, the client's clock is its own, and `now()` here is
transaction time. It is there to stop last month, not the last minute.

### Several guests racing for one slot lose in two different ways (N6)

`bookings_no_overlap` (078) is correct and does its job: exactly one booking
survived every race in QA, at two, three, four and eight concurrent guests,
across eleven runs. **What the losers are told depended on how many of them
there were.** With two, the loser gets `23P01` and the sentence written for
them. With three or more, Postgres frequently raises from inside the exclusion
check itself:

```
ERROR:  deadlock detected
CONTEXT: while checking exclusion constraint on tuple (1,25) in relation "bookings"
```

The client handled `23P01` only, so under exactly the load this feature exists
for — a popular slot — most losing guests saw an unexplained failure. Across
six four-racer runs, two had all three losers deadlock.

`isRetryableBookingFailure` (`40001`, `40P01`) now drives one retry in
`_insertMarketplaceBookingWithRetry`, and a second failure is rendered as the
conflict message rather than a generic banner. **Once, not a loop with
backoff**: the race is already decided by the time the retry runs, and a
client hammering a contended slot adds to the contention it is losing to.

### A listing is a set of units, and the overlap rule keys on the unit (147)

A hotel with twelve rooms is twelve things that can each be booked once. The
listing had been the unit of booking, so the exclusion constraint refused a
second guest the moment one room was taken. 147 adds `listing_units` and
moves the rule down one level.

- **`bookings.unit_id` is `not null` and the database picks it.** The guest
  never names a room: `create_marketplace_booking` takes the first free
  active unit by label (`for update … skip locked`, so two guests racing for
  the last room do not both win it) and refuses with the same `23P01` +
  `listing_overlap` as before when none is free. The constraint keeps its
  name, `bookings_no_overlap`, because the Dart fallback classifier matches
  on it.
- **Every listing has exactly one unit until the host adds more.** The
  backfill made one per listing, `trg_listing_default_unit` makes one for
  every new listing, and a legacy unitless insert (QA seed, the older
  suites, `_insertBookingAsync`) is pinned to the only unit by
  `trg_a_booking_unit_consistent`. So a single-unit listing behaves exactly
  as it did, and the deployed web build keeps booking against the new
  schema. A unitless insert on a multi-unit listing is `22023`
  `unit_required` — only the RPC may book those.
- **`unit_id` cannot be changed after the fact** unless the session sets
  `musafir.unit_reassign = 'on'` (the Phase 4 RPC). A host fixing a room
  clash must go through that function, not an UPDATE.
- **Availability is `listing_rooms_left(listing, from, to) > 0`**, which
  `is_booking_available` now wraps and search still calls. A listing-wide
  block (`listing_availability_blocks.unit_id is null`) is zero rooms; a
  per-unit block takes that one room out. The block constraint keys on
  `(listing_id, coalesce(unit_id, zero-uuid), range)` so the two kinds do not
  collide with each other.
- **`listing_units` is the host's inventory, not public data.** Owner or
  admin only; anon reaches rooms only through `listing_rooms_left`. The
  revoke is explicit because default privileges would have granted anon
  SELECT at create time.

### Hourly stays are a two-layer policy, and the host can only narrow it (148)

A hotel sells day-use in 6- or 12-hour blocks; a seat is sold by the hour
from one upwards; a full house is not worth opening for less than three. The
only hourly rule had been the host's `min_hours`/`max_hours` and a hard-coded
1..12 stepper, so none of these could be expressed. 148 adds a platform
layer above the host's and one check that reads both.

- **Platform: `app_settings.hourly_policy`**, JSON keyed by `listing_type`
  label (`fullHouse`, `hotel` — `hotel` accepted ahead of 149 so the row
  needs no rewrite then): `{"enabled", "min_hours", "slots"}` per type,
  validated by `fn_validate_setting_hourly_policy`. `hourly_policy_for(type)`
  resolves a missing or corrupt entry to `hourly_policy_defaults()` per
  type — the same fail-open the Dart `HourlyPolicy.fromRaw` does, and a test
  in `test/services/hourly_policy_test.dart` pins the Dart defaults to the
  SQL literal.
- **Host: `listings.hourly_slots`, `hourly_window_start/end`** beside the
  existing `min_hours`/`max_hours`. The floor is
  `greatest(policy.min_hours, coalesce(listing.min_hours, 1))`; a host slot
  list **replaces** the platform's (so a hotel can drop 12 h) but every
  slot is still subject to `max_hours`; the window is one Asia/Dhaka
  calendar day with `24:00` a valid end. A host cannot widen anything from
  their form — the form clamps a typed minimum up to the floor before
  saving so the host sees the number guests are held to.
- **`hourly_booking_check` runs inside the RPC for `hour` bookings only**,
  in a fixed order — disabled, floor, max, slots, window — and refuses with
  `22023` + hints `hourly_disabled` / `hourly_min` / `hourly_max` /
  `hourly_slot` / `hourly_window`. The order is part of the contract: a
  1-hour stay at 07:00 that breaks both the floor and the window is told
  about the floor, and the Dart `HourlyRule.refusalFor` returns the same
  answer so the pre-check banner and a refusal that slips past it read
  the same sentence.
- **The Dart copy shapes the picker, never gates.** `resolveHourlyRule`
  decides chips (slotted) versus stepper (free hours), hides a slot above
  the host's max, and drops the hourly plan from the segments entirely when
  nothing is bookable (`HourlyRule.bookable`). The SQL suite
  `148_hourly_policy_test.sql` §3 and the Dart test share one rule table;
  change a case in one and change it in the other.
- Nightly and monthly are untouched: the check is not called for them and
  `minFor`/`maxFor` still apply.


### A hotel is a listing with many units, and only the RPC resizes it (150, applied 2026-10-02)

147 gave every listing one unit and no way to add another. 150 adds
`set_listing_unit_count(listing, n)`, the only way a host changes how many
rooms a listing sells.

- **Shrinking deactivates, never deletes.** `bookings.unit_id` references the
  unit, and history must keep pointing somewhere. Growing reactivates the
  oldest inactive units first, so 10 → 8 → 10 gives back the same rooms.
- **All-or-nothing, by hint.** If fewer free units exist than the shrink
  needs (free = no pending/confirmed/active booking ending after now()), it
  raises 22023 with hint `units_in_use` and changes nothing. The edit screen
  maps that hint, never the message (the message carries counts).
- **The race.** The booking RPC picks a unit `for update of u skip locked`.
  The resize locks every active unit `for update` (waiting) *before* checking
  bookings, so a booking already holding a unit is seen, and one that starts
  later skips the unit being retired.
- **Definer, so it guards itself.** It must see every guest's booking, not
  what the host's RLS shows, and it does its own owner/admin check (42501
  `not_listing_owner`). `listing_unit_count` is invoker and RLS-gated.
- **The edit form only resizes hotels**, and only after the count has
  loaded. A default of 1 saved before the load answered would retire every
  other room.

The hotel trio (`hotel_star_rating`, `hotel_front_desk_24h`,
`hotel_id_required`) is guarded like turf's (`listings_hotel_fields_only_on_hotel`),
so `scopeFieldsToType` clears it whenever the type is not hotel. The Room
Matrix facts (`size_sqft`, `bathroom_kind`, `toilet_kind`) describe any stay
and carry no type guard; they are cleared only for a turf.

**Deploy order:** the save path writes all six columns on every listing, and
PostgREST refuses an unknown column (PGRST204). A build carrying them breaks
*every* listing save on a database without 150. Live first, then build.
