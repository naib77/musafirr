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

**Extent** — the real boundary of a named place: Uttara as the shape Uttara
actually is, Dhaka as the whole city. The counterpart to an Anchor. A search
that resolves to an Extent covers exactly that area, which is why "Uttara"
does not spill into Tongi and "Dhaka" is not reduced to a circle around its
centre. A place has an Extent; a Landmark is only ever an Anchor.

**Ring** — a distance around an Anchor. A search anchored to a bare point
widens through a series of Rings and takes the smallest one that contains any
stay, so a guest in a dense area is not shown the whole city. A Landmark
search uses a single Ring instead of widening, because "everything around this
hospital" is one question, not a series of them.

**Nearest fallback** — what a guest is shown when no Ring contains anything: the
closest stays regardless of distance, labelled as such. A sparse area returns
something honest rather than an empty screen.

## Speaking a search

**Spoken query** — a search said aloud rather than typed, in Bangla or
Banglish. It fills in the same fields the search sheet does; nothing is
searchable by voice that is not searchable by typing.

**Lexicon** — the word list that turns a Spoken query into places, types and
counts. It knows only the phrasings someone put in it, so it is the fast path
rather than the only one.

## Trust

**Verification** — a claim about a Host that Musafir has checked, shown to
guests as a badge. Each kind is earned separately; a Host may have any
combination.

**Address verification** — confirmation that a Host is really at the address
they gave. Earned by an admin **Verification visit**, not by uploading a
document: a bill proves a name on a page, not a person at a door. The Host
submits the address and their proof; the badge appears only after the visit.

**Verification visit** — an admin going to a Host's stated address in person
and recording what they found. The only thing that grants Address
verification.

## Getting paid

**Payout method** — an account a person wants to be paid into: a bKash, Nagad
or Rocket wallet, or a bank account. Belongs to a person rather than a role,
because both sides need one — a Host to receive earnings, a Guest to receive a
refund.

A payout method is **never edited**. Changing where you get paid means adding a
new one and **retiring** the old, which leaves the old account on file and
timestamped. This is the whole defence against a quietly repointed payout: a
changed destination is always a new row in the review queue, never an
untraceable edit.

**Retired** — a payout method withdrawn from use. It is kept forever, because
past **disbursements** point at it as the record of where money actually went;
deleting it would rewrite settled history.

**Payout verification** — an admin checking that a payout method's account
holder name matches the identity already on file, before any money can be sent
to it. A method is *pending* until then, and nothing will be paid to a pending
one. The same shape as an address **Verification visit**: the credential means
"a person checked", so a person checks.

**Disbursement** — money the platform has sent out, recorded after the fact.
Two kinds: a **Payout** to a Host for stays they have earned, and a **Refund**
to a Guest. Recording it is what stops the same stay being paid twice, and what
gives a reference to quote when someone says the money never arrived.

Sending is manual today — an admin transfers from the bKash app or their bank
and then records it. The ledger is the product; the transfer is not automated.
