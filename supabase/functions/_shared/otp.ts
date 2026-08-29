// Shared OTP / phone helpers for the send-otp and verify-otp Edge Functions.
// Keep the phone normalization and message template in sync with the Flutter
// client (OtpService.normalizePhoneNumber / SmsConfig.getOtpMessage) so the
// derived auth email matches on both sides.

export const OTP_LENGTH = 4;
export const OTP_TTL_MINUTES = 5;
export const OTP_MAX_ATTEMPTS = 3;

/// The assigned BD mobile operator prefixes with the national leading zero
/// stripped: 013-019 -> 1[3-9], then eight more digits.
const BARE_BD_MOBILE = /^1[3-9][0-9]{8}$/;

/// App-normalized BD number: strip formatting, collapse +880/880 to a leading 0
/// (e.g. "+880 1673-293542" and "8801673293542" -> "01673293542").
///
/// THIS DECIDES WHICH ACCOUNT A USER LOGS INTO. phoneToEmail below turns the
/// result into the Supabase auth identity, and verify-otp creates one account
/// per distinct value — so any two spellings of one number that come out
/// different here are two different people to the app, with separate listings,
/// bookings and identity verifications.
///
/// The bare-10-digit branch is not cosmetic. The login screen renders "+880" as
/// a decorative prefix and submits the raw field text, so users are invited to
/// omit the leading zero — visually the "+880" replaces it. Without that branch
/// "1711165212" matched nothing and passed through unchanged, producing
/// phone.1711165212@musaafir.app beside phone.01711165212@musaafir.app for one
/// human. Four production accounts were duplicated that way before it was
/// noticed; migration 109 merges the pairs that already exist. Existing rows
/// are NOT renamed to the canonical form — see legacyPhoneToEmail below for why.
///
/// Keep in step with lib/services/auth/phone_number.dart (canonicalBdPhone),
/// which is pinned by test/services/phone_number_test.dart.
export function normalizePhone(phone: string): string {
  let n = phone.replace(/[\s\-()]/g, "");
  if (n.startsWith("+880")) n = "0" + n.slice(4);
  else if (n.startsWith("880")) n = "0" + n.slice(3);
  else if (n.startsWith("+")) n = n.slice(1);
  // Only the exact "10 digits starting 1[3-9]" shape is assumed to be a BD
  // mobile missing its zero. Guessing more widely would rewrite a mistyped
  // number into somebody else's account, which is worse than failing to log in.
  if (BARE_BD_MOBILE.test(n)) n = "0" + n;
  return n;
}

/// Internal Supabase-auth email derived from the phone. Must match the Flutter
/// client's phoneToAuthEmail exactly.
export function phoneToEmail(normalizedPhone: string): string {
  return `phone.${normalizedPhone}@musaafir.app`;
}

/// The identity this number would have been given BEFORE normalizePhone learned
/// to restore a missing leading zero — i.e. the bare 10-digit form. Null when
/// there is no older spelling to look for.
///
/// Existing accounts are NOT renamed to the canonical form. The stored email is
/// an opaque key that admin.generateLink consumes and the client echoes back, so
/// rewriting it would mean renaming 33 live accounts and landing that rename in
/// the same instant as the edge-function deploy — every returning user in the
/// gap gets a new empty account. verify-otp instead looks for both spellings and
/// keeps whichever one it finds.
export function legacyPhoneToEmail(canonicalPhone: string): string | null {
  const m = /^0(1[3-9][0-9]{8})$/.exec(canonicalPhone);
  return m ? `phone.${m[1]}@musaafir.app` : null;
}

/// Every spelling the otp_attempts row for this number might be stored under.
///
/// send-otp writes the row keyed by normalizePhone(input) and verify-otp reads
/// it back the same way, so the two functions must agree on that key — but they
/// are separate deploys. While one carries the bare-10-digit branch and the
/// other does not, a user typing "1711165212" has their code stored under one
/// spelling and looked up under the other, and every such login fails with
/// "No active code". That is 33 of 38 accounts, for as long as the gap lasts.
///
/// Reading both spellings removes the gap in the only direction that matters:
/// a verify-otp carrying this accepts a code minted by either version of
/// send-otp, so the deploys can land in any order. Safe because the codes are
/// short-lived, single-use and hashed, and because the two spellings are the
/// same phone number by definition — nothing widens who can redeem a code.
///
/// Once both functions are deployed everywhere, only the canonical key is ever
/// written and the second candidate simply never matches.
export function otpLookupPhones(normalizedPhone: string): string[] {
  const legacy = /^0(1[3-9][0-9]{8})$/.exec(normalizedPhone);
  return legacy ? [normalizedPhone, legacy[1]] : [normalizedPhone];
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
  return `Your Musaafir verification code is: ${otp}. Valid for ${OTP_TTL_MINUTES} minutes.`;
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
