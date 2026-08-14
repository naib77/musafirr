// Supabase Edge Function: server-side geocoding proxy (place name → lat/lng).
//
// Why: web builds have no platform geocoder (the `geocoding` Flutter package is
// mobile-only), and the Google Geocoding web service must be called with a key
// that never ships to the client. Same posture as google-directions: the key
// lives only in Supabase secrets, verify_jwt is ON so only signed-in users can
// spend it.
//
// Results are biased to Bangladesh (region + country component filter) since
// the marketplace is BD-only — "banani" should resolve to Dhaka, not elsewhere.
//
// Input:  { query: "dakshinkhan" }            — forward: name → coordinates
//         { lat: 23.81, lng: 90.41 }          — reverse: coordinates → address
// Output: { found: true, lat, lng, label } | { found: false } | { error }
//
// Deploy: supabase functions deploy geocode
// Secret: GOOGLE_MAPS_SERVER_KEY (shared with google-directions)

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
    const { query, lat, lng } = await req.json();
    const reverse = typeof lat === "number" && typeof lng === "number" &&
      Number.isFinite(lat) && Number.isFinite(lng);
    if (!reverse && (typeof query !== "string" || query.trim().length === 0)) {
      return jsonResponse(400, { error: "query or lat/lng is required" });
    }

    const url = new URL("https://maps.googleapis.com/maps/api/geocode/json");
    if (reverse) {
      // Reverse: the pin a host dropped on the map → a readable address. Web
      // has no platform reverse-geocoder either, so it lands here too.
      url.searchParams.set("latlng", `${lat},${lng}`);
    } else {
      url.searchParams.set("address", query.trim().slice(0, 200));
      url.searchParams.set("components", "country:BD");
    }
    url.searchParams.set("region", "bd");
    url.searchParams.set("key", SERVER_KEY);

    const resp = await fetch(url.toString());
    const data = await resp.json();

    const first = data?.results?.[0];
    if (data?.status !== "OK" || !first?.geometry?.location) {
      return jsonResponse(200, { found: false });
    }
    // A nonsense query still "matches" at country level (the component filter
    // guarantees Bangladesh) — that's not a place to center a radius search on.
    if ((first.types ?? []).includes("country")) {
      return jsonResponse(200, { found: false });
    }
    return jsonResponse(200, {
      found: true,
      lat: first.geometry.location.lat,
      lng: first.geometry.location.lng,
      label: first.formatted_address ??
        (reverse ? `${lat}, ${lng}` : query.trim()),
    });
  } catch (e) {
    return jsonResponse(500, { error: String(e) });
  }
});
