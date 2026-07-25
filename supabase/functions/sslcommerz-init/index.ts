// Supabase Edge Function: start an SSLCommerz payment session for a booking.
//
// The guest calls this AFTER the host accepts (booking = 'confirmed'). The
// amount is taken from the booking's SERVER-side total_price — never from the
// client — so the payment can't be under-charged. We create a `payments` row
// (status 'initiated') and ask SSLCommerz for a hosted GatewayPageURL, which the
// app opens in a WebView. Settlement is confirmed separately in sslcommerz-ipn.
//
// Input:  { booking_id }
// Output: { success: true, gateway_url, tran_id } | { success: false, error }
//
// Deploy:      supabase functions deploy sslcommerz-init
// Set secrets: supabase secrets set SSLCZ_STORE_ID="..." SSLCZ_STORE_PASSWD="..."
//   optional:  SSLCZ_API_BASE (default sandbox), SSLCZ_CURRENCY (default BDT)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/otp.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STORE_ID = Deno.env.get("SSLCZ_STORE_ID") ?? "";
const STORE_PASSWD = Deno.env.get("SSLCZ_STORE_PASSWD") ?? "";
const API_BASE = Deno.env.get("SSLCZ_API_BASE") ??
  "https://sandbox.sslcommerz.com";
const CURRENCY = Deno.env.get("SSLCZ_CURRENCY") ?? "BDT";

const SESSION_API = `${API_BASE}/gwprocess/v4/api.php`;
const IPN_URL = `${SUPABASE_URL}/functions/v1/sslcommerz-ipn`;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { success: false, error: "Method not allowed" });
  }
  if (!STORE_ID || !STORE_PASSWD) {
    return jsonResponse(500, {
      success: false,
      error: "Payment gateway is not configured",
    });
  }

  try {
    // Identify the caller from their JWT (functions.invoke forwards it).
    const authHeader = req.headers.get("Authorization") ?? "";
    const userClient = createClient(SUPABASE_URL, SERVICE_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData } = await userClient.auth.getUser();
    const user = userData?.user;
    if (!user) {
      return jsonResponse(401, { success: false, error: "Not authenticated" });
    }

    const body = await req.json().catch(() => ({}));
    const bookingId = String(body.booking_id ?? "").trim();
    if (!bookingId) {
      return jsonResponse(400, { success: false, error: "Missing booking_id" });
    }

    const admin = createClient(SUPABASE_URL, SERVICE_KEY);

    // Load the booking + its listing (for the product name) via service role.
    const { data: booking, error: bErr } = await admin
      .from("bookings")
      .select(
        "id, tenant_id, tenant_name, total_price, booking_status, payment_status, listing_id, listing_title, listing_city",
      )
      .eq("id", bookingId)
      .single();

    if (bErr || !booking) {
      return jsonResponse(404, { success: false, error: "Booking not found" });
    }
    // Only the booking's own guest can pay for it.
    if (booking.tenant_id !== user.id) {
      return jsonResponse(403, { success: false, error: "Not your booking" });
    }
    if (booking.payment_status === "paid") {
      return jsonResponse(409, {
        success: false,
        error: "This booking is already paid",
      });
    }
    // Payable in any state after the host accepts and before it's finished:
    // 'confirmed' (accepted) or 'active' (checked in) — never pending/terminal.
    if (booking.booking_status !== "confirmed" &&
        booking.booking_status !== "active") {
      const reason = booking.booking_status === "pending"
        ? "Payment is available after the host accepts your booking"
        : "This booking can no longer be paid";
      return jsonResponse(409, { success: false, error: reason });
    }

    const amount = Number(booking.total_price);
    if (!(amount > 0)) {
      return jsonResponse(400, {
        success: false,
        error: "Invalid booking amount",
      });
    }

    // Unique per attempt. Short, alphanumeric, ties back to the booking.
    const tranId = `MSFR-${bookingId.slice(0, 8)}-${
      crypto.randomUUID().slice(0, 8)
    }`.toUpperCase();

    // Record the attempt before contacting the gateway.
    const { error: pErr } = await admin.from("payments").insert({
      booking_id: bookingId,
      user_id: user.id,
      tran_id: tranId,
      amount,
      currency: CURRENCY,
      status: "initiated",
    });
    if (pErr) {
      return jsonResponse(500, {
        success: false,
        error: "Could not start payment",
      });
    }

    // SSLCommerz session request (application/x-www-form-urlencoded).
    const form = new URLSearchParams({
      store_id: STORE_ID,
      store_passwd: STORE_PASSWD,
      total_amount: amount.toFixed(2),
      currency: CURRENCY,
      tran_id: tranId,
      // All three land back in the WebView; the ?redirect marker lets the app
      // detect the outcome. ipn_url is the authoritative server-to-server call.
      success_url: `${IPN_URL}?redirect=success`,
      fail_url: `${IPN_URL}?redirect=fail`,
      cancel_url: `${IPN_URL}?redirect=cancel`,
      ipn_url: IPN_URL,
      shipping_method: "NO",
      product_name: (booking.listing_title ?? "Musafir booking").slice(0, 255),
      product_category: "rental",
      product_profile: "general",
      cus_name: booking.tenant_name || "Guest",
      cus_email: user.email ?? "guest@musafir.app",
      cus_add1: booking.listing_city ?? "Dhaka",
      cus_city: booking.listing_city ?? "Dhaka",
      cus_country: "Bangladesh",
      cus_phone: user.phone ?? "01700000000",
      value_a: bookingId, // echoed back in the callback
    });

    const resp = await fetch(SESSION_API, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: form.toString(),
    });
    const sess = await resp.json().catch(() => null);

    if (!sess || sess.status !== "SUCCESS" || !sess.GatewayPageURL) {
      const reason = sess?.failedreason ?? "Gateway did not return a session";
      await admin.from("payments").update({
        status: "failed",
        gateway_response: sess ?? {},
      }).eq("tran_id", tranId);
      return jsonResponse(502, { success: false, error: String(reason) });
    }

    return jsonResponse(200, {
      success: true,
      gateway_url: sess.GatewayPageURL,
      tran_id: tranId,
    });
  } catch (e) {
    console.error("[sslcommerz-init]", e);
    return jsonResponse(500, { success: false, error: "Unexpected error" });
  }
});
