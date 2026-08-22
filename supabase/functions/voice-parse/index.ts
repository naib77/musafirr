// Supabase Edge Function: Gemini fallback for voice-search parsing.
//
// Why: the app parses spoken Bangla/Banglish with a lexicon
// (lib/services/voice/voice_query_parser.dart) — free, instant, offline, and
// right for the overwhelming majority of queries. But a lexicon only knows
// what someone typed into it, so every unusual phrasing used to arrive as a
// bug report and leave as another 100 entries. This is the tail: it is called
// ONLY when the lexicon extracted nothing, or when the place it extracted
// failed to geocode. Common queries never reach here and cost nothing.
//
// The model fills slots. It does NOT locate anything: `place` comes back as a
// string and is still resolved by the `geocode` function against Google, the
// same way a typed search is. An LLM that emits coordinates is an LLM that
// confidently sends guests to the wrong city.
//
// Input:  { transcript: "dhanmondi bottris e basa lagbe" }
// Output: { parsed: true, place, types[], guests, max_price, purpose }
//         { parsed: false }            — nothing usable in it
//
// Same key posture as geocode / places-search: the key lives only in Supabase
// secrets, verify_jwt is ON.
//
// PRIVACY: use a PAID-tier key. Google's free tier states plainly that
// "content [is] used to improve our products"; the paid tier states it is
// not. These transcripts are user speech, which `voice_search_log` already
// treats as private (insert-only, no select policy, unreadable even to the
// person who spoke it). A free key would quietly undo that stance for the
// sake of a few cents a month.
//
// Deploy: supabase functions deploy voice-parse
// Secrets: GEMINI_API_KEY  (required)
//          GEMINI_MODEL    (optional, see MODEL below)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders, jsonResponse } from "../_shared/otp.ts";

const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";

// Flash-Lite, not Pro or Flash. This is slot-filling against a fixed schema —
// the hard part is Bangla vocabulary, not reasoning — and it sits in a voice
// interaction where latency is felt directly.
//
// 3.5-flash-lite was picked by measurement, not by price. Against nine real
// Banglish/Bengali cases it and 3.1-flash-lite both scored 9/9, but 3.1
// answered "bosundhara r-a block e basa" with "Bashundhara R/A Block A" —
// inventing a block letter, which is how a guest ends up in the wrong part of
// a large estate. 3.5 returned "Bashundhara R/A Block" and stopped.
// Measured: ~363 in + ~48 out tokens, ~1.1 s, ≈$0.23 per 1,000 calls.
//
// Overridable by secret ON PURPOSE, and the reason is not hypothetical:
// gemini-2.0-flash was shut down while this function was being written, and
// gemini-2.5-flash-lite still appears in ListModels but answers
// generateContent with "no longer available to new users". A model id baked
// into a deployed function is an outage waiting for Google's next cleanup.
//   supabase secrets set GEMINI_MODEL=gemini-3.7-flash
const MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.5-flash-lite";

// The app's enums. Anything outside these lists is dropped rather than passed
// through, so a hallucinated value can never reach SearchFilters.
const TYPES = ["seat", "room", "fullHouse"];
const PURPOSES = [
  "general",
  "medical",
  "exam",
  "tourism",
  "business",
  "student",
];

const SYSTEM = `You extract search filters from a spoken query for a
Bangladeshi homestay marketplace. Speech is Bangla, English, or Banglish
(Bangla written in Latin letters), and comes from a speech recogniser, so
expect mishearings.

Rules:
- "place" is a Bangladeshi place name in ENGLISH, spelled the way Google Maps
  would ("Dhanmondi", "Cox's Bazar", "Uttara sector 7"). Numbers in addresses
  must be DIGITS, even when spoken as words: "dhanmondi bottris" is
  "Dhanmondi 32", "uttara sector attharo" is "Uttara sector 18".
- Never invent a place that was not spoken. If no place was named, use null.
- Never output coordinates.
- "types": seat = a bed in a shared room, room = a private room,
  fullHouse = the whole place. Bangla: সিট/seat, রুম/room, বাসা/বাড়ি/basa/bari
  = fullHouse. Empty array if unstated.
- "guests": integer number of people, or null.
- "max_price": a BDT ceiling as a number, or null. "5 hajar" = 5000,
  "8k" = 8000.
- "purpose": why they are travelling, from the allowed list, or null. Near a
  hospital = medical, an exam centre = exam, sightseeing = tourism.
- Drop verbs and filler ("khojo", "dekho", "lagbe", "chai", "dike", "kache").`;

const SCHEMA = {
  type: "object",
  properties: {
    place: { type: "string", nullable: true },
    types: { type: "array", items: { type: "string", enum: TYPES } },
    guests: { type: "integer", nullable: true },
    max_price: { type: "number", nullable: true },
    purpose: { type: "string", enum: PURPOSES, nullable: true },
  },
  required: ["place", "types"],
};

/// Keeps only what the app's enums actually accept. The schema already
/// constrains the model, but a response is still untrusted input.
function clean(raw: Record<string, unknown>) {
  const place = typeof raw.place === "string" ? raw.place.trim().slice(0, 120) : "";
  const types = Array.isArray(raw.types)
    ? [...new Set(raw.types.filter((t) => TYPES.includes(t as string)))]
    : [];

  const guestsRaw = typeof raw.guests === "number" ? Math.round(raw.guests) : null;
  const guests = guestsRaw !== null && guestsRaw >= 1 && guestsRaw <= 16
    ? guestsRaw
    : null;

  const priceRaw = typeof raw.max_price === "number" ? raw.max_price : null;
  const maxPrice = priceRaw !== null && priceRaw > 0 && priceRaw <= 1_000_000
    ? priceRaw
    : null;

  const purpose = typeof raw.purpose === "string" && PURPOSES.includes(raw.purpose)
    ? raw.purpose
    : null;

  return { place: place.length > 0 ? place : null, types, guests, maxPrice, purpose };
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed" });
  }
  if (!GEMINI_KEY) {
    return jsonResponse(500, { error: "GEMINI_API_KEY not configured" });
  }

  try {
    const { transcript } = await req.json();
    if (typeof transcript !== "string" || transcript.trim().length === 0) {
      return jsonResponse(400, { error: "transcript is required" });
    }
    // A spoken search is a sentence, not a document. The cap bounds both cost
    // and the blast radius of anything pasted in deliberately.
    const text = transcript.trim().slice(0, 300);

    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${GEMINI_KEY}`;

    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: SYSTEM }] },
        contents: [{ role: "user", parts: [{ text }] }],
        generationConfig: {
          // Slot-filling, not writing. Deterministic output also makes the
          // thing testable.
          temperature: 0,
          maxOutputTokens: 200,
          responseMimeType: "application/json",
          responseSchema: SCHEMA,
        },
      }),
    });

    if (!res.ok) {
      console.error("[voice-parse] gemini", res.status, await res.text());
      return jsonResponse(502, { error: "upstream" });
    }

    const body = await res.json();
    const raw = body?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (typeof raw !== "string") return jsonResponse(200, { parsed: false });

    const slots = clean(JSON.parse(raw));
    const empty = slots.place === null && slots.types.length === 0 &&
      slots.guests === null && slots.maxPrice === null &&
      slots.purpose === null;
    if (empty) return jsonResponse(200, { parsed: false });

    return jsonResponse(200, {
      parsed: true,
      place: slots.place,
      types: slots.types,
      guests: slots.guests,
      max_price: slots.maxPrice,
      purpose: slots.purpose,
    });
  } catch (e) {
    console.error("[voice-parse]", e);
    return jsonResponse(500, { error: "parse failed" });
  }
});
