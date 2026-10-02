#!/bin/sh
# Run every SQL suite under supabase/tests/ against the LOCAL mirror, each one
# inside its own `begin … rollback`, and print PASS/FAIL counts per file.
#
#   sh tool/qa/run_sql_tests.sh              # all suites
#   sh tool/qa/run_sql_tests.sh 138 132      # by number / substring
#
# Why the wrapper: most of these files were written to be pasted into the
# Management API or psql by a human who types BEGIN first and ROLLBACK after.
# Run with plain `psql -f` they COMMIT their fixtures — `psql -1` too, since
# that commits at the end — and the second QA round lost an hour to exactly
# that: twelve listings, eight bookings, eleven devices, a payout method and
# forty-four notifications left behind by earlier runs, and a later suite
# failing on "you have already added that account". Only 134_137, 138 and 139_140
# carry their own transaction; for those the outer one is a harmless nest
# (psql warns "there is already a transaction in progress" and moves on).
#
# LOCAL ONLY. Several suites attempt writes that must never be tried on live.
set -u
cd "$(dirname "$0")/../.."
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
DB=${LOCAL_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}
total_pass=0; total_fail=0; total_err=0
for f in supabase/tests/*.sql; do
  name=$(basename "$f" .sql)
  if [ $# -gt 0 ]; then
    match=0; for want in "$@"; do case "$name" in *"$want"*) match=1;; esac; done
    [ "$match" = 1 ] || continue
  fi
  out=$( (echo 'begin;'; cat "$f"; echo 'rollback;') | psql "$DB" -q 2>&1 )
  # Every suite prints one verdict word per row; the formats in use are
  # "| PASS"/"| FAIL" columns, "PASS"/"FAIL: …" cells, and (147 onward, the
  # pg_temp.check_true helper) "NOTICE:  PASS: …" -- which the first two
  # patterns miss, so those suites read PASS=0 without the third. ERROR lines
  # are the file failing to run at all (a missing fixture, a stale column
  # name); check_true's own FAIL is raised, so it lands there too.
  p=$(printf '%s\n' "$out" | grep -cE '(^|\||NOTICE:)\s*PASS\b')
  fl=$(printf '%s\n' "$out" | grep -cE '(^|\|)\s*FAIL\b')
  e=$(printf '%s\n' "$out" | grep -cE '^(psql:.*)?ERROR:' )
  e=$(( e - $(printf '%s\n' "$out" | grep -cE 'ERROR:  current transaction is aborted') ))
  printf '%-48s PASS=%-3s FAIL=%-3s ERR=%s\n' "$name" "$p" "$fl" "$e"
  total_pass=$((total_pass+p)); total_fail=$((total_fail+fl)); total_err=$((total_err+e))
done
echo "TOTAL PASS=$total_pass FAIL=$total_fail ERR=$total_err"
[ "$total_fail" -eq 0 ] && [ "$total_err" -eq 0 ]
