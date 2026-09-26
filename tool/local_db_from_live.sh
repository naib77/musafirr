#!/bin/sh
# Build the LOCAL Supabase database from the live baseline.
#
#   supabase start            # once; Docker must be running
#   sh tool/local_db_from_live.sh
#
# Why not `supabase db reset`: the migration chain does not apply from scratch
# (003 is invalid SQL; live was built from SQL the repo does not hold), so
# config.toml disables migrations locally and this script loads
# supabase/baseline/live_baseline.sql — a replayable, idempotent dump of the
# live catalog made by tool/dump_live_baseline.py — then the reference rows,
# then every migration newer than live, then a synthetic QA seed.
#
# The baseline is applied REPEATEDLY until the count of failing statements
# stops shrinking: that is how cross-dependencies between functions, views and
# policies settle without a topological sort. A stable non-zero count is
# printed in full and is a real finding, not noise.
set -u
DB=${LOCAL_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
cd "$(dirname "$0")/.."
LOG=$(mktemp)

apply() { psql "$DB" -q -v ON_ERROR_STOP=0 -f "$1" 2>&1 | grep -E "^psql:.*(ERROR|FATAL)" ; }

echo "== baseline"
prev=999999
for i in 1 2 3 4 5 6 7 8; do
  apply supabase/baseline/live_baseline.sql > "$LOG"
  n=$(wc -l < "$LOG" | tr -d ' ')
  echo "pass $i: $n failing statements"
  [ "$n" -eq 0 ] && break
  [ "$n" -ge "$prev" ] && break
  prev=$n
done
if [ "$n" -ne 0 ]; then echo "-- remaining failures:"; sort "$LOG" | uniq -c | sort -rn | head -40; fi

echo "== reference rows"
apply supabase/baseline/live_seed.sql

# Migrations that live does not have yet. EMPTY is the correct value right
# after a baseline re-dump — the baseline already contains everything applied
# to live, so replaying a migration on top of it would apply it twice. Add a
# number here the moment you write a migration, and clear it again once it is
# applied to live and the baseline has been regenerated.
# Last cleared 2026-09-19, after 131 and 133-137 went live.
# 138 is written and NOT yet applied to live (QA round 2, 2026-09-19).
echo "== migrations newer than live"
for m in ${NEWER_MIGRATIONS:-138 139 140}; do
  f=$(ls supabase/migrations/${m}_*.sql | head -1)
  echo "-- $f"; psql "$DB" -q -v ON_ERROR_STOP=1 -f "$f" 2>&1 | grep -E "ERROR|FATAL" || true
done

if [ -f supabase/baseline/qa_seed.sql ]; then
  echo "== QA seed"; apply supabase/baseline/qa_seed.sql
fi
rm -f "$LOG"
echo "done"
