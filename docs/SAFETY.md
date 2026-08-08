# Safety at Musafir

How Musafir protects hosts and guests today, how that compares with Uber,
Pathao, and Airbnb, and what's still missing. Updated 2026-08-08.

Platform safety is built in layers — every major marketplace converges on the
same five:

1. **Know who everyone is** (identity)
2. **Tools during the trip/stay** (SOS, sharing, tracking)
3. **A way to reach a human** (support / safety line)
4. **Money-backed protection** (insurance, damage cover)
5. **Reputation and consequences** (reviews, reports, removal)

## What Musafir has today

### Layer 1 — Identity

| Feature | Guest | Host |
|---|:-:|:-:|
| Phone verification (SMS OTP login — every account is a real phone number) | ✅ | ✅ |
| Identity verification: NID front/back + live selfie, reviewed by a human admin | ✅ available | ✅ available |
| Verification revocable by admin at any time (from any status) | ✅ | ✅ |

Identity verification exists for both sides but is **not required to book or
to list** — enforcing it at booking time is a pending product decision.

### Layer 2 — During the stay

| Feature | Guest | Host |
|---|:-:|:-:|
| Safety center (trip detail → "Safety & help", or Profile → Safety) | ✅ | ✅ (via Profile) |
| One-tap **call 999** (national emergency: police/fire/ambulance) | ✅ | ✅ |
| Stay summary ready to read to a dispatcher (address, dates, map link) | ✅ | — |
| **Share my stay** with a trusted contact (WhatsApp/SMS/anything) | ✅ | — |
| Contact privacy: phone numbers exchanged **only after** the booking is confirmed, via a server-enforced RPC scoped to the two participants | ✅ | ✅ |
| All chat in-app → auditable record if something goes wrong | ✅ | ✅ |
| Automated check-in / check-out messages (arrival instructions, checkout) | ✅ | ✅ |

### Layer 3 — Reaching a human

| Feature | Guest | Host |
|---|:-:|:-:|
| **Report a problem** — from listing page, chat menu, safety center; categories: safety / fraud / inappropriate / listing problem / other | ✅ | ✅ (chat) |
| Reports are confidential (the other party is never told who filed) | ✅ | ✅ |
| Admin triage queue (open → reviewing → resolved/dismissed, with outcome notes and an open-count badge) | ✅ | ✅ |
| **Block a user** — hides their listings from Explore and their conversations from the inbox | ✅ | ✅ |

### Layer 4 — Money

| Feature | Guest | Host |
|---|:-:|:-:|
| In-app online payment (SSLCommerz) with full transaction audit trail | ✅ | ✅ |
| Cash payment recorded in-app: host confirms receipt → auditable payment row + receipt + guest notification | ✅ | ✅ |
| Double-booking impossible at the database level (exclusion constraint) | ✅ | ✅ |

### Layer 5 — Reputation

| Feature | Guest | Host |
|---|:-:|:-:|
| **Two-way reviews** — guests review stays, hosts review guests | ✅ | ✅ |
| Ratings drive search ranking (bad actors sink) | ✅ | ✅ |
| Superhost badge | — | ✅ |

## How the big platforms do it

**Uber** — periodic Real-Time ID Checks on drivers (selfie match); in-app
emergency button that shares live location + vehicle details with 911; Share
My Trip with trusted contacts; PIN verification you're in the right car;
RideCheck (crash / long-stop detection that proactively asks both parties if
they're OK); two-way ratings.

**Pathao** (closest market comparison — Bangladesh) — one-tap SOS that sends
live location + vehicle details **directly to the police control room**; live
location sharing; driver identity + vehicle verification; a dedicated Safety
menu; emergency helpline **13301** with a call center and rapid response team;
insurance up to **৳1 lakh** for riders and passengers.

**Airbnb** — government-ID + selfie identity verification (required for
guests in 35 countries); reservation screening for party/damage risk;
approximate listing location until a booking is confirmed; 24-hour safety
line (agent within ~30 seconds); AirCover: $3M host damage protection + $1M
liability; two-way reviews; report/block flows.

## Comparison

| Capability | Uber | Pathao | Airbnb | **Musafir** |
|---|:-:|:-:|:-:|:-:|
| Phone-verified accounts | ✅ | ✅ | ✅ | ✅ |
| Government-ID + selfie verification | ✅ drivers | ✅ drivers | ✅ (req. in 35 countries) | ✅ built, **not enforced at booking** |
| Emergency call from the app | ✅ 911-integrated | ✅ direct to police | via safety line | ✅ dials 999 (no data integration) |
| Share trip/stay with trusted contact | ✅ | ✅ | — | ✅ |
| Live location tracking | ✅ | ✅ | n/a (stays) | n/a (stays) |
| Proactive anomaly check (RideCheck-style) | ✅ | — | — | ❌ |
| Report + block | ✅ | ✅ | ✅ | ✅ |
| Human safety line / hotline | ✅ | ✅ 13301 + call center | ✅ 24h, ~30s | ❌ (admin queue only, no SLA) |
| Insurance / damage protection | ✅ | ✅ ৳1 lakh | ✅ $3M/$1M AirCover | ❌ |
| Contact masking / delayed exchange | ✅ masked calls | partial | ✅ | ✅ post-confirmation |
| Location privacy before booking | n/a | n/a | ✅ approximate until booked | ❌ exact pin shown to anyone |
| Two-way ratings/reviews | ✅ | ✅ | ✅ | ✅ |
| Reservation/risk screening | ✅ | — | ✅ | ❌ |

## Does Musafir protect both host and guest?

**Mostly yes, with a guest-side tilt during the stay and one host-side gap.**

- **Symmetric:** identity verification, reviews, reports, blocks, contact
  privacy, payment audit trail, and the admin queue all work identically in
  both directions. A host can report/block a guest from chat exactly as a
  guest can report a host.
- **Guest-tilted:** the stay-specific safety tools (share-my-stay, dispatcher
  summary, the "Safety & help" button on the trip sheet) live on the guest's
  trip view. The host's reservation detail has no equivalent button yet —
  hosts reach the safety center via Profile → Safety.
- **Host-side gap:** a listing's **exact map pin and full address are visible
  to anyone browsing**, before any booking. Airbnb deliberately shows only an
  approximate circle until confirmation. For hosts renting rooms in their own
  home, this is the single biggest asymmetry.

## What's missing (prioritized)

1. **Require verified identity to book** — the pipeline is fully built; this
   is one gate at booking time. Product decision: it trades early-growth
   friction for trust. (Airbnb's direction; the biggest single upgrade.)
2. **Approximate location until booking confirmed** — closes the host-side
   privacy gap above. Proximity search already works on distances, so search
   quality is unaffected.
3. **Safety button on the host's reservation detail** — parity with the
   guest trip sheet (small).
4. **A reachable human** — even one monitored hotline/WhatsApp number with a
   stated response window, shown in the safety center. This is Pathao's real
   edge locally; an admin queue nobody watches in real time is not a safety
   line.
5. **Server-side block enforcement** — blocks currently hide content in the
   client; the server should also refuse message delivery between blocked
   pairs.
6. **"Arrived safely?" check-in nudge** (RideCheck analog) — the automated
   check-in message exists; add a response prompt whose negative answer opens
   the report flow.
7. **Cash-payment guardrails in UI copy** — warn guests to pay only at
   check-in and only mark-as-received in the app; cash disputes will be the
   most common trust incident.
8. **Reservation risk screening** — later, when volume justifies it (e.g.
   flag first-time accounts booking same-day stays).
9. **Damage deposits → insurance** — the Airbnb/Pathao money layer. Start
   with a simple security-deposit flow; pursue a local insurer partnership
   only at real scale. Do not promise "protection" before the money exists
   to back it.

### Before real users (security prerequisites)

Safety features sit on top of account security. Two known items must be
closed before launch: disable the QA master-OTP login shortcut, and finish
the Google Maps key restriction/rotation. Both are documented in the
project's ops notes.

## Operating the safety queue

Reports land in the admin console → **Safety** (sidebar, with an open-count
badge). Triage flow: **Open → Start review → Resolve (outcome note required)
or Dismiss**; resolved/dismissed reports can be reopened. Every report keeps
reporter, reported user, listing/booking context, and the free-text details.
Until a hotline exists, the queue should be checked at least daily — a
report categorized **"Safety concern"** deserves same-day contact with the
reporter.
