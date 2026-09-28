# Bulk notifications

Sending one in-app notification (and, where allowed, a push) to many people from
the admin console. Migration 129 and `/notifications` in `../musafir-admin`.

Read `docs/BULK_SMS.md` first if you have not: this is its sibling, and the
interesting part is **where the two deliberately differ**.

## Why this is not the SMS design

| | Bulk SMS (128) | Bulk notifications (129) |
| --- | --- | --- |
| Delivery | a worker I wrote, draining a queue | `on_notification_send_push`, which already existed |
| Cost | real money per segment | none |
| Recipient key | a canonical phone, which must be gated and deduped | `user_id` — a primary key does both |
| Reach on live | **38** of 44 | **44** of 44 |
| Partway state | unavoidable, hence claim-before-send | impossible: one `insert … select`, one transaction |
| Retry | needed | meaningless |

**So there is no queue, no worker, no cron sweep and no status column here, and
adding them would be cargo cult.** The rows either all land or none do. The
"nobody twice" property that the SMS side buys with a unique index comes free,
because the audience is selected from `profiles`.

Pressing send twice does send twice — correctly. The confirmation step in the
console is what guards that, not the database.

## The gap this exposes, and what it does NOT fix

`notification_preferences` has existed all along — `global_enabled`, quiet
hours, per-category `enabled` and `channels` — and **`send-push-notification`
references none of it.** `NotificationPreferences.shouldDeliver` in
`lib/models/notification_preferences.dart` is a client-side read, and the push
goes out regardless. That is the "the booking form checks it is not
enforcement" pattern one level down.

129 honours those preferences **for bulk campaigns only**, at the moment the
rows are created. It deliberately does not change what happens to a booking
confirmation or a new-message alert.

The distinction that makes that defensible: a booking alert is something the
user asked for by using the app. A bulk campaign is the exact thing those
toggles were built to refuse. Retrofitting the whole notification system is a
bigger change than this, and doing it silently inside a marketing feature is the
wrong place to discover it broke check-in reminders.

**That leaves a real known gap.** Everything except bulk campaigns still ignores
user preferences. It is worth closing; it is not closed here.

## Four things that will bite you

- **`notification_preferences` is LEFT joined, and that is the whole ballgame.**
  Exactly **one** of 44 accounts has a row. An inner join reduces every campaign
  to **1 recipient** — measured, not guessed. An absent row means the app's
  defaults (enabled, both channels), matching `getForCategory` returning
  `const CategoryPreferences()` for a missing key.

- **Quiet hours cross midnight.** The default window is 22:00–07:00, so
  `v_local between start and end` is *false for the entire window* — the naive
  version reports "not quiet" and pushes at 3am, which is precisely what the
  feature exists to prevent. The `case` handles `start > end` by wrapping.
  Row 11 of the test uses a genuinely wrapping window; an earlier version of
  that test used `now ± 1 hour`, which never wraps, and **passed against the
  broken implementation**. If you touch this, check the test can still fail.

- **Times are read as `Asia/Dhaka`.** `quiet_hours_start/end` are `time` with no
  zone and the product is Bangladesh-only, so there is nothing else they could
  mean — but it is an assumption, written down here rather than inferred from
  the code.

- **`fn_notification_category` must cover every enum label.** An unmapped type
  returns null, which silently ignores the user's category setting rather than
  failing. The two enums have **already drifted**: the database carries
  `booking_rejected`, `checked_in` and `review_prompt`, which the Dart enum does
  not have at all. Row 1 of the test walks `enum_range` and fails on the first
  unmapped label, so the next value added is caught rather than quietly opting
  its recipients out of their own preferences.

## `suppress_push`, and why it is a data flag

A user whose preferences say the promotion category is `inApp` only still wants
the notification — they just do not want their phone to buzz. The trigger had no
way to express that, because it pushes on every insert.

So `data->>'suppress_push' = 'true'` short-circuits it, set **per recipient**,
because the preference is. One campaign can buzz the phones of people who allow
it while still reaching the in-app inbox of those who did not.

It is a flag rather than the trigger consulting preferences itself, and that is
the point: the key is absent from all 787 existing rows (checked, not assumed)
and nothing else writes it, so **every notification the app already raises
behaves exactly as before**. A trigger that started reading preferences for all
notifications would change booking and message delivery as a side effect of a
marketing feature.

Rows 22 and 23 of the test prove both directions on the wire — pg_net queues
into an ordinary table, so inside a rolled-back transaction the request is built
and then discarded unsent.

## The three numbers the console shows

They are three different facts and are never collapsed:

| | |
| --- | --- |
| **Will receive** | rows created — people who see it in the app |
| **Phone will buzz** | of those, how many also get a push |
| **Opted out** | left out entirely, by their own settings |

29 of 44 accounts have an active FCM token, so "will receive" is routinely much
larger than "will buzz" even before preferences are considered. Reporting one
number would misdescribe the send in whichever direction was chosen.

## The ceiling

`notification_bulk_max_recipients`, seeded **2000**. Same fail-closed reasoning
as `sms_bulk_max_recipients`: **0 means DISABLED, not unlimited**, and over the
cap is **refused, never truncated**. Seeded higher than the SMS cap because
these cost nothing — the limit is against a mistake reaching everyone, not
against a bill.

## What is NOT built

- **No scheduling.** A campaign sends when an admin presses the button. Quiet
  hours therefore suppress the *push* rather than deferring it; the person still
  finds the notification in the app.
- **No per-recipient detail page.** `notifications.campaign_id` records which
  campaign produced a row, so the query is there, but nothing renders it.
- **No merge fields.** Unlike SMS, the body is the same for everyone.
- **No CSV.** Notifications need an account; a phone number with no account has
  nowhere to receive one.
- **Nothing outside bulk campaigns honours `notification_preferences`** — see
  above.
