// Supabase Edge Function: the S3 storage signer (plan §6, stage 2).
//
// The only holder of an S3 credential. It never decides who may do what —
// every authorization decision is a migration-157 RPC run under the CALLER's
// JWT (PostgREST verifies it), so this function cannot be talked into acting
// for a user it was not called by. It only turns an already-authorized
// intent into S3 operations, and checks the bytes.
//
// POST { action: "begin", bucket, path, mime_type, size_bytes, upsert?, idempotency_key }
//   -> { intent_id, expires_at, upload: { url, fields } }
//      The client POSTs the file as multipart/form-data: every field, then
//      `file` last. The policy pins key, Content-Type and exact length.
// POST { action: "finalize", intent_id }
//   -> { asset_id, bucket, path, generation, url }
//      Reads the staged bytes back, checks length + magic bytes, promotes
//      that exact version to the immutable committed key, records it.
// POST { action: "read", refs: [{ bucket, path }] }
//   -> { items: [{ bucket, path, generation, url }] }
//      Unreadable / unknown / not-on-S3 refs are absent: fall back.
// POST { action: "delete", bucket, path } -> { deleted: boolean }
// POST { action: "config" } -> { write_buckets: [...] }
//   Which logical buckets new uploads go to S3 for. Server-controlled
//   (S3_WRITE_BUCKETS) so a cohort can be moved or rolled back without an
//   app release; reads and deletes always try S3 first regardless.
// GET  /storage-signer/media/{bucket}/{path}
//   -> 302 to a presigned GET, for what anon may read (the durable public
//      URL stored in rows; a CDN can replace it without rewriting them).
//
// Secrets: S3_ENDPOINT, S3_PUBLIC_ENDPOINT, S3_REGION, S3_ACCESS_KEY_ID,
//   S3_SECRET_ACCESS_KEY, S3_PATH_STYLE, S3_STAGING_BUCKET,
//   S3_BUCKET_PUBLIC (or S3_BUCKET_AVATARS / _LISTING_IMAGES / _CHAT),
//   S3_BUCKET_DOCUMENTS, S3_BUCKET_FACE, SIGNER_PUBLIC_URL,
//   S3_WRITE_BUCKETS (comma list; unset = none, so deploying is not a cutover)
// Local: sh tool/storage_local.sh prints a ready env file.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  copyObject,
  presignGet,
  presignPost,
  s3ConfigFromEnv,
  s3Request,
  sha256Hex,
} from "../_shared/s3.ts";
import { contentMatches } from "../_shared/sniff.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

const env = (k: string) => Deno.env.get(k);
const s3 = s3ConfigFromEnv(env);
const STAGING = env("S3_STAGING_BUCKET")!;
const PUBLIC_URL = (env("SIGNER_PUBLIC_URL") ?? "").replace(/\/+$/, "");

// Logical bucket -> physical bucket. Public media may share one physical
// bucket (S3_BUCKET_PUBLIC) or get one each (S3_BUCKET_AVATARS etc.; the
// production account was provisioned that way). Sharing is safe because
// committed keys already start with the logical bucket name, so prefixes stay
// separate (plan §4). Private evidence never shares with public media.
const PHYSICAL: Record<string, string | undefined> = {
  "avatars": env("S3_BUCKET_AVATARS") ?? env("S3_BUCKET_PUBLIC"),
  "listing-images": env("S3_BUCKET_LISTING_IMAGES") ?? env("S3_BUCKET_PUBLIC"),
  "chat-attachments": env("S3_BUCKET_CHAT") ?? env("S3_BUCKET_PUBLIC"),
  "documents": env("S3_BUCKET_DOCUMENTS"),
  "face-evidence": env("S3_BUCKET_FACE"),
};

const WRITE_BUCKETS = (env("S3_WRITE_BUCKETS") ?? "").split(",").map((b) =>
  b.trim()
)
  .filter((b) => PHYSICAL[b]);

// How long a read URL lives. Private evidence is short: a leaked link must
// die quickly. Public media is long so a browser can cache it (see media()).
const READ_TTL: Record<string, number> = {
  "documents": 3600,
  "face-evidence": 300,
};
const PUBLIC_TTL = 7 * 24 * 3600; // SigV4's maximum
const UPLOAD_TTL = 15 * 60; // matches storage_upload_intents.expires_at

// RPC refusal hint -> HTTP status. Anything unlisted is a 500.
const STATUS: Record<string, number> = {
  storage_denied: 403,
  storage_not_found: 404,
  storage_exists: 409,
  storage_busy: 409,
  storage_idempotency_mismatch: 409,
  storage_rejected: 409,
  storage_expired: 410,
  storage_too_large: 413,
  storage_mime: 415,
  storage_bucket: 400,
  storage_path: 400,
};

class Refusal extends Error {
  constructor(readonly status: number, readonly hint: string, message: string) {
    super(message);
  }
}

// deno-lint-ignore no-explicit-any
function unwrap<T>(res: { data: T; error: any }): T {
  if (res.error) {
    const hint = res.error.hint as string | undefined;
    // 42501 without our hint is PostgREST refusing EXECUTE: a role problem.
    const status = (hint ? STATUS[hint] : undefined) ??
      (res.error.code === "42501" ? 403 : 500);
    throw new Refusal(
      status,
      hint ?? res.error.code ?? "error",
      res.error.message,
    );
  }
  return res.data;
}

function clients(
  req: Request,
): { user: SupabaseClient; service: SupabaseClient } {
  const url = env("SUPABASE_URL")!;
  const opts = { auth: { autoRefreshToken: false, persistSession: false } };
  const auth = req.headers.get("Authorization");
  return {
    // Anon key + the caller's bearer: RPCs see auth.uid() of the caller, or
    // run as anon when there is none. Never the service key here.
    user: createClient(url, env("SUPABASE_ANON_KEY")!, {
      ...opts,
      global: { headers: auth ? { Authorization: auth } : {} },
    }),
    service: createClient(url, env("SUPABASE_SERVICE_ROLE_KEY")!, opts),
  };
}

function mediaUrl(bucket: string, path: string, generation: number): string {
  // `?g=` changes with every replacement, so an immutable-cached old image is
  // never shown for a new one at the same path.
  const p = path.split("/").map(encodeURIComponent).join("/");
  return `${PUBLIC_URL}/media/${bucket}/${p}?g=${generation}`;
}

function readUrl(
  r: {
    bucket: string;
    path: string;
    s3_bucket: string;
    s3_key: string;
    s3_version: string | null;
    generation: number;
  },
): Promise<string> {
  const ttl = READ_TTL[r.bucket];
  if (ttl === undefined) {
    return Promise.resolve(mediaUrl(r.bucket, r.path, r.generation));
  }
  return presignGet(s3, r.s3_bucket, r.s3_key, ttl, {
    versionId: r.s3_version,
  });
}

// ------------------------------------------------------------ actions

async function begin(user: SupabaseClient, b: Record<string, unknown>) {
  if (!WRITE_BUCKETS.includes(String(b.bucket))) {
    // A client with a stale config must not write somewhere the server has
    // routed back to Supabase (rollback); 421 tells it to re-read config.
    return json(421, {
      error: "Uploads for this bucket go to Supabase",
      hint: "storage_not_routed",
    });
  }
  const intent = unwrap(
    await user.rpc("storage_begin_upload", {
      p_bucket: b.bucket,
      p_path: b.path,
      p_mime_type: b.mime_type,
      p_size_bytes: b.size_bytes,
      p_upsert: b.upsert ?? false,
      p_idempotency_key: b.idempotency_key,
    }),
  ) as {
    intent_id: string;
    staging_key: string;
    mime_type: string;
    size_bytes: number;
    expires_at: string;
  };
  const upload = await presignPost(
    s3,
    STAGING,
    intent.staging_key,
    intent.mime_type,
    intent.size_bytes,
    UPLOAD_TTL,
  );
  return json(200, {
    intent_id: intent.intent_id,
    expires_at: intent.expires_at,
    upload,
  });
}

async function finalize(
  user: SupabaseClient,
  service: SupabaseClient,
  b: Record<string, unknown>,
) {
  const intentId = String(b.intent_id ?? "");
  const claim = unwrap(
    await user.rpc("storage_claim_intent", { p_intent_id: intentId }),
  ) as {
    state: string;
    asset_id?: string;
    bucket: string;
    path: string;
    mime_type: string;
    size_bytes: number;
    staging_key: string;
    committed_key: string;
  };

  if (claim.state === "finalized") {
    // A retry after success: answer as the first call did.
    const a = unwrap(
      await service.from("storage_assets").select("*").eq("id", claim.asset_id!)
        .single(),
    ) as {
      bucket: string;
      path: string;
      s3_bucket: string;
      s3_key: string;
      s3_version: string | null;
      generation: number;
    };
    return json(200, {
      asset_id: claim.asset_id,
      bucket: a.bucket,
      path: a.path,
      generation: a.generation,
      url: await readUrl(a),
    });
  }

  const release = () =>
    service.rpc("storage_release_intent", { p_intent_id: intentId });
  const reject = async (reason: string) => {
    await service.rpc("storage_reject_intent", {
      p_intent_id: intentId,
      p_reason: reason,
    });
    await s3Request(s3, "DELETE", STAGING, claim.staging_key).catch(() => {});
    return json(422, {
      error: "Uploaded file failed verification",
      hint: "storage_invalid",
      reason,
    });
  };

  const target = PHYSICAL[claim.bucket];
  if (!target) {
    await release();
    throw new Refusal(
      500,
      "storage_config",
      `no S3 bucket for ${claim.bucket}`,
    );
  }

  try {
    const res = await s3Request(s3, "GET", STAGING, claim.staging_key);
    if (res.status === 404) {
      await res.body?.cancel();
      // Not uploaded yet (or the POST failed). The ticket is still good.
      await release();
      return json(409, {
        error: "Nothing has been uploaded for this ticket",
        hint: "storage_not_uploaded",
      });
    }
    if (!res.ok) throw new Error(`staging GET ${res.status}`);
    const version = res.headers.get("x-amz-version-id");
    const bytes = new Uint8Array(await res.arrayBuffer());

    // The POST policy already pins the length; checking again costs nothing
    // and does not depend on S3 honouring it.
    if (bytes.length !== claim.size_bytes) {
      return await reject(`size ${bytes.length} != ${claim.size_bytes}`);
    }
    if (!contentMatches(claim.mime_type, bytes)) {
      return await reject(`content is not ${claim.mime_type}`);
    }
    const sha256 = await sha256Hex(bytes);

    // Copy the version we just verified, not "whatever is at the key now":
    // a second POST with the same ticket cannot swap bytes in after the check.
    const copied = await copyObject(
      s3,
      { bucket: STAGING, key: claim.staging_key, versionId: version },
      { bucket: target, key: claim.committed_key },
    );
    const asset = unwrap(
      await service.rpc("storage_commit_upload", {
        p_intent_id: intentId,
        p_size_bytes: bytes.length,
        p_sha256: sha256,
        p_mime_type: claim.mime_type,
        p_s3_bucket: target,
        p_s3_key: claim.committed_key,
        p_s3_version: copied.versionId,
      }),
    ) as { asset_id: string; bucket: string; path: string; generation: number };

    // Best effort: the staging lifecycle rule removes anything left behind.
    await s3Request(s3, "DELETE", STAGING, claim.staging_key).then((r) =>
      r.body?.cancel()
    ).catch(() => {});
    const url = await readUrl({
      ...asset,
      s3_bucket: target,
      s3_key: claim.committed_key,
      s3_version: copied.versionId,
    });
    return json(200, { ...asset, url });
  } catch (e) {
    // Transient (S3 or DB): hand the claim back so a retry need not wait
    // out the two-minute abandoned-claim window.
    await release();
    throw e;
  }
}

async function read(user: SupabaseClient, b: Record<string, unknown>) {
  const rows = unwrap(
    await user.rpc("storage_resolve_reads", { p_refs: b.refs ?? [] }),
  ) as {
    bucket: string;
    path: string;
    s3_bucket: string;
    s3_key: string;
    s3_version: string | null;
    generation: number;
  }[];
  const items = await Promise.all(
    rows.map(async (r) => ({
      bucket: r.bucket,
      path: r.path,
      generation: r.generation,
      url: await readUrl(r),
    })),
  );
  return json(200, { items });
}

async function remove(
  user: SupabaseClient,
  service: SupabaseClient,
  b: Record<string, unknown>,
) {
  const loc = unwrap(
    await user.rpc("storage_begin_delete", {
      p_bucket: b.bucket,
      p_path: b.path,
    }),
  ) as
    | { asset_id: string; s3_bucket: string | null; s3_key: string | null }
    | null;
  if (!loc) return json(200, { deleted: false });
  if (loc.s3_bucket && loc.s3_key) {
    // Unversioned DELETE: writes a delete marker. Prior versions remain for
    // the retention/recovery window; the lifecycle rule expires them.
    const res = await s3Request(s3, "DELETE", loc.s3_bucket, loc.s3_key);
    await res.body?.cancel();
    if (!res.ok && res.status !== 404) {
      throw new Error(`S3 DELETE ${res.status}`);
    }
  }
  unwrap(
    await service.rpc("storage_finish_delete", { p_asset_id: loc.asset_id }),
  );
  return json(200, { deleted: true });
}

async function media(user: SupabaseClient, rest: string) {
  const slash = rest.indexOf("/");
  if (slash <= 0) return json(404, { error: "Not found" });
  const bucket = rest.slice(0, slash);
  let path: string;
  try {
    path = rest.slice(slash + 1).split("/").map(decodeURIComponent).join("/");
  } catch {
    return json(400, { error: "Bad path" });
  }
  // Same rule as everything else: what anon may read, through the RPC.
  const rows = unwrap(
    await user.rpc("storage_resolve_reads", { p_refs: [{ bucket, path }] }),
  ) as {
    bucket: string;
    s3_bucket: string;
    s3_key: string;
    s3_version: string | null;
  }[];
  const r = rows[0];
  // Private buckets are never served here, even to a signed-in caller: a
  // redirect URL ends up in logs and caches.
  if (!r || READ_TTL[r.bucket] !== undefined) {
    return json(404, { error: "Not found" });
  }
  // Sign as of the start of the UTC day so the URL is stable all day and the
  // browser's HTTP cache works; it still has 6+ days of validity left.
  const day = new Date();
  day.setUTCHours(0, 0, 0, 0);
  const location = await presignGet(s3, r.s3_bucket, r.s3_key, PUBLIC_TTL, {
    versionId: r.s3_version,
    now: day,
  });
  return new Response(null, {
    status: 302,
    headers: {
      ...cors,
      Location: location,
      "Cache-Control": "public, max-age=3600",
    },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { user, service } = clients(req);
    const url = new URL(req.url);
    const at = url.pathname.indexOf("/media/");
    if (req.method === "GET" && at >= 0) {
      return await media(user, url.pathname.slice(at + "/media/".length));
    }
    if (req.method !== "POST") {
      return json(405, { error: "Method not allowed" });
    }

    const body = await req.json().catch(() => ({})) as Record<string, unknown>;
    switch (body.action) {
      case "begin":
        return await begin(user, body);
      case "finalize":
        return await finalize(user, service, body);
      case "read":
        return await read(user, body);
      case "delete":
        return await remove(user, service, body);
      case "config":
        return json(200, { write_buckets: WRITE_BUCKETS });
      default:
        return json(400, { error: "Unknown action" });
    }
  } catch (e) {
    if (e instanceof Refusal) {
      return json(e.status, { error: e.message, hint: e.hint });
    }
    console.error("storage-signer:", e);
    return json(500, { error: "Storage error" });
  }
});
