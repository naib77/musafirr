-- 073: Capture full SSLCommerz transaction details on `payments`.
--
-- The complete gateway/validation payload already lands in `gateway_response`
-- (jsonb); these structured columns surface the fields the admin panel shows
-- without digging into the JSON. Populated by sslcommerz-ipn on settlement.

alter table public.payments
  add column if not exists card_no      text,        -- masked PAN, e.g. 432149XXXXXX0667
  add column if not exists card_issuer  text,
  add column if not exists card_brand   text,
  add column if not exists store_amount numeric,     -- amount credited to the store (after gateway fee)
  add column if not exists currency_amount numeric,  -- amount in txn currency (validation)
  add column if not exists risk_level   text,
  add column if not exists risk_title   text,
  add column if not exists tran_date    text,        -- gateway-reported transaction time (string)
  add column if not exists validated_at timestamptz; -- when we confirmed via the Validation API

comment on column public.payments.gateway_response is
  'Full raw SSLCommerz payload (session failure, validation response, or IPN body) for audit.';
