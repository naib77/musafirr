-- =============================================================
-- 054 — Include the host's private check-in access details in the
-- pre-check-in message.
--
-- 053 lets hosts store directions / Wi-Fi / door code in the host-only
-- listing_checkin_details table. This wires that data into the automated
-- pre-check-in flow: after the welcome/instructions text and before the map
-- pin, the guest now receives a "check-in details" message containing only
-- the fields the host actually filled in. The cron runs SECURITY DEFINER, so
-- it can read the RLS-protected table on the guest's behalf.
--
-- Also exposes {{wifi_name}}, {{wifi_password}}, {{access_code}} and
-- {{directions}} as template variables for hosts who want them inline.
-- =============================================================

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
    v_address TEXT;
    v_access TEXT;
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
               l.address AS listing_address,
               l.city AS listing_city,
               l.latitude AS listing_lat,
               l.longitude AS listing_lng,
               l.owner_id AS host_id,
               COALESCE(p.full_name, 'Your host') AS host_name,
               cd.directions AS ci_directions,
               cd.wifi_name AS ci_wifi_name,
               cd.wifi_password AS ci_wifi_password,
               cd.access_code AS ci_access_code
        FROM public.bookings b
        JOIN public.listings l ON l.id = b.listing_id
        LEFT JOIN public.profiles p ON p.id = l.owner_id
        LEFT JOIN public.listing_checkin_details cd ON cd.listing_id = b.listing_id
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
            -- Keep in sync with MessageTemplate.defaultContentFor(checkIn).
            v_content := E'Hi {{guest_name}},\n\n' ||
                E'Thanks again for booking at {{listing_title}}!\n\n' ||
                'Please find the details below for a smooth and seamless ' ||
                E'check-in on {{check_in_date}}.\n\n' ||
                E'Address:\n{{listing_address}}\n\n' ||
                'I am sharing the exact map location below so you can find ' ||
                'the place easily. Please let me know your expected arrival ' ||
                'time, and feel free to reach out if you have any questions ' ||
                E'before your stay.\n\n' ||
                'I hope you will have an enjoyable stay at ' ||
                E'{{listing_title}}!\n\n' ||
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

        -- Street address, with the city appended only when it's not
        -- already part of the address.
        v_address := NULLIF(TRIM(BOTH ', ' FROM
            COALESCE(rec.listing_address, '') ||
            CASE WHEN rec.listing_city IS NOT NULL
                      AND (rec.listing_address IS NULL
                           OR rec.listing_address NOT ILIKE '%' || rec.listing_city || '%')
                 THEN ', ' || rec.listing_city ELSE '' END), '');

        v_rendered := v_content;
        v_rendered := replace(v_rendered, '{{guest_name}}', COALESCE(rec.tenant_name, 'Guest'));
        v_rendered := replace(v_rendered, '{{listing_title}}', COALESCE(rec.listing_title, 'your stay'));
        v_rendered := replace(v_rendered, '{{listing_address}}', COALESCE(v_address, rec.listing_title, 'the listing'));
        v_rendered := replace(v_rendered, '{{check_in_date}}', to_char(rec.starts_at, 'FMDay, FMMonth FMDD'));
        v_rendered := replace(v_rendered, '{{check_out_date}}', to_char(rec.ends_at, 'FMDay, FMMonth FMDD'));
        v_rendered := replace(v_rendered, '{{duration}}', v_duration);
        v_rendered := replace(v_rendered, '{{nights}}', v_nights::text);
        v_rendered := replace(v_rendered, '{{guest_count}}', COALESCE(rec.guest_count, 1)::text);
        v_rendered := replace(v_rendered, '{{host_name}}', rec.host_name);
        -- Optional inline access variables (empty when the host left them blank).
        v_rendered := replace(v_rendered, '{{directions}}', COALESCE(rec.ci_directions, ''));
        v_rendered := replace(v_rendered, '{{wifi_name}}', COALESCE(rec.ci_wifi_name, ''));
        v_rendered := replace(v_rendered, '{{wifi_password}}', COALESCE(rec.ci_wifi_password, ''));
        v_rendered := replace(v_rendered, '{{access_code}}', COALESCE(rec.ci_access_code, ''));

        INSERT INTO public.messages (conversation_id, sender_id, content, content_type)
        VALUES (v_conv_id, rec.host_id, v_rendered, 'text');

        -- Build a "check-in details" block from whatever the host provided.
        -- Only non-empty fields appear, so a host who filled in nothing gets
        -- no extra message.
        v_access := '';
        IF NULLIF(TRIM(rec.ci_directions), '') IS NOT NULL THEN
            v_access := v_access || E'\n\n📍 Directions:\n' || TRIM(rec.ci_directions);
        END IF;
        IF NULLIF(TRIM(rec.ci_wifi_name), '') IS NOT NULL THEN
            v_access := v_access || E'\n\n📶 Wi-Fi: ' || TRIM(rec.ci_wifi_name)
                || CASE WHEN NULLIF(TRIM(rec.ci_wifi_password), '') IS NOT NULL
                        THEN E'\nPassword: ' || TRIM(rec.ci_wifi_password) ELSE '' END;
        END IF;
        IF NULLIF(TRIM(rec.ci_access_code), '') IS NOT NULL THEN
            v_access := v_access || E'\n\n🔑 Door / access code: ' || TRIM(rec.ci_access_code);
        END IF;

        IF v_access <> '' THEN
            INSERT INTO public.messages (conversation_id, sender_id, content, content_type)
            VALUES (v_conv_id, rec.host_id,
                    'Check-in details' || v_access, 'text');
        END IF;

        -- The exact map location, Airbnb-style, right after the instructions.
        -- Shape matches the app's LocationMetadata.toJson.
        IF rec.listing_lat IS NOT NULL AND rec.listing_lng IS NOT NULL THEN
            INSERT INTO public.messages
                (conversation_id, sender_id, content, content_type, metadata)
            VALUES (
                v_conv_id,
                rec.host_id,
                COALESCE(v_address, rec.listing_title, 'Listing location'),
                'location',
                jsonb_build_object(
                    'latitude', rec.listing_lat,
                    'longitude', rec.listing_lng,
                    'address', v_address,
                    'place_name', rec.listing_title
                )
            );
        END IF;

        INSERT INTO public.scheduled_message_sends (booking_id, trigger)
        VALUES (rec.booking_id, 'check_in');

        sent_count := sent_count + 1;
    END LOOP;

    RETURN sent_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
