// Supabase Edge Function to send FCM push notifications (HTTP v1 API).
//
// The legacy FCM API (fcm.googleapis.com/fcm/send + server key) was shut
// down by Google in 2024 — every send returned an HTML error page and
// `sent: 0`. This version uses the FCM HTTP v1 API with a service-account
// OAuth token.
//
// Deploy:      supabase functions deploy send-push-notification
// Set secret:  supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)"
//   (Firebase Console → Project settings → Service accounts → Generate new private key)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface NotificationPayload {
  user_id: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
  image_url?: string;
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

// ============================================================
// OAuth2 access token for FCM, cached across invocations
// ============================================================

let cachedToken: { token: string; expiresAt: number } | null = null;

function base64UrlEncode(data: Uint8Array | string): string {
  const bytes =
    typeof data === "string" ? new TextEncoder().encode(data) : data;
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const pkcs8 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const raw = Uint8Array.from(atob(pkcs8), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    raw,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - 60 > now) {
    return cachedToken.token;
  }

  const header = base64UrlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64UrlEncode(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));

  const key = await importPrivateKey(sa.private_key);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const jwt = `${header}.${claims}.${base64UrlEncode(new Uint8Array(signature))}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!response.ok) {
    throw new Error(`OAuth token exchange failed: ${await response.text()}`);
  }

  const json = await response.json();
  cachedToken = { token: json.access_token, expiresAt: now + 3600 };
  return json.access_token;
}

// ============================================================
// Handler
// ============================================================

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const saJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
    if (!saJson) {
      throw new Error(
        "FIREBASE_SERVICE_ACCOUNT not configured. Generate a service-account " +
          "key in the Firebase console and set it with `supabase secrets set`.",
      );
    }
    const serviceAccount: ServiceAccount = JSON.parse(saJson);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const payload: NotificationPayload = await req.json();
    const { user_id, title, body, data, image_url } = payload;

    if (!user_id || !title || !body) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: user_id, title, body" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch the user's active device tokens
    const { data: tokens, error: tokensError } = await supabase
      .from("fcm_tokens")
      .select("token")
      .eq("user_id", user_id)
      .eq("is_active", true);

    if (tokensError) throw tokensError;

    if (!tokens || tokens.length === 0) {
      return new Response(
        JSON.stringify({ success: true, message: "No active tokens", sent: 0 }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    console.log(`Found ${tokens.length} active tokens for user: ${user_id}`);

    const accessToken = await getAccessToken(serviceAccount);
    const endpoint =
      `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;

    // FCM v1 requires every data value to be a string.
    const stringData: Record<string, string> = {
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    };
    for (const [key, value] of Object.entries(data ?? {})) {
      stringData[key] =
        typeof value === "string" ? value : JSON.stringify(value);
    }

    const results = await Promise.all(
      tokens.map(async ({ token }: { token: string }) => {
        const message = {
          message: {
            token,
            notification: {
              title,
              body,
              ...(image_url && { image: image_url }),
            },
            data: stringData,
            android: { priority: "HIGH" },
            apns: {
              payload: { aps: { sound: "default" } },
            },
          },
        };

        try {
          const response = await fetch(endpoint, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${accessToken}`,
            },
            body: JSON.stringify(message),
          });

          if (response.ok) {
            return { token: token.substring(0, 20), success: true };
          }

          const errorBody = await response.text();
          console.error(
            `FCM v1 error ${response.status} for ${token.substring(0, 20)}...: ${errorBody}`,
          );

          // Deactivate dead tokens so we stop retrying them.
          if (
            response.status === 404 ||
            errorBody.includes("UNREGISTERED") ||
            errorBody.includes("INVALID_ARGUMENT")
          ) {
            await supabase
              .from("fcm_tokens")
              .update({ is_active: false })
              .eq("token", token);
          }

          return {
            token: token.substring(0, 20),
            success: false,
            error: `HTTP ${response.status}`,
          };
        } catch (err) {
          console.error(`Error sending to ${token.substring(0, 20)}...:`, err);
          return {
            token: token.substring(0, 20),
            success: false,
            error: (err as Error).message,
          };
        }
      }),
    );

    const sent = results.filter((r) => r.success).length;
    console.log(`Sent ${sent}/${tokens.length} notifications to user ${user_id}`);

    return new Response(
      JSON.stringify({ success: true, sent, total: tokens.length, results }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("send-push-notification error:", error);
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
