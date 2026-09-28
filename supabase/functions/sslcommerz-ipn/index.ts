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
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { decideSettlement, paymentStatusFor } from "../_shared/settlement.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STORE_ID = Deno.env.get("SSLCZ_STORE_ID") ?? "";
const STORE_PASSWD = Deno.env.get("SSLCZ_STORE_PASSWD") ?? "";
const API_BASE = Deno.env.get("SSLCZ_API_BASE") ??
  "https://sandbox.sslcommerz.com";
const VALIDATION_API =
  `${API_BASE}/validator/api/validationserverAPI.php`;

function html(title: string, message: string, autoClose = false): Response {
  // Self-contained page shown after the gateway redirects. On the web new-tab
  // flow it auto-closes (the tab was opened by the app via window.open, so
  // window.close() is permitted) and offers a manual "Return to the app"
  // fallback. Inside the mobile WebView the app pops this screen itself, so the
  // script is a harmless no-op there.
  const closeScript = autoClose
    ? `<script>setTimeout(function(){try{window.close();}catch(e){}},1800);</script>`
    : "";
  return new Response(
    `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title></head><body style="font-family:sans-serif;text-align:center;padding:48px 24px;color:#111"><h2>${title}</h2><p style="color:#555">${message}</p><button onclick="try{window.close();}catch(e){}; history.back();" style="margin-top:20px;padding:12px 28px;font-size:16px;border:0;border-radius:10px;background:#0B7285;color:#fff;cursor:pointer">Return to the app</button>${closeScript}</body></html>`,
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
        ? html("Payment successful", "Your payment is confirmed.", true)
        : new Response("already paid", { status: 200 });
    }
    // Already held → the admins were told once; a second IPN or the browser
    // redirect arriving after it must not tell them again.
    if (payment.status === "pending_review") {
      return redirect
        ? html(
          "Payment received",
          "We have your payment. It is being checked and you will hear from us shortly.",
          true,
        )
        : new Response("already held", { status: 200 });
    }

    // Explicit fail / cancel from the gateway.
    //
    // These two arrive as browser redirects, which carry no signature — anyone
    // who knows a tran_id can POST one (QA report 2026-09-19, scenario 49).
    // So they may only close an attempt that is still `initiated`: a settled,
    // held, abandoned or already-closed row is left exactly as it is, and the
    // page shown says nothing about which. A genuine success IPN for the same
    // tran_id still settles below whatever this wrote, because the success
    // path skips only `paid` and `pending_review`.
    if (redirect === "fail" || gwStatus === "FAILED") {
      await admin.from("payments").update({
        status: "failed",
        gateway_response: body,
      }).eq("id", payment.id).eq("status", "initiated");
      return html("Payment failed", "Your payment did not go through.");
    }
    if (redirect === "cancel") {
      await admin.from("payments").update({
        status: "cancelled",
        gateway_response: body,
      }).eq("id", payment.id).eq("status", "initiated");
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

    // The booking as it is NOW, not as it was when the guest pressed Pay. A
    // booking can be cancelled, rejected or expired while the bank page is
    // open (QA round 2, scenario 41); the money still moves, and marking such
    // a booking paid would post the host an earning for a stay that will not
    // happen. The decision itself is a pure function with its own tests —
    // see _shared/settlement.ts.
    const { data: bookingNow } = await admin
      .from("bookings")
      .select("booking_status, payment_status")
      .eq("id", payment.booking_id)
      .maybeSingle();

    const outcome = decideSettlement({
      gatewayStatus: v?.status,
      gatewayAmount: v?.amount,
      gatewayTranId: v?.tran_id,
      riskLevel: v?.risk_level,
      expectedAmount: Number(payment.amount),
      expectedTranId: tranId,
      bookingStatus: bookingNow?.booking_status,
      bookingPaymentStatus: bookingNow?.payment_status,
    });

    if (outcome.kind === "failed") {
      await admin.from("payments").update({
        status: "failed",
        val_id: valId,
        gateway_response: v ?? body,
      }).eq("id", payment.id);
      return redirect
        ? html("Payment not verified", "We couldn't verify this payment.")
        : new Response("validation failed", { status: 200 });
    }

    // Validated. Two outcomes from here, not one.
    //
    // SSLCommerz sets `risk_level = 1` with a `risk_title` when its own fraud
    // screen fires on a transaction that is otherwise VALID, and its guidance
    // is to hold that payment for review BEFORE delivering the service. Until
    // this function was fixed it stored both fields and marked the payment
    // paid anyway (QA report 2026-09-18, F11), which unlocks "Service
    // complete" for the host and posts their earning through 101's ledger
    // trigger — money we may have to claw back by hand.
    //
    // So a risky payment becomes `pending_review`: the payments row records
    // that the money arrived, the BOOKING is deliberately left unpaid, and an
    // admin resolves it with `admin_release_payment` / `admin_reject_payment`
    // (136) from the console. Anything other than a `risk_level` of 0 counts
    // as risky — an unrecognised code is not a clean one. The same hold now
    // covers a payment that lands on a booking that is no longer open, and a
    // second real payment on a booking already settled (a double charge).
    const num = (x: unknown) => {
      const n = Number(x);
      return Number.isFinite(n) ? n : null;
    };
    const riskLevel = v.risk_level != null ? String(v.risk_level) : null;
    const held = outcome.kind === "held";
    const holdReason = held ? outcome.reason : null;

    // Guard status so a racing IPN + redirect don't double-apply.
    await admin.from("payments").update({
      status: paymentStatusFor(outcome),
      val_id: valId,
      card_type: v.card_type ?? null,
      card_no: v.card_no ?? null,
      card_issuer: v.card_issuer ?? null,
      card_brand: v.card_brand ?? null,
      bank_tran_id: v.bank_tran_id ?? null,
      store_amount: num(v.store_amount),
      currency_amount: num(v.currency_amount ?? v.amount),
      risk_level: riskLevel,
      risk_title: v.risk_title ?? null,
      tran_date: v.tran_date ?? null,
      validated_at: new Date().toISOString(),
      gateway_response: v,
    }).eq("id", payment.id).neq("status", "paid");

    if (!held) {
      await admin.from("bookings").update({ payment_status: "paid" })
        .eq("id", payment.booking_id);
    }

    // Notify over the reliable notifications channel so Trips / Reservations
    // update live — and a push is sent — without a manual refresh.
    //
    // **`payment_received`, not `paymentReceived`.** This block used to send
    // the camelCase name; `notification_type` has no such label, Postgres
    // answered `invalid input value for enum notification_type`, the insert
    // was swallowed by the catch below, and every online payment on live
    // notified NOBODY — 12 of them, against 3 correct notifications from the
    // cash path, which is why the gap stayed invisible. Best-effort is right
    // for a settlement side effect; silent is not, so the failure is logged
    // with the payload that caused it.
    try {
      const { data: bk } = await admin
        .from("bookings")
        .select("tenant_id, listing_id")
        .eq("id", payment.booking_id)
        .single();
      if (bk) {
        let listingTitle = "your booking";
        let ownerId: string | null = null;
        if (bk.listing_id) {
          const { data: lst } = await admin
            .from("listings")
            .select("owner_id, title")
            .eq("id", bk.listing_id)
            .single();
          ownerId = lst?.owner_id ?? null;
          if (lst?.title) listingTitle = lst.title;
        }
        const rows: Record<string, unknown>[] = [];

        if (held) {
          // The guest is told the truth — their money arrived and the booking
          // has not moved — rather than "confirmed", which would be a lie the
          // host would then be asked to act on. The wording depends on WHY
          // it is held: a fraud flag will usually clear; money on a cancelled
          // booking is coming back.
          const guestBody = holdReason === "booking_not_open"
            ? `We received your payment for ${listingTitle}, but that booking is no longer active (${bookingNow?.booking_status ?? "closed"}). Our team will refund you and be in touch.`
            : holdReason === "already_settled"
            ? `We received a second payment for ${listingTitle}, which was already paid. Our team will refund the duplicate and be in touch.`
            : `We received your payment for ${listingTitle}. It is being checked and your booking will be confirmed shortly.`;
          if (bk.tenant_id) {
            rows.push({
              user_id: bk.tenant_id,
              type: "system_alert",
              title: holdReason === "risk_flag"
                ? "Payment received, under review"
                : "Payment received, refund pending",
              body: guestBody,
              action_url: "/trips",
            });
          }
          // Every admin, because nothing else surfaces a held payment.
          const adminBody = holdReason === "booking_not_open"
            ? `A payment for ${listingTitle} arrived after the booking became ${bookingNow?.booking_status ?? "closed"}. Reject it and refund the guest from Payments.`
            : holdReason === "already_settled"
            ? `A second payment arrived for ${listingTitle}, which is already paid. Reject the duplicate and refund the guest from Payments.`
            : `A payment for ${listingTitle} was flagged by the gateway (${v.risk_title ?? "risk"}). Release or reject it from Payments.`;
          const { data: admins } = await admin
            .from("profiles")
            .select("id")
            .eq("role", "admin");
          for (const a of admins ?? []) {
            rows.push({
              user_id: a.id,
              type: "security_alert",
              title: "Payment held for review",
              body: adminBody,
              action_url: "/payments",
            });
          }
        } else {
          if (bk.tenant_id) {
            rows.push({
              user_id: bk.tenant_id,
              type: "payment_received",
              title: "Payment confirmed",
              body: `Your payment for ${listingTitle} is confirmed.`,
              action_url: "/trips",
            });
          }
          if (ownerId) {
            rows.push({
              user_id: ownerId,
              type: "payment_received",
              title: "Payment received",
              body:
                `Payment received for ${listingTitle}. You can now mark the service complete.`,
              action_url: "/reservations",
            });
          }
        }

        if (rows.length) {
          const { error: nErr } = await admin.from("notifications").insert(rows);
          if (nErr) {
            console.error("[sslcommerz-ipn] notify rejected", nErr.message, rows);
          }
        }
      }
    } catch (e) {
      console.error("[sslcommerz-ipn] notify failed", e);
    }

    if (held) {
      return redirect
        ? html(
          "Payment received",
          holdReason === "risk_flag"
            ? "We have your payment. It is being checked and your booking will be confirmed shortly."
            : "We have your payment, but this booking is no longer active. Our team will refund you and be in touch.",
          true,
        )
        : new Response("held for review", { status: 200 });
    }

    return redirect
      ? html("Payment successful", "Your payment is confirmed.", true)
      : new Response("ok", { status: 200 });
  } catch (e) {
    console.error("[sslcommerz-ipn]", e);
    return redirect
      ? html("Payment", "Something went wrong. Check the app for status.")
      : new Response("error", { status: 500 });
  }
});
