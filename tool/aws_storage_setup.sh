#!/bin/sh
# Production S3 for the storage signer (plan §4): the AWS twin of
# tool/storage_local.sh. Builds the buckets and the two IAM users, then writes
# every S3 secret the signer and the retention job read into the live Supabase
# project. Idempotent: re-run after a partial failure.
#
#   brew install awscli                       # once
#   export AWS_ACCESS_KEY_ID=… AWS_SECRET_ACCESS_KEY=…   # an ADMIN key, used
#                                             # only to bootstrap; see below
#   PREFIX=musafir-bd sh tool/aws_storage_setup.sh
#
# Knobs (env): PREFIX (bucket names are global across AWS, so pick one that is
# free), AWS_REGION (default ap-south-1, Mumbai — nearest to Bangladesh),
# WEB_ORIGINS (comma list for CORS; the deployed site and local dev by
# default), PROJECT_REF (the Supabase project), SECRETS_FILE (where the
# generated keys land; outside the repo, mode 600).
#
# What it builds, matching storage_local.sh line for line:
#   - four versioned buckets with Block Public Access on: staging, public
#     media, documents, face evidence. Every read is a presigned GET.
#   - staging: objects and abandoned multipart uploads expire after 1 day
#   - the three stores: noncurrent versions expire after 30 days (the recovery
#     window after a replace/delete; the retention job owns anything longer)
#   - CORS: browsers POST uploads to staging and GET media from public
#   - `<prefix>-signer`: an IAM user that may only get/put/delete objects in
#     those buckets — no ListBucket, so a leaked key cannot enumerate
#     everyone's documents, and no DeleteObjectVersion, so it cannot destroy
#     history
#   - `<prefix>-retention`: may destroy face-evidence versions and nothing
#     else. Only purge-face-evidence holds this key.
#
# The admin key you run this with is never stored anywhere: the signer gets
# its own, freshly created, least-privilege keys, written to SECRETS_FILE and
# pushed to Supabase. S3_WRITE_BUCKETS is deliberately NOT set — the signer
# treats unset as "route nothing to S3", so deploying it is not a cutover.
# Enable buckets one at a time afterwards (plan §8):
#   supabase secrets set --project-ref $PROJECT_REF S3_WRITE_BUCKETS=avatars
set -eu

PREFIX=${PREFIX:-musafir-bd}
REGION=${AWS_REGION:-ap-south-1}
PROJECT_REF=${PROJECT_REF:-bojkmonskqlhuakxhzcb}
WEB_ORIGINS=${WEB_ORIGINS:-https://musafirr.knaib77.workers.dev,http://localhost:*,http://127.0.0.1:*}
SECRETS_FILE=${SECRETS_FILE:-$HOME/.config/musafir/supabase-s3-$PROJECT_REF.env}
export AWS_DEFAULT_REGION=$REGION
# No pager, no colour: this runs non-interactively and is parsed with jq-less sh.
export AWS_PAGER=""

STAGING=$PREFIX-staging
PUBLIC=$PREFIX-public
DOCUMENTS=$PREFIX-documents
FACE=$PREFIX-face
SIGNER_USER=$PREFIX-signer
RETENTION_USER=$PREFIX-retention

for cmd in aws supabase python3; do
  command -v $cmd >/dev/null || { echo "$cmd is required" >&2; exit 1; }
done

echo "== AWS identity"
aws sts get-caller-identity --output text --query 'Arn'

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ---- Buckets ---------------------------------------------------------------
# A bucket that already exists AND is ours is fine; one owned by someone else
# is why PREFIX exists. create-bucket distinguishes the two by error code.
make_bucket() {
  if aws s3api head-bucket --bucket "$1" 2>/dev/null; then
    echo "   $1 exists"
  else
    # us-east-1 is the one region that refuses a LocationConstraint.
    if [ "$REGION" = us-east-1 ]; then
      aws s3api create-bucket --bucket "$1" >/dev/null
    else
      aws s3api create-bucket --bucket "$1" \
        --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
    fi
    echo "   $1 created"
  fi
  aws s3api put-bucket-versioning --bucket "$1" \
    --versioning-configuration Status=Enabled
  aws s3api put-public-access-block --bucket "$1" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
}

echo "== Buckets ($REGION)"
for b in $STAGING $PUBLIC $DOCUMENTS $FACE; do make_bucket $b; done

cat > "$WORK/lifecycle-staging.json" <<'EOF'
{"Rules":[{"ID":"abandoned-uploads","Status":"Enabled","Filter":{"Prefix":""},
  "Expiration":{"Days":1},"NoncurrentVersionExpiration":{"NoncurrentDays":1},
  "AbortIncompleteMultipartUpload":{"DaysAfterInitiation":1}}]}
EOF
cat > "$WORK/lifecycle-store.json" <<'EOF'
{"Rules":[{"ID":"recovery-window","Status":"Enabled","Filter":{"Prefix":""},
  "NoncurrentVersionExpiration":{"NoncurrentDays":30}}]}
EOF
aws s3api put-bucket-lifecycle-configuration --bucket $STAGING \
  --lifecycle-configuration "file://$WORK/lifecycle-staging.json"
for b in $PUBLIC $DOCUMENTS $FACE; do
  aws s3api put-bucket-lifecycle-configuration --bucket $b \
    --lifecycle-configuration "file://$WORK/lifecycle-store.json"
done

# CORS: the browser POSTs the multipart form straight to staging (presigned
# POST) and GETs media from public after the signer's 302. Private buckets get
# no CORS at all — their reads are same-origin-free presigned GETs in <img>
# tags or downloads, never cross-origin fetches.
ORIGINS_JSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1].split(",")))' "$WEB_ORIGINS")
cat > "$WORK/cors-staging.json" <<EOF
{"CORSRules":[{"AllowedOrigins":$ORIGINS_JSON,"AllowedMethods":["POST"],
  "AllowedHeaders":["*"],"ExposeHeaders":["ETag"],"MaxAgeSeconds":3600}]}
EOF
cat > "$WORK/cors-public.json" <<EOF
{"CORSRules":[{"AllowedOrigins":$ORIGINS_JSON,"AllowedMethods":["GET","HEAD"],
  "AllowedHeaders":["*"],"MaxAgeSeconds":86400}]}
EOF
aws s3api put-bucket-cors --bucket $STAGING --cors-configuration "file://$WORK/cors-staging.json"
aws s3api put-bucket-cors --bucket $PUBLIC --cors-configuration "file://$WORK/cors-public.json"
echo "   lifecycle + CORS applied"

# ---- IAM -------------------------------------------------------------------
cat > "$WORK/signer-policy.json" <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
  "Action":["s3:GetObject","s3:GetObjectVersion","s3:PutObject","s3:DeleteObject"],
  "Resource":["arn:aws:s3:::$STAGING/*","arn:aws:s3:::$PUBLIC/*",
              "arn:aws:s3:::$DOCUMENTS/*","arn:aws:s3:::$FACE/*"]}]}
EOF
cat > "$WORK/retention-policy.json" <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
  "Action":["s3:DeleteObject","s3:DeleteObjectVersion"],
  "Resource":["arn:aws:s3:::$FACE/*"]}]}
EOF

# Returns "KEY SECRET" for a user, creating the user and a fresh key. An
# existing key is not reused: its secret is unrecoverable, and rotating here
# is the point. IAM allows two keys per user, so a third run must delete one
# in the console first — the error says so.
make_user() {
  user=$1; policy=$2
  aws iam get-user --user-name "$user" >/dev/null 2>&1 \
    || aws iam create-user --user-name "$user" >/dev/null
  aws iam put-user-policy --user-name "$user" --policy-name "$user" \
    --policy-document "file://$WORK/$policy"
  aws iam create-access-key --user-name "$user" --output text \
    --query 'AccessKey.[AccessKeyId,SecretAccessKey]'
}

echo "== IAM users"
SIGNER_KEYS=$(make_user $SIGNER_USER signer-policy.json)
RETENTION_KEYS=$(make_user $RETENTION_USER retention-policy.json)
echo "   $SIGNER_USER, $RETENTION_USER: new access keys issued"

# ---- Secrets ---------------------------------------------------------------
mkdir -p "$(dirname "$SECRETS_FILE")"
umask 077
cat > "$SECRETS_FILE" <<EOF
# Supabase edge-function secrets for the S3 storage signer. Generated by
# tool/aws_storage_setup.sh on $(date -u +%Y-%m-%dT%H:%MZ). Keep out of git.
S3_ENDPOINT=https://s3.$REGION.amazonaws.com
S3_PUBLIC_ENDPOINT=https://s3.$REGION.amazonaws.com
S3_REGION=$REGION
S3_PATH_STYLE=false
S3_ACCESS_KEY_ID=$(echo "$SIGNER_KEYS" | cut -f1)
S3_SECRET_ACCESS_KEY=$(echo "$SIGNER_KEYS" | cut -f2)
S3_STAGING_BUCKET=$STAGING
S3_BUCKET_PUBLIC=$PUBLIC
S3_BUCKET_DOCUMENTS=$DOCUMENTS
S3_BUCKET_FACE=$FACE
SIGNER_PUBLIC_URL=https://$PROJECT_REF.supabase.co/functions/v1/storage-signer
S3_RETENTION_ACCESS_KEY_ID=$(echo "$RETENTION_KEYS" | cut -f1)
S3_RETENTION_SECRET_ACCESS_KEY=$(echo "$RETENTION_KEYS" | cut -f2)
EOF

echo "== Supabase secrets ($PROJECT_REF)"
supabase secrets set --project-ref "$PROJECT_REF" --env-file "$SECRETS_FILE"

cat <<EOF

Done. Secrets written to $SECRETS_FILE (mode 600) and to Supabase.
S3_WRITE_BUCKETS is unset on purpose: nothing routes to S3 until you say so.

Next:
  supabase functions deploy storage-signer purge-face-evidence --project-ref $PROJECT_REF
  curl -s -X POST https://$PROJECT_REF.supabase.co/functions/v1/storage-signer \\
       -H "apikey: \$ANON" -H "Authorization: Bearer \$ANON" -d '{"action":"config"}'
  # -> {"write_buckets":[]}
Then DEACTIVATE the admin key you ran this with (IAM console): the signer has
its own keys now, and that one was only ever needed to bootstrap.
EOF
