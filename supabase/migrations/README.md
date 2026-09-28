# How this database is rebuilt — and why it is not from these files

**The migration chain is history, not a build script.** A database is created
from `supabase/baseline/live_baseline.sql` (a dump of the live catalog) plus
the migrations numbered *after* whatever live already has. `tool/local_db_from
_live.sh` does exactly that; CLAUDE.md's Supabase section is the operating
manual.

This was decided on 2026-09-19, and it is a decision about a fact rather than
a preference: **the chain cannot rebuild live, and repairing it would mean
writing DDL nobody has.**

## What was measured

`003_messaging.sql` contained

```sql
CONSTRAINT unique_conversation UNIQUE (
  LEAST(participant_one_id, participant_two_id),
  GREATEST(participant_one_id, participant_two_id)
)
```

which is **not valid Postgres and never was** — a UNIQUE *constraint* takes
bare column names; only a unique *index* may be built over expressions. So
`supabase start` on an empty database stopped dead there and everything below
was unreachable. That is repaired: the file now creates
`uniq_conversation_per_pair`, the index live actually has, under live's name.

With it repaired, all 137 files were replayed in order into an empty database
with a minimal Supabase scaffold (an `auth` schema with `users`, `uid()`,
`role()`, `jwt()`; a stub `storage`; PostGIS and pgcrypto):

| | |
| --- | --- |
| Applied clean | 103 |
| Failed | 34 |

Some of those 34 are the scaffold rather than the repo — there is no
`supabase_realtime` publication, no `net` schema, no `cron` schema, and
`storage.buckets` is a stub without `file_size_limit` / `allowed_mime_types`.
A real Supabase instance supplies all of those.

**The rest are the reason this decision goes the way it does.** Eight
migrations from 062 onward fail with `column l.max_guests does not exist`,
three with `column b.listing_title does not exist`, and others with
`listings.city`, `facilities.code` and `facilities.icon` missing. Those
columns exist on live and **no file in this directory adds them**. The chain
is not merely out of order; pieces of it were never committed.

## What this means in practice

- **Do not add a migration expecting `supabase db reset` to work.** It will
  not, and nothing in CI checks it.
- **A new migration is still a real, reviewable file here**, applied in order
  to live through the Management API and recorded in `NEWER_MIGRATIONS` in
  `tool/local_db_from_live.sh` so a fresh local mirror picks it up.
- **Regenerate the baseline after applying to live**
  (`python3 tool/dump_live_baseline.py`), or the next mirror is built from a
  catalog that predates your change and then replays your migration on top of
  a schema that already has it.
- Repairing the chain properly would mean reconstructing the missing DDL from
  the live catalog — which is precisely what the baseline already is. Doing it
  twice would buy nothing but a second source of truth to keep in step.
