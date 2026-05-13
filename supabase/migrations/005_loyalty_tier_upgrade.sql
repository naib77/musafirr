-- Migration: 005_loyalty_tier_upgrade.sql
-- Description: Automatic loyalty tier upgrade triggers and functions
-- Created: 2024

-- ============================================
-- FUNCTION: Calculate eligible tier
-- ============================================

CREATE OR REPLACE FUNCTION calculate_eligible_tier(
  p_total_bookings INTEGER,
  p_total_nights INTEGER,
  p_total_spent DECIMAL
) RETURNS UUID AS $$
DECLARE
  v_tier_id UUID;
BEGIN
  -- Find highest tier the user qualifies for
  SELECT id INTO v_tier_id
  FROM loyalty_tiers
  WHERE min_bookings <= p_total_bookings
    AND min_nights_stayed <= p_total_nights
    AND min_total_spent <= p_total_spent
  ORDER BY level DESC
  LIMIT 1;

  -- Default to Bronze if no tier found
  IF v_tier_id IS NULL THEN
    SELECT id INTO v_tier_id
    FROM loyalty_tiers
    WHERE level = 1
    LIMIT 1;
  END IF;

  RETURN v_tier_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- FUNCTION: Check and upgrade tier
-- ============================================

CREATE OR REPLACE FUNCTION check_and_upgrade_tier(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_loyalty RECORD;
  v_current_tier_level INTEGER;
  v_eligible_tier_id UUID;
  v_eligible_tier_level INTEGER;
  v_result JSONB;
BEGIN
  -- Get current user loyalty
  SELECT * INTO v_loyalty
  FROM user_loyalty
  WHERE user_id = p_user_id;

  -- If no loyalty record, create one
  IF NOT FOUND THEN
    INSERT INTO user_loyalty (user_id, current_tier_id)
    SELECT p_user_id, id FROM loyalty_tiers WHERE level = 1
    RETURNING * INTO v_loyalty;
  END IF;

  -- Get current tier level
  SELECT COALESCE(level, 1) INTO v_current_tier_level
  FROM loyalty_tiers
  WHERE id = v_loyalty.current_tier_id;

  -- Calculate eligible tier
  v_eligible_tier_id := calculate_eligible_tier(
    v_loyalty.total_bookings,
    v_loyalty.total_nights_stayed,
    v_loyalty.total_amount_spent
  );

  -- Get eligible tier level
  SELECT level INTO v_eligible_tier_level
  FROM loyalty_tiers
  WHERE id = v_eligible_tier_id;

  -- Check if upgrade is possible
  IF v_eligible_tier_level > v_current_tier_level THEN
    -- Perform upgrade
    UPDATE user_loyalty
    SET current_tier_id = v_eligible_tier_id,
        previous_tier_id = v_loyalty.current_tier_id,
        tier_upgraded_at = NOW(),
        updated_at = NOW()
    WHERE user_id = p_user_id;

    -- Return upgrade info
    SELECT jsonb_build_object(
      'upgraded', TRUE,
      'previous_tier', jsonb_build_object(
        'id', old_tier.id,
        'name', old_tier.name,
        'level', old_tier.level
      ),
      'new_tier', jsonb_build_object(
        'id', new_tier.id,
        'name', new_tier.name,
        'level', new_tier.level,
        'discount_percentage', new_tier.discount_percentage
      )
    ) INTO v_result
    FROM loyalty_tiers old_tier, loyalty_tiers new_tier
    WHERE old_tier.id = v_loyalty.current_tier_id
      AND new_tier.id = v_eligible_tier_id;

    RETURN v_result;
  END IF;

  -- No upgrade
  RETURN jsonb_build_object('upgraded', FALSE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- FUNCTION: Update loyalty after booking
-- ============================================

CREATE OR REPLACE FUNCTION update_loyalty_after_booking(
  p_user_id UUID,
  p_nights INTEGER,
  p_amount DECIMAL
) RETURNS JSONB AS $$
DECLARE
  v_loyalty RECORD;
  v_upgrade_result JSONB;
  v_loyalty_points INTEGER;
BEGIN
  -- Calculate loyalty points (1 point per ৳100 spent)
  v_loyalty_points := FLOOR(p_amount / 100);

  -- Get or create user loyalty
  INSERT INTO user_loyalty (user_id, current_tier_id, total_bookings, total_nights_stayed, total_amount_spent, loyalty_points)
  SELECT p_user_id, id, 1, p_nights, p_amount, v_loyalty_points
  FROM loyalty_tiers WHERE level = 1
  ON CONFLICT (user_id) DO UPDATE
  SET total_bookings = user_loyalty.total_bookings + 1,
      total_nights_stayed = user_loyalty.total_nights_stayed + p_nights,
      total_amount_spent = user_loyalty.total_amount_spent + p_amount,
      loyalty_points = user_loyalty.loyalty_points + v_loyalty_points,
      updated_at = NOW()
  RETURNING * INTO v_loyalty;

  -- Check for tier upgrade
  v_upgrade_result := check_and_upgrade_tier(p_user_id);

  RETURN jsonb_build_object(
    'loyalty', jsonb_build_object(
      'total_bookings', v_loyalty.total_bookings,
      'total_nights_stayed', v_loyalty.total_nights_stayed,
      'total_amount_spent', v_loyalty.total_amount_spent,
      'loyalty_points', v_loyalty.loyalty_points
    ),
    'upgrade', v_upgrade_result
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- TRIGGER: Auto-check tier on loyalty update
-- ============================================

CREATE OR REPLACE FUNCTION auto_check_tier_upgrade()
RETURNS TRIGGER AS $$
DECLARE
  v_eligible_tier_id UUID;
  v_current_tier_level INTEGER;
  v_eligible_tier_level INTEGER;
BEGIN
  -- Only check if stats were updated (not just timestamps)
  IF OLD.total_bookings = NEW.total_bookings
     AND OLD.total_nights_stayed = NEW.total_nights_stayed
     AND OLD.total_amount_spent = NEW.total_amount_spent THEN
    RETURN NEW;
  END IF;

  -- Get current tier level
  SELECT COALESCE(level, 1) INTO v_current_tier_level
  FROM loyalty_tiers
  WHERE id = NEW.current_tier_id;

  -- Calculate eligible tier
  v_eligible_tier_id := calculate_eligible_tier(
    NEW.total_bookings,
    NEW.total_nights_stayed,
    NEW.total_amount_spent
  );

  -- Get eligible tier level
  SELECT level INTO v_eligible_tier_level
  FROM loyalty_tiers
  WHERE id = v_eligible_tier_id;

  -- Upgrade if eligible
  IF v_eligible_tier_level > v_current_tier_level THEN
    NEW.previous_tier_id := NEW.current_tier_id;
    NEW.current_tier_id := v_eligible_tier_id;
    NEW.tier_upgraded_at := NOW();

    RAISE NOTICE 'User % upgraded to tier level %', NEW.user_id, v_eligible_tier_level;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if exists
DROP TRIGGER IF EXISTS auto_tier_upgrade_trigger ON user_loyalty;

-- Create trigger
CREATE TRIGGER auto_tier_upgrade_trigger
  BEFORE UPDATE ON user_loyalty
  FOR EACH ROW EXECUTE FUNCTION auto_check_tier_upgrade();

-- ============================================
-- FUNCTION: Create initial user loyalty
-- ============================================

CREATE OR REPLACE FUNCTION create_initial_user_loyalty()
RETURNS TRIGGER AS $$
DECLARE
  v_bronze_tier_id UUID;
BEGIN
  -- Get Bronze tier ID
  SELECT id INTO v_bronze_tier_id
  FROM loyalty_tiers
  WHERE level = 1
  LIMIT 1;

  -- Create loyalty record
  INSERT INTO user_loyalty (user_id, current_tier_id)
  VALUES (NEW.id, v_bronze_tier_id)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Note: This trigger should be created on the profiles/users table
-- Uncomment if profiles table exists:
-- DROP TRIGGER IF EXISTS create_loyalty_on_signup ON profiles;
-- CREATE TRIGGER create_loyalty_on_signup
--   AFTER INSERT ON profiles
--   FOR EACH ROW EXECUTE FUNCTION create_initial_user_loyalty();

-- ============================================
-- FUNCTION: Get user loyalty with tier
-- ============================================

CREATE OR REPLACE FUNCTION get_user_loyalty_with_tier(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'loyalty', jsonb_build_object(
      'id', ul.id,
      'user_id', ul.user_id,
      'total_bookings', ul.total_bookings,
      'total_nights_stayed', ul.total_nights_stayed,
      'total_amount_spent', ul.total_amount_spent,
      'loyalty_points', ul.loyalty_points,
      'credits_balance', ul.credits_balance,
      'tier_upgraded_at', ul.tier_upgraded_at
    ),
    'current_tier', jsonb_build_object(
      'id', lt.id,
      'name', lt.name,
      'level', lt.level,
      'discount_percentage', lt.discount_percentage,
      'priority_support', lt.priority_support,
      'free_cancellation_window', lt.free_cancellation_window,
      'early_access_hours', lt.early_access_hours,
      'badge_color', lt.badge_color,
      'icon_name', lt.icon_name
    ),
    'next_tier', (
      SELECT jsonb_build_object(
        'id', nt.id,
        'name', nt.name,
        'level', nt.level,
        'min_bookings', nt.min_bookings,
        'min_nights_stayed', nt.min_nights_stayed,
        'min_total_spent', nt.min_total_spent,
        'discount_percentage', nt.discount_percentage
      )
      FROM loyalty_tiers nt
      WHERE nt.level = lt.level + 1
    ),
    'progress', jsonb_build_object(
      'bookings_progress', ul.total_bookings,
      'bookings_required', COALESCE((
        SELECT min_bookings FROM loyalty_tiers WHERE level = lt.level + 1
      ), ul.total_bookings),
      'nights_progress', ul.total_nights_stayed,
      'nights_required', COALESCE((
        SELECT min_nights_stayed FROM loyalty_tiers WHERE level = lt.level + 1
      ), ul.total_nights_stayed),
      'spent_progress', ul.total_amount_spent,
      'spent_required', COALESCE((
        SELECT min_total_spent FROM loyalty_tiers WHERE level = lt.level + 1
      ), ul.total_amount_spent)
    )
  ) INTO v_result
  FROM user_loyalty ul
  JOIN loyalty_tiers lt ON lt.id = ul.current_tier_id
  WHERE ul.user_id = p_user_id;

  -- Create default if not found
  IF v_result IS NULL THEN
    -- Create user loyalty first
    INSERT INTO user_loyalty (user_id, current_tier_id)
    SELECT p_user_id, id FROM loyalty_tiers WHERE level = 1
    ON CONFLICT (user_id) DO NOTHING;

    -- Retry query
    SELECT jsonb_build_object(
      'loyalty', jsonb_build_object(
        'id', ul.id,
        'user_id', ul.user_id,
        'total_bookings', 0,
        'total_nights_stayed', 0,
        'total_amount_spent', 0,
        'loyalty_points', 0,
        'credits_balance', 0
      ),
      'current_tier', jsonb_build_object(
        'id', lt.id,
        'name', lt.name,
        'level', lt.level,
        'discount_percentage', lt.discount_percentage,
        'priority_support', lt.priority_support,
        'free_cancellation_window', lt.free_cancellation_window,
        'early_access_hours', lt.early_access_hours,
        'badge_color', lt.badge_color,
        'icon_name', lt.icon_name
      ),
      'next_tier', (
        SELECT jsonb_build_object(
          'id', nt.id,
          'name', nt.name,
          'level', nt.level,
          'min_bookings', nt.min_bookings,
          'min_nights_stayed', nt.min_nights_stayed,
          'min_total_spent', nt.min_total_spent,
          'discount_percentage', nt.discount_percentage
        )
        FROM loyalty_tiers nt
        WHERE nt.level = 2
      ),
      'progress', jsonb_build_object(
        'bookings_progress', 0,
        'bookings_required', (SELECT min_bookings FROM loyalty_tiers WHERE level = 2),
        'nights_progress', 0,
        'nights_required', (SELECT min_nights_stayed FROM loyalty_tiers WHERE level = 2),
        'spent_progress', 0,
        'spent_required', (SELECT min_total_spent FROM loyalty_tiers WHERE level = 2)
      )
    ) INTO v_result
    FROM user_loyalty ul
    JOIN loyalty_tiers lt ON lt.id = ul.current_tier_id
    WHERE ul.user_id = p_user_id;
  END IF;

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- FUNCTION: Complete referral and credit rewards
-- ============================================

CREATE OR REPLACE FUNCTION complete_referral(
  p_referral_completion_id UUID,
  p_booking_id UUID
) RETURNS JSONB AS $$
DECLARE
  v_completion RECORD;
  v_referral RECORD;
BEGIN
  -- Get completion
  SELECT * INTO v_completion
  FROM referral_completions
  WHERE id = p_referral_completion_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Referral completion not found');
  END IF;

  -- Get referral
  SELECT * INTO v_referral
  FROM user_referrals
  WHERE id = v_completion.referral_id;

  -- Update completion
  UPDATE referral_completions
  SET first_booking_id = p_booking_id,
      first_booking_completed_at = NOW(),
      referrer_reward_credited = TRUE,
      referrer_reward_credited_at = NOW(),
      status = 'completed',
      updated_at = NOW()
  WHERE id = p_referral_completion_id;

  -- Update referral stats
  UPDATE user_referrals
  SET successful_referrals = successful_referrals + 1,
      total_rewards_earned = total_rewards_earned + referrer_reward_amount,
      updated_at = NOW()
  WHERE id = v_completion.referral_id;

  -- Credit referrer's wallet (add to credits_balance)
  UPDATE user_loyalty
  SET credits_balance = credits_balance + v_referral.referrer_reward_amount,
      updated_at = NOW()
  WHERE user_id = v_referral.referrer_id;

  RETURN jsonb_build_object(
    'success', TRUE,
    'referrer_id', v_referral.referrer_id,
    'reward_amount', v_referral.referrer_reward_amount
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- VIEW: User loyalty summary
-- ============================================

CREATE OR REPLACE VIEW user_loyalty_summary AS
SELECT
  ul.user_id,
  ul.total_bookings,
  ul.total_nights_stayed,
  ul.total_amount_spent,
  ul.loyalty_points,
  ul.credits_balance,
  lt.name AS tier_name,
  lt.level AS tier_level,
  lt.discount_percentage,
  lt.priority_support,
  lt.badge_color,
  lt.icon_name,
  ul.tier_upgraded_at,
  CASE
    WHEN ul.tier_upgraded_at IS NOT NULL
      AND ul.tier_upgraded_at > NOW() - INTERVAL '7 days'
    THEN TRUE
    ELSE FALSE
  END AS recently_upgraded
FROM user_loyalty ul
JOIN loyalty_tiers lt ON lt.id = ul.current_tier_id;

-- Grant access to the view
GRANT SELECT ON user_loyalty_summary TO authenticated;
