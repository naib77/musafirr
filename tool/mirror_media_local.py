#!/usr/bin/env python3
"""Mirror live PUBLIC listings and their media into the local stack, with
every stored image moved onto local MinIO behind the storage signer.

    sh tool/storage_local.sh            # MinIO up
    python3 tool/mirror_media_local.py  # idempotent; re-run any time

What it does, and why each step is shaped the way it is:

1. Reads live through the ANON key only, so it copies exactly what a signed-out
   visitor already sees: published listings, the one hotel property, amenity
   links, and the hosts' public profiles. No phone numbers, documents, NID or
   face evidence ever leave live (those buckets are private; they are not
   touched). The local database stays free of private user data.
2. Gives each mirrored host a local auth user (`mirror-<id>@mirror.local`,
   password `qa-password`) under the SAME uuid, because listings.owner_id and
   the storage owner rules key on it.
3. Copies every Supabase-stored image (live public URLs, plus whatever the
   local Supabase Storage holds) into MinIO at the key the signer itself
   would commit (`{bucket}/{path}@{uuid}`), and registers it in
   storage_assets with its real owner, sha256, size and MinIO version — the
   same row a finalize writes, so reads, deletes and replaces behave as if it
   had been uploaded through the signer.
4. Rewrites every row that named an old URL to the signer's media URL.

Unsplash and other non-Supabase URLs are left alone: they were never ours.
"""
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
import uuid

LIVE = "https://bojkmonskqlhuakxhzcb.supabase.co"
LOCAL_API = os.environ.get("LOCAL_API", "http://127.0.0.1:54321")
DB = os.environ.get("LOCAL_DB_URL", "postgresql://postgres:postgres@127.0.0.1:54322/postgres")
SIGNER = os.environ.get("SIGNER_PUBLIC_URL", "http://127.0.0.1:8000/storage-signer")
MINIO = "musafir_minio"
MC_HOST = "http://minioadmin:minioadmin@localhost:9000"
# Logical bucket -> physical MinIO bucket; mirrors the signer's BUCKETS map.
PHYSICAL = {
    "avatars": "musafir-public",
    "listing-images": "musafir-public",
    "chat-attachments": "musafir-public",
    "documents": "musafir-documents",
    "face-evidence": "musafir-face",
}
HERE = os.path.dirname(os.path.abspath(__file__))


def live_anon_key():
    # The compiled-in default: a public client credential, not a secret.
    src = open(os.path.join(HERE, "..", "lib", "config", "supabase_config.dart")).read()
    start = src.index("'eyJ", src.index("SUPABASE_ANON_KEY")) + 1
    return src[start:src.index("'", start)]


def local_service_key():
    # The standard local demo key, read from the running stack.
    out = subprocess.run(["supabase", "status", "-o", "json"], capture_output=True, text=True).stdout
    return json.loads(out[out.index("{"):])["SERVICE_ROLE_KEY"]


def get(url, key=None):
    req = urllib.request.Request(url)
    if key:
        req.add_header("apikey", key)
        req.add_header("Authorization", f"Bearer {key}")
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read(), r.headers.get("Content-Type", "application/octet-stream")


def rest(table, key, query="select=*"):
    body, _ = get(f"{LIVE}/rest/v1/{table}?{query}", key)
    return json.loads(body)


def psql(sql):
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
        f.write(sql)
    try:
        r = subprocess.run(["psql", DB, "-v", "ON_ERROR_STOP=1", "-qAt", "-f", f.name],
                           capture_output=True, text=True)
    finally:
        os.unlink(f.name)
    if r.returncode:
        sys.exit(r.stderr)
    return r.stdout


def lit(value):
    """A SQL literal for a JSON document: dollar-quoted, so no escaping."""
    return "$j$" + json.dumps(value) + "$j$::jsonb"


def mc(*args, stdin=None):
    r = subprocess.run(["docker", "exec", "-i", "-e", f"MC_HOST_m={MC_HOST}", MINIO, "mc", *args],
                       input=stdin, capture_output=True)
    if r.returncode:
        sys.exit(r.stderr.decode() or r.stdout.decode())
    return r.stdout


def put(body, ctype, s3_bucket, s3_key):
    """Store bytes with a real Content-Type (MinIO serves it on every GET).

    Not `mc pipe --attr`: that drops Content-Type once the stream goes
    multipart, and the object then serves as application/octet-stream. The
    image has no shell, so the file goes in with `docker cp` and `mc cp`.
    """
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(body)
    os.chmod(f.name, 0o644)  # the container's mc runs as nonroot
    inside = f"/tmp/mirror-{uuid.uuid4()}"
    try:
        subprocess.run(["docker", "cp", f.name, f"{MINIO}:{inside}"], check=True, capture_output=True)
        mc("cp", "--quiet", "--attr", f"Content-Type={ctype}", inside, f"m/{s3_bucket}/{s3_key}")
    finally:
        os.unlink(f.name)
        subprocess.run(["docker", "exec", MINIO, "rm", "-f", inside], capture_output=True)


def parse_storage_url(url):
    """(bucket, path) for a Supabase public/authenticated object URL, else None."""
    marker = "/storage/v1/object/"
    if not url or marker not in url:
        return None
    rest_ = url.split(marker, 1)[1].split("?", 1)[0]
    parts = rest_.split("/", 2)
    if len(parts) < 3 or parts[0] not in ("public", "authenticated", "sign"):
        return None
    return parts[1], urllib.parse.unquote(parts[2])


def media_url(bucket, path, generation):
    quoted = "/".join(urllib.parse.quote(p, safe="") for p in path.split("/"))
    return f"{SIGNER}/media/{bucket}/{quoted}?g={generation}"


def main():
    anon = live_anon_key()

    # ---- 1. Live public rows ------------------------------------------------
    listings = rest("listings", anon)
    properties = rest("properties", anon)
    links = rest("listing_facilities", anon)
    owner_ids = sorted({l["owner_id"] for l in listings} | {p["owner_id"] for p in properties})
    profiles = rest("public_profiles", anon, "select=*&id=in.(" + ",".join(owner_ids) + ")")
    print(f"live: {len(listings)} listings, {len(properties)} properties, "
          f"{len(profiles)} host profiles, {len(links)} amenity links")

    psql(f"""
begin;
-- Hosts: a local auth user under the live uuid (the profile row is made by
-- the auth trigger), then the public profile fields on top.
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
  email_change_token_new, email_change)
select '00000000-0000-0000-0000-000000000000', p.id, 'authenticated', 'authenticated',
       'mirror-' || p.id || '@mirror.local', extensions.crypt('qa-password', extensions.gen_salt('bf')),
       now(), '{{"provider":"email","providers":["email"]}}'::jsonb,
       jsonb_build_object('full_name', p.full_name, 'role', 'owner'), now(), now(), '', '', '', ''
  from jsonb_to_recordset({lit(profiles)}) as p(id uuid, full_name text)
on conflict (id) do nothing;

insert into public.profiles (id, full_name, role)
select p.id, p.full_name, 'owner'
  from jsonb_to_recordset({lit(profiles)}) as p(id uuid, full_name text)
on conflict (id) do nothing;

update public.profiles t set full_name = p.full_name, bio = p.bio, avatar_url = p.avatar_url
  from jsonb_to_recordset({lit(profiles)}) as p(id uuid, full_name text, bio text, avatar_url text)
 where t.id = p.id;

insert into public.properties
select * from jsonb_populate_recordset(null::public.properties, {lit(properties)})
on conflict (id) do update set image_urls = excluded.image_urls;

-- Columns anon cannot see on live take their local defaults.
insert into public.listings
select * from jsonb_populate_recordset(null::public.listings, {lit(listings)})
on conflict (id) do update set image_urls = excluded.image_urls,
                               host_avatar_url = excluded.host_avatar_url;

insert into public.listing_facilities (listing_id, facility_id)
select l.listing_id, l.facility_id
  from jsonb_to_recordset({lit(links)}) as l(listing_id uuid, facility_id uuid)
  join public.facilities f on f.id = l.facility_id
  -- Links to listings anon cannot see (hidden, inactive) come back too.
  join public.listings x on x.id = l.listing_id
on conflict do nothing;
commit;
""")

    # ---- 2. Every Supabase-stored object the local rows point at ------------
    # Each URL with the owner of the row that names it: upload paths do not
    # reliably carry one (`listing_<ts>/…` was written before the listing had
    # an id, `property_<id>/…` names a property).
    referenced = json.loads(psql("""
select coalesce(json_agg(json_build_object('url', u, 'owner', o)), '[]') from (
  select distinct on (u) u, o from (
    select unnest(image_urls) u, owner_id o from public.listings
    union all select unnest(image_urls), owner_id from public.properties
    union all select host_avatar_url, owner_id from public.listings
    union all select avatar_url, id from public.profiles
    union all select listing_image_url, null::uuid from public.bookings
    union all select reviewer_avatar_url, null::uuid from public.reviews
  ) s where u like '%/storage/v1/object/%' order by u, o nulls last
) d;
"""))
    # Local Supabase Storage objects too (seed uploads, private ones included —
    # they are local test data, never live user data).
    local_objects = json.loads(psql("""
select coalesce(json_agg(json_build_object('bucket', bucket_id, 'path', name, 'owner', owner)), '[]')
  from storage.objects where bucket_id = any(array['avatars','listing-images','chat-attachments','documents','face-evidence']);
"""))

    owners = {l["id"]: l["owner_id"] for l in listings}
    owners.update({p["id"]: p["owner_id"] for p in properties})
    sources = []  # (old_url or None, bucket, path, fetch_url, fetch_key, owner)
    for ref in referenced:
        url = ref["url"]
        parsed = parse_storage_url(url)
        if not parsed:
            continue
        bucket, path = parsed
        if bucket not in PHYSICAL:
            continue
        first = path.split("/", 1)[0]
        stem = path.rsplit("/", 1)[-1].split(".", 1)[0]
        owner = ref["owner"] or owners.get(first) or (stem if bucket == "avatars" else None)
        key = anon if url.startswith(LIVE) else local_service_key()
        sources.append((url, bucket, path, url, key, owner))
    if local_objects:
        svc = local_service_key()
        for o in local_objects:
            quoted = urllib.parse.quote(o["path"])
            sources.append((None, o["bucket"], o["path"],
                            f"{LOCAL_API}/storage/v1/object/{o['bucket']}/{quoted}", svc, o["owner"]))

    already = {(r["bucket"], r["path"]) for r in json.loads(psql(
        "select coalesce(json_agg(json_build_object('bucket', bucket, 'path', path)), '[]') "
        "from public.storage_assets where state = 'active' and s3_key is not null;"))}

    assets, rewrites, seen = [], [], set()
    for old_url, bucket, path, fetch_url, key, owner in sources:
        if (bucket, path) in seen:
            continue
        seen.add((bucket, path))
        if (bucket, path) in already:
            gen = int(psql(f"select generation from public.storage_assets where bucket = '{bucket}' "
                           f"and path = $p${path}$p$;").strip())
            if old_url:
                rewrites.append({"old": old_url, "new": media_url(bucket, path, gen)})
            continue
        if not owner:
            print(f"  skip {bucket}/{path}: owner unknown")
            continue
        try:
            body, ctype = get(fetch_url, key)
        except Exception as e:  # a dead link on live is not ours to fix here
            print(f"  skip {bucket}/{path}: {e}")
            continue
        ctype = ctype.split(";")[0].strip()
        s3_bucket = PHYSICAL[bucket]
        s3_key = f"{bucket}/{path}@{uuid.uuid4()}"
        put(body, ctype, s3_bucket, s3_key)
        version = json.loads(mc("stat", "--json", f"m/{s3_bucket}/{s3_key}")).get("versionID") or None
        assets.append({"bucket": bucket, "path": path, "owner_id": owner, "mime_type": ctype,
                       "size_bytes": len(body), "sha256": hashlib.sha256(body).hexdigest(),
                       "s3_bucket": s3_bucket, "s3_key": s3_key, "s3_version": version})
        if old_url:
            rewrites.append({"old": old_url, "new": media_url(bucket, path, 1)})
        print(f"  copied {bucket}/{path} ({len(body)} B, {ctype})")

    # ---- 3. Register, then point every row at the signer --------------------
    psql(f"""
begin;
insert into public.storage_assets (bucket, path, owner_id, mime_type, size_bytes, sha256,
       supabase_path, s3_bucket, s3_key, s3_version)
select a.bucket, a.path, a.owner_id, a.mime_type, a.size_bytes, a.sha256,
       a.path, a.s3_bucket, a.s3_key, a.s3_version
  from jsonb_to_recordset({lit(assets)}) as a(bucket text, path text, owner_id uuid,
       mime_type text, size_bytes bigint, sha256 text, s3_bucket text, s3_key text, s3_version text)
on conflict (bucket, path) do nothing;

create temp table rw on commit drop as
select * from jsonb_to_recordset({lit(rewrites)}) as r(old text, new text);

update public.listings l set image_urls = array(
  select coalesce(rw.new, u) from unnest(l.image_urls) with ordinality x(u, i)
    left join rw on rw.old = x.u order by x.i)
 where exists (select 1 from unnest(l.image_urls) u join rw on rw.old = u);
update public.properties p set image_urls = array(
  select coalesce(rw.new, u) from unnest(p.image_urls) with ordinality x(u, i)
    left join rw on rw.old = x.u order by x.i)
 where exists (select 1 from unnest(p.image_urls) u join rw on rw.old = u);
update public.listings t set host_avatar_url = rw.new from rw where t.host_avatar_url = rw.old;
update public.profiles t set avatar_url = rw.new from rw where t.avatar_url = rw.old;
update public.bookings t set listing_image_url = rw.new from rw where t.listing_image_url = rw.old;
update public.reviews t set reviewer_avatar_url = rw.new from rw where t.reviewer_avatar_url = rw.old;
commit;
""")
    left = psql("""
select count(*) from (
  select unnest(image_urls) u from public.listings
  union all select unnest(image_urls) from public.properties
  union all select avatar_url from public.profiles
) s where u like '%/storage/v1/object/%';
""").strip()
    print(f"registered {len(assets)} new objects, rewrote {len(rewrites)} URLs; "
          f"rows still naming Supabase Storage: {left}")


if __name__ == "__main__":
    main()
