// Supabase Edge Function: Google Places proxy for the landmark picker.
//
// Why: the `landmarks` table only holds seeded anchors, but guests expect
// Google-Maps-style type-ahead — three letters of "lub" should already suggest
// Lubana General Hospital. Places Autocomplete is prefix-based (Text Search
// needs near-complete names), so suggestions come from Autocomplete and the
// chosen suggestion is resolved to coordinates with Place Details. Same key
// posture as geocode/google-directions: the key lives only in Supabase
// secrets, verify_jwt is ON.
//
// Input:  { query: "lub" }         → suggestions (no coordinates)
//         { place_id: "ChIJ…" }    → coordinates for a chosen suggestion
// Output: { results: [{ name, label, place_id }] }
//         { found: true, name, label, lat, lng } | { found: false }
//
// Deploy: supabase functions deploy places-search
// Secret: GOOGLE_MAPS_SERVER_KEY (shared with geocode / google-directions)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders, jsonResponse } from "../_shared/otp.ts";

const SERVER_KEY = Deno.env.get("GOOGLE_MAPS_SERVER_KEY") ?? "";

const BD = { latMin: 20.5, latMax: 26.7, lngMin: 88.0, lngMax: 92.8 };

async function suggest(query: string): Promise<Response> {
  const url = new URL(
    "https://maps.googleapis.com/maps/api/place/autocomplete/json",
  );
  url.searchParams.set("input", query.slice(0, 120));
  url.searchParams.set("components", "country:BD");
  // POIs only — plain areas/addresses are the geocode function's job.
  url.searchParams.set("types", "establishment");
  url.searchParams.set("key", SERVER_KEY);

  const data = await (await fetch(url.toString())).json();
  if (data?.status !== "OK" && data?.status !== "ZERO_RESULTS") {
    return jsonResponse(502, { error: `places: ${data?.status ?? "unknown"}` });
  }

  const results = (data.predictions ?? [])
    .map((p: {
      place_id?: string;
      structured_formatting?: { main_text?: string; secondary_text?: string };
      description?: string;
    }) => ({
      name: p.structured_formatting?.main_text ?? p.description ?? "",
      label: (p.structured_formatting?.secondary_text ?? "")
        .replace(/, Bangladesh$/, ""),
      place_id: p.place_id ?? "",
    }))
    .filter((r: { name: string; place_id: string }) => r.name && r.place_id)
    .slice(0, 8);

  return jsonResponse(200, { results });
}

async function resolve(placeId: string): Promise<Response> {
  const url = new URL(
    "https://maps.googleapis.com/maps/api/place/details/json",
  );
  url.searchParams.set("place_id", placeId.slice(0, 300));
  url.searchParams.set("fields", "name,formatted_address,geometry");
  url.searchParams.set("key", SERVER_KEY);

  const data = await (await fetch(url.toString())).json();
  const loc = data?.result?.geometry?.location;
  if (data?.status !== "OK" || !loc) {
    return jsonResponse(200, { found: false });
  }
  // Belt-and-braces: the country component filter should guarantee BD, but a
  // stale/foreign place_id must not center a search abroad.
  if (
    loc.lat < BD.latMin || loc.lat > BD.latMax ||
    loc.lng < BD.lngMin || loc.lng > BD.lngMax
  ) {
    return jsonResponse(200, { found: false });
  }
  return jsonResponse(200, {
    found: true,
    name: data.result.name ?? "",
    label: (data.result.formatted_address ?? "")
      .replace(/, Bangladesh$/, ""),
    lat: loc.lat,
    lng: loc.lng,
  });
}

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
    const { query, place_id } = await req.json();
    if (typeof place_id === "string" && place_id.length > 0) {
      return await resolve(place_id);
    }
    if (typeof query === "string" && query.trim().length >= 2) {
      return await suggest(query.trim());
    }
    return jsonResponse(400, { error: "query or place_id is required" });
  } catch (e) {
    return jsonResponse(500, { error: String(e) });
  }
});
