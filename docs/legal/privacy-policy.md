<!--
Markdown source for the live page web/legal/privacy.html. If you change one,
change the other — the HTML is what users and Google Play actually see.

NOT LEGAL ADVICE. The factual claims (what is collected, who it goes to) were
read off the code and are accurate as of 2026-08-26. Have counsel review before
the app is public. See web/legal/_shared.md.
-->

# Privacy Policy

**Musaafir** · Last updated 26 August 2026

This policy explains what Musaafir collects when you use the app or website to
find or host a stay, why we collect it, who we share it with, and how you get
it deleted. It covers the Android app (`co.iobytes.musafir`) and the web app.

**The short version.** We collect your phone number to sign you in, your
listing and profile details so stays can be found and booked, your location so
we can show nearby stays, and — if you choose to become a verified host — your
national ID and a selfie. We do not sell your data and we do not use it for
advertising.

## 1. Who we are

Musaafir is a marketplace for short and long stays in Bangladesh, connecting
guests with hosts. It is operated by iObytes, Dhaka, Bangladesh. For anything
in this policy, contact **support@musaafir.app**.

## 2. What we collect

| Data | Why | When |
| --- | --- | --- |
| Mobile number | It is your account identifier and how we sign you in, by one-time code (OTP) | Always — required |
| Name | Shown to the host or guest you are booking with | Always — required |
| Email address | Optional alternative contact | Only if you enter one |
| Profile photo | Shown on your profile and in chat | Only if you upload one |
| Approximate and precise location | To show stays near you, to centre the map, and to turn a place name into coordinates. Foreground only — we never collect location while the app is closed or in the background | Only while you use search or the map, and only if you grant the permission |
| Listing details and photos, including the property address and its coordinates | To publish your listing so guests can find and book it | Hosts, when you create or edit a listing |
| Booking records — dates, guests, prices, status | To operate the booking and keep a record for both sides | When you book or accept a booking |
| Messages between guest and host | To deliver in-app chat, and to investigate reports of abuse | When you send a message |
| Reviews and ratings you write | Published on listings and profiles | When you submit one |
| National ID number, photographs of your national ID (front and back), and a selfie | To verify that a host is a real, identifiable person. This is the most sensitive data we hold and we treat it accordingly | Hosts only, when you submit host verification |
| Proof-of-address document | To confirm a host controls the property, where our settings require it | Hosts only, when required |
| Payout details — mobile wallet or bank account | To pay hosts their booking earnings, and to send guests a refund | When you add a payout method |
| Payment records | To reconcile what has been paid for a booking | When a payment is made |
| Push notification token | To send you booking and message notifications | If you allow notifications |
| Microphone audio, transiently | Voice search. See section 4 | Only while you hold the voice search button |

### What we do not collect

- We have no advertising SDKs and no advertising identifiers.
- We do not track you across other apps or websites.
- We do not collect background or continuous location.
- We do not read your contacts, call log, or SMS messages. The app can read an
  incoming OTP message to fill the code in for you; that happens on your
  device and the message is not sent to us.
- We do not access your photo library. When you attach a photo, Android's own
  photo picker hands us only the images you tapped.

## 3. Permissions the app asks for

- **Location** — to find stays near you and centre the map. Decline it and
  search still works; you type a place name instead.
- **Camera** — to photograph a listing, your ID, or take a verification selfie.
- **Microphone** — voice search only, and only while you hold the button.
- **Notifications** — booking updates and new messages.

Each is asked for at the moment it is first needed, and each is optional. The
app works without any of them, with the corresponding feature unavailable.

## 4. Voice search

When you use voice search, the speech-to-text conversion is performed by
Google's speech recogniser — either on your device or through Google Play
services. **We never receive or store the audio.** What reaches us is the
transcribed text of your search.

That text is then interpreted into search filters. This is normally done on
your device; if it cannot be parsed locally, the text of your query is sent to
Google's Gemini API to be turned into filters. Only the query text is sent —
not your identity, your account, or your location.

## 5. Who we share data with

We do not sell personal data and we do not share it with advertisers. We share
it with these service providers, only to the extent needed to run the app:

| Provider | What it receives | What for |
| --- | --- | --- |
| Supabase | Effectively all account, listing, booking, message and document data | Our database, file storage, and server functions |
| Google Maps Platform | Coordinates and place or address text | Maps, geocoding, place search, and directions |
| Google Firebase Cloud Messaging | Your device push token and the notification content | Delivering push notifications |
| Google (speech recogniser) | Voice search audio, transiently | Speech to text — see section 4 |
| Google Gemini API | The text of a voice search query, when it cannot be parsed on device | Turning a spoken query into search filters |
| SMS gateway (GenNet) | Your mobile number and the one-time code | Delivering your login OTP |
| SSLCommerz | Payment amount, booking reference, and whatever you enter on their payment page | Processing online payments. Card and wallet credentials are entered on SSLCommerz's own page and never pass through us |

We also share data between users where the product plainly requires it: when a
booking is made, the guest and host see each other's name, profile photo, and
the contact details needed to complete the stay. A host's verification
documents are **never** shown to guests — only a verified badge.

We may disclose data where we are legally required to, or where it is
necessary to investigate fraud, abuse, or a threat to someone's safety. How a
law enforcement request is made and handled is set out in our
[Guidelines for Law Enforcement](law-enforcement-guidelines.md).

## 6. How long we keep it

- **Account data** — while your account exists.
- **Bookings, payments, and payouts** — retained after account deletion where
  we need them for financial and tax records, or to resolve a dispute.
- **Verification documents (ID, selfie, address proof)** — kept while you are
  a host, and deleted when your account is deleted, subject to the
  fraud-prevention exception above.
- **One-time codes** — minutes. They expire quickly and are stored hashed, not
  in plain text.
- **Voice audio** — never stored by us at all.

## 7. Security

All traffic between the app and our servers is encrypted in transit (HTTPS).
Access to stored data is restricted by row-level database rules so that, as a
rule, you can read your own records and the records of bookings you are party
to. Login codes are stored hashed. Verification documents are held in
non-public storage.

No system is perfectly secure. If we discover a breach affecting your data we
will notify you and take the steps required of us.

## 8. Your choices and rights

- **See or correct your data** — most of it is editable in the app under
  Profile. For anything else, email us.
- **Withdraw a permission** — at any time in Android Settings → Apps →
  Musaafir → Permissions.
- **Turn off notifications** — in the app's notification settings or in
  Android Settings.
- **Delete your account and data** — see *Delete your account*
  (`/legal/delete-account.html`). You do not need the app installed to request
  this.

We answer requests to **support@musaafir.app** within 30 days.

## 9. Children

Musaafir is not intended for anyone under 18 and we do not knowingly collect
data from children. If you believe a child has created an account, email us
and we will remove it.

## 10. Changes

If we change this policy we will update the date at the top of this page, and
for a significant change we will tell you in the app before it takes effect.

## 11. Contact

iObytes, Dhaka, Bangladesh — **support@musaafir.app**
