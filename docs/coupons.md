# Coupons — admin & integration reference

Simple coupon-code discounts. **Admins create codes; guests redeem them at
checkout.** Two discount kinds: `percentage` and `flat`. Defined in migration
[`supabase/migrations/069_coupons.sql`](../supabase/migrations/069_coupons.sql)
(already applied to the live DB `bojkmonskqlhuakxhzcb`).

## Tables

### `public.coupons`
| column | type | notes |
|---|---|---|
| `id` | uuid | pk |
| `code` | text, unique | auto-uppercased/trimmed by trigger |
| `discount_type` | text | `'percentage'` or `'flat'` |
| `discount_value` | numeric | percentage → 0–100; flat → amount (BDT) |
| `max_discount_amount` | numeric, null | cap for percentage coupons (null = no cap) |
| `min_booking_amount` | numeric | default 0; min pre-discount total to qualify |
| `usage_limit` | int, null | total redemptions allowed (null = unlimited) |
| `used_count` | int | maintained by `redeem_coupon` |
| `per_user_limit` | int, null | per-user redemptions (default 1; null = unlimited) |
| `is_active` | bool | default true |
| `starts_at` / `expires_at` | timestamptz, null | validity window |
| `created_by` | uuid, null | admin user id |
| `created_at` | timestamptz | |

### `public.coupon_redemptions`
`id, coupon_id, user_id, booking_id, discount_amount, redeemed_at` — one row per redemption.

### `public.bookings` (added columns)
`coupon_code text`, `discount_amount numeric default 0` — `total_price` stores the **final (discounted)** amount.

## RLS / security
- **Only admins** (`is_admin()` → `profiles.role = 'admin'`) can read/write `coupons`. Guests **cannot** read the table (prevents code enumeration).
- Guests interact only through two `SECURITY DEFINER` functions:
  - `validate_coupon(p_code text, p_amount numeric) → jsonb` — checks active/date/limits/min-amount and returns the **authoritative** discount. Returns `{valid, message, coupon_id, code, discount_type, discount_value, discount_amount, final_amount}`.
  - `redeem_coupon(p_coupon_id uuid, p_booking_id uuid, p_discount_amount numeric)` — records the redemption + bumps `used_count`, re-checking limits (raises on violation). Called by the app after a booking is created.

## Admin panel (Next.js `../musafir-admin`) — how to create/manage
Use a Supabase client authenticated as an **admin** user (RLS enforces `is_admin()`). Direct table CRUD:

```ts
// create
await supabase.from('coupons').insert({
  code: 'WELCOME10',
  discount_type: 'percentage',   // or 'flat'
  discount_value: 10,            // 10% (or e.g. 200 for flat ৳200)
  max_discount_amount: 500,      // cap for percentage (omit/null for flat)
  min_booking_amount: 0,
  usage_limit: null,             // or a number
  per_user_limit: 1,             // null = unlimited
  starts_at: null,
  expires_at: '2026-12-31T23:59:59Z',
  is_active: true,
});

// list
await supabase.from('coupons').select('*').order('created_at', { ascending: false });

// deactivate (prefer over delete to keep redemption history)
await supabase.from('coupons').update({ is_active: false }).eq('id', id);

// usage
await supabase.from('coupon_redemptions').select('*').eq('coupon_id', id);
```

Suggested admin form fields: code, type (percentage/flat), value, max discount (percentage only), min booking amount, total usage limit, per-user limit, start/expiry dates, active toggle.

## Flutter app (guest side — already wired)
- `lib/services/discount/coupon_service.dart` — `validate()` / `redeem()` over the RPCs.
- Booking sheet (`_BookingSheet` in `lib/screens/explore/listing_detail_screen.dart`) — coupon input + discount line; re-validates against the final total on confirm; persists `coupon_code` + `discount_amount` on the booking and calls `redeem_coupon`.

## Demo coupons currently seeded (live)
- `WELCOME10` — 10% off, cap ৳500, unlimited uses, 1/user.
- `FLAT200` — ৳200 off, min booking ৳1000, 100 total uses, 1/user.
