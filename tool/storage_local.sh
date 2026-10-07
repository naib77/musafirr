#!/bin/sh
# Local S3 for the storage signer (plan §4, stage 2): MinIO in Docker, set up
# the way the AWS resources will be, so the signer is exercised against the
# same rules it will meet in production.
#
#   sh tool/storage_local.sh          # idempotent; prints the signer env
#
# What it builds, and the AWS equivalent each line stands in for:
#   - four versioned buckets: staging, public media, documents, face evidence
#     (separate physical buckets so retention/access rules cannot mix; §4)
#   - staging: objects expire after 1 day (abandoned uploads; §6)
#   - noncurrent versions expire after 30 days (recovery window after a
#     replace/delete; the retention job owns anything longer)
#   - no anonymous access anywhere (Block Public Access): every read is a
#     presigned GET
#   - a `musafir-signer` user whose policy allows only object get/put/delete
#     on those buckets, no list, no bucket admin (the signer's IAM role; §8)
#   - a `musafir-retention` user that may destroy face-evidence versions and
#     nothing else (the retention job's role; the signer cannot)
#
# Why the Chainguard image: Docker Hub's minio/minio and quay.io refuse
# anonymous pulls here, and Homebrew's minio segfaults on macOS 26.
set -eu

IMAGE=cgr.dev/chainguard/minio:latest
NAME=musafir_minio
ROOT_USER=minioadmin
ROOT_PASS=minioadmin
SIGNER_USER=musafir-signer
SIGNER_PASS=musafir-signer-local-secret
RETENTION_USER=musafir-retention
RETENTION_PASS=musafir-retention-local-secret
BUCKETS="musafir-staging musafir-public musafir-documents musafir-face"

if ! docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
  if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
    docker start "$NAME" >/dev/null
  else
    docker run -d --name "$NAME" --restart unless-stopped \
      -p 9000:9000 -p 9001:9001 \
      -e MINIO_ROOT_USER=$ROOT_USER -e MINIO_ROOT_PASSWORD=$ROOT_PASS \
      -v musafir_minio_data:/data \
      "$IMAGE" server /data --console-address :9001 >/dev/null
  fi
fi

i=0
until curl -sf http://127.0.0.1:9000/minio/health/live >/dev/null; do
  i=$((i + 1)); [ $i -gt 30 ] && { echo "MinIO did not come up" >&2; exit 1; }
  sleep 1
done

# mc runs from the same image, sharing a throwaway config dir.
CFG=$(mktemp -d)
trap 'rm -rf "$CFG"' EXIT
mc() {
  docker run --rm -i --network host -v "$CFG:/cfg" -v "$CFG:/work" -w /work \
    --entrypoint mc "$IMAGE" --config-dir /cfg "$@"
}
mc alias set local http://127.0.0.1:9000 $ROOT_USER $ROOT_PASS >/dev/null

for b in $BUCKETS; do
  mc mb --ignore-existing "local/$b" >/dev/null
  mc version enable "local/$b" >/dev/null
  mc anonymous set none "local/$b" >/dev/null
done

cat > "$CFG/lifecycle-staging.json" <<'EOF'
{"Rules":[{"ID":"abandoned-uploads","Status":"Enabled","Filter":{"Prefix":""},
  "Expiration":{"Days":1},"NoncurrentVersionExpiration":{"NoncurrentDays":1}}]}
EOF
cat > "$CFG/lifecycle-store.json" <<'EOF'
{"Rules":[{"ID":"recovery-window","Status":"Enabled","Filter":{"Prefix":""},
  "NoncurrentVersionExpiration":{"NoncurrentDays":30}}]}
EOF
mc ilm import local/musafir-staging < "$CFG/lifecycle-staging.json" >/dev/null
for b in musafir-public musafir-documents musafir-face; do
  mc ilm import "local/$b" < "$CFG/lifecycle-store.json" >/dev/null
done

# The signer's least-privilege policy. ListBucket is withheld on purpose: a
# leaked key should not be able to enumerate everyone's documents.
cat > "$CFG/signer-policy.json" <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
  "Action":["s3:GetObject","s3:GetObjectVersion","s3:PutObject","s3:DeleteObject"],
  "Resource":["arn:aws:s3:::musafir-staging/*","arn:aws:s3:::musafir-public/*",
              "arn:aws:s3:::musafir-documents/*","arn:aws:s3:::musafir-face/*"]}]}
EOF
mc admin policy create local musafir-signer /work/signer-policy.json >/dev/null 2>&1 \
  || true
mc admin user add local $SIGNER_USER $SIGNER_PASS >/dev/null
mc admin policy attach local musafir-signer --user $SIGNER_USER >/dev/null 2>&1 || true

cat > "$CFG/retention-policy.json" <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
  "Action":["s3:DeleteObject","s3:DeleteObjectVersion"],
  "Resource":["arn:aws:s3:::musafir-face/*"]}]}
EOF
mc admin policy create local musafir-retention /work/retention-policy.json >/dev/null 2>&1 \
  || true
mc admin user add local $RETENTION_USER $RETENTION_PASS >/dev/null
mc admin policy attach local musafir-retention --user $RETENTION_USER >/dev/null 2>&1 || true

# "|| true" above only forgives "already exists/attached"; prove it took.
mc admin user info local $SIGNER_USER | grep -q musafir-signer
mc admin user info local $RETENTION_USER | grep -q musafir-retention

# MinIO applies CORS server-wide (MINIO_API_CORS_ALLOW_ORIGIN, default "*"),
# not per bucket; on AWS each bucket gets a CORS rule for the app's origins.

cat <<EOF
MinIO ready: http://127.0.0.1:9000 (console :9001, $ROOT_USER/$ROOT_PASS)

# Signer env (supabase/functions/.env.local), for 'supabase functions serve':
S3_ENDPOINT=http://host.docker.internal:9000
S3_PUBLIC_ENDPOINT=http://127.0.0.1:9000
S3_REGION=us-east-1
S3_PATH_STYLE=true
S3_ACCESS_KEY_ID=$SIGNER_USER
S3_SECRET_ACCESS_KEY=$SIGNER_PASS
S3_STAGING_BUCKET=musafir-staging
S3_BUCKET_PUBLIC=musafir-public
S3_BUCKET_DOCUMENTS=musafir-documents
S3_BUCKET_FACE=musafir-face
SIGNER_PUBLIC_URL=http://127.0.0.1:54321/functions/v1/storage-signer
S3_WRITE_BUCKETS=avatars,listing-images,chat-attachments,documents,face-evidence
S3_RETENTION_ACCESS_KEY_ID=$RETENTION_USER
S3_RETENTION_SECRET_ACCESS_KEY=$RETENTION_PASS
EOF
