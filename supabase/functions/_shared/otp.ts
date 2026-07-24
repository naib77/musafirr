// Shared OTP / phone helpers for the send-otp and verify-otp Edge Functions.
// Keep the phone normalization and message template in sync with the Flutter
// client (OtpService.normalizePhoneNumber / SmsConfig.getOtpMessage) so the
// derived auth email matches on both sides.

export const OTP_LENGTH = 4;
export const OTP_TTL_MINUTES = 5;
export const OTP_MAX_ATTEMPTS = 3;

/// App-normalized BD number: strip formatting, collapse +880/880 to a leading 0
/// (e.g. "+880 1673-293542" and "8801673293542" -> "01673293542").
export function normalizePhone(phone: string): string {
  let n = phone.replace(/[\s\-()]/g, "");
  if (n.startsWith("+880")) n = "0" + n.slice(4);
  else if (n.startsWith("880")) n = "0" + n.slice(3);
  else if (n.startsWith("+")) n = n.slice(1);
  return n;
}

/// Internal Supabase-auth email derived from the phone. Must match the Flutter
/// client's _phoneToEmail exactly.
export function phoneToEmail(normalizedPhone: string): string {
  return `phone.${normalizedPhone}@musafir.app`;
}

/// GenNet msisdn format (8801673293542) from an app-normalized number.
export function toMsisdn(normalizedPhone: string): string {
  let d = normalizedPhone.replace(/[^0-9]/g, "");
  if (d.startsWith("880")) return d;
  if (d.startsWith("0")) d = d.slice(1);
  return `880${d}`;
}

/// Display format stored in profiles.mobile (+880 1673293542).
export function formatPhoneForDisplay(normalizedPhone: string): string {
  const d = normalizedPhone.replace(/[^0-9]/g, "");
  if (d.startsWith("880")) return `+880 ${d.slice(3)}`;
  if (d.startsWith("0")) return `+880 ${d.slice(1)}`;
  return `+880 ${d}`;
}

/// SHA-256 hex of the OTP. Both storing (send-otp) and checking (verify-otp)
/// use this, so the hash never has to leave the server.
export async function hashOtp(otp: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(otp),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/// Cryptographically-random numeric OTP.
export function generateOtp(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(OTP_LENGTH));
  let otp = "";
  for (const b of bytes) otp += (b % 10).toString();
  return otp;
}

/// Per-request reference id for GenNet: alphanumeric, day-unique, <= 20 chars.
export function generateCsmsId(): string {
  const ts = Date.now().toString(36);
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let rand = "";
  for (const b of crypto.getRandomValues(new Uint8Array(5))) {
    rand += chars[b % chars.length];
  }
  const id = `${ts}${rand}`.toUpperCase();
  return id.length > 20 ? id.slice(-20) : id;
}

export function otpMessage(otp: string): string {
  return `Your Musafir verification code is: ${otp}. Valid for ${OTP_TTL_MINUTES} minutes.`;
}

/// Parse the MASTER_OTP_PHONES secret (comma/space separated) into a normalized
/// allowlist. Empty when unset.
export function masterOtpAllowlist(): Set<string> {
  const raw = Deno.env.get("MASTER_OTP_PHONES") ?? "";
  const set = new Set<string>();
  for (const part of raw.split(/[,\s]+/)) {
    const p = part.trim();
    if (p && p !== "*") set.add(normalizePhone(p));
  }
  return set;
}

/// True when MASTER_OTP_PHONES is the wildcard "*", meaning the master code is
/// accepted for EVERY phone number (test/demo builds — no real SMS is sent).
export function masterOtpAllPhones(): boolean {
  return (Deno.env.get("MASTER_OTP_PHONES") ?? "").trim() === "*";
}

/// True when `otp` is the configured master code AND the master OTP applies to
/// `normalizedPhone` — i.e. MASTER_OTP_PHONES is "*" (all phones) or the phone is
/// on the allowlist. Returns false unless both MASTER_OTP and MASTER_OTP_PHONES
/// secrets are set — so production (secrets unset) has no bypass at all.
export function isMasterOtp(normalizedPhone: string, otp: string): boolean {
  const master = Deno.env.get("MASTER_OTP") ?? "";
  if (!master || otp !== master) return false;
  if (masterOtpAllPhones()) return true;
  return masterOtpAllowlist().has(normalizedPhone);
}

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function jsonResponse(
  status: number,
  body: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
