// Supabase Edge Function: SSLCommerz callback + IPN handler (settlement).
//
// This is the AUTHORITATIVE settlement path. SSLCommerz hits it two ways:
//   • server-to-server IPN  → POST {IPN_URL}                (no redirect param)
//   • browser redirect      → POST {IPN_URL}?redirect=...   (success|fail|cancel)
//     — the app's WebView loads this and reads the outcome.
//
// We NEVER trust the POSTed status alone. On success we re-validate the
// transaction against SSLCommerz's Validation API using our secret store creds,
// then confirm the amount matches the `payments` row we created in
// sslcommerz-init before marking it paid. Idempotent — safe to receive twice.
//
// Deploy WITHOUT jwt verification (SSLCommerz can't send a Supabase JWT):
//   supabase functions deploy sslcommerz-ipn --no-verify-jwt

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STORE_ID = Deno.env.get("SSLCZ_STORE_ID") ?? "";
const STORE_PASSWD = Deno.env.get("SSLCZ_STORE_PASSWD") ?? "";
const API_BASE = Deno.env.get("SSLCZ_API_BASE") ??
  "https://sandbox.sslcommerz.com";
const VALIDATION_API =
  `${API_BASE}/validator/api/validationserverAPI.php`;

function html(title: string, message: string): Response {
  // Minimal self-contained page shown briefly inside the WebView.
  return new Response(
    `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title></head><body style="font-family:sans-serif;text-align:center;padding:48px 24px;color:#111"><h2>${title}</h2><p style="color:#555">${message}</p></body></html>`,
    { status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } },
  );
}

async function parseBody(req: Request): Promise<Record<string, string>> {
  const out: Record<string, string> = {};
  try {
    const ct = req.headers.get("content-type") ?? "";
    if (ct.includes("application/json")) {
      Object.assign(out, await req.json());
    } else {
      const form = await req.formData();
      for (const [k, v] of form.entries()) out[k] = String(v);
    }
  } catch (_) { /* ignore */ }
  return out;
}

serve(async (req: Request) => {
  const url = new URL(req.url);
  const redirect = url.searchParams.get("redirect"); // success|fail|cancel|null
  const admin = createClient(SUPABASE_URL, SERVICE_KEY);

  const body = await parseBody(req);
  const tranId = body.tran_id ?? "";
  const valId = body.val_id ?? "";
  const gwStatus = (body.status ?? "").toUpperCase();

  try {
    if (!tranId) {
      return redirect
        ? html("Payment", "Missing transaction reference.")
        : new Response("no tran_id", { status: 400 });
    }

    // Look up the attempt we recorded at init.
    const { data: payment } = await admin
      .from("payments")
      .select("id, booking_id, amount, currency, status")
      .eq("tran_id", tranId)
      .single();

    if (!payment) {
      return redirect
        ? html("Payment", "Unknown transaction.")
        : new Response("unknown tran_id", { status: 404 });
    }

    // Already settled → idempotent no-op.
    if (payment.status === "paid") {
      return redirect
        ? html("Payment successful", "Your payment is confirmed. Return to the app.")
        : new Response("already paid", { status: 200 });
    }

    // Explicit fail / cancel from the gateway.
    if (redirect === "fail" || gwStatus === "FAILED") {
      await admin.from("payments").update({
        status: "failed",
        gateway_response: body,
      }).eq("id", payment.id);
      return html("Payment failed", "Your payment did not go through.");
    }
    if (redirect === "cancel") {
      await admin.from("payments").update({
        status: "cancelled",
        gateway_response: body,
      }).eq("id", payment.id);
      return html("Payment cancelled", "You cancelled the payment.");
    }

    // Success path — re-validate with SSLCommerz before trusting anything.
    if (!valId) {
      return redirect
        ? html("Payment", "Awaiting confirmation from the bank.")
        : new Response("no val_id", { status: 400 });
    }

    const vurl = `${VALIDATION_API}?val_id=${encodeURIComponent(valId)}` +
      `&store_id=${encodeURIComponent(STORE_ID)}` +
      `&store_passwd=${encodeURIComponent(STORE_PASSWD)}&v=1&format=json`;
    const vres = await fetch(vurl);
    const v = await vres.json().catch(() => null);

    const validStatus = v && (v.status === "VALID" || v.status === "VALIDATED");
    const amountOk = v &&
      Math.abs(Number(v.amount) - Number(payment.amount)) < 0.01;
    const tranOk = v && v.tran_id === tranId;

    if (!validStatus || !amountOk || !tranOk) {
      await admin.from("payments").update({
        status: "failed",
        val_id: valId,
        gateway_response: v ?? body,
      }).eq("id", payment.id);
      return redirect
        ? html("Payment not verified", "We couldn't verify this payment.")
        : new Response("validation failed", { status: 200 });
    }

    // Confirmed. Mark paid + capture full transaction details + mirror onto the
    // booking. Guard status so a racing IPN + redirect don't double-apply.
    const num = (x: unknown) => {
      const n = Number(x);
      return Number.isFinite(n) ? n : null;
    };
    await admin.from("payments").update({
      status: "paid",
      val_id: valId,
      card_type: v.card_type ?? null,
      card_no: v.card_no ?? null,
      card_issuer: v.card_issuer ?? null,
      card_brand: v.card_brand ?? null,
      bank_tran_id: v.bank_tran_id ?? null,
      store_amount: num(v.store_amount),
      currency_amount: num(v.currency_amount ?? v.amount),
      risk_level: v.risk_level != null ? String(v.risk_level) : null,
      risk_title: v.risk_title ?? null,
      tran_date: v.tran_date ?? null,
      validated_at: new Date().toISOString(),
      gateway_response: v,
    }).eq("id", payment.id).neq("status", "paid");

    await admin.from("bookings").update({ payment_status: "paid" })
      .eq("id", payment.booking_id);

    return redirect
      ? html("Payment successful", "Your payment is confirmed. Return to the app.")
      : new Response("ok", { status: 200 });
  } catch (e) {
    console.error("[sslcommerz-ipn]", e);
    return redirect
      ? html("Payment", "Something went wrong. Check the app for status.")
      : new Response("error", { status: 500 });
  }
});
