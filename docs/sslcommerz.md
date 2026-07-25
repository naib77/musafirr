# SSLCommerz payments — integration reference

Guests pay for a booking through **SSLCommerz** (sandbox). Payment is available
**any time after the host accepts and before the stay is finished** — i.e. while
`booking_status` is `confirmed` (accepted) or `active` (checked in) — and the
host can only mark a booking **completed** once `payment_status = 'paid'`.

The amount is taken from the booking's **server-side** `total_price` (see the
booking-hardening RPC in migration 070) and every successful payment is
**re-validated against SSLCommerz's Validation API** server-side before it's
trusted — the client never decides that a payment succeeded.

Defined in migrations
[`072_sslcommerz_payments.sql`](../supabase/migrations/072_sslcommerz_payments.sql)
+ [`073_payment_transaction_details.sql`](../supabase/migrations/073_payment_transaction_details.sql)
and Edge Functions
[`sslcommerz-init`](../supabase/functions/sslcommerz-init/index.ts) +
[`sslcommerz-ipn`](../supabase/functions/sslcommerz-ipn/index.ts)
(all applied/deployed to the live project `bojkmonskqlhuakxhzcb`).

## Flow

```
Guest requests booking        → booking_status = pending,             payment_status = unpaid
Host accepts                  → booking_status = confirmed,           payment_status = unpaid
Guest taps "Pay ৳X"           → sslcommerz-init creates a session → gateway opens (confirmed OR active)
Guest completes payment       → SSLCommerz → sslcommerz-ipn validates → payment_status = paid
Host taps "Service Complete"  → allowed only when payment_status = paid → booking completed
```

Payment settles via **two** independent paths, both idempotent:
1. **Browser redirect** — the WebView loads `…/sslcommerz-ipn?redirect=success`,
   which validates + marks paid, then the app closes the WebView.
2. **Server-to-server IPN** — SSLCommerz POSTs `…/sslcommerz-ipn` directly.

After the gateway closes, the app polls the specific attempt by `tran_id`
(`SslcommerzService.awaitSettlement`) and resolves it to **paid / failed /
pending** — so a declined or unverifiable payment surfaces a real error rather
than a silent "will update".

## Tables

### `public.payments`
| column | type | notes |
|---|---|---|
| `id` | uuid | pk |
| `booking_id` | uuid | → `bookings.id` (cascade) |
| `user_id` | uuid | → `auth.users.id` (the paying guest) |
| `tran_id` | text, unique | our reference: `MSFR-<booking8>-<rand8>` |
| `amount` | numeric | server-computed booking total at init time |
| `currency` | text | default `BDT` |
| `status` | text | `initiated` \| `paid` \| `failed` \| `cancelled` |
| `val_id` | text | SSLCommerz validation id (on success) |
| `card_type` | text | method / card scheme (e.g. `VISA`, `bKash`) |
| `card_no` | text | masked PAN, e.g. `432149XXXXXX0667` |
| `card_issuer` | text | issuing bank |
| `card_brand` | text | e.g. `VISA`, `MASTER` |
| `bank_tran_id` | text | bank's transaction reference |
| `store_amount` | numeric | amount credited to the store (after gateway fee) |
| `currency_amount` | numeric | amount in the transaction currency (validation) |
| `risk_level` | text | SSLCommerz fraud risk level |
| `risk_title` | text | human label for the risk level |
| `tran_date` | text | gateway-reported transaction time (string) |
| `validated_at` | timestamptz | when we confirmed via the Validation API |
| `gateway_response` | jsonb | full raw payload (session failure / validation / IPN) for audit |
| `created_at` / `updated_at` | timestamptz | `updated_at` kept fresh by a trigger |

> The structured `card_*` / `store_amount` / `risk_*` / `tran_date` /
> `validated_at` columns were added in migration 073; the complete payload is
> always in `gateway_response`. Failed and cancelled attempts are saved too
> (with their response), so **every** transaction is recorded.

### `public.bookings` (added column)
`payment_status text default 'unpaid'` — `unpaid` \| `paid` \| `refunded`.
Mirrors the successful payment so lists/gates don't need a join.

## RLS / security
- `payments` is **read-only for clients**: the paying guest, the listing's host,
  or an admin can `select`; there is **no** client `insert`/`update` policy.
- All writes happen in the Edge Functions using the **service role** (bypasses
  RLS). `sslcommerz-init` also runs a service client but first resolves the
  caller from their JWT and checks the booking is theirs + `confirmed`/`active`.
- Admins read `payments` through the same select policy (see the admin panel
  below).
- A success is only trusted after calling the **Validation API** with the secret
  store password and confirming `status ∈ {VALID, VALIDATED}`, `tran_id` matches,
  and the validated `amount` equals the `payments.amount` we recorded at init.

## Edge Functions

### `sslcommerz-init` (JWT-protected)
`POST { booking_id }` → `{ success, gateway_url, tran_id } | { success:false, error }`

Loads the booking (service role), verifies caller ownership +
`booking_status ∈ {confirmed, active}` + not already paid, inserts a `payments`
row (`initiated`), calls the SSLCommerz **Session API**
(`/gwprocess/v4/api.php`), and returns the hosted `GatewayPageURL`.

### `sslcommerz-ipn` (public — deployed `--no-verify-jwt`)
Handles both the browser redirect (`?redirect=success|fail|cancel`) and the
server-to-server IPN. On success it validates via the **Validation API**
(`/validator/api/validationserverAPI.php`), then sets `payments.status = 'paid'`
and `bookings.payment_status = 'paid'`. Returns a small HTML page for the
WebView; `200 ok` for pure IPN. Safe to receive twice.

> SSLCommerz cannot send a Supabase JWT, so this function **must** be deployed
> with `--no-verify-jwt`. Its security comes from the Validation API + amount
> match, not from auth.

## Configuration (secrets — never in the repo)

Set as Supabase Function secrets (values from the SSLCommerz merchant panel):

```bash
npx supabase secrets set \
  SSLCZ_STORE_ID="<store id>" \
  SSLCZ_STORE_PASSWD="<store password / API secret>" \
  SSLCZ_API_BASE="https://sandbox.sslcommerz.com"   # omit/replace for production
```

| secret | purpose |
|---|---|
| `SSLCZ_STORE_ID` | merchant store id |
| `SSLCZ_STORE_PASSWD` | store password / API secret key |
| `SSLCZ_API_BASE` | gateway base URL (default: sandbox). Production: `https://securepay.sslcommerz.com` |
| `SSLCZ_CURRENCY` | optional, default `BDT` |

`SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` are injected automatically. The
callback URLs are derived from `SUPABASE_URL`, so nothing else to configure.

## Deploy

```bash
# migrations 072 (payments + bookings.payment_status) and 073 (detail columns)
# applied via the Management API, or: npx supabase db push

npx supabase functions deploy sslcommerz-init
npx supabase functions deploy sslcommerz-ipn --no-verify-jwt
```

## Flutter (app side — already wired)
- [`lib/services/payment/sslcommerz_service.dart`](../lib/services/payment/sslcommerz_service.dart)
  — `initiate(bookingId)` + `awaitSettlement(tranId)` → `PaymentSettlement`
  (`paid` / `failed` / `pending`).
- [`lib/screens/payment/payment_webview_screen.dart`](../lib/screens/payment/payment_webview_screen.dart)
  — hosts the gateway page (`webview_flutter`), reports `PaymentOutcome`.
- [`lib/screens/trips/trips_screen.dart`](../lib/screens/trips/trips_screen.dart)
  — "Pay ৳X" button on `confirmed`/`active` + unpaid bookings; "Paid" badge
  afterwards.
- [`lib/screens/host/host_reservations_screen.dart`](../lib/screens/host/host_reservations_screen.dart)
  — "Service Complete" blocked until `booking.isPaid`.
- `Booking.paymentStatus` / `Booking.isPaid` on the model.

> `webview_flutter` ships native code — after pulling, do a full rebuild
> (`flutter clean && flutter pub get && flutter run`), not just hot restart.

### Platform handling
`_payForBooking` branches on `kIsWeb`:
- **Mobile (Android/iOS)** — opens the gateway in an in-app WebView
  (`PaymentWebViewScreen`) that detects the success/fail/cancel redirect.
- **Web** — `webview_flutter` has no web support, so it opens the hosted gateway
  in a **new browser tab** (`url_launcher`, gesture-driven to avoid popup
  blocking) and confirms via polling. Settlement is still done server-side by
  `sslcommerz-ipn`.

Both paths share `_settlePayment` (poll by `tran_id` + refresh). The web build
is verified (`flutter build web`).

## Error handling
Every failure is surfaced to the user and recorded in `payments`:

| where | condition | client sees | DB |
|---|---|---|---|
| `sslcommerz-init` | not signed in / not your booking / wrong state / already paid | inline error message | — |
| `sslcommerz-init` | gateway didn't return a session | "gateway" error | attempt → `failed` (+ response) |
| `sslcommerz-ipn` | validation `status ∉ {VALID,VALIDATED}`, `tran_id` or amount mismatch | resolves to `failed` | attempt → `failed` (+ response) |
| gateway page | user cancels / bank declines | "Payment failed / cancelled" | attempt → `cancelled` / `failed` |
| app | settle doesn't confirm within the poll budget | "will update shortly" (pending) | unchanged until IPN lands |
| app | network / RPC error | "Could not start payment. Try again." | — |

`awaitSettlement` distinguishes **paid / failed / pending**, so a declined or
unverifiable payment shows a real error instead of a false success.

## Admin panel (`../musafir-admin`)
Admins see **every** transaction at **Payments** (sidebar):
- [`payments/page.tsx`](../../musafir-admin/src/app/(dashboard)/payments/page.tsx)
  — list + status filter tabs + summary (count · paid · total collected), joined
  to the booking's listing and guest.
- [`payments/payment-details.tsx`](../../musafir-admin/src/app/(dashboard)/payments/payment-details.tsx)
  — per-transaction dialog with all fields (amounts, references, card, risk,
  validation time) **plus the raw `gateway_response` JSON**.

Access is via the existing `payments_select` RLS policy (admins can read all).
Payments are read-only in the panel — the app + Edge Functions own writes.

## Testing (sandbox)
1. Create a booking as a guest, accept it as the host → the guest sees **Pay ৳X**.
2. Tap it, complete payment on the SSLCommerz page with a sandbox test card, e.g.
   VISA `4111 1111 1111 1111`, any future expiry, any CVV, OTP `111111` / `123456`.
3. The booking flips to **Paid**; the host's **Service Complete** unlocks.

On **web** (`flutter run -d chrome`): tap **Pay** → **Open payment page** (opens
a new tab) → pay with a sandbox card → return and tap **I've paid**. The booking
flips to Paid once the server settles.

Optional: enable IPN in the merchant panel (Settings → IPN) pointing at
`https://bojkmonskqlhuakxhzcb.supabase.co/functions/v1/sslcommerz-ipn` for the
server-to-server path — the success redirect already settles without it.

## Going to production
- Swap `SSLCZ_API_BASE` to `https://securepay.sslcommerz.com` and set the live
  `SSLCZ_STORE_ID` / `SSLCZ_STORE_PASSWD`.
- Refunds (`payment_status = 'refunded'`) are modelled but not yet wired — add a
  refund path if a host rejects/cancels after payment.
