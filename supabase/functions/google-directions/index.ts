// Supabase Edge Function: server-side Google Directions proxy.
//
// Why: the Google Maps key must never be a usable client secret. Map *rendering*
// (web JS + native SDKs) unavoidably needs a client key (restricted by
// referrer/app id), but the Directions *web service* is a plain server call — so
// we run it here with a key that lives only in Supabase secrets and never ships
// to the app. The client sends origin/destination/mode; we return Google's raw
// Directions JSON, which the app already knows how to parse.
//
// Auth: verify_jwt is ON (default) so only signed-in app users can spend the
// key — an anonymous proxy would just move the abuse problem to our bill.
//
// Input:  { origin: "lat,lng", destination: "lat,lng", mode?: "driving" }
// Output: Google Directions JSON, or { error }
//
// Deploy:     supabase functions deploy google-directions
// Set secret: supabase secrets set GOOGLE_MAPS_SERVER_KEY="..."

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders, jsonResponse } from "../_shared/otp.ts";

const SERVER_KEY = Deno.env.get("GOOGLE_MAPS_SERVER_KEY") ?? "";

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed" });
  }
  if (!SERVER_KEY) {
    return jsonResponse(500, { error: "GOOGLE_MAPS_SERVER_KEY not configured" });
  }

  try {
    const { origin, destination, mode } = await req.json();
    if (typeof origin !== "string" || typeof destination !== "string") {
      return jsonResponse(400, {
        error: "origin and destination (\"lat,lng\") are required",
      });
    }
    // Whitelist the travel mode so the value can't be used to smuggle params.
    const allowed = ["driving", "walking", "bicycling", "transit"];
    const travelMode = allowed.includes(mode) ? mode : "driving";

    const url = new URL("https://maps.googleapis.com/maps/api/directions/json");
    url.searchParams.set("origin", origin);
    url.searchParams.set("destination", destination);
    url.searchParams.set("mode", travelMode);
    url.searchParams.set("key", SERVER_KEY);

    const resp = await fetch(url.toString());
    const data = await resp.json();
    return jsonResponse(200, data);
  } catch (e) {
    return jsonResponse(500, { error: String(e) });
  }
});
