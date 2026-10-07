// Minimal S3 client for the storage signer: SigV4 over WebCrypto, no SDK.
//
// Why hand-rolled: the signer needs five operations (presigned POST,
// presigned GET, GET, CopyObject, DELETE) and nothing else. The AWS SDK is a
// large npm graph to pin, `deno check` in CI and review for a function that
// holds an IAM key; SigV4 is ~100 lines, and `s3_test.ts` pins it against
// AWS's own published example signature.
//
// Works against AWS S3 (virtual-hosted URLs) and MinIO locally (path-style:
// `S3_PATH_STYLE=true`). Two endpoints because the signer and the client
// reach S3 by different hosts locally — the edge runtime is in Docker and
// sees `host.docker.internal`, the app sees `127.0.0.1` — and the Host
// header is part of every signature, so a URL handed to a client must be
// signed for the host the client will use.

const enc = new TextEncoder();

export interface S3Config {
  endpoint: string; // signer -> S3
  publicEndpoint: string; // client -> S3
  region: string;
  accessKeyId: string;
  secretAccessKey: string;
  pathStyle: boolean;
}

/**
 * [credentials] names the env prefix of the key pair, so a second role (the
 * face-retention job's, which may destroy versions) never shares the
 * signer's key: `S3_` -> S3_ACCESS_KEY_ID, `S3_RETENTION_` ->
 * S3_RETENTION_ACCESS_KEY_ID.
 */
export function s3ConfigFromEnv(
  env: (k: string) => string | undefined,
  credentials = "S3_",
): S3Config {
  const need = (k: string) => {
    const v = env(k);
    if (!v) throw new Error(`missing ${k}`);
    return v;
  };
  const endpoint = need("S3_ENDPOINT").replace(/\/+$/, "");
  return {
    endpoint,
    publicEndpoint: (env("S3_PUBLIC_ENDPOINT") ?? endpoint).replace(/\/+$/, ""),
    region: need("S3_REGION"),
    accessKeyId: need(`${credentials}ACCESS_KEY_ID`),
    secretAccessKey: need(`${credentials}SECRET_ACCESS_KEY`),
    pathStyle: env("S3_PATH_STYLE") === "true",
  };
}

// ------------------------------------------------------------ primitives

export function hex(bytes: ArrayBuffer | Uint8Array): string {
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export async function sha256Hex(data: Uint8Array | string): Promise<string> {
  const bytes = typeof data === "string" ? enc.encode(data) : data;
  return hex(
    await crypto.subtle.digest("SHA-256", bytes as Uint8Array<ArrayBuffer>),
  );
}

async function hmac(
  key: Uint8Array | string,
  data: string,
): Promise<Uint8Array> {
  const k = await crypto.subtle.importKey(
    "raw",
    (typeof key === "string" ? enc.encode(key) : key) as Uint8Array<
      ArrayBuffer
    >,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(data)));
}

export async function signingKey(
  secret: string,
  date: string,
  region: string,
  service = "s3",
): Promise<Uint8Array> {
  const kDate = await hmac("AWS4" + secret, date);
  const kRegion = await hmac(kDate, region);
  const kService = await hmac(kRegion, service);
  return hmac(kService, "aws4_request");
}

/** RFC 3986 encoding as SigV4 wants it; `/` kept for object keys. */
export function uriEncode(s: string, keepSlash: boolean): string {
  return [...enc.encode(s)].map((b) => {
    const c = String.fromCharCode(b);
    if (/[A-Za-z0-9\-._~]/.test(c) || (keepSlash && c === "/")) return c;
    return "%" + b.toString(16).toUpperCase().padStart(2, "0");
  }).join("");
}

export function amzDate(now: Date): { amz: string; day: string } {
  const amz = now.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  return { amz, day: amz.slice(0, 8) };
}

function objectUrl(
  cfg: S3Config,
  base: string,
  bucket: string,
  key?: string,
): URL {
  const u = new URL(base);
  const path = key === undefined ? "" : "/" + uriEncode(key, true);
  if (cfg.pathStyle) {
    u.pathname = "/" + bucket + path;
  } else {
    u.hostname = `${bucket}.${u.hostname}`;
    u.pathname = path || "/";
  }
  return u;
}

function canonicalQuery(params: [string, string][]): string {
  return params
    .map(([k, v]) => [uriEncode(k, false), uriEncode(v, false)])
    .sort((
      [a, x],
      [b, y],
    ) => (a < b ? -1 : a > b ? 1 : x < y ? -1 : x > y ? 1 : 0))
    .map(([k, v]) => `${k}=${v}`)
    .join("&");
}

// ------------------------------------------------------------ presigned GET

export async function presignGet(
  cfg: S3Config,
  bucket: string,
  key: string,
  expiresIn: number,
  opts: { versionId?: string | null; now?: Date } = {},
): Promise<string> {
  const { amz, day } = amzDate(opts.now ?? new Date());
  const scope = `${day}/${cfg.region}/s3/aws4_request`;
  const url = objectUrl(cfg, cfg.publicEndpoint, bucket, key);
  const params: [string, string][] = [
    ["X-Amz-Algorithm", "AWS4-HMAC-SHA256"],
    ["X-Amz-Credential", `${cfg.accessKeyId}/${scope}`],
    ["X-Amz-Date", amz],
    ["X-Amz-Expires", String(expiresIn)],
    ["X-Amz-SignedHeaders", "host"],
  ];
  if (opts.versionId) params.push(["versionId", opts.versionId]);
  const query = canonicalQuery(params);
  const canonical = [
    "GET",
    url.pathname,
    query,
    `host:${url.host}\n`,
    "host",
    "UNSIGNED-PAYLOAD",
  ].join("\n");
  const toSign = ["AWS4-HMAC-SHA256", amz, scope, await sha256Hex(canonical)]
    .join("\n");
  const sig = hex(
    await hmac(await signingKey(cfg.secretAccessKey, day, cfg.region), toSign),
  );
  return `${url.origin}${url.pathname}?${query}&X-Amz-Signature=${sig}`;
}

// ------------------------------------------------------------ presigned POST

export interface PresignedPost {
  url: string;
  fields: Record<string, string>;
}

/**
 * A browser-form upload bound to one exact key, one exact Content-Type and
 * one exact length. POST policy conditions are enforced by S3; the same
 * conditions on a presigned PUT are not (plan §6), which is why uploads use
 * POST.
 */
export async function presignPost(
  cfg: S3Config,
  bucket: string,
  key: string,
  contentType: string,
  sizeBytes: number,
  expiresIn: number,
  now: Date = new Date(),
): Promise<PresignedPost> {
  const { amz, day } = amzDate(now);
  const credential = `${cfg.accessKeyId}/${day}/${cfg.region}/s3/aws4_request`;
  const policy = {
    expiration: new Date(now.getTime() + expiresIn * 1000).toISOString(),
    conditions: [
      { bucket },
      { key },
      { "Content-Type": contentType },
      ["content-length-range", sizeBytes, sizeBytes],
      { "x-amz-algorithm": "AWS4-HMAC-SHA256" },
      { "x-amz-credential": credential },
      { "x-amz-date": amz },
    ],
  };
  const policyB64 = btoa(JSON.stringify(policy));
  const sig = hex(
    await hmac(
      await signingKey(cfg.secretAccessKey, day, cfg.region),
      policyB64,
    ),
  );
  return {
    url: objectUrl(cfg, cfg.publicEndpoint, bucket).toString().replace(
      /\/$/,
      "",
    ),
    fields: {
      key,
      "Content-Type": contentType,
      "x-amz-algorithm": "AWS4-HMAC-SHA256",
      "x-amz-credential": credential,
      "x-amz-date": amz,
      policy: policyB64,
      "x-amz-signature": sig,
    },
  };
}

// ------------------------------------------------------------ signed requests

export async function s3Request(
  cfg: S3Config,
  method: "GET" | "PUT" | "DELETE" | "HEAD",
  bucket: string,
  key: string,
  opts: {
    query?: [string, string][];
    headers?: Record<string, string>;
    now?: Date;
  } = {},
): Promise<Response> {
  const { amz, day } = amzDate(opts.now ?? new Date());
  const scope = `${day}/${cfg.region}/s3/aws4_request`;
  const url = objectUrl(cfg, cfg.endpoint, bucket, key);
  const query = canonicalQuery(opts.query ?? []);
  const payload = await sha256Hex("");
  const headers: Record<string, string> = {
    ...Object.fromEntries(
      Object.entries(opts.headers ?? {}).map(([k, v]) => [k.toLowerCase(), v]),
    ),
    host: url.host,
    "x-amz-date": amz,
    "x-amz-content-sha256": payload,
  };
  const names = Object.keys(headers).sort();
  const canonical = [
    method,
    url.pathname,
    query,
    names.map((n) => `${n}:${headers[n].trim()}\n`).join(""),
    names.join(";"),
    payload,
  ].join("\n");
  const toSign = ["AWS4-HMAC-SHA256", amz, scope, await sha256Hex(canonical)]
    .join("\n");
  const sig = hex(
    await hmac(await signingKey(cfg.secretAccessKey, day, cfg.region), toSign),
  );
  const { host: _host, ...send } = headers;
  return fetch(`${url.origin}${url.pathname}${query ? "?" + query : ""}`, {
    method,
    headers: {
      ...send,
      authorization:
        `AWS4-HMAC-SHA256 Credential=${cfg.accessKeyId}/${scope}, SignedHeaders=${
          names.join(";")
        }, Signature=${sig}`,
    },
  });
}

/** Server-side copy of one exact source version; returns the new version. */
export async function copyObject(
  cfg: S3Config,
  from: { bucket: string; key: string; versionId?: string | null },
  to: { bucket: string; key: string },
): Promise<{ versionId: string | null }> {
  const source = `/${from.bucket}/${uriEncode(from.key, true)}` +
    (from.versionId ? `?versionId=${encodeURIComponent(from.versionId)}` : "");
  const res = await s3Request(cfg, "PUT", to.bucket, to.key, {
    headers: { "x-amz-copy-source": source },
  });
  const body = await res.text();
  // CopyObject can answer 200 with an <Error> body when it fails mid-copy.
  if (!res.ok || body.includes("<Error>")) {
    throw new Error(`copy failed: ${res.status} ${body.slice(0, 200)}`);
  }
  return { versionId: res.headers.get("x-amz-version-id") };
}
