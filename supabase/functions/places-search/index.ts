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
//           + scope: "all" widens beyond establishments (areas, addresses) —
//             used by the main search bar; the landmark picker wants POIs only
//           + types: ["hospital", …] restricts predictions to those Google
//             place types (picker categories: a Medical search must not
//             suggest restaurants). Requested upstream AND re-checked on the
//             returned predictions.
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

async function fetchPredictions(
  query: string,
  typesParam: string,
): Promise<{ status: string; predictions: unknown[] }> {
  const url = new URL(
    "https://maps.googleapis.com/maps/api/place/autocomplete/json",
  );
  url.searchParams.set("input", query.slice(0, 120));
  url.searchParams.set("components", "country:BD");
  if (typesParam) url.searchParams.set("types", typesParam);
  url.searchParams.set("key", SERVER_KEY);

  const data = await (await fetch(url.toString())).json();
  return {
    status: data?.status ?? "unknown",
    predictions: data?.predictions ?? [],
  };
}

async function suggest(
  query: string,
  scope?: string,
  types?: unknown,
): Promise<Response> {
  // Category restriction ("hospital", "university", …): sanitized, max 5.
  const wanted = (Array.isArray(types) ? types : [])
    .filter((t): t is string =>
      typeof t === "string" && /^[a-z_]{2,40}$/.test(t)
    )
    .slice(0, 5);

  // Default is POIs only (landmark picker); scope "all" also predicts areas,
  // localities and addresses for the main search bar.
  let { status, predictions } = await fetchPredictions(
    query,
    wanted.length > 0 ? wanted.join("|") : (scope !== "all" ? "establishment" : ""),
  );
  // Not every type combination is accepted as a request filter — fall back to
  // plain establishments and rely on the prediction-level check below.
  if (status === "INVALID_REQUEST" && wanted.length > 0) {
    ({ status, predictions } = await fetchPredictions(query, "establishment"));
  }
  if (status !== "OK" && status !== "ZERO_RESULTS") {
    return jsonResponse(502, { error: `places: ${status}` });
  }

  const results = predictions
    // Re-check the category on each prediction's own types — the request
    // filter is an upstream optimization, this is the guarantee.
    .filter((p: { types?: string[] }) =>
      wanted.length === 0 ||
      (p.types ?? []).some((t: string) => wanted.includes(t))
    )
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
    const { query, place_id, scope, types } = await req.json();
    if (typeof place_id === "string" && place_id.length > 0) {
      return await resolve(place_id);
    }
    if (typeof query === "string" && query.trim().length >= 2) {
      return await suggest(
        query.trim(),
        typeof scope === "string" ? scope : undefined,
        types,
      );
    }
    return jsonResponse(400, { error: "query or place_id is required" });
  } catch (e) {
    return jsonResponse(500, { error: String(e) });
  }
});
