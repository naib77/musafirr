// A fixed-window rate limit for the edge functions that spend a paid key.
//
// geocode, places-search, google-directions and voice-parse sit behind
// verify_jwt, which accepts the ANON key — the one compiled into build/web.
// None of them looked at who was calling, so anybody with the bundle could
// run up the Google and Gemini invoices at whatever rate they liked (QA
// report 2026-09-19, scenario 56). Signed-out search legitimately needs
// places-search, so the answer is a counter, not a login gate.
//
// The counter is `fn_rate_limit_hit` (migration 140), in the database rather
// than in this isolate's memory, because there are many edge runtimes and one
// database. The key is the caller's user id when the JWT carries one and the
// client IP otherwise — and the two get DIFFERENT limits, because Bangladeshi
// mobile operators put thousands of subscribers behind one CGNAT address, so a
// per-IP limit tight enough to stop one abuser would throttle a whole
// neighbourhood of signed-out visitors.
//
// Fails OPEN. If the counter cannot be reached the request proceeds and the
// failure is logged: a rate limiter that can take search down is a worse
// outage than the one it prevents.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { jsonResponse } from "./otp.ts";

export interface RateLimitRule {
  /** Hits allowed per window for a signed-in user (keyed by their id). */
  perUser: number;
  /** Hits allowed per window for an anonymous caller (keyed by IP). */
  perIp: number;
  windowSeconds: number;
}

/** Who a request counts against: a user id, or failing that an address. */
export interface RateLimitSubject {
  kind: "user" | "ip";
  key: string;
}

/**
 * The `sub` of the bearer token, if it is a user token. The gateway has
 * already verified the signature (verify_jwt), so this only decodes the
 * payload; it never trusts it for anything but choosing a bucket. The anon
 * key is itself a JWT with `role: "anon"` and no `sub`, which is why the role
 * is checked rather than the mere presence of a token.
 */
export function jwtSubject(authorization: string | null): string | null {
  if (!authorization) return null;
  const m = /^Bearer\s+([A-Za-z0-9\-_]+)\.([A-Za-z0-9\-_]+)\.([A-Za-z0-9\-_]*)$/
    .exec(authorization.trim());
  if (!m) return null;
  try {
    const b64 = m[2].replace(/-/g, "+").replace(/_/g, "/");
    const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
    const payload = JSON.parse(atob(padded));
    if (payload?.role !== "authenticated") return null;
    return typeof payload?.sub === "string" && payload.sub.length > 0
      ? payload.sub
      : null;
  } catch {
    return null;
  }
}

/**
 * The client address as the edge gateway reports it. `x-forwarded-for` is a
 * comma list with the client first; the rest are proxies. Falls back to a
 * fixed key so a request with no address at all still shares ONE bucket
 * rather than escaping the limit.
 */
export function clientIp(headers: Headers): string {
  const cf = headers.get("cf-connecting-ip");
  if (cf && cf.trim()) return cf.trim();
  const xff = headers.get("x-forwarded-for");
  if (xff) {
    const first = xff.split(",")[0].trim();
    if (first) return first;
  }
  const real = headers.get("x-real-ip");
  if (real && real.trim()) return real.trim();
  return "unknown";
}

export function rateLimitSubject(headers: Headers): RateLimitSubject {
  const sub = jwtSubject(headers.get("authorization"));
  if (sub) return { kind: "user", key: sub };
  return { kind: "ip", key: clientIp(headers) };
}

/** The database bucket for a function and a subject. */
export function rateLimitBucket(fn: string, subject: RateLimitSubject): string {
  return `${fn}:${subject.kind}:${subject.key}`;
}

/**
 * Count this request. Returns a 429 response to send when the caller is over
 * the limit, or null to proceed. Never throws.
 */
export async function enforceRateLimit(
  req: Request,
  fn: string,
  rule: RateLimitRule,
): Promise<Response | null> {
  const subject = rateLimitSubject(req.headers);
  const limit = subject.kind === "user" ? rule.perUser : rule.perIp;
  try {
    const url = Deno.env.get("SUPABASE_URL");
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key) {
      console.error(`[rate-limit] ${fn}: service credentials missing; not limiting`);
      return null;
    }
    const admin = createClient(url, key, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data, error } = await admin.rpc("fn_rate_limit_hit", {
      p_bucket: rateLimitBucket(fn, subject),
      p_limit: limit,
      p_window_seconds: rule.windowSeconds,
    });
    if (error) {
      console.error(`[rate-limit] ${fn}: counter failed; not limiting`, error.message);
      return null;
    }
    const verdict = data as { allowed?: boolean; retry_after_seconds?: number } | null;
    if (verdict && verdict.allowed === false) {
      const retry = Math.max(1, Number(verdict.retry_after_seconds ?? rule.windowSeconds));
      const res = jsonResponse(429, {
        error: "Too many requests. Please slow down.",
        retry_after_seconds: retry,
      });
      res.headers.set("Retry-After", String(retry));
      return res;
    }
    return null;
  } catch (e) {
    console.error(`[rate-limit] ${fn}: unexpected failure; not limiting`, e);
    return null;
  }
}
