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
//           + category: "hospital" | "exam_center" | "university" |
//             "tourist_spot" | "business_hub" — the landmark category being
//             picked. Restricts suggestions to that kind of place, so a
//             Medical search can't suggest restaurants. See CATEGORIES below.
//         { place_id: "ChIJ…" }    → coordinates for a chosen suggestion
// Output: { results: [{ name, label, place_id }] }
//         { found: true, name, label, lat, lng } | { found: false }
//
// The landmark-category → Google-place-type mapping lives HERE, not in the
// app: Android guests run whatever APK they last installed, so a mapping fix
// must not require a client release.
//
// Deploy: supabase functions deploy places-search
// Secret: GOOGLE_MAPS_SERVER_KEY (shared with geocode / google-directions)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders, jsonResponse } from "../_shared/otp.ts";

const SERVER_KEY = Deno.env.get("GOOGLE_MAPS_SERVER_KEY") ?? "";

const BD = { latMin: 20.5, latMax: 26.7, lngMin: 88.0, lngMax: 92.8 };

interface Corner {
  lat: number;
  lng: number;
}

// A Place Details geometry's box → the { ne, sw } corners the app filters and
// frames by. Prefers the exact `bounds` over the padded display `viewport`;
// null when neither is present (a precise point like a single building).
function extractBounds(
  geometry: {
    bounds?: { northeast?: Corner; southwest?: Corner };
    viewport?: { northeast?: Corner; southwest?: Corner };
  } | undefined,
): { ne_lat: number; ne_lng: number; sw_lat: number; sw_lng: number } | null {
  const box = geometry?.bounds ?? geometry?.viewport;
  const ne = box?.northeast;
  const sw = box?.southwest;
  if (
    !ne || !sw ||
    typeof ne.lat !== "number" || typeof ne.lng !== "number" ||
    typeof sw.lat !== "number" || typeof sw.lng !== "number"
  ) {
    return null;
  }
  return { ne_lat: ne.lat, ne_lng: ne.lng, sw_lat: sw.lat, sw_lng: sw.lng };
}

/// Per landmark category, two distinct things (they are NOT the same list):
///
/// `request` — what Google is *asked* to restrict to. Autocomplete allows at
///   most 5 types from place-types Table 1/2 joined by "|", OR exactly one
///   Table 3 filter ("(regions)", "establishment", …) which cannot be mixed
///   with anything else. Exceeding either rule returns INVALID_REQUEST.
/// `accept`  — what a returned prediction must actually carry to be shown.
///   This is the precision guarantee, has no length limit, and may be wider
///   than `request` (e.g. historic mosques count as tourist spots but we
///   don't proactively ask Google for every mosque).
///
/// Verified against the live API for Bangladesh, Aug 2026:
/// - "health" is deliberately NOT accepted for hospitals: it's a broad
///   Table 2 umbrella that also covers pharmacies ("LUBAB FARMECY" leaked in
///   under it), so it defeats the point of the filter.
/// - Business hubs are *areas* here (the seeded ones are Motijheel, Gulshan,
///   Karwan Bazar, Agrabad, Uttara), not businesses — hence "(regions)".
const CATEGORIES: Record<string, { request: string; accept: string[] }> = {
  hospital: {
    request: "hospital|doctor",
    accept: ["hospital", "doctor"],
  },
  exam_center: {
    request: "school|primary_school|secondary_school|university|library",
    accept: [
      "school",
      "primary_school",
      "secondary_school",
      "university",
      "library",
    ],
  },
  university: {
    request: "university",
    accept: ["university"],
  },
  tourist_spot: {
    request: "tourist_attraction|museum|park|natural_feature|zoo",
    accept: [
      "tourist_attraction",
      "museum",
      "park",
      "natural_feature",
      "zoo",
      "amusement_park",
      "aquarium",
      "art_gallery",
      "campground",
      // Historic mosques/temples (Sixty Dome Mosque, Kantajew Temple) are
      // among the country's main sights but are often typed only as places
      // of worship.
      "place_of_worship",
      "mosque",
      "hindu_temple",
      "church",
    ],
  },
  business_hub: {
    request: "(regions)",
    accept: [
      "locality",
      "sublocality",
      "sublocality_level_1",
      "sublocality_level_2",
      "sublocality_level_3",
      "neighborhood",
      "administrative_area_level_1",
      "administrative_area_level_2",
      "administrative_area_level_3",
      "political",
    ],
  },
};

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

function onCategory(prediction: unknown, accept: string[] | null): boolean {
  if (accept === null) return true;
  const types = (prediction as { types?: string[] }).types ?? [];
  return types.some((t) => accept.includes(t));
}

function toResults(predictions: unknown[], accept: string[] | null) {
  return predictions
    .filter((p) => onCategory(p, accept))
    .map((p) => {
      const pred = p as {
        place_id?: string;
        structured_formatting?: { main_text?: string; secondary_text?: string };
        description?: string;
      };
      return {
        name: pred.structured_formatting?.main_text ?? pred.description ?? "",
        label: (pred.structured_formatting?.secondary_text ?? "")
          .replace(/, Bangladesh$/, ""),
        place_id: pred.place_id ?? "",
      };
    })
    .filter((r) => r.name && r.place_id)
    .slice(0, 8);
}

async function suggest(
  query: string,
  scope?: string,
  category?: string,
): Promise<Response> {
  const cat = (typeof category === "string" && CATEGORIES[category]) || null;
  const accept = cat?.accept ?? null;

  // Pass 1 — ask Google for the category directly. Highest precision, and for
  // a typical query ("lub" → hospitals) it is the only call made.
  // Without a category: POIs only (landmark picker default), or anything at
  // all for the main search bar (scope "all").
  const first = await fetchPredictions(
    query,
    cat ? cat.request : (scope !== "all" ? "establishment" : ""),
  );
  if (!cat) {
    if (first.status !== "OK" && first.status !== "ZERO_RESULTS") {
      return jsonResponse(502, { error: `places: ${first.status}` });
    }
    return jsonResponse(200, { results: toResults(first.predictions, null) });
  }

  const strict = toResults(first.predictions, accept);
  if (strict.length > 0) return jsonResponse(200, { results: strict });

  // Pass 2 — Google's request-level type filter is applied over a limited
  // candidate set, so a narrow filter can return nothing even when a matching
  // place exists ("lalbagh" finds no tourist_attraction, yet Lalbagh Kellah is
  // one; likewise Sixty Dome Mosque). Re-ask unrestricted and keep only
  // on-category predictions — recall without giving up precision: an
  // off-category query ("kfc" under Medical) still ends up empty.
  const second = await fetchPredictions(query, "");
  if (
    second.status !== "OK" && second.status !== "ZERO_RESULTS" &&
    first.status !== "OK" && first.status !== "ZERO_RESULTS"
  ) {
    return jsonResponse(502, { error: `places: ${first.status}` });
  }
  return jsonResponse(200, { results: toResults(second.predictions, accept) });
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
    // The place's extent (Place Details returns `viewport`, occasionally the
    // tighter `bounds`) so an area picked from the search bar — "Uttara",
    // "Bashundhara R/A" — filters and frames to exactly that area, not a fixed
    // ring that spills into the next neighbourhood.
    bounds: extractBounds(data.result.geometry),
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
    const { query, place_id, scope, category } = await req.json();
    if (typeof place_id === "string" && place_id.length > 0) {
      return await resolve(place_id);
    }
    if (typeof query === "string" && query.trim().length >= 2) {
      return await suggest(
        query.trim(),
        typeof scope === "string" ? scope : undefined,
        typeof category === "string" ? category : undefined,
      );
    }
    return jsonResponse(400, { error: "query or place_id is required" });
  } catch (e) {
    return jsonResponse(500, { error: String(e) });
  }
});
