// Supabase Edge Function: drain one bulk-SMS campaign's recipient queue.
//
// Input:  { campaignId }
// Output: { ok, claimed, sent, failed, remaining, done }
//
// Deploy:      supabase functions deploy send-bulk-sms
// Set secrets: (reuses GENNET_API_TOKEN / GENNET_SID from send-otp)
//   optional:  SMS_BATCH_SIZE (default 50), SMS_CONCURRENCY (default 5),
//              SMS_TIME_BUDGET_MS (default 50000)
//
// Also needs two rows in public.app_secrets so the pg_cron sweep can reach it:
//   sms_worker_url    = https://<ref>.supabase.co/functions/v1/send-bulk-sms
//   sms_worker_secret = <random string, also set as SMS_WORKER_SECRET here>
//
// ── Why this is not a loop over a list of numbers ──────────────────────────
//
// Every recipient is a row, and this function never decides who to send to. It
// asks the database for a batch (`admin_claim_sms_batch`), which marks those
// rows 'sending' and commits BEFORE any of them is handed to GenNet. So if this
// function dies mid-batch, those rows stay 'sending' and nothing — not the cron
// sweep, not a second invocation, not the retry button — will pick them up
// again. A message is lost rather than sent twice. That is the deliberate
// direction: see migration 128.
//
// It is therefore safe to invoke concurrently. Two callers racing get disjoint
// batches, because the claim uses `for update skip locked`.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, generateCsmsId, jsonResponse } from "../_shared/otp.ts";

const GENNET_BASE_URL = Deno.env.get("GENNET_BASE_URL") ??
  "https://isms.gennet.com.bd/api/v3/send-sms";

const BATCH_SIZE = Number(Deno.env.get("SMS_BATCH_SIZE") ?? "50");
// GenNet is a shared shortcode route; firing 50 requests at once is how you get
// rate-limited into a wall of failures that then need retrying by hand.
const CONCURRENCY = Number(Deno.env.get("SMS_CONCURRENCY") ?? "5");
// Edge functions are killed at the platform's wall clock. Stopping early and
// leaving rows 'pending' is harmless — the every-minute sweep resumes them —
// whereas being killed mid-send leaves rows stranded in 'sending'.
const TIME_BUDGET_MS = Number(Deno.env.get("SMS_TIME_BUDGET_MS") ?? "50000");

interface Claimed {
  id: string;
  msisdn: string;
  body_rendered: string;
}

function serviceClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
}

/**
 * Two callers are allowed in, and neither is a browser.
 *
 * The admin console holds the service-role key and calls this directly for
 * immediacy. The pg_cron sweep has no key, so it presents the shared secret
 * from app_secrets instead. Anything else is refused before a campaign id is
 * even read — this endpoint spends money.
 */
function authorised(req: Request): boolean {
  const workerSecret = Deno.env.get("SMS_WORKER_SECRET") ?? "";
  const presented = req.headers.get("x-sms-worker-secret") ?? "";
  if (workerSecret && presented && timingSafeEqual(workerSecret, presented)) {
    return true;
  }

  const auth = req.headers.get("Authorization") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  return serviceKey !== "" && auth === `Bearer ${serviceKey}`;
}

/** Constant-time compare, so a wrong secret cannot be discovered a byte at a time. */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** One message. Never throws — a thrown error here would abandon the row in 'sending'. */
async function sendOne(
  msisdn: string,
  text: string,
  apiToken: string,
  sid: string,
): Promise<{ ok: boolean; status?: string; ref?: string; error?: string }> {
  try {
    const csmsId = generateCsmsId();
    const res = await fetch(GENNET_BASE_URL, {
      method: "POST",
      headers: { "accept": "*/*", "Content-Type": "application/json" },
      body: JSON.stringify({
        api_token: apiToken,
        sid,
        msisdn,
        sms: text,
        csms_id: csmsId,
      }),
    });

    const raw = await res.text();
    let data: Record<string, unknown> | null = null;
    try {
      data = JSON.parse(raw);
    } catch (_) { /* non-JSON falls through to the status check */ }

    const apiStatus = (data?.["status"] as string | undefined)?.toUpperCase();
    const accepted = res.ok &&
      (apiStatus === "SUCCESS" || data?.["status_code"] === 200);

    if (accepted) return { ok: true, status: apiStatus ?? "SUCCESS", ref: csmsId };

    const msg = (data?.["error_message"] as string | undefined) ??
      `HTTP ${res.status}`;
    return { ok: false, status: apiStatus ?? String(res.status), error: msg };
  } catch (e) {
    return { ok: false, error: String(e) };
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (!authorised(req)) {
    return jsonResponse(401, { ok: false, error: "Unauthorized" });
  }

  const apiToken = Deno.env.get("GENNET_API_TOKEN");
  const sid = Deno.env.get("GENNET_SID");
  if (!apiToken || !sid) {
    return jsonResponse(500, { ok: false, error: "SMS provider not configured" });
  }

  let campaignId: string;
  try {
    const body = await req.json();
    campaignId = String(body?.campaignId ?? "");
    if (!campaignId) throw new Error("missing campaignId");
  } catch (e) {
    return jsonResponse(400, { ok: false, error: `Bad request: ${e}` });
  }

  const supabase = serviceClient();
  const startedAt = Date.now();
  let claimedTotal = 0;
  let sent = 0;
  let failed = 0;

  while (Date.now() - startedAt < TIME_BUDGET_MS) {
    const { data, error } = await supabase.rpc("admin_claim_sms_batch", {
      p_campaign_id: campaignId,
      p_limit: BATCH_SIZE,
    });

    if (error) {
      console.error("[send-bulk-sms] claim failed:", error);
      return jsonResponse(500, { ok: false, error: error.message });
    }

    const batch = (data ?? []) as Claimed[];
    if (batch.length === 0) break; // nothing left pending
    claimedTotal += batch.length;

    // Fixed-size worker pool over the batch, rather than Promise.all over all
    // of it — see CONCURRENCY above.
    let cursor = 0;
    const workers = Array.from(
      { length: Math.min(CONCURRENCY, batch.length) },
      async () => {
        while (cursor < batch.length) {
          const row = batch[cursor++];
          const result = await sendOne(
            row.msisdn,
            row.body_rendered,
            apiToken,
            sid,
          );

          if (result.ok) sent++;
          else failed++;

          // Recording the outcome must not be skipped even when the send threw,
          // or the row stays 'sending' forever and needs a human.
          const { error: markError } = await supabase.rpc(
            "admin_mark_sms_result",
            {
              p_recipient_id: row.id,
              p_ok: result.ok,
              p_provider_status: result.status ?? null,
              p_provider_ref: result.ref ?? null,
              p_error: result.error ?? null,
            },
          );
          if (markError) {
            console.error(
              `[send-bulk-sms] could not mark ${row.id}:`,
              markError,
            );
          }
        }
      },
    );
    await Promise.all(workers);
  }

  const { count: remaining } = await supabase
    .from("sms_recipients")
    .select("id", { count: "exact", head: true })
    .eq("campaign_id", campaignId)
    .eq("status", "pending");

  console.log(
    `[send-bulk-sms] campaign=${campaignId} claimed=${claimedTotal} sent=${sent} failed=${failed} remaining=${remaining ?? "?"}`,
  );

  return jsonResponse(200, {
    ok: true,
    claimed: claimedTotal,
    sent,
    failed,
    remaining: remaining ?? 0,
    done: (remaining ?? 0) === 0,
  });
});
