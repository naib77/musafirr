# Local database from a live baseline

Moved verbatim from `CLAUDE.md` on 2026-10-01 to keep that file small.
The short rule for each section is still in `CLAUDE.md`; the reasoning is here.

### The migration chain does not apply from scratch; local comes from a live baseline

`supabase start` on an empty database used to fail at **003**: `UNIQUE
(LEAST(a,b), GREATEST(a,b))` is not valid Postgres and never was. That file is
repaired (it creates `uniq_conversation_per_pair`, the index live actually
has), and the chain still does not rebuild the database — **and now we know
why, rather than suspecting it.** Replaying all 137 files into an empty
database applied 103 and failed 34, and among the failures are eight
migrations from 062 onward that need `listings.max_guests`, three that need
`bookings.listing_title`, plus `listings.city`, `facilities.code` and
`facilities.icon`. Those columns are on live and **nothing in
`supabase/migrations` adds them**: pieces of the chain were never committed.

So the decision recorded in `supabase/migrations/README.md` is that **the
baseline is the build and the chain is history.** Read that file before
adding a migration; the two things it asks of you are to bump
`NEWER_MIGRATIONS` in `tool/local_db_from_live.sh` and to regenerate the
baseline after applying to live.

Live cannot be `pg_dump`ed from here either — the `SUPABASE_DB_URL` "value"
the secrets API returns is a SHA-256, and there is no DB password on this
machine. So the local database is a **catalog dump through the Management
API**:

```sh
supabase start                      # config.toml has migrations+seed OFF
python3 tool/dump_live_baseline.py  # -> supabase/baseline/live_baseline.sql
sh tool/local_db_from_live.sh       # baseline (retried to stable), reference
                                    # rows, migrations newer than live, QA seed
supabase functions serve --env-file supabase/functions/.env.local --no-verify-jwt
```

Where it listens, once started:

| Studio UI | <http://127.0.0.1:54323> |
| Postgres | `postgresql://postgres:postgres@127.0.0.1:54322/postgres` |
| API / PostgREST / Auth | <http://127.0.0.1:54321> |
| anon + service keys | `supabase status` (the standard local demo keys, not secrets) |

`supabase start` on an ALREADY-RUNNING stack only prints status — it will not
add a service you excluded earlier. To gain Studio you must `supabase stop`
(which keeps the data volume; only `--no-backup` deletes it) and start again
with a shorter `-x` list.

Checked 2026-09-18 with the same catalog query on both: identical on tables,
functions, policies, triggers, views, indexes, RLS, cron, definers and anon
column grants. Not in the mirror: storage policies, auth config, secret
values. Seed accounts are `phone.170000000N@musaafir.app`, password
`qa-password`, and the local master OTP `3969` on those five numbers.

Three traps: the baseline is applied **repeatedly** on purpose (function,
view and policy order settles by retry; a count that stops shrinking above
zero is a finding); triggers are create-if-absent because `postgres` can
create but not drop a trigger on `spatial_ref_sys`; and
`NEWER_MIGRATIONS` in the loader must be bumped when live moves.
