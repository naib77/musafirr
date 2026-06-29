-- Phase 2: monthly standings snapshots → rank-change (▲▼) indicators.
--
-- A daily job snapshots the current month's standings. Comparing a host's
-- current monthly rank to last month's snapshot yields the rank delta.

CREATE TABLE IF NOT EXISTS public.host_leaderboard_snapshots (
  period text NOT NULL,                 -- 'YYYY-MM'
  host_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rank bigint NOT NULL,
  score numeric NOT NULL,
  captured_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  PRIMARY KEY (period, host_id)
);

-- Locked down: only the SECURITY DEFINER functions (and service role) touch it.
ALTER TABLE public.host_leaderboard_snapshots ENABLE ROW LEVEL SECURITY;

-- Rebuild the ranking functions to also return prev_rank (last month's rank).
DROP FUNCTION IF EXISTS public.get_host_rank(uuid, text);
DROP FUNCTION IF EXISTS public.get_host_leaderboard(text, int, int);
DROP FUNCTION IF EXISTS public.host_leaderboard_ranked(text);

CREATE OR REPLACE FUNCTION public.host_leaderboard_ranked(p_period text)
RETURNS TABLE (
  rank bigint,
  host_id uuid,
  name text,
  avatar_url text,
  score numeric,
  rating numeric,
  review_count bigint,
  completed_bookings bigint,
  prev_rank bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH params AS (
    SELECT
      CASE WHEN p_period = 'monthly'
        THEN date_trunc('month', timezone('utc', now())) END AS start_ts,
      CASE WHEN p_period = 'monthly'
        THEN to_char(
          date_trunc('month', timezone('utc', now())) - interval '1 month',
          'YYYY-MM') END AS prev_period
  ),
  rev AS (
    SELECT r.reviewee_id AS host_id, COUNT(*) AS review_count,
           AVG(r.overall_rating) AS avg_rating
    FROM public.reviews r, params
    WHERE r.review_type = 'guest_to_host'
      AND (params.start_ts IS NULL OR r.created_at >= params.start_ts)
    GROUP BY r.reviewee_id
  ),
  bk AS (
    SELECT l.owner_id AS host_id, COUNT(*) AS completed_bookings
    FROM public.bookings b
    JOIN public.listings l ON l.id = b.listing_id, params
    WHERE b.booking_status = 'completed'
      AND (params.start_ts IS NULL OR b.ends_at >= params.start_ts)
    GROUP BY l.owner_id
  ),
  gmean AS (
    SELECT COALESCE(AVG(r.overall_rating), 4.5) AS m
    FROM public.reviews r, params
    WHERE r.review_type = 'guest_to_host'
      AND (params.start_ts IS NULL OR r.created_at >= params.start_ts)
  ),
  scored AS (
    SELECT
      p.id AS host_id, p.full_name AS name, p.avatar_url,
      COALESCE(rev.review_count, 0) AS review_count,
      COALESCE(rev.avg_rating, 0) AS avg_rating,
      COALESCE(bk.completed_bookings, 0) AS completed_bookings,
      COALESCE(p.response_rate, 0) AS response_rate,
      ((5 * gmean.m) + COALESCE(rev.avg_rating, 0) * COALESCE(rev.review_count, 0))
        / (5 + COALESCE(rev.review_count, 0)) AS bayes
    FROM public.profiles p
    CROSS JOIN gmean
    LEFT JOIN rev ON rev.host_id = p.id
    LEFT JOIN bk ON bk.host_id = p.id
    WHERE p.is_host = TRUE
      AND COALESCE(p.leaderboard_opt_out, FALSE) = FALSE
      AND COALESCE(bk.completed_bookings, 0) >= 1
  ),
  ranked AS (
    SELECT
      ROW_NUMBER() OVER (
        ORDER BY score_calc DESC, review_count DESC, completed_bookings DESC
      ) AS rank,
      host_id, name, avatar_url, score_calc AS score,
      ROUND(avg_rating, 1) AS rating, review_count, completed_bookings
    FROM (
      SELECT host_id, name, avatar_url, review_count, completed_bookings, avg_rating,
        ROUND(
            50 * (bayes / 5.0)
          + 30 * (LEAST(completed_bookings, 50)::numeric / 50.0)
          + 20 * (response_rate / 100.0)
        , 1) AS score_calc
      FROM scored
    ) s
  )
  SELECT
    r.rank, r.host_id, r.name, r.avatar_url, r.score, r.rating,
    r.review_count, r.completed_bookings,
    snap.rank AS prev_rank
  FROM ranked r
  CROSS JOIN params
  LEFT JOIN public.host_leaderboard_snapshots snap
    ON snap.host_id = r.host_id AND snap.period = params.prev_period;
$$;

CREATE OR REPLACE FUNCTION public.get_host_leaderboard(
  p_period text DEFAULT 'all_time',
  p_limit int DEFAULT 100,
  p_offset int DEFAULT 0
)
RETURNS TABLE (
  rank bigint, host_id uuid, name text, avatar_url text, score numeric,
  rating numeric, review_count bigint, completed_bookings bigint, prev_rank bigint
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM public.host_leaderboard_ranked(p_period)
  ORDER BY rank
  LIMIT GREATEST(p_limit, 0) OFFSET GREATEST(p_offset, 0);
$$;

CREATE OR REPLACE FUNCTION public.get_host_rank(
  p_host_id uuid,
  p_period text DEFAULT 'all_time'
)
RETURNS TABLE (
  rank bigint, host_id uuid, name text, avatar_url text, score numeric,
  rating numeric, review_count bigint, completed_bookings bigint, prev_rank bigint
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM public.host_leaderboard_ranked(p_period)
  WHERE host_id = p_host_id;
$$;

-- Snapshots the CURRENT month's standings (idempotent upsert). The last run
-- before month rollover becomes that month's final standing.
CREATE OR REPLACE FUNCTION public.capture_monthly_leaderboard_snapshot()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO public.host_leaderboard_snapshots (period, host_id, rank, score, captured_at)
  SELECT to_char(timezone('utc', now()), 'YYYY-MM'), host_id, rank, score, timezone('utc', now())
  FROM public.host_leaderboard_ranked('monthly')
  ON CONFLICT (period, host_id) DO UPDATE
    SET rank = EXCLUDED.rank,
        score = EXCLUDED.score,
        captured_at = EXCLUDED.captured_at;
$$;

GRANT EXECUTE ON FUNCTION public.host_leaderboard_ranked(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_host_leaderboard(text, int, int) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_host_rank(uuid, text) TO anon, authenticated;

-- Seed an initial snapshot so future months have a baseline for deltas.
SELECT public.capture_monthly_leaderboard_snapshot();

-- Schedule the daily capture via pg_cron. Best-effort: if pg_cron isn't
-- available the migration still succeeds; enable it in the dashboard and run
-- the cron.schedule call below manually.
DO $cron$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
  PERFORM cron.schedule(
    'capture-monthly-leaderboard',
    '30 0 * * *',
    'SELECT public.capture_monthly_leaderboard_snapshot();'
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron unavailable (%); schedule capture_monthly_leaderboard_snapshot() manually.', SQLERRM;
END
$cron$;
