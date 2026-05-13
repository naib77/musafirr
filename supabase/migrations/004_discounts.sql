-- Migration: 004_discounts.sql
-- Description: Discount system tables for Musafir
-- Created: 2024

-- ============================================
-- ENUM TYPES
-- ============================================

-- Discount types
CREATE TYPE discount_type AS ENUM (
  'percentage',      -- e.g., 10% off
  'fixed_amount',    -- e.g., ৳500 off
  'free_nights'      -- e.g., Stay 7, pay 5
);

-- Discount categories (who created/owns it)
CREATE TYPE discount_category AS ENUM (
  'platform',        -- Platform-wide promotions
  'host',            -- Host-created discounts
  'referral',        -- Referral rewards
  'loyalty',         -- Loyalty tier benefits
  'first_booking',   -- First-time user discount
  'seasonal',        -- Seasonal campaigns
  'flash_sale'       -- Time-limited flash sales
);

-- Discount status
CREATE TYPE discount_status AS ENUM (
  'draft',           -- Not yet active
  'active',          -- Currently active
  'paused',          -- Temporarily paused
  'expired',         -- Past end date
  'exhausted'        -- Usage limit reached
);

-- Stacking behavior
CREATE TYPE stacking_behavior AS ENUM (
  'stackable',       -- Can combine with other discounts
  'exclusive',       -- Cannot combine with others
  'best_only'        -- Only apply if best discount
);

-- ============================================
-- DISCOUNTS TABLE
-- ============================================

CREATE TABLE discounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Basic info
  code VARCHAR(50) UNIQUE,           -- Promo code (null for auto-applied)
  name VARCHAR(255) NOT NULL,
  description TEXT,

  -- Discount configuration
  type discount_type NOT NULL,
  category discount_category NOT NULL,
  status discount_status DEFAULT 'draft',

  -- Value configuration
  value DECIMAL(10, 2) NOT NULL,     -- Percentage (0-100) or fixed amount in BDT
  max_discount_amount DECIMAL(10, 2), -- Cap for percentage discounts
  min_booking_amount DECIMAL(10, 2) DEFAULT 0,

  -- Free nights configuration (for free_nights type)
  free_nights_config JSONB,          -- { "stay": 7, "pay": 5 }

  -- Validity period
  starts_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ends_at TIMESTAMPTZ,

  -- Usage limits
  total_usage_limit INTEGER,         -- Max total uses (null = unlimited)
  per_user_limit INTEGER DEFAULT 1,  -- Max uses per user
  current_usage_count INTEGER DEFAULT 0,

  -- Eligibility rules
  eligible_user_ids UUID[],          -- Specific users (null = all)
  eligible_listing_ids UUID[],       -- Specific listings (null = all)
  eligible_host_ids UUID[],          -- Specific hosts (null = all)
  min_nights INTEGER DEFAULT 1,
  max_nights INTEGER,

  -- New user eligibility
  new_users_only BOOLEAN DEFAULT FALSE,
  first_booking_only BOOLEAN DEFAULT FALSE,

  -- Booking date restrictions
  booking_start_date DATE,           -- Booking must be after this date
  booking_end_date DATE,             -- Booking must be before this date
  check_in_start_date DATE,          -- Check-in must be after this date
  check_in_end_date DATE,            -- Check-in must be before this date

  -- Day of week restrictions (0 = Sunday, 6 = Saturday)
  allowed_check_in_days INTEGER[],   -- e.g., [0, 6] for weekends only

  -- Stacking rules
  stacking_behavior stacking_behavior DEFAULT 'best_only',
  stackable_with_categories discount_category[],
  priority INTEGER DEFAULT 100,      -- Lower = higher priority

  -- Ownership
  created_by UUID REFERENCES auth.users(id),
  host_id UUID REFERENCES auth.users(id), -- For host-created discounts

  -- Metadata
  metadata JSONB DEFAULT '{}',

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  -- Constraints
  CONSTRAINT valid_percentage CHECK (
    type != 'percentage' OR (value >= 0 AND value <= 100)
  ),
  CONSTRAINT valid_fixed_amount CHECK (
    type != 'fixed_amount' OR value > 0
  ),
  CONSTRAINT valid_dates CHECK (
    ends_at IS NULL OR ends_at > starts_at
  )
);

-- ============================================
-- DISCOUNT USAGES TABLE
-- ============================================

CREATE TABLE discount_usages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  discount_id UUID NOT NULL REFERENCES discounts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  booking_id UUID,                   -- REFERENCES bookings(id) when exists

  -- Applied values
  original_amount DECIMAL(10, 2) NOT NULL,
  discount_amount DECIMAL(10, 2) NOT NULL,
  final_amount DECIMAL(10, 2) NOT NULL,

  -- Context
  applied_at TIMESTAMPTZ DEFAULT NOW(),
  listing_id UUID,

  -- For stacked discounts
  stacked_with UUID[],               -- Other discount IDs applied together

  -- Status tracking
  is_reversed BOOLEAN DEFAULT FALSE,
  reversed_at TIMESTAMPTZ,
  reversal_reason TEXT,

  -- Metadata
  metadata JSONB DEFAULT '{}',

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),

  -- Constraints
  CONSTRAINT unique_user_discount_booking UNIQUE (discount_id, user_id, booking_id)
);

-- ============================================
-- USER REFERRALS TABLE
-- ============================================

CREATE TABLE user_referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Referrer (who shared the code)
  referrer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  referral_code VARCHAR(20) NOT NULL UNIQUE,

  -- Referral configuration
  referrer_reward_amount DECIMAL(10, 2) DEFAULT 500.00,  -- ৳500 reward
  referee_discount_amount DECIMAL(10, 2) DEFAULT 500.00, -- ৳500 off first booking

  -- Stats
  total_referrals INTEGER DEFAULT 0,
  successful_referrals INTEGER DEFAULT 0,  -- Completed first booking
  total_rewards_earned DECIMAL(10, 2) DEFAULT 0,

  -- Status
  is_active BOOLEAN DEFAULT TRUE,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- REFERRAL COMPLETIONS TABLE
-- ============================================

CREATE TABLE referral_completions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  referral_id UUID NOT NULL REFERENCES user_referrals(id) ON DELETE CASCADE,
  referee_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Completion tracking
  signed_up_at TIMESTAMPTZ DEFAULT NOW(),
  first_booking_id UUID,
  first_booking_completed_at TIMESTAMPTZ,

  -- Rewards
  referee_discount_applied BOOLEAN DEFAULT FALSE,
  referrer_reward_credited BOOLEAN DEFAULT FALSE,
  referrer_reward_credited_at TIMESTAMPTZ,

  -- Status
  status VARCHAR(20) DEFAULT 'pending', -- pending, discount_used, completed

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  -- Constraints
  CONSTRAINT unique_referee UNIQUE (referee_id)
);

-- ============================================
-- LOYALTY TIERS TABLE
-- ============================================

CREATE TABLE loyalty_tiers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Tier info
  name VARCHAR(50) NOT NULL UNIQUE,
  level INTEGER NOT NULL UNIQUE,     -- 1 = Bronze, 2 = Silver, etc.

  -- Requirements
  min_bookings INTEGER DEFAULT 0,
  min_nights_stayed INTEGER DEFAULT 0,
  min_total_spent DECIMAL(12, 2) DEFAULT 0,

  -- Benefits
  discount_percentage DECIMAL(5, 2) DEFAULT 0,
  priority_support BOOLEAN DEFAULT FALSE,
  free_cancellation_window INTEGER DEFAULT 24, -- Hours
  early_access_hours INTEGER DEFAULT 0,        -- Hours before public

  -- Visual
  badge_color VARCHAR(20),
  icon_name VARCHAR(50),

  -- Metadata
  metadata JSONB DEFAULT '{}',

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- USER LOYALTY TABLE
-- ============================================

CREATE TABLE user_loyalty (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  current_tier_id UUID REFERENCES loyalty_tiers(id),

  -- Progress tracking
  total_bookings INTEGER DEFAULT 0,
  total_nights_stayed INTEGER DEFAULT 0,
  total_amount_spent DECIMAL(12, 2) DEFAULT 0,

  -- Points/credits (optional future use)
  loyalty_points INTEGER DEFAULT 0,
  credits_balance DECIMAL(10, 2) DEFAULT 0,

  -- Tier history
  tier_upgraded_at TIMESTAMPTZ,
  previous_tier_id UUID REFERENCES loyalty_tiers(id),

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- CAMPAIGNS TABLE (for seasonal/flash sales)
-- ============================================

CREATE TABLE campaigns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Campaign info
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(100) NOT NULL UNIQUE,
  description TEXT,

  -- Display
  banner_image_url TEXT,
  banner_title VARCHAR(255),
  banner_subtitle VARCHAR(255),
  highlight_color VARCHAR(20),

  -- Validity
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,

  -- Associated discounts
  discount_ids UUID[],

  -- Targeting
  target_user_segments JSONB,        -- e.g., {"new_users": true, "tier": ["gold"]}
  featured_listing_ids UUID[],

  -- Status
  status VARCHAR(20) DEFAULT 'draft', -- draft, scheduled, active, ended

  -- Display settings
  show_on_home BOOLEAN DEFAULT TRUE,
  show_on_explore BOOLEAN DEFAULT TRUE,
  show_countdown BOOLEAN DEFAULT FALSE,

  -- Metadata
  metadata JSONB DEFAULT '{}',

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- INDEXES
-- ============================================

-- Discounts indexes
CREATE INDEX idx_discounts_code ON discounts(code) WHERE code IS NOT NULL;
CREATE INDEX idx_discounts_status ON discounts(status);
CREATE INDEX idx_discounts_category ON discounts(category);
CREATE INDEX idx_discounts_dates ON discounts(starts_at, ends_at);
CREATE INDEX idx_discounts_host ON discounts(host_id) WHERE host_id IS NOT NULL;
CREATE INDEX idx_discounts_active ON discounts(status, starts_at, ends_at)
  WHERE status = 'active';

-- Discount usages indexes
CREATE INDEX idx_discount_usages_discount ON discount_usages(discount_id);
CREATE INDEX idx_discount_usages_user ON discount_usages(user_id);
CREATE INDEX idx_discount_usages_booking ON discount_usages(booking_id) WHERE booking_id IS NOT NULL;
CREATE INDEX idx_discount_usages_user_discount ON discount_usages(user_id, discount_id);

-- Referrals indexes
CREATE INDEX idx_user_referrals_code ON user_referrals(referral_code);
CREATE INDEX idx_user_referrals_referrer ON user_referrals(referrer_id);
CREATE INDEX idx_referral_completions_referral ON referral_completions(referral_id);
CREATE INDEX idx_referral_completions_referee ON referral_completions(referee_id);

-- Loyalty indexes
CREATE INDEX idx_user_loyalty_user ON user_loyalty(user_id);
CREATE INDEX idx_user_loyalty_tier ON user_loyalty(current_tier_id);

-- Campaigns indexes
CREATE INDEX idx_campaigns_slug ON campaigns(slug);
CREATE INDEX idx_campaigns_status ON campaigns(status);
CREATE INDEX idx_campaigns_dates ON campaigns(starts_at, ends_at);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

ALTER TABLE discounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE discount_usages ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE referral_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE loyalty_tiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_loyalty ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaigns ENABLE ROW LEVEL SECURITY;

-- Discounts: Public can view active discounts, hosts can manage their own
CREATE POLICY "Anyone can view active public discounts"
  ON discounts FOR SELECT
  USING (
    status = 'active'
    AND starts_at <= NOW()
    AND (ends_at IS NULL OR ends_at > NOW())
    AND (host_id IS NULL OR host_id = auth.uid())
  );

CREATE POLICY "Hosts can manage their own discounts"
  ON discounts FOR ALL
  USING (host_id = auth.uid())
  WITH CHECK (host_id = auth.uid() AND category = 'host');

CREATE POLICY "Admins can manage all discounts"
  ON discounts FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND is_admin = TRUE
    )
  );

-- Discount usages: Users can view their own
CREATE POLICY "Users can view their own discount usages"
  ON discount_usages FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "System can create discount usages"
  ON discount_usages FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- User referrals: Users can view and manage their own
CREATE POLICY "Users can view their own referral"
  ON user_referrals FOR SELECT
  USING (referrer_id = auth.uid());

CREATE POLICY "Users can create their referral"
  ON user_referrals FOR INSERT
  WITH CHECK (referrer_id = auth.uid());

CREATE POLICY "Anyone can view referral codes for validation"
  ON user_referrals FOR SELECT
  USING (is_active = TRUE);

-- Referral completions: Limited access
CREATE POLICY "Referrers can view their referral completions"
  ON referral_completions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM user_referrals
      WHERE id = referral_completions.referral_id
      AND referrer_id = auth.uid()
    )
  );

CREATE POLICY "System can manage referral completions"
  ON referral_completions FOR ALL
  USING (referee_id = auth.uid());

-- Loyalty tiers: Public read
CREATE POLICY "Anyone can view loyalty tiers"
  ON loyalty_tiers FOR SELECT
  USING (TRUE);

-- User loyalty: Users can view their own
CREATE POLICY "Users can view their own loyalty"
  ON user_loyalty FOR SELECT
  USING (user_id = auth.uid());

-- Campaigns: Public read for active
CREATE POLICY "Anyone can view active campaigns"
  ON campaigns FOR SELECT
  USING (
    status = 'active'
    AND starts_at <= NOW()
    AND ends_at > NOW()
  );

-- ============================================
-- FUNCTIONS
-- ============================================

-- Function to check if a discount is valid
CREATE OR REPLACE FUNCTION is_discount_valid(
  p_discount_id UUID,
  p_user_id UUID,
  p_booking_amount DECIMAL,
  p_nights INTEGER,
  p_check_in_date DATE,
  p_listing_id UUID DEFAULT NULL,
  p_host_id UUID DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
  v_discount RECORD;
  v_usage_count INTEGER;
  v_result JSONB;
BEGIN
  -- Get discount
  SELECT * INTO v_discount FROM discounts WHERE id = p_discount_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', FALSE, 'reason', 'Discount not found');
  END IF;

  -- Check status
  IF v_discount.status != 'active' THEN
    RETURN jsonb_build_object('valid', FALSE, 'reason', 'Discount is not active');
  END IF;

  -- Check dates
  IF v_discount.starts_at > NOW() THEN
    RETURN jsonb_build_object('valid', FALSE, 'reason', 'Discount has not started yet');
  END IF;

  IF v_discount.ends_at IS NOT NULL AND v_discount.ends_at < NOW() THEN
    RETURN jsonb_build_object('valid', FALSE, 'reason', 'Discount has expired');
  END IF;

  -- Check total usage limit
  IF v_discount.total_usage_limit IS NOT NULL
     AND v_discount.current_usage_count >= v_discount.total_usage_limit THEN
    RETURN jsonb_build_object('valid', FALSE, 'reason', 'Discount usage limit reached');
  END IF;

  -- Check per-user limit
  IF v_discount.per_user_limit IS NOT NULL THEN
    SELECT COUNT(*) INTO v_usage_count
    FROM discount_usages
    WHERE discount_id = p_discount_id
      AND user_id = p_user_id
      AND is_reversed = FALSE;

    IF v_usage_count >= v_discount.per_user_limit THEN
      RETURN jsonb_build_object('valid', FALSE, 'reason', 'You have already used this discount');
    END IF;
  END IF;

  -- Check minimum booking amount
  IF p_booking_amount < v_discount.min_booking_amount THEN
    RETURN jsonb_build_object(
      'valid', FALSE,
      'reason', format('Minimum booking amount is ৳%s', v_discount.min_booking_amount)
    );
  END IF;

  -- Check minimum nights
  IF p_nights < v_discount.min_nights THEN
    RETURN jsonb_build_object(
      'valid', FALSE,
      'reason', format('Minimum stay is %s nights', v_discount.min_nights)
    );
  END IF;

  -- Check maximum nights
  IF v_discount.max_nights IS NOT NULL AND p_nights > v_discount.max_nights THEN
    RETURN jsonb_build_object(
      'valid', FALSE,
      'reason', format('Maximum stay is %s nights', v_discount.max_nights)
    );
  END IF;

  -- Check eligible users
  IF v_discount.eligible_user_ids IS NOT NULL
     AND NOT (p_user_id = ANY(v_discount.eligible_user_ids)) THEN
    RETURN jsonb_build_object('valid', FALSE, 'reason', 'You are not eligible for this discount');
  END IF;

  -- Check eligible listings
  IF v_discount.eligible_listing_ids IS NOT NULL
     AND p_listing_id IS NOT NULL
     AND NOT (p_listing_id = ANY(v_discount.eligible_listing_ids)) THEN
    RETURN jsonb_build_object('valid', FALSE, 'reason', 'This discount is not valid for this listing');
  END IF;

  -- Check eligible hosts
  IF v_discount.eligible_host_ids IS NOT NULL
     AND p_host_id IS NOT NULL
     AND NOT (p_host_id = ANY(v_discount.eligible_host_ids)) THEN
    RETURN jsonb_build_object('valid', FALSE, 'reason', 'This discount is not valid for this host');
  END IF;

  -- Check check-in date restrictions
  IF v_discount.check_in_start_date IS NOT NULL
     AND p_check_in_date < v_discount.check_in_start_date THEN
    RETURN jsonb_build_object('valid', FALSE, 'reason', 'Check-in date is too early for this discount');
  END IF;

  IF v_discount.check_in_end_date IS NOT NULL
     AND p_check_in_date > v_discount.check_in_end_date THEN
    RETURN jsonb_build_object('valid', FALSE, 'reason', 'Check-in date is too late for this discount');
  END IF;

  -- Check day of week restrictions
  IF v_discount.allowed_check_in_days IS NOT NULL
     AND NOT (EXTRACT(DOW FROM p_check_in_date)::INTEGER = ANY(v_discount.allowed_check_in_days)) THEN
    RETURN jsonb_build_object('valid', FALSE, 'reason', 'This discount is not valid for this check-in day');
  END IF;

  -- All checks passed
  RETURN jsonb_build_object(
    'valid', TRUE,
    'discount', jsonb_build_object(
      'id', v_discount.id,
      'name', v_discount.name,
      'type', v_discount.type,
      'value', v_discount.value,
      'max_discount_amount', v_discount.max_discount_amount,
      'stacking_behavior', v_discount.stacking_behavior
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to calculate discount amount
CREATE OR REPLACE FUNCTION calculate_discount_amount(
  p_discount_id UUID,
  p_booking_amount DECIMAL,
  p_nights INTEGER
) RETURNS DECIMAL AS $$
DECLARE
  v_discount RECORD;
  v_amount DECIMAL;
BEGIN
  SELECT * INTO v_discount FROM discounts WHERE id = p_discount_id;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  CASE v_discount.type
    WHEN 'percentage' THEN
      v_amount := p_booking_amount * (v_discount.value / 100);
      -- Apply max cap if set
      IF v_discount.max_discount_amount IS NOT NULL
         AND v_amount > v_discount.max_discount_amount THEN
        v_amount := v_discount.max_discount_amount;
      END IF;

    WHEN 'fixed_amount' THEN
      v_amount := v_discount.value;
      -- Don't exceed booking amount
      IF v_amount > p_booking_amount THEN
        v_amount := p_booking_amount;
      END IF;

    WHEN 'free_nights' THEN
      -- Calculate free nights discount
      IF v_discount.free_nights_config IS NOT NULL THEN
        DECLARE
          v_stay INTEGER := (v_discount.free_nights_config->>'stay')::INTEGER;
          v_pay INTEGER := (v_discount.free_nights_config->>'pay')::INTEGER;
          v_free_nights INTEGER;
          v_per_night_rate DECIMAL;
        BEGIN
          IF p_nights >= v_stay THEN
            v_free_nights := v_stay - v_pay;
            v_per_night_rate := p_booking_amount / p_nights;
            v_amount := v_free_nights * v_per_night_rate;
          ELSE
            v_amount := 0;
          END IF;
        END;
      ELSE
        v_amount := 0;
      END IF;
  END CASE;

  RETURN COALESCE(v_amount, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to apply a discount
CREATE OR REPLACE FUNCTION apply_discount(
  p_discount_id UUID,
  p_user_id UUID,
  p_booking_id UUID,
  p_listing_id UUID,
  p_original_amount DECIMAL,
  p_nights INTEGER
) RETURNS JSONB AS $$
DECLARE
  v_discount_amount DECIMAL;
  v_final_amount DECIMAL;
  v_usage_id UUID;
BEGIN
  -- Calculate discount amount
  v_discount_amount := calculate_discount_amount(p_discount_id, p_original_amount, p_nights);
  v_final_amount := p_original_amount - v_discount_amount;

  -- Create usage record
  INSERT INTO discount_usages (
    discount_id, user_id, booking_id, listing_id,
    original_amount, discount_amount, final_amount
  ) VALUES (
    p_discount_id, p_user_id, p_booking_id, p_listing_id,
    p_original_amount, v_discount_amount, v_final_amount
  ) RETURNING id INTO v_usage_id;

  -- Increment usage count
  UPDATE discounts
  SET current_usage_count = current_usage_count + 1,
      updated_at = NOW()
  WHERE id = p_discount_id;

  RETURN jsonb_build_object(
    'success', TRUE,
    'usage_id', v_usage_id,
    'discount_amount', v_discount_amount,
    'final_amount', v_final_amount
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to generate unique referral code
CREATE OR REPLACE FUNCTION generate_referral_code(p_user_id UUID)
RETURNS TEXT AS $$
DECLARE
  v_code TEXT;
  v_exists BOOLEAN;
  v_name TEXT;
BEGIN
  -- Get user's name for personalized code
  SELECT UPPER(SUBSTRING(COALESCE(full_name, 'USER') FROM 1 FOR 4))
  INTO v_name
  FROM profiles
  WHERE id = p_user_id;

  -- Generate unique code
  LOOP
    v_code := v_name || UPPER(SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 4));

    SELECT EXISTS(SELECT 1 FROM user_referrals WHERE referral_code = v_code)
    INTO v_exists;

    EXIT WHEN NOT v_exists;
  END LOOP;

  RETURN v_code;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- TRIGGERS
-- ============================================

-- Update timestamps
CREATE OR REPLACE FUNCTION update_discount_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_discounts_timestamp
  BEFORE UPDATE ON discounts
  FOR EACH ROW EXECUTE FUNCTION update_discount_timestamp();

CREATE TRIGGER update_user_referrals_timestamp
  BEFORE UPDATE ON user_referrals
  FOR EACH ROW EXECUTE FUNCTION update_discount_timestamp();

CREATE TRIGGER update_user_loyalty_timestamp
  BEFORE UPDATE ON user_loyalty
  FOR EACH ROW EXECUTE FUNCTION update_discount_timestamp();

CREATE TRIGGER update_campaigns_timestamp
  BEFORE UPDATE ON campaigns
  FOR EACH ROW EXECUTE FUNCTION update_discount_timestamp();

-- Auto-update discount status based on dates
CREATE OR REPLACE FUNCTION check_discount_status()
RETURNS TRIGGER AS $$
BEGIN
  -- Check if expired
  IF NEW.ends_at IS NOT NULL AND NEW.ends_at < NOW() AND NEW.status = 'active' THEN
    NEW.status := 'expired';
  END IF;

  -- Check if exhausted
  IF NEW.total_usage_limit IS NOT NULL
     AND NEW.current_usage_count >= NEW.total_usage_limit
     AND NEW.status = 'active' THEN
    NEW.status := 'exhausted';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_discount_status_trigger
  BEFORE UPDATE ON discounts
  FOR EACH ROW EXECUTE FUNCTION check_discount_status();

-- ============================================
-- SEED DATA: Loyalty Tiers
-- ============================================

INSERT INTO loyalty_tiers (name, level, min_bookings, min_nights_stayed, min_total_spent, discount_percentage, priority_support, free_cancellation_window, early_access_hours, badge_color, icon_name) VALUES
  ('Bronze', 1, 0, 0, 0, 0, FALSE, 24, 0, '#CD7F32', 'star_border'),
  ('Silver', 2, 3, 10, 15000, 3, FALSE, 48, 12, '#C0C0C0', 'star_half'),
  ('Gold', 3, 7, 25, 50000, 5, TRUE, 72, 24, '#FFD700', 'star'),
  ('Platinum', 4, 15, 50, 150000, 8, TRUE, 168, 48, '#E5E4E2', 'workspace_premium')
ON CONFLICT (name) DO NOTHING;

-- ============================================
-- SEED DATA: Sample Platform Discounts
-- ============================================

INSERT INTO discounts (code, name, description, type, category, status, value, min_booking_amount, min_nights, starts_at, per_user_limit, stacking_behavior) VALUES
  ('WELCOME500', 'Welcome Discount', 'Get ৳500 off your first booking!', 'fixed_amount', 'first_booking', 'active', 500, 2000, 1, NOW(), 1, 'stackable'),
  ('EARLYBIRD10', 'Early Bird Discount', '10% off when you book 30+ days in advance', 'percentage', 'platform', 'active', 10, 5000, 2, NOW(), NULL, 'best_only'),
  ('LONGSTAY15', 'Long Stay Discount', '15% off for stays of 7+ nights', 'percentage', 'platform', 'active', 15, 10000, 7, NOW(), NULL, 'stackable'),
  ('WEEKEND20', 'Weekend Special', '20% off weekend stays (max ৳2000)', 'percentage', 'seasonal', 'active', 20, 3000, 2, NOW(), 2, 'exclusive')
ON CONFLICT (code) DO NOTHING;

-- Update WEEKEND20 to only allow Friday-Sunday check-ins
UPDATE discounts
SET allowed_check_in_days = ARRAY[5, 6, 0]
WHERE code = 'WEEKEND20';
