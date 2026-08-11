# Context — Musafir

Shared vocabulary for the Musafir marketplace. Glossary only: no
implementation detail, no decisions, no plans. Those live in `docs/` (see
`docs/GUEST_SEARCH_FLOW.md`, `docs/architecture.md`).

## Roles

**Guest** — someone looking for a place to stay, and the side of the app they
browse and book from. A person is a Guest and a Host at the same time; which
side they see is a mode they choose, not a different account.

**Host** — someone offering a place to stay, and the side of the app they
manage listings and reservations from.

**Mode** — which side (Guest or Host) a signed-in person is currently using.
Remembered per person, so reopening the app returns them to the side they
were last on.

## Stays

**Listing** — one bookable offer from a Host.

**Type** — what unit a Listing is: a seat, a room, or a full house. What the
guest gets.

**Purpose** — what a stay is *for*: medical, exam, tourism, business, student,
or general. Independent of Type — a room and a seat can both serve a medical
trip. A Listing may serve several Purposes; a search carries at most one.

## Finding a stay

**Landmark** — a real-world place a guest wants to be near: a named hospital,
exam center, university, tourist spot, or business hub. Never a stay itself.

**Landmark category** — the kind of place a Landmark is (hospital,
exam_center, university, tourist_spot, business_hub). Each Purpose that needs
a Landmark maps to exactly one category. A category is *not* the same as an
external map provider's classification of a place — one category can span
several of those.

**Business hub** — a commercial *area* or district (Motijheel, Gulshan,
Karwan Bazar), not an individual business. The Landmark category for
business-purpose stays.

**Exam center** — any venue where an exam is sat: a school, a college, a
university, or a test center run by an examining body. Not a distinct kind of
institution, which is why one can rarely be recognised by classification
alone.

**Anchor** — the Landmark (or resolved point) a search measures distance
from. A search with an anchor ranks by nearness and shows everything around
the anchor; Purpose then stops acting as a filter, because a guest who picked
a specific hospital wants every stay near it, not only the ones a Host
labelled "medical".

**Suggestion** — a candidate place offered while the guest types, before it
has coordinates. Becomes a Landmark only once chosen. Suggestions come from
both the curated Landmarks the project maintains and a live map service; the
guest is not meant to be able to tell which is which, beyond a section
heading.
