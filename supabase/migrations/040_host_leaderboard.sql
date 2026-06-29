-- Host leaderboard (Phase 1): a public, read-only ranking of hosts by a
-- composite "Host Score" blended from review quality, activity and reliability.
--
-- Computed live by an RPC for both 'all_time' and 'monthly' windows. At current
-- scale a live aggregation is fine; a materialized view + pg_cron is the scale
-- path (Phase 2/3) without changing the app-facing contract.

-- Let a host hide from the public board.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS leaderboard_opt_out BOOLEAN NOT NULL DEFAULT FALSE;

CREATE OR REPLACE FUNCTION public.get_host_leaderboard(
  p_period text DEFAULT 'all_time',
  p_limit int DEFAULT 100,
  p_offset int DEFAULT 0
)
RETURNS TABLE (
  rank bigint,
  host_id uuid,
  name text,
  avatar_url text,
  score numeric,
  rating numeric,
  review_count bigint,
  completed_bookings bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH params AS (
    SELECT CASE
      WHEN p_period = 'monthly'
      THEN date_trunc('month', timezone('utc', now()))
      ELSE NULL
    END AS start_ts
  ),
  -- Per-host guest review stats in the window.
  rev AS (
    SELECT r.reviewee_id AS host_id,
           COUNT(*) AS review_count,
           AVG(r.overall_rating) AS avg_rating
    FROM public.reviews r, params
    WHERE r.review_type = 'guest_to_host'
      AND (params.start_ts IS NULL OR r.created_at >= params.start_ts)
    GROUP BY r.reviewee_id
  ),
  -- Per-host completed bookings in the window.
  bk AS (
    SELECT l.owner_id AS host_id,
           COUNT(*) AS completed_bookings
    FROM public.bookings b
    JOIN public.listings l ON l.id = b.listing_id, params
    WHERE b.booking_status = 'completed'
      AND (params.start_ts IS NULL OR b.ends_at >= params.start_ts)
    GROUP BY l.owner_id
  ),
  -- Global mean rating for the Bayesian prior (so a single 5-star review
  -- doesn't top the board). Falls back to 4.5 when there are no reviews yet.
  gmean AS (
    SELECT COALESCE(AVG(r.overall_rating), 4.5) AS m
    FROM public.reviews r, params
    WHERE r.review_type = 'guest_to_host'
      AND (params.start_ts IS NULL OR r.created_at >= params.start_ts)
  ),
  scored AS (
    SELECT
      p.id AS host_id,
      p.full_name AS name,
      p.avatar_url,
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
      AND COALESCE(bk.completed_bookings, 0) >= 1  -- eligibility: real activity
  ),
  final AS (
    SELECT
      host_id, name, avatar_url, review_count, completed_bookings, avg_rating,
      ROUND(
          50 * (bayes / 5.0)
        + 30 * (LEAST(completed_bookings, 50)::numeric / 50.0)
        + 20 * (response_rate / 100.0)
      , 1) AS score
    FROM scored
  )
  SELECT
    ROW_NUMBER() OVER (
      ORDER BY score DESC, review_count DESC, completed_bookings DESC
    ) AS rank,
    host_id, name, avatar_url, score,
    ROUND(avg_rating, 1) AS rating,
    review_count, completed_bookings
  FROM final
  ORDER BY score DESC, review_count DESC, completed_bookings DESC
  LIMIT GREATEST(p_limit, 0) OFFSET GREATEST(p_offset, 0);
$$;

GRANT EXECUTE ON FUNCTION public.get_host_leaderboard(text, int, int)
  TO anon, authenticated;
