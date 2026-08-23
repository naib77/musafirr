#!/bin/sh
# Who can see a listing's exact address?
#
# `can_see_listing_address()` (migrations 093 / 103) is the only thing standing
# between a browsing stranger and a host's front door. It is enforced in RLS,
# so no Dart test can reach it — this script is the regression check instead.
#
# It synthesises one booking per status for a single guest on a single listing,
# asks the real function what it would disclose, prints the table, and ROLLS
# EVERYTHING BACK. Nothing is written. Safe to run against production, which is
# the point: the rule that matters is the one the live database is enforcing,
# not the one in the migration file.
#
# Usage:  sh tool/verify_address_privacy.sh
# Exit:   0 if every row matches the expected rule, 1 otherwise.

set -eu

PROJECT_REF="${SUPABASE_PROJECT_REF:-bojkmonskqlhuakxhzcb}"
TOKEN="${SUPABASE_ACCESS_TOKEN:-$(security find-generic-password -s "Supabase CLI" -w 2>/dev/null || true)}"

if [ -z "$TOKEN" ]; then
  echo "No Supabase token. Set SUPABASE_ACCESS_TOKEN, or log in with the CLI." >&2
  exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/probe.sql" <<'SQL'
begin;
create temp table m(ord int, scenario text, discloses boolean, expected boolean);

do $$
declare
  v_guest uuid; v_listing uuid; v_st text; v_i int := 0;
begin
  -- A real listing, and a real non-admin, non-owner profile with no booking on
  -- it, so the only bookings in play are the ones synthesised below.
  select l.id into v_listing from public.listings l order by l.id limit 1;
  select p.id into v_guest
    from public.profiles p
   where p.role <> 'admin'
     and p.id <> (select owner_id from public.listings where id = v_listing)
     and not exists (select 1 from public.bookings b
                      where b.listing_id = v_listing and b.tenant_id = p.id)
   order by p.id
   limit 1;

  if v_guest is null then
    raise exception 'no unrelated profile available to probe with';
  end if;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_guest::text, 'role', 'authenticated')::text, true);

  insert into m values (0, 'no booking at all',
                        public.can_see_listing_address(v_listing), false);

  -- One booking at a time, ending yesterday: a *recent* stay.
  foreach v_st in array array['pending','confirmed','active','completed','rejected','cancelled'] loop
    v_i := v_i + 1;
    delete from public.bookings where tenant_id = v_guest and listing_id = v_listing;
    insert into public.bookings
      (listing_id, tenant_id, tenant_name, starts_at, ends_at, booking_status,
       pricing_unit, unit_count, total_price, guest_count)
    values (v_listing, v_guest, 'ZZ Probe', now() - interval '2 day',
            now() - interval '1 day', v_st::public.booking_status,
            'day', 1, 100, 1);
    insert into m values (v_i, 'recent '||v_st||' booking',
                          public.can_see_listing_address(v_listing),
                          v_st in ('confirmed','active','completed'));
  end loop;

  -- The bug 103 fixed: a stay that finished long ago must NOT still disclose.
  delete from public.bookings where tenant_id = v_guest and listing_id = v_listing;
  insert into public.bookings
    (listing_id, tenant_id, tenant_name, starts_at, ends_at, booking_status,
     pricing_unit, unit_count, total_price, guest_count)
  values (v_listing, v_guest, 'ZZ Probe', now() - interval '91 day',
          now() - interval '90 day', 'completed', 'day', 1, 100, 1);
  insert into m values (10, 'completed 90 days ago',
                        public.can_see_listing_address(v_listing), false);

  -- ...and the reported scenario exactly: old completed stay + a NEW request
  -- the host has not accepted.
  insert into public.bookings
    (listing_id, tenant_id, tenant_name, starts_at, ends_at, booking_status,
     pricing_unit, unit_count, total_price, guest_count)
  values (v_listing, v_guest, 'ZZ Probe', now() + interval '5 day',
          now() + interval '6 day', 'pending', 'day', 1, 100, 1);
  insert into m values (11, 'completed 90d ago + NEW pending',
                        public.can_see_listing_address(v_listing), false);
end $$;

select scenario,
       case when discloses then 'EXACT' else 'area'  end as sees,
       case when expected  then 'EXACT' else 'area'  end as should_see,
       (discloses = expected) as ok
  from m order by ord;
rollback;
SQL

python3 - "$WORK/probe.sql" "$WORK/probe.json" <<'PY'
import json, sys
json.dump({"query": open(sys.argv[1]).read()}, open(sys.argv[2], "w"))
PY

curl -sS -X POST "https://api.supabase.com/v1/projects/$PROJECT_REF/database/query" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary "@$WORK/probe.json" > "$WORK/out.json"

python3 - "$WORK/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
if isinstance(d, dict):
    print("query failed:", str(d)[:500]); sys.exit(1)
bad = 0
print()
print(f"  {'sees':<6} {'should':<7} scenario")
print(f"  {'-'*6} {'-'*7} {'-'*40}")
for r in d:
    ok = r["ok"]
    bad += 0 if ok else 1
    print(f"  {r['sees']:<6} {r['should_see']:<7} {r['scenario']}"
          + ("" if ok else "   <-- WRONG"))
print()
if bad:
    print(f"FAIL — {bad} scenario(s) disagree with the rule."); sys.exit(1)
print("OK — address disclosure matches the rule.")
PY
