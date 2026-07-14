// Supabase Edge Function: generate + send a phone OTP via GenNet's iSMS API.
//
// The OTP is generated and hashed HERE, stored in public.otp_attempts, and the
// SMS is sent with the GenNet token held as a server-side secret. The client
// only ever sends a phone number and never learns the code — verification
// happens server-side in the verify-otp function.
//
// Input:  { phone }
// Output: { success: true } | { success: false, error }
//
// Deploy:      supabase functions deploy send-otp
// Set secrets: supabase secrets set GENNET_API_TOKEN="..." GENNET_SID="IOBYTESNONMASK"
//   optional:  GENNET_BASE_URL, OTP_MAX_PER_HOUR (default 5),
//              MASTER_OTP + MASTER_OTP_PHONES (QA bypass for listed numbers only)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  corsHeaders,
  generateCsmsId,
  generateOtp,
  hashOtp,
  jsonResponse,
  masterOtpAllowlist,
  normalizePhone,
  OTP_TTL_MINUTES,
  otpMessage,
  toMsisdn,
} from "../_shared/otp.ts";

const GENNET_BASE_URL = Deno.env.get("GENNET_BASE_URL") ??
  "https://isms.gennet.com.bd/api/v3/send-sms";
const MAX_PER_HOUR = Number(Deno.env.get("OTP_MAX_PER_HOUR") ?? "5");

function serviceClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const phone = normalizePhone(String(body?.phone ?? ""));
    if (!phone) {
      return jsonResponse(400, { success: false, error: "Missing phone" });
    }

    // QA numbers on the master allowlist skip real SMS entirely — verify-otp
    // accepts the master code for them without a stored OTP.
    if (Deno.env.get("MASTER_OTP") && masterOtpAllowlist().has(phone)) {
      console.log(`[send-otp] master allowlist hit for ${phone}; skipping SMS`);
      return jsonResponse(200, { success: true });
    }

    const apiToken = Deno.env.get("GENNET_API_TOKEN");
    const sid = Deno.env.get("GENNET_SID");
    if (!apiToken || !sid) {
      console.error("[send-otp] GENNET_API_TOKEN / GENNET_SID not configured");
      return jsonResponse(500, {
        success: false,
        error: "SMS provider not configured",
      });
    }

    const supabase = serviceClient();

    // ---- per-phone rate limit (fail-open on DB error) --------------------
    if (MAX_PER_HOUR > 0) {
      try {
        const sinceIso = new Date(Date.now() - 60 * 60 * 1000).toISOString();
        const { count, error } = await supabase
          .from("otp_attempts")
          .select("id", { count: "exact", head: true })
          .eq("phone", phone)
          .gte("created_at", sinceIso);
        if (!error && typeof count === "number" && count >= MAX_PER_HOUR) {
          console.warn(`[send-otp] rate limit for ${phone}: ${count}/hr`);
          return jsonResponse(429, {
            success: false,
            error: "Too many OTP requests. Please try again later.",
          });
        }
      } catch (e) {
        console.error("[send-otp] rate-limit check failed (allowing):", e);
      }
    }

    // ---- generate + store -------------------------------------------------
    const otp = generateOtp();
    const otpHash = await hashOtp(otp);
    const expiresAt = new Date(Date.now() + OTP_TTL_MINUTES * 60 * 1000)
      .toISOString();

    const { error: insertError } = await supabase.from("otp_attempts").insert({
      phone,
      otp_hash: otpHash,
      expires_at: expiresAt,
    });
    if (insertError) {
      console.error("[send-otp] failed to store OTP:", insertError);
      return jsonResponse(500, { success: false, error: "Could not store OTP" });
    }

    // ---- send via GenNet --------------------------------------------------
    const gennetResponse = await fetch(GENNET_BASE_URL, {
      method: "POST",
      headers: { "accept": "*/*", "Content-Type": "application/json" },
      body: JSON.stringify({
        api_token: apiToken,
        sid,
        msisdn: toMsisdn(phone),
        sms: otpMessage(otp),
        csms_id: generateCsmsId(),
      }),
    });

    const rawBody = await gennetResponse.text();
    let data: Record<string, unknown> | null = null;
    try {
      data = JSON.parse(rawBody);
    } catch (_) { /* non-JSON handled via status below */ }

    const apiStatus = (data?.["status"] as string | undefined)?.toUpperCase();
    const accepted = gennetResponse.ok &&
      (apiStatus === "SUCCESS" || data?.["status_code"] === 200);

    if (accepted) {
      return jsonResponse(200, { success: true });
    }

    const errMsg = (data?.["error_message"] as string | undefined) ||
      `HTTP ${gennetResponse.status}`;
    console.error(`[send-otp] GenNet failed: ${errMsg} (body: ${rawBody})`);
    return jsonResponse(502, {
      success: false,
      error: `Failed to send SMS: ${errMsg}`,
    });
  } catch (e) {
    console.error("[send-otp] error:", e);
    return jsonResponse(500, { success: false, error: String(e) });
  }
});
