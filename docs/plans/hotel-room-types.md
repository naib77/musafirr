# Hotels with several room types — plan

Status: proposal (2026-10-02). Nothing built. Follows `docs/plans/hotel.md`
(147–152, live).

## 1. The problem

Today a hotel listing is **one room category**: "Deluxe Double, 12 rooms".
A real hotel sells several: Super Deluxe Room, Super Deluxe Triple, Sea Front
Deluxe, each with its own price, beds, size, view, photos and room count
(the ShareTrip / Booking.com / Agoda page shape: one hotel page, a table of
room types, a quantity picker per type, one checkout).

A host can model that today only as **three unrelated listings**, which
breaks in five places:

| Where | What goes wrong |
| --- | --- |
| Search | Three cards for one hotel, competing with each other. |
| Hotel facts | Star rating, 24h front desk, ID rule, check-in time, location, hotel amenities, house rules, entered and kept in sync three times. |
| Trade licence (152) | Uploaded and reviewed three times. It names one premises, not one room type. |
| Reviews | Split three ways; a guest wants the hotel's rating. |
| Booking | One booking is one room. "2 Deluxe + 1 Triple" is three checkouts and three payments, and the second can fail after the first is paid. |

So the answer is **no**: one type per listing is fine for a room or a guest
house, but not for a hotel.

### 1.1 What ShareTrip's hotel page actually does (Hotel Sea Crown, saved page)

**Hotel level, shown once:**
- name, address, "3.0 km from city center", map;
- description and gallery;
- check-in 02:00 PM, check-out 11:00 AM, "Reception open until 12:00 AM";
- about 80 hotel amenities in about 20 groups (Meals, Pool and beach,
  Services, Accessibility, Parking, Pets…);
- "Starts from ৳3,285 per night/room": the cheapest type.

**Room type level, four types, each a card:**

| Type | Bed | Capacity | View | Area | ৳/night |
| --- | --- | --- | --- | --- | --- |
| Super Deluxe Room | DOUBLE × 1 | 2 adults, 2 children | partial sea view | 18 sqm | 3,285 |
| Super Deluxe Triple | TRIPLE × 2 | 3 adults, 2 children | with view | 27 sqm | 3,791 |
| Sea Front Deluxe Room | DOUBLE × 1 | 2 adults, 2 children | sea view | 18 sqm | 4,296 |
| Sea Front Deluxe Supreme | KING × 1 | 2 adults, 2 children | sea front | 12 sqm | 4,549 |

Each card also has:
- its own photos ("View images");
- a subset of room amenities (TV, safe, slippers…);
- "Hurry up! Only 1 room available";
- **options** ("1 Option" each): a price with Breakfast Included, Non-Smoking
  room, and "Free cancellation before 24 Oct 2026", plus the total
  "For 1 Room, 2 Nights ৳8,214" and "+ taxes and fees".

**How a guest books:**
- **The search, not the page, carries the room count**: "1 Room, 3 Guests
  (1 Child)", and in the URL
  `numberOfGuestsInRooms=[{"adults":2,"children":[2]}]`. Children have ages.
- **"Book Now" is per room type**: it books the searched room count of
  that one type.
- **The page never lets a guest mix types** in one checkout.

What this changes below:
- **v1 checkout is "N rooms of one type"**, not a mixed cart. Mixing types
  moves to deferred (§4, §7).
- **Capacity is adults + children**, not one guest number (§3, §6).
- **View and bed type are enums plus a bed count** (§3).
- **"Options" are rate plans.** ShareTrip has the slot but uses one option
  per type, so one price per type plus a breakfast flag is enough for v1
  (§7).

## 2. The choice: what is a "listing"

**A. Keep listing = room type; add a parent `properties` row (recommended).**
Every room-level fact already lives on `listings`: price, hourly price and
policy, `max_guests`, beds, `size_sqft`, bathroom, photos, amenities, units,
blocks, instant book. So does every booking rule (`create_marketplace_booking`,
`listing_rooms_left`, `hourly_booking_check`, the exclusion constraints).
None of that changes. The new row holds what belongs to the hotel, and the
guest sees the property, not the listings.

**B. Listing = hotel; new `listing_room_types` table under it.**
Cleaner names, but price, capacity, hourly policy, photos and units all move
off `listings`. That means rewriting `search_listings`, the booking RPC, the
hourly check, refunds, payouts and every Dart price path, all of which
"database is the enforcement" depends on. Too much blast radius for a naming win.

Option A also leaves room, guest house and full house listings untouched:
`property_id` is null for them.

## 3. Data model (option A)

```sql
create table public.properties (
  id                    uuid primary key default gen_random_uuid(),
  owner_id              uuid not null references public.profiles(id) on delete cascade,
  kind                  text not null default 'hotel' check (kind in ('hotel')),
  name                  text not null,           -- "Hotel Sea Crown"
  description           text,
  -- location: moves here for children (same columns as listings today)
  address, area, lat, lng, geo ...,
  hotel_star_rating     smallint check (hotel_star_rating between 1 and 5),
  hotel_front_desk_24h  boolean,
  hotel_id_required     boolean,
  check_in_time         text,
  check_out_time        text,
  house_rules           text,
  cover_image_path      text,
  is_published          boolean not null default false,
  created_at            timestamptz not null default now()
);
alter table public.listings add column property_id uuid references public.properties(id) on delete cascade;
create table public.property_amenities (...);  -- hotel-level: restaurant, gym, pickup
```

Rules:

- **A listing with a `property_id` is a room type.** Its own title becomes the
  type name ("Sea Front Deluxe"). Room-level columns stay on the listing.
- **The property owns the hotel-level facts.** 150's `hotel_*` columns on
  child listings are written from the property by a trigger (or read through a
  view) so `search_listings` and the existing detail code keep working during
  the move. Single source of truth: the property. A direct write to a child's
  `hotel_*` columns is refused.
- **Location is the property's.** Children copy it on write, the same way, so
  the PostGIS search and "near hospital" keep using `listings.geo`.
- **Trade licence moves to the property.** `listing_trade_licences` gains a
  `property_id`, or becomes `property_trade_licences`. `listing_licence_verified`
  answers through the parent, so the badge code needs no change.
- **Same owner.** A trigger refuses a `property_id` whose owner is not the
  listing's owner.
- **RLS, the 152 way.** The owner reads and writes their own property. The
  public reads published properties through a view or RPC. A host-written
  `is_published` goes through `PublishGate`'s existing checks.
- **Existing single-type hotels** get backfilled: one property per hotel
  listing, with that listing as its only type. No hotel is left without a
  property.

Room-type fields from §1.1 that we lack go on `listings`, nullable, for all
types. We have `beds`, `bedrooms`, `max_guests`, `size_sqft` and
`smoking_allowed`; we are missing:

- `bed_type text check (bed_type in ('single','double','queen','king','twin','triple'))`.
  `beds` stays the count, which gives "TRIPLE × 2".
- `view_type text check (view_type in ('sea_front','sea_view','partial_sea_view','hill_view','lake_view','city_view','garden_view','none'))`.
  Cox's Bazar sells on view: two types with the same bed and area differ by
  ৳1,000 because of it.
- `max_adults`, `max_children`. `max_guests` becomes their sum for hotels
  (a check constraint), so every existing guest-count check keeps working.
- `breakfast_included boolean`. Rate plans are deferred (§7).
- Area: keep `size_sqft` (what Bangladeshi hosts quote). Show sqm next to it
  on the detail page.

Room amenities stay per listing, so they are already per type. Hotel
amenities (restaurant, gym, beach facilities, parking) move to the property.
ShareTrip's split is the same.

## 4. Booking several rooms in one checkout

v1 matches ShareTrip: **N rooms of one type**, with the same dates and one
payment. In the API below, `p_items` holds exactly one item in v1. Mixing
types ("2 Deluxe + 1 Triple") uses the same tables and RPC with more items,
and is deferred until guests ask for it (§7).

One booking stays **one row, one unit, one `total_price`**: every trigger,
refund, payout, review and accept-window rule is per booking and stays so.
A multi-room stay is a **group** of bookings:

```sql
create table public.booking_groups (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.profiles(id),
  property_id uuid not null references public.properties(id),
  created_at  timestamptz not null default now()
);
alter table public.bookings add column group_id uuid references public.booking_groups(id);

create function public.create_property_booking(
  p_property_id uuid,
  p_starts_at timestamptz, p_ends_at timestamptz,
  p_items jsonb           -- [{"listing_id":..., "rooms":2, "guests":[2,1]}, ...]
) returns uuid             -- group id
```

- **All-or-nothing.** It loops `create_marketplace_booking`'s logic per room
  inside one transaction. If any room is not free, the whole call raises
  `listing_overlap` and nothing is held. The unit pick keeps
  `for update skip locked`, so 2 × Deluxe gets two different units.
- **Limits.** At most 10 rooms per group (an `app_settings` key, not Dart);
  every item must belong to `p_property_id`; same dates for every item (v1).
- **Payment: one payment for the group.** Today `payments.booking_id` is one
  booking. Add `payments.group_id`; the SSLCommerz init sums the group, and
  the IPN marks every booking in it paid in one transaction. A partial
  payment does not exist.
- **Host accept.** The host accepts or declines the group as a whole (one
  RPC), so a guest is never left with half a family trip. Instant book on
  every type in the group means the group is confirmed.
- **Cancel / refund.** v1 cancels the whole group; the refund is the sum of
  each booking's existing refund-policy result. Per-room cancel is deferred.
- **Single room keeps the old path.** One room of one type still calls
  `create_marketplace_booking`, so the current web build keeps working
  against the new database (the rollout rule in hotel.md).

## 5. Guest UI

- **Search card = the property:** cover photo, name, star rating, area,
  property rating, "from ৳X / night" (cheapest type that is free and fits),
  and the licensed badge. A property's children never appear as their own cards.
  `search_listings` gains a collapse: per property, keep the cheapest
  matching child plus `property_id`, `property_name` and `types_matching`.
- **Property page** (`/hotel/:propertyId`; link-preview Worker added):
  - header, gallery, hotel facts, amenities, map, reviews (all children);
  - then a **room-type list**, each row with photos, beds, size, view,
    max guests, breakfast, price for the chosen dates, "N rooms left"
    (`listing_rooms_left`, already built), and a quantity stepper (0..left);
  - a sticky summary: "2 rooms · 3 nights · ৳X", then Reserve.
- **Hourly** stays per type (each child has its own hourly policy). A mixed
  group must be all nightly or all hourly with the same slot.
- `/listing/:id` for a child redirects to the property page with that type
  pre-selected, so old shared links keep working.

## 6. Search party ("2 rooms: 2 adults + 1 child, 2 adults")

ShareTrip searches by **rooms × occupants**:
`[{"adults":2,"children":[2]}]`, where each child has an age. Because v1
books one type per checkout, the matching rule is simple:

> A room type matches when, for the search's R rooms, `rooms_left ≥ R` and
> every room's adults ≤ `max_adults` and children ≤ `max_children`.

A property matches when any of its types matches. Its card shows the
cheapest matching type.

- **Phase 1** keeps today's total-guests search: one room, guests ≤
  `max_guests`.
- **Phase 3** adds a **Rooms** stepper and a per-room adults/children split to
  the When panel, for hotels only. The guest split there is search-only
  today (search-ui.md), and that rule still holds: only `p_rooms` and the
  per-room maxima reach `search_listings`, as optional keys omitted when
  unused.
- Child ages are captured but not enforced in v1. ShareTrip asks for them,
  and none of the hotels we list price by age.

## 7. Deferred, on purpose

- **Rate plans** (room only / with breakfast / non-refundable at a discount):
  a second price per type is a pricing model change. v1 has one price per
  type plus a `breakfast_included` flag.
- **Mixing room types** in one checkout ("2 Deluxe + 1 Triple"). ShareTrip
  does not do it either; the group design already allows it.
- **Per-type cancellation deadline** ("Free cancellation before 24 Oct").
  For now the platform refund policy (139/140) applies, and the page states
  its deadline from the check-in date.
- **Taxes and fees line.** We have no VAT model yet. The price shown is the
  price charged.
- **Different dates per room** in one group.
- **Per-room cancellation** inside a group.
- **Channel manager** or OTA sync.

## 8. Host UI: adding a hotel like Sea Crown

Three levels, each entered once: **hotel → room types → rooms (by name)**.

### Step 1: the hotel (once)

"List your property", then **Hotel**, opens a short property wizard:

1. Name ("Hotel Sea Crown") and description.
2. Location: map pin plus address ("Marine Drive, Kola Toli New Beach"). Every
   room type inherits it.
3. Hotel facts: star rating, check-in 2:00 PM, check-out 11:00 AM, reception
   hours or 24h, ID required.
4. Hotel amenities: restaurant, buffet breakfast, beach facilities, parking,
   gym, elevator. These are `hotelGroups` from 150, moved to the property.
5. Hotel photos: lobby, outside, restaurant.
6. Trade licence: optional, can be added later (152).

This saves a draft property and lands on the **property dashboard**, which
is empty: "Add your first room type".

### Step 2: each room type

**Add room type** opens the existing listing wizard, trimmed to room facts.
Location and hotel facts are not asked again.

| Field | Sea Crown example |
| --- | --- |
| Type name | Super Deluxe Room |
| Bed | Double × 1 |
| Max adults / children | 2 / 2 |
| View | Partial sea view |
| Size | 194 sqft (18 sqm) |
| Room amenities | Cable TV, room service, wardrobe, shower/bathtub, safe |
| Breakfast included | yes |
| Smoking | no |
| Price per night (and hourly, optional) | ৳3,285 |
| Photos | this type's room |
| **Rooms** | 101, 102, 103, 104, 105 (see below) |

For the next type, **Duplicate** copies everything except the name,
photos and rooms. "Sea Front Deluxe Room" is Super Deluxe with a different
view and price, so it takes about 30 seconds.

### Step 3: the rooms of a type, by name

The **Rooms** field takes room names, not just a count:

- **Type names or numbers**: chips `101` `102` `103`, Enter after each.
- **Range shortcut**: typing `101-110` adds ten rooms, `A1-A5` five.
  Parsing is a pure Dart function (`parseRoomLabels`) with tests: a range
  is at most 100 rooms, the same 40-character limit as 152, and duplicates
  are dropped and shown.
- **Count only**: a host who doesn't care about numbers sets "8 rooms". The
  rooms are named Room 1–8 and can be renamed later (152's rename already
  does this).

Sea Crown would end up like this:

| Room type | Rooms | Count |
| --- | --- | --- |
| Super Deluxe Room | 101–105, 201–205 | 10 |
| Super Deluxe Triple | 106, 107, 206, 207 | 4 |
| Sea Front Deluxe Room | 301–308 | 8 |
| Sea Front Deluxe Supreme | 401, 402 | 2 |

The property dashboard shows this table, with a price and status for each
type, and "24 rooms" for the hotel.

### Step 4: publish

- Publishing the property publishes every complete type.
- A type with no rooms, no price or no photo stays a draft, and the
  dashboard says why.
- A type can be paused on its own: the Sea Front rooms can be under
  renovation while the rest sells.

### Later changes (dashboard → type → Rooms)

| Host action | What happens |
| --- | --- |
| Add room 109 | Added at once. |
| Rename 101 to "101 Sea" | Already built (152). |
| Remove room 105 | Refused with "has bookings on 3 Nov" while it has future bookings (hint `units_in_use`). Otherwise it is deactivated, not deleted, so past bookings keep their room. |
| Move room 206 from Triple to Super Deluxe (re-classified) | Allowed only with no future bookings; same rule. |
| Block room 302 for repairs | Already built (151, per-room blocks). |

### Database side of this

- **Names must be unique within the hotel.** Today they are unique per listing
  (`unique (listing_id, label)`), but a hotel cannot have two room 101s in
  different types. A trigger checks the label across all of the property's
  listings (23505, hint `room_label_taken`).
- **Units are written through definer RPCs, not table DML.** 152 left the
  host only `update (label)`, and that stays. New:
  - `add_listing_units(p_listing_id, p_labels text[])`: owner, at most 200
    per call;
  - `deactivate_listing_unit(p_unit_id)`: locks the unit, checks bookings,
    hint `units_in_use`, same as 150's shrink;
  - `move_listing_unit(p_unit_id, p_to_listing_id)`: same owner and same
    property, no future bookings, sets `musafir.unit_reassign`.

  `set_listing_unit_count` stays for count-only hosts and non-hotel listings.
- The wizard saves the type, then calls `add_listing_units` with the
  names. If that fails, the type stays a draft with the rooms step marked
  unfinished; nothing is half-published.

### Elsewhere

- Reservations, availability blocks and room moves between rooms stay per
  type (built in 151/152). The host calendar gets a property filter and
  shows rows by type, then by room name.
- Admin console: a properties list; the licence queue keyed by property.

## 9. Phases

| Phase | Migration(s) | Dart | Admin | Gate |
| --- | --- | --- | --- | --- |
| **1. Properties** | 153: `properties`, `listings.property_id`, owner trigger, hotel-fact sync trigger, backfill one property per hotel listing, RLS, licence moved to property, `add_listing_units` / `deactivate_listing_unit` / `move_listing_unit`, label unique per property | host: property wizard, "Add room type", Rooms field with names and ranges (`parseRoomLabels`), Duplicate type, property dashboard; guest: property page (single-room booking only, existing RPC), search collapse | properties list, licence queue by property | live backfill asserts every hotel listing has a property; current build still books |
| **2. Room-type facts** | 154: `bed_type`, `view_type`, `max_adults`/`max_children`, `breakfast_included` | room-type cards as in §1.1, "Only N rooms left", duplicate type | — | — |
| **3. N rooms of one type** | 155: `booking_groups`, `bookings.group_id`, `create_property_booking` (one item), `payments.group_id`, group accept/cancel, SSLCommerz group init + IPN, `search_listings` `p_rooms` + per-room maxima | Rooms stepper + per-room split in When panel (hotels), "For 2 Rooms, 2 Nights ৳X", group in My trips and host reservations | group view in bookings | SQL suite: all-or-nothing, race of two groups for the last rooms, IPN marks all paid, refund sum; payment run on sandbox before live |
| **4. Mixed types** (optional) | none (RPC already takes items) | per-type quantity steppers, cart summary | — | demand |

Each phase follows hotel.md's rule: database first, verify on live, then
`sh tool/build_web.sh`. Phase 1 needs no booking-engine change; phase 3 is
the only one that touches money and gets its own payment test run
(`docs/qa/payment-test-plan.md`).

## 10. Risks

- **Search collapse and pagination.** Collapsing children inside
  `search_listings` must happen before `limit/offset`, or pages come back
  short. Do it in the `base` CTE (`distinct on (coalesce(property_id, id))`
  ordered by price).
- **Sync triggers are definer writes on an owner-updatable table**: the 133
  lesson. Every `hotel_*` and location column on a child needs the guard, or
  a host edits one child out of sync.
- **Group payment is new money code.** Until phase 3 is live, a guest books
  rooms one at a time, which is today's behaviour, not a regression.
- **Reviews move to property level.** The listing rating stays as is; the
  property rating is an aggregate. Recompute it in the same rating-refresh
  trigger, not in Dart.

## 11. Decisions needed

- **R1.** Option A (property over listings) vs B (types under a listing).
  Recommended: A.
- **R2.** Group accept: all-or-nothing (recommended) vs the host may decline
  single rooms.
- **R3.** Max rooms per group (suggest 10, in `app_settings`).
- **R4.** Do guest houses (`room` type, several rooms) also get properties,
  or hotels only for now? Suggest hotels only; `kind` leaves room.
- **R5.** Rate plans in v1 or later. Suggest later; a breakfast flag only.
- **R6.** Mixed types in one checkout. Suggest no for v1 (ShareTrip doesn't
  either); N rooms of one type covers families and groups.
