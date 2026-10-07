#!/usr/bin/env python3
"""Register live Supabase Storage objects in storage_assets, pointing at their
S3 copies (plan §18 step 9, stage 3).

    python3 tool/register_s3_backfill.py                  # rehearse on local DB, rolled back
    python3 tool/register_s3_backfill.py --target live    # rehearse on live, rolled back
    python3 tool/register_s3_backfill.py --target live --apply

Re-runnable, and the same run is the later catch-up (step 7): every live
`storage.objects` row in the five app buckets is checked against the target
registry, and only rows that are new or CHANGED since they were registered are
(re)copied and (re)registered. "Changed" matters because existing app builds
keep writing to Supabase after this runs, and some paths are overwritten in
place (`avatars/{uid}.jpg`, upserted documents): a registry row left pointing
at the older S3 copy would make S3-reading clients serve the old file.

Why each step is shaped the way it is:

1. The object list comes from LIVE `storage.objects` (read-only), whatever the
   target, so a local rehearsal exercises exactly the rows live will get.
2. Each object is copied at `{bucket}/{path}@{storage.objects.id}`. An S3 copy
   already there is reused only if it was written after the object last
   changed; otherwise it is re-copied from Supabase (the bucket is versioned,
   so the overwritten copy survives as an older version).
3. Every S3 copy is re-read and hashed before it is registered: the registry's
   sha256 is a claim the evidence verifiers rely on, so it is measured here,
   never taken from the copy's metadata alone.
4. The owner is the Supabase object's owner, never this script (plan §3);
   `business_created_at` is the object's own creation time.
5. Before anything is written, the affected registry rows are snapshotted into
   a rollback SQL file. Without --apply the whole write runs in a transaction
   that is rolled back, so the rehearsal proves the SQL against real
   constraints and changes nothing.

Bytes stream through memory, never disk. Uses the AWS key in the gitignored
supabase/functions/.env.local and the service_role key fetched from the CLI.
URL rewrites (plan step 5) are deliberately NOT here: they need a snapshot
taken at the moment they run.
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.parse

REF = "bojkmonskqlhuakxhzcb"
LIVE = f"https://{REF}.supabase.co"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
BUCKETS = ["avatars", "listing-images", "chat-attachments", "documents", "face-evidence"]
ENV_PHYSICAL = {
    "avatars": "S3_BUCKET_AVATARS",
    "listing-images": "S3_BUCKET_LISTING_IMAGES",
    "chat-attachments": "S3_BUCKET_CHAT",
    "documents": "S3_BUCKET_DOCUMENTS",
    "face-evidence": "S3_BUCKET_FACE",
}


def load_env():
    """AWS credentials and the physical bucket names, as the signer sees them."""
    vals = {}
    for line in open(os.path.join(ROOT, "supabase", "functions", ".env.local")):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            vals[k] = v  # later lines win, like the signer's env file
    aws = dict(os.environ, AWS_ACCESS_KEY_ID=vals["S3_ACCESS_KEY_ID"],
               AWS_SECRET_ACCESS_KEY=vals["S3_SECRET_ACCESS_KEY"],
               AWS_DEFAULT_REGION=vals.get("S3_REGION", "ap-south-1"))
    # Same fallback as the signer: a per-bucket name, else the shared one.
    physical = {b: vals.get(ENV_PHYSICAL[b]) or vals.get("S3_BUCKET_PUBLIC") for b in BUCKETS}
    missing = [b for b, p in physical.items() if not p]
    if missing:
        sys.exit(f"no physical bucket for {missing} in .env.local")
    return aws, physical


def query(target, sql):
    """Run SQL on the target; returns the last statement's rows."""
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
        f.write(sql)
    try:
        flag = ["--linked"] if target == "live" else ["--local"]
        r = subprocess.run(["supabase", "db", "query", *flag, "-o", "json", "-f", f.name],
                           capture_output=True, text=True, cwd=ROOT)
    finally:
        os.unlink(f.name)
    if r.returncode:
        sys.exit(f"{target} query failed:\n{r.stderr or r.stdout}")
    out = r.stdout
    # Take the first JSON object that carries `rows`: on a terminal the CLI can
    # print other JSON or text around it (its "new version" notice), which
    # json.loads rejects as extra data.
    dec, i = json.JSONDecoder(), out.find("{")
    while i != -1:
        try:
            doc, end = dec.raw_decode(out, i)
        except ValueError:
            i = out.find("{", i + 1)
            continue
        if isinstance(doc, dict) and "rows" in doc:
            return doc["rows"]
        i = out.find("{", end)
    if "error" in out.lower() or "{" in out:
        sys.exit(f"{target} query: no rows in CLI output:\n{out[-1500:]}")
    return []


def lit(value):
    """A SQL literal for a JSON document: dollar-quoted, so no escaping."""
    return "$j$" + json.dumps(value) + "$j$::jsonb"


def ts(value):
    """Postgres text ('2026-09-04 08:07:32.87947+00') or S3 ISO time, as UTC.

    By hand, because this Python's fromisoformat wants six fraction digits
    and a `+00:00` offset, and Postgres gives neither.
    """
    if not value:
        return None
    m = re.match(r"(\d{4}-\d\d-\d\d)[T ](\d\d:\d\d:\d\d)(?:\.(\d+))?(Z|[+-]\d\d(?::?\d\d)?)?$", value)
    if not m:
        sys.exit(f"unparseable timestamp {value!r}")
    date, time, frac, tz = m.groups()
    tz = "+00:00" if tz in (None, "Z") else tz[:3] + ":" + (tz[3:].lstrip(":") or "00")
    return datetime.datetime.fromisoformat(f"{date}T{time}.{(frac or '0')[:6].ljust(6, '0')}{tz}")


def aws(env, *args, data=None):
    r = subprocess.run(["aws", *args], input=data, env=env, capture_output=True)
    return r.returncode, r.stdout, r.stderr.decode()


def head(env, bucket, key):
    code, out, _ = aws(env, "s3api", "head-object", "--bucket", bucket, "--key", key, "--output", "json")
    return json.loads(out) if code == 0 else None


def service_key():
    keys = json.loads(subprocess.check_output(
        ["supabase", "projects", "api-keys", "--project-ref", REF, "-o", "json"],
        stderr=subprocess.DEVNULL))
    return next(k["api_key"] for k in keys if k["name"] == "service_role")


def download_supabase(svc, bucket, path):
    url = f"{LIVE}/storage/v1/object/authenticated/{bucket}/" + urllib.parse.quote(path)
    # curl, not urllib: the system Python's urllib has hung on this endpoint.
    r = subprocess.run(["curl", "-sf", "-m", "120", url, "-H", f"Authorization: Bearer {svc}",
                        "-H", f"apikey: {svc}"], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", choices=["local", "live"], default="local")
    ap.add_argument("--apply", action="store_true", help="commit (default: rehearse and roll back)")
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "s3_backfill"))
    args = ap.parse_args()
    env, physical = load_env()
    os.makedirs(args.out, exist_ok=True)

    # ---- 1. What live holds, and what the target registry already says ------
    objects = query("live", f"""
select id::text, bucket_id, name, metadata->>'mimetype' mime, (metadata->>'size')::bigint size,
       owner_id, created_at, updated_at
  from storage.objects where bucket_id = any(array{BUCKETS!r}) order by bucket_id, name;""")
    registry = {(r["bucket"], r["path"]): r for r in query(args.target, """
select * from public.storage_assets;""")}
    print(f"live objects: {len(objects)}; {args.target} registry rows: {len(registry)}")

    # ---- 2. Decide, copy where needed, verify every S3 copy ----------------
    svc = None
    rows, counts = [], {"current": 0, "reused": 0, "copied": 0, "failed": 0}
    for o in objects:
        bucket, path = o["bucket_id"], o["name"]
        dest = physical[bucket]
        changed_at = ts(o["updated_at"]) or ts(o["created_at"])
        reg = registry.get((bucket, path))
        if (reg and reg["state"] == "active" and reg["s3_bucket"] == dest
                and ts(reg["updated_at"]) >= changed_at):
            counts["current"] += 1
            continue
        if not o["owner_id"]:
            print(f"  FAIL {bucket}/{path}: no owner on the Supabase object")
            counts["failed"] += 1
            continue
        key = f"{bucket}/{path}@{o['id']}"
        h = head(env, dest, key)
        fresh = h and ts(h["LastModified"]) >= changed_at and h["ContentLength"] == o["size"]
        if not fresh:
            svc = svc or service_key()
            body = download_supabase(svc, bucket, path)
            if body is None or len(body) != o["size"]:
                print(f"  FAIL {bucket}/{path}: Supabase download")
                counts["failed"] += 1
                continue
            sha = hashlib.sha256(body).hexdigest()
            code, _, err = aws(env, "s3", "cp", "-", f"s3://{dest}/{key}", "--only-show-errors",
                               "--content-type", o["mime"] or "application/octet-stream",
                               "--metadata", f"sha256={sha},source=supabase,object-id={o['id']}",
                               data=body)
            if code:
                print(f"  FAIL {bucket}/{path}: S3 put: {err[-200:]}")
                counts["failed"] += 1
                continue
            h = head(env, dest, key)
        # Re-read the stored bytes: the registered hash is measured, not trusted.
        code, body, _ = aws(env, "s3", "cp", f"s3://{dest}/{key}", "-")
        sha = hashlib.sha256(body).hexdigest() if code == 0 else None
        claimed = (h or {}).get("Metadata", {}).get("sha256")
        if sha is None or len(body) != o["size"] or (claimed and claimed != sha):
            print(f"  FAIL {bucket}/{path}: S3 re-read mismatch")
            counts["failed"] += 1
            continue
        counts["reused" if fresh else "copied"] += 1
        # "null" is what S3 reports for an object written before versioning:
        # store no version, so reads take the current one.
        version = h.get("VersionId")
        rows.append({"bucket": bucket, "path": path, "owner_id": o["owner_id"],
                     "mime_type": o["mime"] or "application/octet-stream", "size_bytes": o["size"],
                     "sha256": sha, "business_created_at": o["created_at"],
                     "s3_bucket": dest, "s3_key": key,
                     "s3_version": None if version in (None, "null") else version})
    print("  " + ", ".join(f"{k}={v}" for k, v in counts.items()))
    if counts["failed"]:
        sys.exit("refusing to register with failures; fix and re-run")
    if not rows:
        print("nothing to register")
        return

    # ---- 3. Rollback file first, then the write ----------------------------
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    keys = [{"bucket": r["bucket"], "path": r["path"]} for r in rows]
    before = [registry[(r["bucket"], r["path"])] for r in rows if (r["bucket"], r["path"]) in registry]
    rollback = os.path.join(args.out, f"rollback_{args.target}_{stamp}.sql")
    with open(rollback, "w") as f:
        f.write(f"""-- Undo register_s3_backfill.py {args.target} {stamp}: remove the
-- {len(rows)} rows it wrote, then restore the {len(before)} it replaced.
begin;
delete from public.storage_assets a
 using jsonb_to_recordset({lit(keys)}) as k(bucket text, path text)
 where a.bucket = k.bucket and a.path = k.path;
insert into public.storage_assets
select * from jsonb_populate_recordset(null::public.storage_assets, {lit(before)});
commit;
""")
    with open(os.path.join(args.out, f"rows_{args.target}_{stamp}.json"), "w") as f:
        json.dump(rows, f, indent=1)

    # supabase_path = path: the Supabase copy stays, verified, for rollback (§5).
    # A changed object keeps its row id and bumps generation, so old media
    # URLs (?g=) stop being served from caches.
    write = f"""
insert into public.storage_assets (bucket, path, owner_id, mime_type, size_bytes, sha256,
       business_created_at, supabase_path, s3_bucket, s3_key, s3_version)
select r.bucket, r.path, r.owner_id, r.mime_type, r.size_bytes, r.sha256,
       r.business_created_at, r.path, r.s3_bucket, r.s3_key, r.s3_version
  from jsonb_to_recordset({lit(rows)}) as r(bucket text, path text, owner_id uuid, mime_type text,
       size_bytes bigint, sha256 text, business_created_at timestamptz, s3_bucket text,
       s3_key text, s3_version text)
on conflict (bucket, path) do update set
  owner_id = excluded.owner_id, mime_type = excluded.mime_type, size_bytes = excluded.size_bytes,
  generation = storage_assets.generation
             + (storage_assets.sha256 is distinct from excluded.sha256)::int,
  sha256 = excluded.sha256, state = 'active', supabase_path = excluded.supabase_path,
  s3_bucket = excluded.s3_bucket, s3_key = excluded.s3_key, s3_version = excluded.s3_version,
  updated_at = now();
"""
    summary = ("select string_agg(format('%s=%s rows/%s B', bucket, n, bytes), ', ' order by bucket) "
               "from (select bucket, count(*) n, sum(size_bytes) bytes from public.storage_assets "
               "where state = 'active' and s3_key is not null group by bucket) s")
    if args.apply:
        result = query(args.target, f"begin;{write}{summary};commit;")
        # The CLI returns the last statement's rows; re-read to report.
        result = query(args.target, summary + ";")
    else:
        # The rehearsal ends by raising, so it cannot commit whatever happens;
        # the message carries what the registry would have held.
        sql = (f"do $do$ declare v_sum text; begin {write} {summary} into v_sum; "
               f"raise exception 'REHEARSAL-OK %', v_sum; end $do$;")
        with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
            f.write(sql)
        r = subprocess.run(["supabase", "db", "query",
                            "--linked" if args.target == "live" else "--local", "-f", f.name],
                           capture_output=True, text=True, cwd=ROOT)
        os.unlink(f.name)
        msg = r.stdout + r.stderr
        if "REHEARSAL-OK" not in msg:
            sys.exit(f"rehearsal failed:\n{msg[-2000:]}")
        result = [msg[msg.index("REHEARSAL-OK"):].splitlines()[0]]
    print(f"{'APPLIED' if args.apply else 'rehearsed (rolled back)'} on {args.target}: "
          f"{len(rows)} rows; rollback file {os.path.relpath(rollback, ROOT)}")
    for r in result:
        print(f"  {r}")


if __name__ == "__main__":
    main()
