# Hotels on Musafir — implementation plan

Status: in progress. Phase 1 (147, units) and Phase 2 (148, hourly policy)
are built and green on the local mirror as of 2026-10-02 — SQL suites, Dart
tests, guest picker, host fields and the admin editor — and **not yet applied
to live**. Phases 3–4 are not started. Decisions D1–D5 at the end are taken.

Scope: a hotel host lists a **room category** ("Deluxe Double", 12 rooms), a
guest books it by the night **or by the hour (minimum 6 hours)**, the database
assigns a physical room, and the rest of the marketplace (payment, host
accept, reviews, refunds) works exactly as it does for a room or a full house.

Hourly rules — whether hourly is allowed, the minimum, and the slot lengths —
become configurable **per listing type from the admin console**, with the host
tuning within that, for every type, not only hotels.

## 1. What the other platforms do, and what we take from each

Observed as of 2026 on their public sites; none of it is copied verbatim.

| | Booking.com | ShareTrip / GoZayaan (BD OTAs) | Musafir today |
| --- | --- | --- | --- |
| Unit of sale | Property → room types → N rooms per type → rate plans | Hotel → room types with count, meal plan, refundable flag | One listing = one bookable thing |
| Guest picks | Dates, rooms × guests; sees "only 2 left" | City + dates + rooms/guests; room cards with price per night | Dates (or date + start time + hours) |
| Room assignment | Hotel assigns at check-in | Hotel assigns | n/a |
| Confirmation | Instant for most properties | Instant after payment | Host accepts within `booking_accept_window_hours` |
| Hourly / day-use | No (Agoda has "day use", typically 6–10 h windows) | No | Yes, any whole hours ≥ host minimum |
| Policies shown | Check-in window, ID, children, pets, cancellation | Cancellation, check-in/out | House rules + refund policy (139) |

What we take:

- **Room category with a count, not one listing per physical room.** Every
  platform sells the category; the room number is the hotel's business.
- **"N rooms left"** on the card and detail page — a count the database can
  answer cheaply once units exist.
- **Instant confirmation as an option.** Hotels expect it; a 24-hour accept
  window is a homestay habit. Off by default, host-switchable (decision D2).
- **Hourly is our differentiator**, so it is designed properly rather than
  bolted on: slots instead of free hours, a platform floor, and a day-use
  window, because every hotel in Dhaka that sells 6-hour stays sells them
  between roughly 08:00 and 22:00, and nothing today stops a 3 am booking
  (noted as missing in `docs/notes/database-booking-and-search.md`).

## 2. Where the current model breaks, precisely

- `bookings_no_overlap` is `EXCLUDE (listing_id WITH =, tstzrange WITH &&)`
  over active statuses. One active booking per listing per range. Correct for
  a room; wrong for twelve of them.
- `create_marketplace_booking` and `is_booking_available` both ask "is this
  *listing* free", and `search_listings` filters dates through
  `is_booking_available` inside its `base` CTE.
- Hourly rules are two nullable integers per listing (`min_hours`,
  `max_hours`), enforced only in the RPC with `coalesce(v_min, 1)`. There is
  no platform floor, no slot concept, and no opening window. The guest picker
  is date + start time + an hours stepper, checked yes/no afterwards.
- `listing_type` is a Postgres enum (`seat, room, fullHouse, turf`); adding a
  label is a two-migration, non-reversible change (55P04, see the turf note).

## 3. Data model

### 3.1 Units (phase 1, every listing type)

```sql
create table public.listing_units (
  id          uuid primary key default gen_random_uuid(),
  listing_id  uuid not null references public.listings(id) on delete cascade,
  label       text,                       -- "101", "Room A"; host-only
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (listing_id, label)
);
alter table public.bookings add column unit_id uuid references public.listing_units(id);
```

- Backfill: **one unit per existing listing**, then `bookings.unit_id` for
  every row from its listing's single unit. After that `unit_id` becomes
  `not null`.
- `bookings_no_overlap` is **replaced** by the same exclusion over `unit_id`.
  Because every listing has exactly one unit at swap time, the two
  constraints are equivalent on live data; the migration asserts this
  (`select count(*) from listings l where (select count(*) from listing_units
  where listing_id = l.id) <> 1` must be 0) before dropping the old one.
  `bookings_no_tenant_overlap` is untouched.
- `listings.unit_count` is **not** a column; it is `count(*) from listing_units
  where is_active`. A host "adds rooms" by adding units. The wizard offers a
  stepper and creates N unlabelled units; labels are optional and host-only.
- RLS: host full access to their listing's units (owner_id match); public
  reads nothing from the table directly — the count comes back through
  `search_listings` and a `listing_rooms_left(listing_id, starts, ends)`
  function so unit labels never leak to guests.

### 3.2 Hourly policy (phase 2, every listing type)

Two layers, platform then host, both enforced in the RPC.

**Platform layer — one `app_settings` key, `hourly_policy`**, JSON text:

```json
{
  "seat":      {"enabled": true,  "min_hours": 1, "slots": null},
  "room":      {"enabled": true,  "min_hours": 1, "slots": null},
  "fullHouse": {"enabled": true,  "min_hours": 3, "slots": null},
  "turf":      {"enabled": true,  "min_hours": 1, "slots": null},
  "hotel":     {"enabled": true,  "min_hours": 6, "slots": [6, 12]}
}
```

- `enabled` — may this type be booked by the hour at all.
- `min_hours` — the floor; a host's `min_hours` is clamped **up** to it.
- `slots` — if non-null, the only durations a guest may book for this type,
  unless the host narrows further. `null` = any whole hours ≥ minimum.
- One key rather than fifteen because `fn_validate_app_setting` already has a
  precedent for a structured value (`search_radius_tiers_m`), and a policy
  that is one row is one audit-log line when it changes. The validator arm
  parses with `jsonb`, requires every top-level key to be a `listing_type`
  label, `min_hours >= 1`, `slots` all multiples of 1 and ≥ `min_hours`.
- Read by `AppSettingsService` (fail-open to the defaults above, same pattern
  as every other key) and by the RPC directly from the table at booking time,
  so a stale client cannot book below the floor.

**Host layer — three columns on `listings`:**

```sql
alter table public.listings
  add column hourly_slots      integer[],   -- null = inherit platform slots / free hours
  add column hourly_window_start time,      -- day-use window, both null = any time
  add column hourly_window_end   time;
```

`min_hours` / `max_hours` stay as they are. Effective rule for a booking:

```
allowed      = policy[type].enabled and listing.hourly_rate is not null
floor        = greatest(policy[type].min_hours, coalesce(listing.min_hours, 1))
slots        = coalesce(listing.hourly_slots, policy[type].slots)   -- null = free
qty ok       = qty >= floor and (max_hours is null or qty <= max_hours)
               and (slots is null or qty = any(slots))
window ok    = both null, or starts_at::time >= start and ends_at::time <= end
               (same calendar day in Asia/Dhaka; no cross-midnight slots)
```

This lives in **one SQL function**, `hourly_booking_check(listing, starts,
ends)`, called by the RPC — and is mirrored by **one Dart function**,
`HourlyPolicy.resolve(type, settings, listing)`, that the picker, the host
form and the validation message all read from. Two copies of the rule is how
055's `coalesce(v_min, 1)` / `minFor`'s `?? 1` pairing had to be documented as
a trap; this time the Dart side has a test that feeds the same fixtures the
SQL suite uses.

Pricing stays `hourly_rate × hours` in this phase. A hotel that wants 6 h for
৳1,500 sets `hourly_rate = 250`. Per-slot prices (6 h = 1,500, 12 h = 2,200)
are decision D1.

### 3.3 Hotel type (phase 3)

Two migrations, committed between (55P04):

- `149_listing_type_hotel.sql` — `alter type listing_type add value 'hotel'`.
- `150_hotel_details.sql` — columns, constraint, amenities:

```sql
alter table public.listings
  add column hotel_star_rating smallint check (hotel_star_rating between 1 and 5),
  add column hotel_front_desk_24h boolean,
  add column hotel_id_required boolean,
  add column size_sqft integer check (size_sqft > 0),
  add column bathroom_kind text check (bathroom_kind in ('attached','common')),
  add column toilet_kind   text check (toilet_kind   in ('commode','indian'));
alter table public.listings add constraint listings_hotel_fields_only_on_hotel check (
  listing_type = 'hotel' or (hotel_star_rating is null and hotel_front_desk_24h is null
                             and hotel_id_required is null));
```

`size_sqft`, `bathroom_kind`, `toilet_kind` come from the Room Matrix sheet
and apply to every stay type, not only hotels. Amenity rows (matched by name
from `FacilityCatalog`, same contract as 121/146): `24h Front Desk`, `Room
Service`, `Restaurant`, `Breakfast Included`, `Housekeeping`, `Gym`, `Airport
Pickup`, `Luggage Storage`, `In-room Safe`, `Keycard Access`. A `hotelGroups`
list in `FacilityCatalog` offers these plus the stay essentials and hides
Kitchen / Freezer / Washing Machine, the way `turfGroups` hides Wi-Fi from a
pitch.

Trade licence: host verification already has a document path
(`require_listing_address_proof`, identity + face review in 142–145). A hotel
listing requires a `trade_licence` document before `PublishGate` lets it go
live; the admin console's verification queue reviews it with the others.

## 4. Booking flow after the change

**Guest, nightly** — unchanged UI. `create_marketplace_booking` finds a free
unit instead of checking the listing:

```sql
select u.id into v_unit from public.listing_units u
 where u.listing_id = p_listing_id and u.is_active
   and not exists (select 1 from bookings b where b.unit_id = u.id
                   and b.booking_status in ('pending','confirmed','active')
                   and tstzrange(b.starts_at,b.ends_at,'[)') && tstzrange(p_starts_at,p_ends_at,'[)'))
   and not exists (select 1 from listing_availability_blocks blk
                   where (blk.listing_id = p_listing_id and blk.unit_id is null or blk.unit_id = u.id)
                   and tstzrange(blk.starts_at,blk.ends_at,'[)') && tstzrange(p_starts_at,p_ends_at,'[)'))
 order by u.label nulls last, u.created_at
 for update skip locked
 limit 1;
if v_unit is null then
  raise exception 'No room is free for these dates' using errcode='23P01', hint='listing_overlap';
end if;
```

`for update skip locked` is what makes two guests racing for a 12-room
category each get a *different* room instead of one losing with a deadlock
(the N6 finding). The `listing_overlap` hint is kept so `BookingConflict`
in Dart needs no new branch; the client's one retry (`40001`/`40P01`) stays.

**Guest, hourly** — the "By the hour" mode in the When panel and the detail
sheet's hourly plan both change from an hours stepper to **slot chips**
(`6 h · 12 h`) when `HourlyPolicy.resolve` returns slots, and keep the
stepper (clamped to the floor) when it returns free hours. Start time is
constrained to the day-use window when one is set. The sentence under the
picker is generated from the resolved policy ("Minimum 6 hours for hotels"),
not hard-coded.

**Host** — reservations show the assigned room label; a host can move a
booking to another free unit (`reassign_booking_unit`, RPC, same overlap
check). `listing_availability_blocks` gains a nullable `unit_id` so room 104
can be blocked for maintenance without blocking the category.

**Payment, accept window, refunds, reviews, payouts** — untouched. One
booking is still one row with one `total_price`; reviews stay per listing
(the room category), which is what a guest wants to read.

## 5. Phases and migrations

| Phase | Migration(s) | Dart | Admin console | Ship gate |
| --- | --- | --- | --- | --- |
| **1. Units** | 147: table, backfill, `bookings.unit_id`, constraint swap, RPC + `is_booking_available` over units, `listing_rooms_left`, `blocks.unit_id`, RLS | none required (RPC assigns); optional "rooms left" line | none | SQL suite green on local; live verified: every listing has 1 unit, old constraint dropped only after assert; a booking from the *current* web build still succeeds |
| **2. Hourly policy** | 148: `hourly_policy` setting + validator arm, listing columns, `hourly_booking_check`, RPC calls it | `HourlyPolicy.resolve` + tests; slot chips in When panel and detail sheet; host pricing fields gain slots + window, min clamped to floor | `hourly_policy` added to `TEXT_SETTING_KEYS` with a per-type editor | Fixtures shared between SQL and Dart tests; build_web after 148 is live |
| **3. Hotel type** | 149 (enum) · commit · 150 (columns, amenities, constraint) | `ListingType.hotel`, `scopeFieldsToType`, wizard steps, unit stepper, palette `hotel` token (4.5:1 test), search chip, card badge, voice parser label, link-preview Worker | trade-licence review in the verification queue | 149 applied and committed before 150 is written; build_web after 150 |
| **4. Operations** | 151: `instant_book` (D2), `reassign_booking_unit` | host reassign UI, "N rooms left", per-unit blocks in the availability screen | — | — |

Rollout rule for every phase: **database first, verify on live, then
`sh tool/build_web.sh` and commit `build/web`.** The RPC assigns units and
reads the policy from the table, so a stale cached bundle keeps working
against the new database; the reverse order would offer hotels and slots the
database refuses.

After each migration goes live: add it to `NEWER_MIGRATIONS`, regenerate the
baseline (`python3 tool/dump_live_baseline.py`), clear `NEWER_MIGRATIONS`.

## 6. Tests

- **SQL** (`tool/qa/run_sql_tests.sh`): race at 1, 2, 12 units with 2–8
  concurrent bookers — exactly N survive, losers get `listing_overlap`, no
  `40P01`; existing single-unit listings behave identically to before the
  swap; hourly: below floor refused, non-slot duration refused, outside
  window refused, host min below floor is clamped not honoured, disabled type
  refused even with `hourly_rate` set; blocks per unit vs per listing.
- **Dart**: `HourlyPolicy.resolve` against the same fixture table;
  `scopeFieldsToType` zeroes hotel fields on a room and vice versa; wizard
  step list for hotel puts photos last and `_canProceed` keys on identity;
  palette contrast for the `hotel` token; `FacilityCatalog.ownerSelectable`
  still deduplicated with `hotelGroups` added.
- **Manual on live** (the only proof, per CLAUDE.md): book a nightly and a
  6-hour stay on a hotel fixture from the deployed web build; confirm the
  host sees a room label; `sh tool/verify_deploy.sh` GREEN.

## 7. Risks

| Risk | Mitigation |
| --- | --- |
| Constraint swap on live `bookings` | Assert one unit per listing in the same transaction before `drop constraint`; keep the old constraint's definition in the migration comment for a manual re-add |
| `hotel` enum label cannot be removed | Phase 3 starts only after phases 1–2 are live and measured |
| Two copies of the hourly rule drift | One SQL function, one Dart function, shared fixtures, and the rule documented in `docs/notes/database-booking-and-search.md` |
| Day-use window and Asia/Dhaka | Compare in `Asia/Dhaka`, never `now()`'s zone; a test books 21:00–03:00 and is refused |
| Admin writes a bad `hourly_policy` | Validator arm refuses; `AppSettingsService` falls back to defaults if the JSON is unreadable |
| Unit labels are host-private | No public policy on `listing_units`; counts only through functions |

## 8. Decisions needed

- **D1 — Slot pricing.** Linear (`hourly_rate × hours`, phase 2 as written) or
  per-slot prices (`hourly_slot_prices jsonb`)? Per-slot matches how hotels
  quote day-use (6 h and 12 h are rarely 1:2) but adds a column, a validator,
  a pricing branch in the RPC and a price table in the UI. Recommendation:
  linear now, per-slot in phase 4 if hotel hosts ask.
- **D2 — Instant confirmation.** Hotels expect it; homestays rely on the
  accept window. Recommendation: `listings.instant_book boolean default
  false`, host-switchable for any type, RPC inserts as `confirmed` when set.
- **D3 — Couples / ID policy.** `hotel_id_required` is in the plan. A
  "married couples only" field is common in Bangladesh but is a legal and
  reputational choice for the platform. Recommendation: not in the data
  model; hosts may state it in `additional_rules`.
- **D4 — Guest picks a room?** Recommendation: no. The database assigns; the
  host can reassign. Letting guests pick means exposing labels and a seat-map
  UI nobody has asked for.
- **D5 — Minimum for other types.** The defaults above (seat/room/turf 1 h,
  full house 3 h, hotel 6 h) are placeholders. The admin console owns them
  after phase 2.
