// Supabase Edge Function: Google Places Text Search proxy (POI name → candidates).
//
// Why: the `landmarks` table only holds seeded anchors, but guests expect to
// type any hospital / university / attraction name — "lubana hospital" — and
// find it like they would on Google Maps. Places Text Search resolves free-text
// POI names to coordinates. Same key posture as geocode/google-directions: the
// key lives only in Supabase secrets, verify_jwt is ON.
//
// Bangladesh-only marketplace: the query gets ", Bangladesh" appended (region=bd
// alone still leaks neighbouring-country results) and results are additionally
// clamped to a BD bounding box.
//
// Input:  { query: "lubana hospital", type?: "hospital" }   // our landmark type
// Output: { results: [{ name, label, lat, lng, place_id }] } | { error }
//
// Deploy: supabase functions deploy places-search
// Secret: GOOGLE_MAPS_SERVER_KEY (shared with geocode / google-directions)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders, jsonResponse } from "../_shared/otp.ts";

const SERVER_KEY = Deno.env.get("GOOGLE_MAPS_SERVER_KEY") ?? "";

// Landmark types that map onto a Google place type filter; the rest
// (exam_center, business_hub) search untyped — the query text carries intent.
const TYPE_MAP: Record<string, string> = {
  hospital: "hospital",
  university: "university",
  tourist_spot: "tourist_attraction",
};

const BD = { latMin: 20.5, latMax: 26.7, lngMin: 88.0, lngMax: 92.8 };

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
    const { query, type } = await req.json();
    if (typeof query !== "string" || query.trim().length < 2) {
      return jsonResponse(400, { error: "query is required" });
    }

    const url = new URL(
      "https://maps.googleapis.com/maps/api/place/textsearch/json",
    );
    url.searchParams.set("query", `${query.trim().slice(0, 120)}, Bangladesh`);
    url.searchParams.set("region", "bd");
    const gtype = typeof type === "string" ? TYPE_MAP[type] : undefined;
    if (gtype) url.searchParams.set("type", gtype);
    url.searchParams.set("key", SERVER_KEY);

    const resp = await fetch(url.toString());
    const data = await resp.json();

    if (data?.status !== "OK" && data?.status !== "ZERO_RESULTS") {
      return jsonResponse(502, { error: `places: ${data?.status ?? "unknown"}` });
    }

    const results = (data.results ?? [])
      .filter((r: { geometry?: { location?: { lat: number; lng: number } } }) => {
        const l = r.geometry?.location;
        return (
          l &&
          l.lat >= BD.latMin && l.lat <= BD.latMax &&
          l.lng >= BD.lngMin && l.lng <= BD.lngMax
        );
      })
      .slice(0, 8)
      .map((r: {
        name?: string;
        formatted_address?: string;
        place_id?: string;
        geometry: { location: { lat: number; lng: number } };
      }) => ({
        name: r.name ?? "",
        label: r.formatted_address ?? "",
        lat: r.geometry.location.lat,
        lng: r.geometry.location.lng,
        place_id: r.place_id ?? "",
      }));

    return jsonResponse(200, { results });
  } catch (e) {
    return jsonResponse(500, { error: String(e) });
  }
});
