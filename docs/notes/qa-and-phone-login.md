# Master OTP and phone-number canonicalisation

Moved verbatim from `CLAUDE.md` on 2026-10-01 to keep that file small.
The short rule for each section is still in `CLAUDE.md`; the reasoning is here.

## QA

**The master OTP is ON as of 2026-09-03, scoped to one number.**
`MASTER_OTP_PHONES` is the single entry `01673293542` — an explicit allowlist,
never `*` — because a Play reviewer cannot receive a Bangladeshi SMS and the
Console's *Sign in details* declaration needs credentials that work. That number
is the existing `naib1` account (verified host, real listings and bookings), so
the reviewer sees a populated app; `verify-otp` resolves it to the **legacy**
identity `phone.1673293542@musaafir.app`, not a fresh empty account.  otp = 3969

It had been OFF since 2026-08-26, when the secrets were unset on the owner's
instruction. Both functions read secrets at runtime, so neither the re-enable nor
a future unset needs a redeploy.

**The master path is not rate-limited, and cannot be given a longer code.** A
wrong guess makes `isMasterOtp` return false and falls through to the normal
path, which finds no `otp_attempts` row and answers "No active code" *without
incrementing anything* — so `OTP_MAX_ATTEMPTS` never applies. `OTP_LENGTH` is 4
and `OtpInputField` renders exactly 4 auto-submitting boxes, so the keyspace is
10,000 and a five-digit code could not be typed. Anyone who guesses that this
number is allowlisted can brute-force it unthrottled and take the account. Unset
the two secrets once a review passes, and re-set them for the next one.

Before the 2026-08-26 shutdown it was `1234` against `MASTER_OTP_PHONES='*'` —
the wildcard, so it really did log into **any** phone number, not an allowlist. `README.md` still shows the
command that set it to a single number; that is stale, and the live value was
confirmed by hashing candidates against the Management API's SHA-256 of the
secret. The secret is server-side: `OtpConfig.masterOtpEnabled` defaults to
false, so a plain `flutter build` never carried a bypass regardless.

If you re-enable it — the Play reviewer needs a login that does not require
receiving a Bangladeshi SMS, so you probably will — use an **explicit allowlist,
never `*`**, and mind the format. `masterOtpAllowlist()` runs each entry through
`normalizePhone()`, which reduces every spelling to the **11-digit leading-`0`**
form, so `01673293542`, `+8801673293542` and now the bare `1673293542` all match
the same entry. The bare form used to match nothing, which is the likeliest
reason the allowlist was widened to `*` in the first place — see the section
below for the account-duplication bug that same gap caused. The stale
`README.md` command still shows the pre-fix single-number form.

Login goes through the `send-otp` Supabase edge function rather than the Dart
`ConsoleSmsGateway`, so driving a login can attempt a real SMS — do not automate
it against a number you do not own. That is also why the unset above was *not*
verified by attempting a login.

## One phone number, one account

`normalizePhone` in `supabase/functions/_shared/otp.ts` is not formatting — it
**decides which account a login lands on.** `verify-otp` turns its output into
the synthetic auth identity `phone.<canonical>@musaafir.app` and creates one
account per distinct value, so two spellings of one number that canonicalise
differently are two different people: separate listings, separate bookings, and
a separate identity verification to submit and have approved.

It shipped with a hole. `+880…`, `880…` and an already-canonical `01…` were all
handled, but a **bare 10-digit** number matched no branch and passed through
unchanged — while `phone_input_field.dart` renders `+880` as a decorative
`prefixIcon` and submits the raw field text, so the UI actively invites you to
omit the zero. Four production accounts were duplicated before anyone noticed,
with users submitting documents twice and their listings split across two
logins. Migration 109 merged them (**applied 2026-08-27**).

Two things guard it now, and both matter:

- **`lib/services/auth/phone_number.dart` is the only Dart implementation.**
  There used to be three — `OtpService`, a diverged private copy on
  `SupabaseAuthService`, and `MockAuthService` — plus the TypeScript one, and
  **none had a test**. A shared "keep these in step" comment was already false.
- **`sh tool/verify_phone_parity.sh`** runs the same 16 inputs through the Dart
  and the TypeScript and diffs them. Run it whenever you touch either side; it
  is not in CI, which has no node step.

Existing rows are deliberately **not** renamed to the canonical form. The stored
email is an opaque key that `admin.generateLink` consumes and the client echoes
back to redeem the token, so a bulk rename would have to land in the same
instant as the function deploy — every returning user in the gap gets a brand-new
empty account, and 33 of 38 accounts are the legacy spelling. `verify-otp` reads
the canonical identity and then the legacy one instead, which is
order-independent and needs no data change.

For the same reason `otpLookupPhones` makes `verify-otp` accept an `otp_attempts`
row stored under **either** spelling. `send-otp` writes that row and `verify-otp`
reads it, but they are separate deploys — without this, the minutes between them
fail every bare-form login with "No active code".
