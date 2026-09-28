# Bulk SMS

Sending one message to many people, from the admin console. Migration 128, the
`send-bulk-sms` edge function, and `/sms` in `../musafir-admin`.

## The one rule

**Nobody is ever texted twice.** Everything below is shaped by that, and where a
choice had to be made between losing a message and repeating one, losing wins.

That is not squeamishness. An unsent marketing message costs nothing and can be
sent again deliberately. A duplicate costs money, annoys the recipient, and — on
a non-masked route to numbers that never asked for marketing — is the kind of
thing that gets a sender ID blocked.

## Shape

```
admin console  ──▶  admin_create_sms_campaign     (draft, nothing sent)
               ──▶  admin_add_sms_recipients      (queue built, deduped)
               ──▶  admin_start_sms_campaign      ← the irreversible one
                         │
                         ├─ console invokes send-bulk-sms   (promptness)
                         └─ pg_cron sweeps every minute     (the guarantee)
                                     │
                         send-bulk-sms ──▶ admin_claim_sms_batch   (mark 'sending', COMMIT)
                                       ──▶ GenNet iSMS
                                       ──▶ admin_mark_sms_result   ('sent' / 'failed')
```

### Claim before send

`admin_claim_sms_batch` flips rows to `sending` and **commits before GenNet is
called**. So a crash in that gap loses the message rather than repeating it, and
the row is left in `sending` where nothing picks it up again — not the sweep,
not a second worker, not the Retry button.

`admin_retry_sms_failures` therefore re-queues **only** rows the provider
actually refused (`failed`). Row 19 of the test file is the negative control:
flip a row to `sending`, retry, and assert it was left alone. Making retry
"helpful" enough to include it turns that row red, which is exactly the bug it
is there to catch.

The claim uses `for update skip locked`, so the console's direct invocation and
the cron sweep can overlap: the second one takes the rows the first did not.

### Deduplication is an index, not a check

`sms_recipients` has a unique index on `(campaign_id, phone)`. The compose form
dedupes too, and the audience query does `distinct on (phone)` — but those exist
so the **count the admin confirms is honest**, not to make the send safe. The
index is what makes it safe, the same way `bookings_no_overlap` rather than the
booking form's `if exists` is the real backstop.

## The phone number is a gate, not a router

`fn_canonical_bd_phone` returns **null** for anything that is not an assigned BD
mobile (`01[3-9]` + 8 digits). This is a deliberate divergence from
`normalizePhone` in `supabase/functions/_shared/otp.ts` and `canonicalBdPhone`
in `lib/services/auth/phone_number.dart`, which must pass unrecognised input
*through* so a mistyped login fails against a nonexistent account.

It matters because `profiles.mobile` is not clean. On live, as of 2026-09-16:

| | |
| --- | --- |
| Profiles | 44 |
| Distinct `mobile` values | 40 — four numbers appear twice |
| Rows that are not a number | 2 — one literal `pending_<uuid>`, one `+880 1233293542` (`123` is not an assigned prefix) |
| **Actually reachable** | **38** |

A router would have handed the placeholder string to the SMS provider. The test
file's rows 01–05 pin both halves: junk refused, and real numbers in all four
spellings still accepted — without that second half a gate that refused
everything would pass.

**The audience prefers the auth identity over `profiles.mobile`**, falling back
to it. The identity is the number that actually received an OTP, so it is known
deliverable; `mobile` is typed and displayed. Where both exist they normally
canonicalise to the same thing — the identity only wins the cases where they do
not.

## Opt-out is keyed on the number

`sms_suppressions(phone)`, not a column on `profiles`. A number uploaded by CSV
has no account, so a profile column would have nowhere to record that its owner
asked to stop — and that is the case most likely to need it.

`kind = 'promotional'` honours the list; `kind = 'transactional'` does not, and
is for something a user cannot reasonably opt out of (a service interruption).
It is not a way round the list for marketing. Rows 12 and 13 of the test are the
pair: a suppressed number skipped by one and reached by the other, so neither
can pass for the wrong reason.

## The ceiling fails CLOSED, and that inverts the house rule

`sms_bulk_max_recipients` (seeded 500). **0 means bulk SMS is DISABLED, not
unlimited** — the opposite of `max_devices_per_user` (125) and
`android_min_version_code` (122).

Those fail open because the worst they can do is lock a user out of an app they
can only get back into via a real SMS. This one fails closed because the worst
*it* can do is spend money texting thousands of people, and neither the money
nor the messages come back. There is no "unlimited" value, and a campaign over
the ceiling is **refused, never truncated** — sending to the first 500 of 900
would leave the admin believing 900 were reached.

Whoever adds the next setting: check which direction the damage runs before
copying the 0-means-no-limit idiom.

## Cost is shown before it is spent

Bangla is UCS-2: **70 characters per segment against English's 160**, so the
same-length message costs more than twice as much. The compose screen shows the
encoding, the per-recipient segment count and the total live.

`fn_sms_segments` / `smsSegments` are deliberately **conservative** — anything
outside printable ASCII counts as UCS-2, which over-estimates a message using
only GSM-7's handful of accented letters by one tier. Over-estimating is the
safe direction. The provider's own count is what appears on the invoice.

Concatenated segments give up header room, so 161 GSM-7 characters is two parts
of 153, not 160 + 1. Both implementations get this right and both are tested.

## "Formatting" means merge fields

SMS has no bold, no colour, no links that render. What it has is
personalisation: `{{name}}` and `{{first_name}}`.

Each recipient's text is **rendered at queue time and stored** on their row
rather than re-derived at send time, so the preview is exactly what goes out and
the campaign stays auditable after an account is renamed.

An unknown placeholder is **left visible** rather than blanked, so a typo shows
up as `{{nmae}}` in the preview instead of silently disappearing — and
`createCampaignAction` refuses the campaign outright, because the preview is
skippable and the refusal is not.

## CSV

A `phone` column and optionally a `name` column, found by header name; with no
header, first column is the number and second the name. Commas, semicolons and
tabs all work (Excel emits all three depending on locale), quoted fields are
honoured, and the byte-order mark Excel prepends is stripped.

**Every unusable line is reported with its line number**, never silently
dropped. An importer that quietly discards a tenth of a file is how an admin
comes to believe a campaign reached people it never did.

### Dropping a file

The whole card is the drop target, not just the button — a drop zone smaller
than the thing that looks like one is how a file lands on the page behind it.
Three details that are easy to get wrong and are written down because they were:

- **`dragleave` fires on every crossing into a child element**, so a boolean set
  from enter/leave flickers the highlight off while the file is still over the
  target. `dragDepth` counts enters against leaves instead.
- **A drop anywhere else makes the browser navigate to the file**, discarding a
  composed message with no warning. A document-level `preventDefault` on
  `dragover`/`drop` swallows that; the zone's own handler still runs.
- **The file input's value is cleared after each change**, or picking the *same*
  file again after a Remove fires no `change` event and appears to do nothing.

`fileRejectionReason` is a pure function in `src/lib/sms.ts` rather than logic
inside the form, so the drop zone and the picker cannot disagree about what they
accept. It refuses a spreadsheet by extension: an `.xlsx` read as text yields
several hundred "not a Bangladeshi mobile number" lines, which reads as the
importer being broken rather than the file being the wrong format — and the
admin's next move is to give up, not to re-save as CSV.

### The sample file

The compose screen offers **Sample file**, built in the browser from
`SAMPLE_CSV` in `src/lib/sms.ts` rather than served as a static asset — so the
file an admin downloads is the exact text the check script proves the importer
accepts. There is no second copy to drift out of step.

Every row earns its place: the four accepted spellings of a number, a name
containing a comma (quoted — the case a naive split gets wrong), a Bangla name,
and a row with no name at all. The numbers are format-valid but unassigned
(`…12345678`), so the file can be imported to try the flow without risking a
text to a stranger.

The download carries a **byte-order mark**. Excel sniffs encoding, and without
one it opens a UTF-8 CSV in the local 8-bit codepage — the Bangla name comes
back as mojibake and an admin who edits and re-saves uploads the damage.
`parseCsv` strips the BOM on the way in, so the download → edit → upload round
trip is closed, and a check pins both halves.

`../musafir-admin/scripts/check-sms-helpers.mjs` (`npm run check:sms`) is the
only test this parser has — 64 checks, including the quoted-comma case, which
goes red under a naive `line.split(",")`, and ten on the sample itself, which
go red if a single row of it stops importing.

## Deploying it

Order matters, and **none of this is done**:

1. Apply `supabase/migrations/128_sms_campaigns.sql`.
2. Deploy the function: `supabase functions deploy send-bulk-sms`.
   It reuses `GENNET_API_TOKEN` / `GENNET_SID` from `send-otp` — no new
   provider credential.
3. Set `SMS_WORKER_SECRET` on the function, and **three** rows in
   `app_secrets` so the cron sweep can reach it:
   - `sms_worker_url` = `https://<ref>.supabase.co/functions/v1/send-bulk-sms`
   - `sms_worker_secret` = the same value as `SMS_WORKER_SECRET`
   - `sms_worker_auth` = the project's **anon** key

   Until all three exist the sweep is a no-op (deliberately — a cron job that
   raises is a cron job that stops running), and campaigns rely solely on the
   console's direct invocation.

### The sweep needs two headers, and the second one is not optional

The edge-function **gateway rejects a request carrying no `Authorization`
header before any of our code runs** — `401 UNAUTHORIZED_NO_AUTH_HEADER`.
Verified against live: worker secret alone gets 401 from the platform; anon
bearer + worker secret gets 200.

So `sweep_sms_campaigns` sends both, and they do different jobs:

| Header | Satisfies | Proves |
| --- | --- | --- |
| `Authorization: Bearer <anon key>` | the platform gateway | **nothing** — the anon key ships inside `build/web` |
| `x-sms-worker-secret` | the function's own check, constant-time | that the caller is the sweep |

Sending only the bearer would let anyone holding the public key drive the
endpoint. Sending only the secret gets a silent 401 every minute, and the
sweep — the half that *guarantees* a campaign finishes — never runs at all.
That failure is invisible: campaigns still work whenever an admin is watching,
and stall forever when one is not.

`send_push_on_notification_insert` carries the same pair for the same reason;
it is the precedent to copy, not `send-otp`, which is called by a browser with
a real session.
4. Deploy `../musafir-admin` by hand; it has no deploy config.

The Flutter app needs **nothing**. No client change, no migration dependency,
no `build/web` rebuild.

## What is NOT built

- **No in-app opt-out.** The suppression list is admin-writable only. A user
  asking to stop has to ask a human, who sets it from the console. An "STOP"
  keyword would need an inbound webhook from GenNet, which is a separate
  integration.
- **No scheduling.** A campaign sends when an admin presses the button.
- **No delivery receipts.** `provider_status` records whether GenNet *accepted*
  the message, not whether the handset received it. DLR is another GenNet
  endpoint and another webhook.
- **No per-recipient merge data beyond the name.** The CSV's extra columns are
  parsed but not exposed as merge fields.
- **GenNet's batch endpoint is not used.** Every message is its own request, at
  a concurrency of 5. Whether `msisdn` accepts a comma-separated list was **not
  tested** — testing it means sending real SMS — and per-recipient status is
  worth more than the round trips saved at this volume.
