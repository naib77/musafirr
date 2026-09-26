// Tests for the bucket-choosing half of the rate limiter — the part that
// decides WHO a request counts against. The counter itself is
// fn_rate_limit_hit, pinned by supabase/tests/139_140_open_items_test.sql.
//
//   deno test supabase/functions/_shared/

import {
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  clientIp,
  jwtSubject,
  rateLimitBucket,
  rateLimitSubject,
} from "./rate_limit.ts";

function jwt(payload: Record<string, unknown>): string {
  const enc = (o: unknown) =>
    btoa(JSON.stringify(o)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return `${enc({ alg: "HS256", typ: "JWT" })}.${enc(payload)}.sig`;
}

Deno.test("a user token is keyed by its sub", () => {
  const h = new Headers({
    authorization: `Bearer ${jwt({ role: "authenticated", sub: "u-123" })}`,
    "x-forwarded-for": "1.2.3.4",
  });
  assertEquals(rateLimitSubject(h), { kind: "user", key: "u-123" });
  assertEquals(rateLimitBucket("geocode", rateLimitSubject(h)), "geocode:user:u-123");
});

Deno.test("the anon key is NOT a user: it is keyed by IP", () => {
  // The compiled-in anon key is a JWT with role anon and no sub. Treating it
  // as a user would put every signed-out visitor in one bucket.
  const h = new Headers({
    authorization: `Bearer ${jwt({ role: "anon", iss: "supabase" })}`,
    "x-forwarded-for": "203.0.113.9, 10.0.0.1",
  });
  assertEquals(jwtSubject(h.get("authorization")), null);
  assertEquals(rateLimitSubject(h), { kind: "ip", key: "203.0.113.9" });
});

Deno.test("a token that claims authenticated but has no sub falls back to IP", () => {
  const h = new Headers({
    authorization: `Bearer ${jwt({ role: "authenticated" })}`,
    "x-forwarded-for": "198.51.100.7",
  });
  assertEquals(rateLimitSubject(h), { kind: "ip", key: "198.51.100.7" });
});

Deno.test("garbage in the Authorization header is not a crash", () => {
  assertEquals(jwtSubject("Bearer not.a.jwt!!"), null);
  assertEquals(jwtSubject("Bearer a.b"), null);
  assertEquals(jwtSubject("Basic abc"), null);
  assertEquals(jwtSubject(`Bearer x.${btoa("{not json")}.y`), null);
});

Deno.test("client IP prefers cf-connecting-ip, then the first forwarded hop", () => {
  assertEquals(
    clientIp(new Headers({ "cf-connecting-ip": "9.9.9.9", "x-forwarded-for": "1.1.1.1" })),
    "9.9.9.9",
  );
  assertEquals(clientIp(new Headers({ "x-forwarded-for": " 1.1.1.1 , 2.2.2.2" })), "1.1.1.1");
  assertEquals(clientIp(new Headers({ "x-real-ip": "3.3.3.3" })), "3.3.3.3");
});

Deno.test("no address at all shares one bucket rather than escaping the limit", () => {
  assertEquals(clientIp(new Headers()), "unknown");
  assertEquals(rateLimitSubject(new Headers()), { kind: "ip", key: "unknown" });
});
