// Supabase Edge Function to send FCM push notifications
// Deploy: supabase functions deploy send-push-notification
// Set secret: supabase secrets set FCM_SERVER_KEY=your_server_key

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
  data?: Record<string, string>;
  image_url?: string;
}

interface FCMMessage {
  to: string;
  notification: {
    title: string;
    body: string;
    image?: string;
  };
  data?: Record<string, string>;
  priority: string;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const fcmServerKey = Deno.env.get("FCM_SERVER_KEY");
    if (!fcmServerKey) {
      throw new Error("FCM_SERVER_KEY not configured");
    }

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
        }
      );
    }

    // Get active FCM tokens for the user
    const { data: tokens, error: tokenError } = await supabase
      .from("fcm_tokens")
      .select("token")
      .eq("user_id", user_id)
      .eq("is_active", true);

    if (tokenError) {
      console.error("Error fetching tokens:", tokenError);
      throw tokenError;
    }

    if (!tokens || tokens.length === 0) {
      console.log(`No active FCM tokens found for user: ${user_id}`);
      return new Response(
        JSON.stringify({ success: true, message: "No active tokens", sent: 0 }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    console.log(`Found ${tokens.length} active tokens for user: ${user_id}`);

    // Send notification to all active tokens
    const results = await Promise.all(
      tokens.map(async ({ token }) => {
        const message: FCMMessage = {
          to: token,
          notification: {
            title,
            body,
            ...(image_url && { image: image_url }),
          },
          data: {
            ...data,
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
          priority: "high",
        };

        try {
          const response = await fetch("https://fcm.googleapis.com/fcm/send", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `key=${fcmServerKey}`,
            },
            body: JSON.stringify(message),
          });

          const result = await response.json();
          console.log(`FCM response for token ${token.substring(0, 20)}...:`, result);

          // If token is invalid, deactivate it
          if (result.failure === 1 && result.results?.[0]?.error) {
            const error = result.results[0].error;
            if (
              error === "NotRegistered" ||
              error === "InvalidRegistration"
            ) {
              console.log(`Deactivating invalid token: ${token.substring(0, 20)}...`);
              await supabase
                .from("fcm_tokens")
                .update({ is_active: false })
                .eq("token", token);
            }
          }

          return { token: token.substring(0, 20), success: result.success === 1 };
        } catch (err) {
          console.error(`Error sending to token ${token.substring(0, 20)}...:`, err);
          return { token: token.substring(0, 20), success: false, error: err.message };
        }
      })
    );

    const successCount = results.filter((r) => r.success).length;

    return new Response(
      JSON.stringify({
        success: true,
        sent: successCount,
        total: tokens.length,
        results,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Error in send-push-notification:", error);
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
