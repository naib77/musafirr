<!--
NEW DOCUMENT — no live counterpart yet. web/legal/ has privacy.html and
terms.html but no refund page; terms-conditions.md §4 now points here. To ship
it, convert to web/legal/refund.html in the same style as its siblings and add
it to the footer links of all three existing pages.

The *mechanics* below are read off the code and are true today: payment happens
only after the host accepts (docs/sslcommerz.md), pending requests expire after
24h (booking_lifecycle_service.dart), refunds are manual Disbursements to a
verified payout method (CONTEXT.md "Getting paid"), and there is no platform
service fee to withhold (host payout = full booking total).

The *numbers* — the 72-hour cancellation window, the first-night retention, the
10 working days — are proposals, chosen to be simpler and more guest-friendly
than Travela's tiered scheme (their smallest refund tier keeps 65%+). Nothing
in the code enforces them yet; the owner must sign them off before this goes
live.

2026-08-30 revision after reading Airbnb's Rebooking & Refund Policy (help
article 2868): booking-issue reporting window widened 24h → 72h (24h was
harsher than the harshest mainstream comparator), partial-stay refunds spelled
out, fraud exclusion added, and force majeure split into its own document
(major-disruptive-events-policy.md) referenced from §5.

NOT LEGAL ADVICE. Have counsel review before the app is public. See
web/legal/_shared.md.
-->

# Refund & Cancellation Policy

**Musaafir** · Last updated 30 August 2026

This policy says what happens to your money when a booking is cancelled or
goes wrong. It forms part of our [Terms & Conditions](terms-conditions.md).
Musaafir charges **no service fee and no cancellation fee** — a refund is a
refund of what you actually paid, and the tables below say how much of it
comes back.

**The short version.** You pay nothing until a host accepts your request, so
withdrawing a request is always free. After you have paid, cancelling three or
more days before check-in gets you a full refund. If the host cancels, or the
stay is not what the listing promised, you get a full refund regardless of
timing.

## 1. When money actually moves

Understanding the refund rules starts with when you pay:

- A booking request is **free to make**. Nothing is charged when you request.
- The host has **24 hours** to accept. If they do not respond, the request
  expires on its own and you owe nothing.
- Payment is due **after the host accepts** — online through SSLCommerz
  (cards, bKash and other mobile wallets), or in cash on arrival where the
  host accepts cash.
- A host can only mark a stay complete once it is paid.

So a cancellation before acceptance, or before you have paid, never involves a
refund — there is nothing to refund. The rest of this policy is about bookings
you have already paid for online.

## 2. If you cancel (guest)

| When you cancel | What you get back |
| --- | --- |
| Before the host accepts, or before you have paid | Nothing was charged — nothing to refund |
| 72 hours or more before check-in | **100%** of what you paid |
| Less than 72 hours before check-in, up to the check-in time | Everything except the **first night**. A one-night stay gets no refund |
| After check-in, or if you do not show up | No refund, unless section 4 or 5 applies |

Cancelling is done from **Trips** in the app; the host is notified in your
conversation automatically.

## 3. If the host cancels

You get a **100% refund**, always, no matter when the cancellation happens —
and we will help you find another stay for the same dates where we can.

Hosts: cancelling an accepted booking without a genuine reason harms guests
and your standing on the platform. Repeated cancellations can lead to your
listings being demoted, suspended, or your account removed — see the
[Terms & Conditions](terms-conditions.md). A cancellation covered by the
[Major Disruptive Events Policy](major-disruptive-events-policy.md) carries no
penalty.

## 4. If the stay is not what was promised

You are entitled to a refund — up to a full one — when a **booking issue**
occurs:

- **You cannot get in.** The host cannot be reached at check-in, fails to hand
  over keys or access, or refuses you the stay — including refusing you for
  who you are (see the
  [Nondiscrimination Policy](nondiscrimination-policy.md)).
- **The listing was materially inaccurate.** Wrong type of space (a shared
  room sold as a private one, a room sold as a whole unit), a materially
  different location, missing rooms, undisclosed other occupants, or advertised
  essentials — bathroom, kitchen, AC, water, electricity backup — absent or
  broken.
- **It is not clean or not safe.** The space is unsanitary, has undisclosed
  pests or animals, or has a hazard that genuinely affects your stay.

For a booking-issue claim to be valid, you must:

1. **Report it within 72 hours** of discovering it — through the report option
   in the app or to **support@musaafir.app** — with photos or video where the
   issue is photographable. If reporting that fast was genuinely not possible,
   tell us why and we may still accept the claim;
2. **Give the host a reasonable chance to fix it** (a missing key gets
   delivered, a dirty room gets cleaned), unless the issue is a safety issue
   or the host is unreachable;
3. **Not have caused the issue** — yourself, your co-travellers, or anyone you
   invited; and
4. **Not stay on regardless.** If the issue is unresolved and you remain for
   the rest of the booking anyway, we may reduce the refund to the nights
   affected.

Where a booking issue is confirmed, we refund the affected nights in full —
the whole booking if you had to leave or never got in; the remaining nights if
the stay failed partway. How much comes back scales with how severe the issue
was, how much of the stay it affected, and the evidence provided. Because the
host is paid the full booking amount, every taka refunded for a booking issue
is recovered from the host's payout.

A fabricated or exaggerated claim is fraud: it violates our
[Terms & Conditions](terms-conditions.md) and can end your account. Hosts may
dispute a booking-issue decision with their own evidence — see section 8.

## 5. Major disruptive events

When a large-scale event — a cyclone evacuation, a curfew, a declared public
health emergency — prevents or legally prohibits stays in an area, the
[Major Disruptive Events Policy](major-disruptive-events-policy.md) overrides
the tiers in section 2: guests cancel with a **full refund** regardless of
timing, and hosts cancel without penalty. That policy says exactly what
qualifies and what does not.

## 6. Cash bookings

Where you pay the host in cash, Musaafir never holds your money, so there is
nothing we can refund ourselves. Cancellation before check-in simply means you
do not pay. If a booking issue arises on a cash stay after you have paid the
host, report it the same way — we will mediate, and a host who keeps money for
a stay they did not honestly provide faces the same enforcement as in
section 3 — but the repayment itself must come from the host.

## 7. How refunds are paid, and how fast

Refunds are paid to a **payout method** on your Musaafir account — a bKash,
Nagad or Rocket wallet, or a bank account — added under Profile → Payments.
Before the first payment to any method, we verify that the account holder's
name matches the identity on your account; a refund cannot be sent to a method
that has not been verified. This is deliberate: it is what prevents someone
else redirecting your refund.

Once approved, a refund is sent within **10 working days**, and usually much
sooner. Every refund is recorded with a reference you can quote if the money
does not arrive.

## 8. Disagreements

If you believe a refund decision is wrong — guest or host — reply to the
decision or write to **support@musaafir.app** with the booking reference and
any evidence within **7 days**. A person, not a rule, reviews disputes.

## 9. Changes

We may change this policy; the date at the top changes when we do. A
cancellation or claim is handled under the policy that was in force when the
booking was made.

## 10. Contact

iObytes, Dhaka, Bangladesh — **support@musaafir.app**
