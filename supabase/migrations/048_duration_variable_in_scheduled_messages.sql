-- Migration: {{duration}} variable in scheduled messages
--
-- Hourly bookings rendered as "1 night(s)" in scheduled messages. The app's
-- templates now use {{duration}} — a unit-aware length of stay ("2 hours" /
-- "7 nights" / "1 month", mirroring Booking.durationLabel). Teach the cron
-- pre-check-in sender the same variable.

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
    v_units INTEGER;
    v_duration TEXT;
BEGIN
    FOR rec IN
        SELECT b.id AS booking_id,
               b.tenant_id,
               b.tenant_name,
               b.guest_count,
               b.starts_at,
               b.ends_at,
               b.pricing_unit,
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
        CONTINUE WHEN rec.starts_at > NOW() + make_interval(days => v_lead_days);

        v_conv_id := public.get_or_create_conversation(
            rec.tenant_id, rec.host_id, rec.booking_id, rec.listing_id);

        v_nights := GREATEST(1, (rec.ends_at::date - rec.starts_at::date));

        -- Unit-aware duration, mirroring Booking.durationLabel in the app.
        IF rec.pricing_unit::text = 'hour' THEN
            v_units := GREATEST(1, FLOOR(EXTRACT(EPOCH FROM (rec.ends_at - rec.starts_at)) / 3600)::int);
            v_duration := v_units || CASE WHEN v_units = 1 THEN ' hour' ELSE ' hours' END;
        ELSIF rec.pricing_unit::text = 'month' THEN
            v_units := GREATEST(1, ROUND((rec.ends_at::date - rec.starts_at::date) / 30.0)::int);
            v_duration := v_units || CASE WHEN v_units = 1 THEN ' month' ELSE ' months' END;
        ELSE
            v_duration := v_nights || CASE WHEN v_nights = 1 THEN ' night' ELSE ' nights' END;
        END IF;

        v_rendered := v_content;
        v_rendered := replace(v_rendered, '{{guest_name}}', COALESCE(rec.tenant_name, 'Guest'));
        v_rendered := replace(v_rendered, '{{listing_title}}', COALESCE(rec.listing_title, 'your stay'));
        v_rendered := replace(v_rendered, '{{check_in_date}}', to_char(rec.starts_at, 'FMDay, FMMonth FMDD'));
        v_rendered := replace(v_rendered, '{{check_out_date}}', to_char(rec.ends_at, 'FMDay, FMMonth FMDD'));
        v_rendered := replace(v_rendered, '{{duration}}', v_duration);
        v_rendered := replace(v_rendered, '{{nights}}', v_nights::text);
        v_rendered := replace(v_rendered, '{{guest_count}}', COALESCE(rec.guest_count, 1)::text);
        v_rendered := replace(v_rendered, '{{host_name}}', rec.host_name);

        INSERT INTO public.messages (conversation_id, sender_id, content, content_type)
        VALUES (v_conv_id, rec.host_id, v_rendered, 'text');

        INSERT INTO public.scheduled_message_sends (booking_id, trigger)
        VALUES (rec.booking_id, 'check_in');

        sent_count := sent_count + 1;
    END LOOP;

    RETURN sent_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
