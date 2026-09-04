// Supabase Edge Function: verify a phone OTP and mint a real session.
//
// This is the fix for the deterministic-password auth bypass. Verification runs
// entirely server-side against the hash stored by send-otp; on success we:
//   1. ensure the auth user exists (create with a random password if new),
//   2. rotate the user's password to a fresh random value — this destroys any
//      old phone-derived password so it can never be used to sign in again,
//   3. return a single-use magic-link token_hash (via admin.generateLink) that
//      the client exchanges for a session with auth.verifyOTP.
// No guessable credential is ever produced or transmitted.
//
// Input:  { phone, otp }
// Output: { success: true, isExistingUser, tokenHash, email }
//         | { success: false, error, attemptsRemaining? }
//
// Deploy: supabase functions deploy verify-otp
// Secrets: (shared with send-otp) optional MASTER_OTP + MASTER_OTP_PHONES

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  corsHeaders,
  formatPhoneForDisplay,
  hashOtp,
  isMasterOtp,
  jsonResponse,
  legacyPhoneToEmail,
  normalizePhone,
  otpLookupPhones,
  OTP_MAX_ATTEMPTS,
  phoneToEmail,
} from "../_shared/otp.ts";

function serviceClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
}

function randomPassword(): string {
  return `${crypto.randomUUID()}${crypto.randomUUID()}`;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const phone = normalizePhone(String(body?.phone ?? ""));
    const otp = String(body?.otp ?? "").trim();
    if (!phone || !otp) {
      return jsonResponse(400, { success: false, error: "Missing phone or otp" });
    }

    const supabase = serviceClient();

    // ---- verify the code -------------------------------------------------
    if (!isMasterOtp(phone, otp)) {
      const { data: rows, error } = await supabase
        .from("otp_attempts")
        .select("id, otp_hash, attempts, expires_at")
        // Either spelling — see otpLookupPhones. Lets this deploy land
        // before or after send-otp's without breaking logins in between.
        .in("phone", otpLookupPhones(phone))
        .eq("is_used", false)
        .gt("expires_at", new Date().toISOString())
        .order("created_at", { ascending: false })
        .limit(1);

      if (error) {
        console.error("[verify-otp] lookup failed:", error);
        return jsonResponse(500, { success: false, error: "Verification failed" });
      }

      const entry = rows?.[0];
      if (!entry) {
        return jsonResponse(200, {
          success: false,
          error: "No active code. Please request a new one.",
        });
      }

      if ((entry.attempts ?? 0) >= OTP_MAX_ATTEMPTS) {
        await supabase.from("otp_attempts").update({ is_used: true })
          .eq("id", entry.id);
        return jsonResponse(200, {
          success: false,
          error: "Too many attempts. Please request a new code.",
        });
      }

      const matches = (await hashOtp(otp)) === entry.otp_hash;
      if (!matches) {
        const attempts = (entry.attempts ?? 0) + 1;
        await supabase.from("otp_attempts").update({ attempts })
          .eq("id", entry.id);
        return jsonResponse(200, {
          success: false,
          error: "Invalid code",
          attemptsRemaining: Math.max(0, OTP_MAX_ATTEMPTS - attempts),
        });
      }

      await supabase.from("otp_attempts")
        .update({ is_used: true, verified_at: new Date().toISOString() })
        .eq("id", entry.id);
    }

    // ---- ensure the auth user, rotate password, mint session -------------
    //
    // TWO candidate identities. normalizePhone used to leave a bare 10-digit
    // number alone, so accounts created before that fix are stored as
    // phone.1711165212@ rather than phone.01711165212@ — and the login screen
    // renders "+880" as a decorative prefix while submitting the raw text, so
    // most users typed it that way. 33 of 38 accounts are the bare form.
    //
    // Their stored email is NOT rewritten, here or by a migration. It is an
    // opaque key that admin.generateLink consumes and that the client echoes
    // back to verify the token, so a rename would have to land in the same
    // instant as this function's deploy; every returning user in the gap would
    // be handed a brand-new empty account. Looking for both spellings instead
    // is order-independent and needs no migration: whichever row exists keeps
    // its own address, and only genuinely new accounts get the canonical one.
    const canonicalEmail = phoneToEmail(phone);
    const legacyEmail = legacyPhoneToEmail(phone);
    const admin = supabase.auth.admin;

    const lookupByEmail = async (candidate: string): Promise<string | null> => {
      const { data } = await supabase.rpc(
        "get_auth_user_id_by_email",
        { p_email: candidate },
      );
      return (data as string | null) ?? null;
    };

    // Canonical first, so that once the duplicate pairs are merged the legacy
    // branch is only ever reached by accounts that have no canonical twin.
    let email = canonicalEmail;
    let userId: string | null = await lookupByEmail(canonicalEmail);
    if (!userId && legacyEmail) {
      const legacyId = await lookupByEmail(legacyEmail);
      if (legacyId) {
        userId = legacyId;
        email = legacyEmail;
      }
    }
    let isExistingUser = false;

    if (userId) {
      // Rotate away any old phone-derived password.
      await admin.updateUserById(userId, { password: randomPassword() });
      const { data: profile } = await supabase
        .from("profiles")
        .select("signup_completed")
        .eq("id", userId)
        .maybeSingle();
      isExistingUser = profile?.signup_completed === true;
    } else {
      const { data: created, error: createError } = await admin.createUser({
        email: canonicalEmail,
        email_confirm: true,
        password: randomPassword(),
        user_metadata: { mobile: formatPhoneForDisplay(phone) },
      });
      if (createError || !created?.user) {
        console.error("[verify-otp] createUser failed:", createError);
        return jsonResponse(500, {
          success: false,
          error: "Could not create account",
        });
      }
      userId = created.user.id;
      isExistingUser = false; // brand-new: client goes to profile completion
      email = canonicalEmail; // new accounts are always canonical
    }

    const { data: link, error: linkError } = await admin.generateLink({
      type: "magiclink",
      email,
    });
    if (linkError || !link?.properties?.hashed_token) {
      console.error("[verify-otp] generateLink failed:", linkError);
      return jsonResponse(500, {
        success: false,
        error: "Could not establish session",
      });
    }

    return jsonResponse(200, {
      success: true,
      isExistingUser,
      tokenHash: link.properties.hashed_token,
      email,
    });
  } catch (e) {
    console.error("[verify-otp] error:", e);
    return jsonResponse(500, { success: false, error: String(e) });
  }
});
