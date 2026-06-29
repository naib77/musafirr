-- Refactor the leaderboard scoring into ONE shared function so the board and a
-- single host's rank can't drift apart, then add get_host_rank for the
-- "You're #X" dashboard card.

-- Full ranked set (no limit). Single source of truth for the Host Score.
CREATE OR REPLACE FUNCTION public.host_leaderboard_ranked(p_period text)
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
  rev AS (
    SELECT r.reviewee_id AS host_id,
           COUNT(*) AS review_count,
           AVG(r.overall_rating) AS avg_rating
    FROM public.reviews r, params
    WHERE r.review_type = 'guest_to_host'
      AND (params.start_ts IS NULL OR r.created_at >= params.start_ts)
    GROUP BY r.reviewee_id
  ),
  bk AS (
    SELECT l.owner_id AS host_id,
           COUNT(*) AS completed_bookings
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
      AND COALESCE(bk.completed_bookings, 0) >= 1
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
  FROM final;
$$;

-- The public board now just pages over the shared ranking.
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
  SELECT * FROM public.host_leaderboard_ranked(p_period)
  ORDER BY rank
  LIMIT GREATEST(p_limit, 0) OFFSET GREATEST(p_offset, 0);
$$;

-- A single host's rank (for the "You're #X" card). Returns 0 or 1 row.
CREATE OR REPLACE FUNCTION public.get_host_rank(
  p_host_id uuid,
  p_period text DEFAULT 'all_time'
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
  SELECT * FROM public.host_leaderboard_ranked(p_period)
  WHERE host_id = p_host_id;
$$;

GRANT EXECUTE ON FUNCTION public.host_leaderboard_ranked(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_host_leaderboard(text, int, int) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_host_rank(uuid, text) TO anon, authenticated;
