-- ---------------------------------------------------------------------------
-- 096 — voice_search_log
-- ---------------------------------------------------------------------------
-- Voice search parses Bangla and Banglish with a lexicon, not a model. A
-- lexicon written up front is a guess; this table turns it into a measurement.
-- Every spoken query lands here with what the parser made of it, so the misses
-- can be read back and the phrasings people actually used added to the lists
-- in lib/services/voice/voice_query_parser.dart.
--
-- This is the whole reason the feature can stay free: it replaces an LLM
-- fallback with a weekly read of real speech.
-- ---------------------------------------------------------------------------

create table if not exists public.voice_search_log (
  id            bigint generated always as identity primary key,
  created_at    timestamptz not null default now(),

  -- Null for a guest who has not signed in; voice search does not require an
  -- account, and refusing to log those would bias the sample toward users who
  -- already converted.
  user_id       uuid references auth.users(id) on delete set null,

  -- Exactly what the recogniser returned, in whichever script it used.
  transcript    text not null,
  locale_id     text,

  -- What the parser pulled out. All nullable: a row where these are empty IS
  -- the interesting case.
  parsed_place     text,
  parsed_types     text[],
  parsed_purpose   text,
  parsed_guests    int,
  parsed_max_price numeric,

  -- False when nothing at all could be extracted — the miss queue.
  parsed        boolean not null default false,
  result_count  int
);

-- The two questions this table gets asked: "what missed recently" and "what
-- misses most often".
create index if not exists voice_search_log_misses_idx
  on public.voice_search_log (created_at desc)
  where parsed = false;

create index if not exists voice_search_log_created_idx
  on public.voice_search_log (created_at desc);

-- ---------------------------------------------------------------------------
-- RLS: append-only from the client, readable by nobody
-- ---------------------------------------------------------------------------
-- Transcripts are user speech, so they are treated as private telemetry.
-- Clients may insert and nothing else; reads happen with the service role
-- (SQL editor / admin), which bypasses RLS. No select policy is defined, so
-- anon and authenticated cannot read a single row — including their own.
alter table public.voice_search_log enable row level security;

drop policy if exists voice_search_log_insert on public.voice_search_log;
create policy voice_search_log_insert
  on public.voice_search_log
  for insert
  to anon, authenticated
  with check (
    -- A signed-in client may only attribute a row to itself; a guest must
    -- leave it null. Stops one user's speech being logged under another's id.
    user_id is null or user_id = auth.uid()
  );

grant insert on public.voice_search_log to anon, authenticated;
