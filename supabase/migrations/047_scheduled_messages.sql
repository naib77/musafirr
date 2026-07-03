-- Migration: Host scheduled messages (Airbnb-style)
--
-- Hosts author message templates with {{variables}} that send automatically:
--   * booking_confirmed — sent by the app when the host accepts
--   * check_in          — sent by pg_cron N days before arrival (this file)
--   * check_out         — sent by the app when the stay completes
--
-- Every host starts with sensible defaults (defined in the app and mirrored
-- here for the cron path); a message_templates row exists only once the host
-- customizes or disables a trigger.

-- ============================================================
-- 1. Templates
-- ============================================================

CREATE TABLE IF NOT EXISTS public.message_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    host_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    trigger TEXT NOT NULL CHECK (trigger IN ('booking_confirmed', 'check_in', 'check_out')),
    content TEXT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    lead_days INTEGER NOT NULL DEFAULT 2 CHECK (lead_days BETWEEN 0 AND 14),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT message_templates_one_per_trigger UNIQUE (host_id, trigger)
);

ALTER TABLE public.message_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Hosts manage own templates" ON public.message_templates
    FOR ALL
    USING (auth.uid() = host_id)
    WITH CHECK (auth.uid() = host_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.message_templates TO authenticated;

-- ============================================================
-- 2. Dedup ledger so the cron sender fires once per booking
-- ============================================================

CREATE TABLE IF NOT EXISTS public.scheduled_message_sends (
    booking_id UUID NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
    trigger TEXT NOT NULL,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (booking_id, trigger)
);

ALTER TABLE public.scheduled_message_sends ENABLE ROW LEVEL SECURITY;
-- No policies: only the SECURITY DEFINER cron function touches this table.

-- ============================================================
-- 3. Pre-check-in sender (runs hourly via pg_cron)
-- ============================================================

CREATE OR REPLACE FUNCTION public.send_pre_checkin_messages()
RETURNS integer AS $$
DECLARE
    sent_count integer := 0;
    rec RECORD;
    v_content TEXT;
    v_enabled BOOLEAN;
    v_lead_days INTEGER;
    v_conv_id UUID;
    v_rendered TEXT;
    v_nights INTEGER;
BEGIN
    FOR rec IN
        SELECT b.id AS booking_id,
               b.tenant_id,
               b.tenant_name,
               b.guest_count,
               b.starts_at,
               b.ends_at,
               COALESCE(b.listing_title, l.title) AS listing_title,
               b.listing_id,
               l.owner_id AS host_id,
               COALESCE(p.full_name, 'Your host') AS host_name
        FROM public.bookings b
        JOIN public.listings l ON l.id = b.listing_id
        LEFT JOIN public.profiles p ON p.id = l.owner_id
        WHERE b.booking_status = 'confirmed'
        AND b.tenant_id IS NOT NULL
        AND b.starts_at > NOW()
        AND NOT EXISTS (
            SELECT 1 FROM public.scheduled_message_sends s
            WHERE s.booking_id = b.id AND s.trigger = 'check_in'
        )
    LOOP
        -- Host's template, or the built-in default (keep the text in sync
        -- with MessageTemplate.defaultContentFor in the app).
        SELECT t.content, t.enabled, t.lead_days
        INTO v_content, v_enabled, v_lead_days
        FROM public.message_templates t
        WHERE t.host_id = rec.host_id AND t.trigger = 'check_in';

        IF NOT FOUND THEN
            v_enabled := TRUE;
            v_lead_days := 2;
            v_content := E'Hi {{guest_name}},\n\n' ||
                'Your check-in at {{listing_title}} is coming up on ' ||
                E'{{check_in_date}}!\n\n' ||
                'Please let me know your expected arrival time, and feel ' ||
                'free to reach out if you have any questions before your ' ||
                E'stay.\n\n' ||
                E'See you soon!\n\n' ||
                E'Thanks,\n{{host_name}}';
        END IF;

        CONTINUE WHEN NOT v_enabled;
        -- Not yet inside the send window.
        CONTINUE WHEN rec.starts_at > NOW() + make_interval(days => v_lead_days);

        v_conv_id := public.get_or_create_conversation(
            rec.tenant_id, rec.host_id, rec.booking_id, rec.listing_id);

        v_nights := GREATEST(1, (rec.ends_at::date - rec.starts_at::date));

        v_rendered := v_content;
        v_rendered := replace(v_rendered, '{{guest_name}}', COALESCE(rec.tenant_name, 'Guest'));
        v_rendered := replace(v_rendered, '{{listing_title}}', COALESCE(rec.listing_title, 'your stay'));
        v_rendered := replace(v_rendered, '{{check_in_date}}', to_char(rec.starts_at, 'FMDay, FMMonth FMDD'));
        v_rendered := replace(v_rendered, '{{check_out_date}}', to_char(rec.ends_at, 'FMDay, FMMonth FMDD'));
        v_rendered := replace(v_rendered, '{{nights}}', v_nights::text);
        v_rendered := replace(v_rendered, '{{guest_count}}', COALESCE(rec.guest_count, 1)::text);
        v_rendered := replace(v_rendered, '{{host_name}}', rec.host_name);

        -- The insert fires the last-message (046) and new-message
        -- notification (045) triggers, so the guest gets the push too.
        INSERT INTO public.messages (conversation_id, sender_id, content, content_type)
        VALUES (v_conv_id, rec.host_id, v_rendered, 'text');

        INSERT INTO public.scheduled_message_sends (booking_id, trigger)
        VALUES (rec.booking_id, 'check_in');

        sent_count := sent_count + 1;
    END LOOP;

    RETURN sent_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================
-- 4. Schedule hourly (same guarded pattern as 018/035)
-- ============================================================

DO $schedule$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        BEGIN
            PERFORM cron.unschedule('send-pre-checkin-messages');
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        PERFORM cron.schedule(
            'send-pre-checkin-messages',
            '30 * * * *',
            'SELECT public.send_pre_checkin_messages()'
        );

        RAISE NOTICE 'Pre-check-in message job scheduled';
    ELSE
        RAISE NOTICE 'pg_cron not available. Trigger send_pre_checkin_messages() via the scheduled-jobs edge function.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Could not schedule cron job: %', SQLERRM;
END $schedule$;

-- Keep updated_at fresh on template edits.
CREATE OR REPLACE FUNCTION public.touch_message_templates_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_message_template_update ON public.message_templates;
CREATE TRIGGER on_message_template_update
    BEFORE UPDATE ON public.message_templates
    FOR EACH ROW
    EXECUTE FUNCTION public.touch_message_templates_updated_at();
