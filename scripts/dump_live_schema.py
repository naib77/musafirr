#!/usr/bin/env python3
"""Generate a faithful snapshot of the LIVE public schema via the Supabase
Management API (no DB password / Docker needed). Output is a readable,
reference-grade SQL file — the authoritative source of truth for the live DB."""
import json, os, subprocess, sys, urllib.request

REF = "bojkmonskqlhuakxhzcb"
TOKEN = subprocess.check_output(
    ["security", "find-generic-password", "-s", "Supabase CLI", "-w"]
).decode().strip()
URL = f"https://api.supabase.com/v1/projects/{REF}/database/query"


def q(sql):
    req = urllib.request.Request(
        URL, data=json.dumps({"query": sql}).encode(),
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json",
                 "User-Agent": "curl/8.4.0"},
        method="POST")
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        print(f"QUERY FAILED (HTTP {e.code}):\n{sql[:200]}\n{e.read()[:300]}", file=sys.stderr)
        raise

# Exclude objects owned by an extension (e.g. PostGIS) — not part of the app schema.
NOT_EXT = "and not exists (select 1 from pg_depend d where d.objid={oid} and d.deptype='e')"


out = []
w = out.append
w("-- ============================================================")
w("-- LIVE SCHEMA SNAPSHOT — public schema of Supabase project " + REF)
w("-- Source of truth for the live database. Generated from the live")
w("-- catalog via the Management API (NOT hand-written, NOT from the")
w("-- migration files — which have drifted). Reference-grade: faithful to")
w("-- live, but not guaranteed to replay cleanly as-is. Regenerate with")
w("-- `python3 scripts/dump_live_schema.py` (uses the Supabase CLI keychain")
w("-- token; no DB password or Docker needed).")
w("-- ============================================================\n")

# ---- ENUMS ----
w("-- ========================= ENUM TYPES =========================")
enums = q("""select t.typname as name,
  array_agg(quote_literal(e.enumlabel) order by e.enumsortorder) as labels
from pg_type t join pg_enum e on e.enumtypid=t.oid
join pg_namespace n on n.oid=t.typnamespace where n.nspname='public'
  and not exists (select 1 from pg_depend d where d.objid=t.oid and d.deptype='e')
group by t.typname order by t.typname""")
for e in enums:
    w(f"create type public.{e['name']} as enum ({', '.join(e['labels'])});")
w("")

# ---- TABLES + COLUMNS ----
tables = [r["table_name"] for r in q(
    "select c.relname as table_name from pg_class c join pg_namespace n on n.oid=c.relnamespace"
    " where n.nspname='public' and c.relkind='r'"
    " and not exists (select 1 from pg_depend d where d.objid=c.oid and d.deptype='e')"
    " order by c.relname")]
cols = q("""select table_name, column_name, ordinal_position,
  case when data_type='USER-DEFINED' then udt_name
       when data_type='ARRAY' then udt_name
       else data_type end as type,
  is_nullable, column_default, character_maximum_length
from information_schema.columns where table_schema='public'
order by table_name, ordinal_position""")
by_tbl = {}
for c in cols:
    by_tbl.setdefault(c["table_name"], []).append(c)

# constraints grouped by table
cons = q("""select conrelid::regclass::text as tbl, conname,
  pg_get_constraintdef(oid) as def, contype
from pg_constraint where connamespace='public'::regnamespace
order by conrelid::regclass::text, contype desc, conname""")
cons_by_tbl = {}
for c in cons:
    cons_by_tbl.setdefault(c["tbl"], []).append(c)

w("-- ========================= TABLES =========================")
for t in tables:
    w(f"\ncreate table public.{t} (")
    lines = []
    for c in by_tbl.get(t, []):
        typ = c["type"]
        if c["character_maximum_length"]:
            typ += f"({c['character_maximum_length']})"
        seg = f"  {c['column_name']} {typ}"
        if c["column_default"] is not None:
            seg += f" default {c['column_default']}"
        if c["is_nullable"] == "NO":
            seg += " not null"
        lines.append(seg)
    w(",\n".join(lines))
    w(");")
    # constraints as ALTERs (full DDL from pg_get_constraintdef)
    for c in cons_by_tbl.get(f"public.{t}", []):
        w(f"alter table public.{t} add constraint {c['conname']} {c['def']};")
w("")

# ---- INDEXES (non-constraint) ----
idx = q("""select tablename, indexname, indexdef from pg_indexes
where schemaname='public'
  and indexname not in (select conname from pg_constraint where connamespace='public'::regnamespace)
order by tablename, indexname""")
idx = [i for i in idx if i["tablename"] in tables]
if idx:
    w("-- ========================= INDEXES =========================")
    for i in idx:
        w(i["indexdef"] + ";")
    w("")

# ---- RLS + POLICIES ----
w("-- ==================== ROW LEVEL SECURITY ====================")
rls = [r["tablename"] for r in q(
    "select tablename from pg_tables where schemaname='public' and rowsecurity"
    " order by tablename")]
for t in rls:
    w(f"alter table public.{t} enable row level security;")
w("")
pols = q("""select tablename, policyname, cmd, roles::text as roles, qual, with_check
from pg_policies where schemaname='public' order by tablename, policyname""")
w("-- Policies")
for p in pols:
    roles = p["roles"].strip("{}").replace(",", ", ")
    parts = [f'create policy "{p["policyname"]}" on public.{p["tablename"]}',
             f"  as permissive for {p['cmd'].lower()} to {roles}"]
    if p["qual"] is not None:
        parts.append(f"  using ({p['qual']})")
    if p["with_check"] is not None:
        parts.append(f"  with check ({p['with_check']})")
    w("\n".join(parts) + ";")
w("")

# ---- VIEWS ----
views = q("""select c.relname as table_name, pg_get_viewdef(c.oid, true) as def
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='v'
  and not exists (select 1 from pg_depend d where d.objid=c.oid and d.deptype='e')
order by c.relname""")
if views:
    w("-- ========================= VIEWS =========================")
    for v in views:
        w(f"create or replace view public.{v['table_name']} as\n{v['def']}")
    w("")

# ---- FUNCTIONS ----
fns = q("""select p.proname, pg_get_functiondef(p.oid) as def
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.prokind='f'
  and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')
order by p.proname, p.oid""")
w("-- ========================= FUNCTIONS =========================")
for f in fns:
    w(f["def"].rstrip() + ";\n")

# ---- TRIGGERS ----
trg = q("""select pg_get_triggerdef(t.oid) as def
from pg_trigger t join pg_class c on c.oid=t.tgrelid
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and not t.tgisinternal
order by c.relname, t.tgname""")
if trg:
    w("-- ========================= TRIGGERS =========================")
    for t in trg:
        w(t["def"] + ";")
    w("")

dest = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "..", "..", "..", "..", "..", "..")
# write to repo docs/
repo = "/Users/naib/workspaces/personal/projects/musafirr"
path = os.path.join(repo, "docs", "live_schema.sql")
with open(path, "w") as fh:
    fh.write("\n".join(out) + "\n")

print(f"wrote {path}")
print(f"  enums={len(enums)} tables={len(tables)} indexes={len(idx)} "
      f"rls_tables={len(rls)} policies={len(pols)} views={len(views)} "
      f"functions={len(fns)} triggers={len(trg)}")
