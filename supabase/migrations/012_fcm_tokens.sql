-- =============================================
-- FCM Tokens Table for Push Notifications
-- =============================================

-- Table to store user FCM tokens for push notifications
CREATE TABLE IF NOT EXISTS public.fcm_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    device_type TEXT DEFAULT 'android', -- 'android', 'ios', 'web'
    device_name TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    last_used_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE,

    -- Ensure one token per device per user
    UNIQUE(user_id, token)
);

-- Index for quick lookups by user
CREATE INDEX idx_fcm_tokens_user_id ON public.fcm_tokens(user_id);
CREATE INDEX idx_fcm_tokens_active ON public.fcm_tokens(user_id, is_active) WHERE is_active = TRUE;

-- RLS policies
ALTER TABLE public.fcm_tokens ENABLE ROW LEVEL SECURITY;

-- Users can insert their own tokens
CREATE POLICY "Users can insert own fcm tokens"
ON public.fcm_tokens FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Users can view their own tokens
CREATE POLICY "Users can view own fcm tokens"
ON public.fcm_tokens FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Users can update their own tokens
CREATE POLICY "Users can update own fcm tokens"
ON public.fcm_tokens FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Users can delete their own tokens
CREATE POLICY "Users can delete own fcm tokens"
ON public.fcm_tokens FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

-- Service role can read all tokens (for sending notifications)
CREATE POLICY "Service role can read all fcm tokens"
ON public.fcm_tokens FOR SELECT
TO service_role
USING (TRUE);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_fcm_token_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-update timestamp
CREATE TRIGGER fcm_tokens_updated_at
    BEFORE UPDATE ON public.fcm_tokens
    FOR EACH ROW
    EXECUTE FUNCTION update_fcm_token_timestamp();

-- Function to upsert FCM token (insert or update if exists)
CREATE OR REPLACE FUNCTION upsert_fcm_token(
    p_user_id UUID,
    p_token TEXT,
    p_device_type TEXT DEFAULT 'android',
    p_device_name TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO public.fcm_tokens (user_id, token, device_type, device_name)
    VALUES (p_user_id, p_token, p_device_type, p_device_name)
    ON CONFLICT (user_id, token)
    DO UPDATE SET
        is_active = TRUE,
        last_used_at = NOW(),
        updated_at = NOW(),
        device_type = COALESCE(EXCLUDED.device_type, fcm_tokens.device_type),
        device_name = COALESCE(EXCLUDED.device_name, fcm_tokens.device_name)
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION upsert_fcm_token TO authenticated;
