// Pins the hand-rolled SigV4 in s3.ts and the magic-byte check in sniff.ts.
//
//   deno test supabase/functions/_shared/

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  amzDate,
  hex,
  presignGet,
  presignPost,
  type S3Config,
  signingKey,
  uriEncode,
} from "./s3.ts";
import { contentMatches } from "./sniff.ts";

// AWS's published example: "Examples of How to Derive a Signing Key for
// Signature Version 4". If this drifts, every signature is wrong.
Deno.test("signing key matches the AWS reference vector", async () => {
  const key = await signingKey(
    "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
    "20120215",
    "us-east-1",
    "iam",
  );
  assertEquals(
    hex(key),
    "f4780e2d9f65fa895f9c67b32ce1baf0b0d8a43505a000a1a9e090d414db404d",
  );
});

// AWS's published presigned-URL example ("Authenticating Requests: Using
// Query Parameters"), GET /test.txt from examplebucket, 86400 s.
Deno.test("presigned GET matches the AWS reference signature", async () => {
  const cfg: S3Config = {
    endpoint: "https://s3.amazonaws.com",
    publicEndpoint: "https://s3.amazonaws.com",
    region: "us-east-1",
    accessKeyId: "AKIAIOSFODNN7EXAMPLE",
    secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    pathStyle: false,
  };
  const url = await presignGet(cfg, "examplebucket", "test.txt", 86400, {
    now: new Date("2013-05-24T00:00:00Z"),
  });
  assert(url.startsWith("https://examplebucket.s3.amazonaws.com/test.txt?"));
  assert(
    url.endsWith(
      "X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404",
    ),
    url,
  );
});

const local: S3Config = {
  endpoint: "http://host.docker.internal:9000",
  publicEndpoint: "http://127.0.0.1:9000",
  region: "us-east-1",
  accessKeyId: "k",
  secretAccessKey: "s",
  pathStyle: true,
};

Deno.test("path-style URLs are signed for the public host", async () => {
  const url = await presignGet(local, "pub", "avatars/u.webp@x", 60, {
    versionId: "v 1",
  });
  assert(url.startsWith("http://127.0.0.1:9000/pub/avatars/u.webp%40x?"), url);
  assert(url.includes("versionId=v%201"), url);
});

Deno.test("POST policy binds key, type and exact length", async () => {
  const now = new Date("2026-10-02T10:00:00Z");
  const post = await presignPost(
    local,
    "staging",
    "staging/abc",
    "image/webp",
    1234,
    600,
    now,
  );
  assertEquals(post.url, "http://127.0.0.1:9000/staging");
  const policy = JSON.parse(atob(post.fields.policy));
  assertEquals(policy.expiration, "2026-10-02T10:10:00.000Z");
  assertEquals(policy.conditions.slice(0, 4), [
    { bucket: "staging" },
    { key: "staging/abc" },
    { "Content-Type": "image/webp" },
    ["content-length-range", 1234, 1234],
  ]);
  assertEquals(post.fields["x-amz-date"], amzDate(now).amz);
  assertEquals(post.fields["x-amz-signature"].length, 64);
});

Deno.test("uriEncode keeps unreserved characters and optionally slashes", () => {
  assertEquals(uriEncode("a b/c@d~e", true), "a%20b/c%40d~e");
  assertEquals(uriEncode("a/b", false), "a%2Fb");
});

const bytes = (...xs: (number | string)[]) =>
  new Uint8Array(
    xs.flatMap((x) =>
      typeof x === "string" ? [...x].map((c) => c.charCodeAt(0)) : [x]
    ),
  );

Deno.test("content must match the declared type", () => {
  assert(contentMatches("image/jpeg", bytes(0xff, 0xd8, 0xff, 0xe0)));
  assert(!contentMatches("image/jpeg", bytes("<html>")));
  assert(
    contentMatches("image/png", bytes(0x89, "PNG", 0x0d, 0x0a, 0x1a, 0x0a)),
  );
  assert(contentMatches("image/webp", bytes("RIFF", 0, 0, 0, 0, "WEBP")));
  assert(!contentMatches("image/webp", bytes("RIFF", 0, 0, 0, 0, "WAVE")));
  assert(contentMatches("application/pdf", bytes("%PDF-1.7")));
  assert(contentMatches("video/webm", bytes(0x1a, 0x45, 0xdf, 0xa3)));
  assert(contentMatches("video/mp4", bytes(0, 0, 0, 0x18, "ftypisom")));
  assert(!contentMatches("video/mp4", bytes(0, 0, 0, 0x18, "ftypheic")));
  assert(contentMatches("image/heic", bytes(0, 0, 0, 0x18, "ftypheic")));
  assert(contentMatches("text/plain", bytes("hello\n")));
  assert(!contentMatches("text/plain", bytes("he", 0, "llo")));
  assert(!contentMatches("application/x-msdownload", bytes("MZ")));
  assert(!contentMatches("image/jpeg", new Uint8Array()));
});
