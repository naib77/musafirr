-- =============================================================
-- 056 — Host-selectable language for automated guest messages.
--
-- Adds profiles.message_language ('en' | 'bn'). The Dart send path
-- (BookingConversationService) reads it for the accept/checkout/cancel/
-- check-in-notice messages; this migration teaches the pre-check-in cron the
-- same trick: it renders the check-in message, the "check-in details" block,
-- and the map pin in the host's language.
--
-- Bangla default bodies/labels mirror lib/models/message_template.dart and
-- lib/services/messaging/booking_system_messages.dart — keep them in sync.
-- =============================================================

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS message_language TEXT NOT NULL DEFAULT 'en';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'profiles_message_language_check'
    ) THEN
        ALTER TABLE public.profiles
            ADD CONSTRAINT profiles_message_language_check
            CHECK (message_language IN ('en', 'bn'));
    END IF;
END $$;

-- Localizes the English month/weekday names produced by to_char(...) into
-- Bangla. Digits are left as Western numerals.
CREATE OR REPLACE FUNCTION public._localize_date_bn(d TEXT)
RETURNS TEXT AS $$
    SELECT replace(replace(replace(replace(replace(replace(replace(
           replace(replace(replace(replace(replace(replace(replace(
           replace(replace(replace(replace(replace($1,
           'January', 'জানুয়ারি'), 'February', 'ফেব্রুয়ারি'),
           'March', 'মার্চ'), 'April', 'এপ্রিল'), 'May', 'মে'),
           'June', 'জুন'), 'July', 'জুলাই'), 'August', 'আগস্ট'),
           'September', 'সেপ্টেম্বর'), 'October', 'অক্টোবর'),
           'November', 'নভেম্বর'), 'December', 'ডিসেম্বর'),
           'Sunday', 'রবিবার'), 'Monday', 'সোমবার'), 'Tuesday', 'মঙ্গলবার'),
           'Wednesday', 'বুধবার'), 'Thursday', 'বৃহস্পতিবার'),
           'Friday', 'শুক্রবার'), 'Saturday', 'শনিবার');
$$ LANGUAGE sql IMMUTABLE;

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
    v_lang TEXT;
    v_default_en TEXT;
    v_default_bn TEXT;
    v_ci_date TEXT;
    v_co_date TEXT;
BEGIN
    -- Keep in sync with MessageTemplate.defaultContentFor(checkIn, en).
    v_default_en := E'Hi {{guest_name}},\n\n' ||
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

    -- Keep in sync with MessageTemplate.defaultContentFor(checkIn, bn).
    v_default_bn := E'হ্যালো {{guest_name}},\n\n' ||
        E'{{listing_title}}-এ বুকিং করার জন্য আবারও ধন্যবাদ!\n\n' ||
        '{{check_in_date}} তারিখে সহজ ও ঝামেলাহীন চেক-ইনের জন্য নিচের ' ||
        E'তথ্যগুলো দেখুন।\n\n' ||
        E'ঠিকানা:\n{{listing_address}}\n\n' ||
        'জায়গাটি সহজে খুঁজে পেতে আমি নিচে সঠিক ম্যাপ লোকেশন শেয়ার করছি। ' ||
        'অনুগ্রহ করে আপনার সম্ভাব্য আগমনের সময় জানাবেন, এবং থাকার আগে ' ||
        E'কোনো প্রশ্ন থাকলে নির্দ্বিধায় যোগাযোগ করবেন।\n\n' ||
        E'আশা করি {{listing_title}}-এ আপনার থাকা আনন্দদায়ক হবে!\n\n' ||
        E'ধন্যবাদ,\n{{host_name}}';

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
               COALESCE(p.message_language, 'en') AS message_language,
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
        v_lang := rec.message_language;

        SELECT t.content, t.enabled, t.lead_days
        INTO v_content, v_enabled, v_lead_days
        FROM public.message_templates t
        WHERE t.host_id = rec.host_id AND t.trigger = 'check_in';

        IF NOT FOUND THEN
            v_enabled := TRUE;
            v_lead_days := 2;
            v_content := CASE WHEN v_lang = 'bn' THEN v_default_bn ELSE v_default_en END;
        ELSIF v_content = v_default_en OR v_content = v_default_bn THEN
            -- Un-customized template: follow the host's language (mirrors
            -- MessageTemplate.resolveContent).
            v_content := CASE WHEN v_lang = 'bn' THEN v_default_bn ELSE v_default_en END;
        END IF;

        CONTINUE WHEN NOT v_enabled;
        CONTINUE WHEN rec.starts_at > NOW() + make_interval(days => v_lead_days);

        v_conv_id := public.get_or_create_conversation(
            rec.tenant_id, rec.host_id, rec.booking_id, rec.listing_id);

        v_nights := GREATEST(1, (rec.ends_at::date - rec.starts_at::date));

        -- Unit-aware duration, mirroring Booking.durationLabel in the app.
        IF rec.pricing_unit::text = 'hour' THEN
            v_units := GREATEST(1, FLOOR(EXTRACT(EPOCH FROM (rec.ends_at - rec.starts_at)) / 3600)::int);
            v_duration := v_units || CASE WHEN v_lang = 'bn' THEN ' ঘণ্টা'
                                          WHEN v_units = 1 THEN ' hour' ELSE ' hours' END;
        ELSIF rec.pricing_unit::text = 'month' THEN
            v_units := GREATEST(1, ROUND((rec.ends_at::date - rec.starts_at::date) / 30.0)::int);
            v_duration := v_units || CASE WHEN v_lang = 'bn' THEN ' মাস'
                                          WHEN v_units = 1 THEN ' month' ELSE ' months' END;
        ELSE
            v_duration := v_nights || CASE WHEN v_lang = 'bn' THEN ' রাত'
                                           WHEN v_nights = 1 THEN ' night' ELSE ' nights' END;
        END IF;

        -- Street address, with the city appended only when it's not
        -- already part of the address.
        v_address := NULLIF(TRIM(BOTH ', ' FROM
            COALESCE(rec.listing_address, '') ||
            CASE WHEN rec.listing_city IS NOT NULL
                      AND (rec.listing_address IS NULL
                           OR rec.listing_address NOT ILIKE '%' || rec.listing_city || '%')
                 THEN ', ' || rec.listing_city ELSE '' END), '');

        -- Localized dates (digits stay Western in Bangla).
        v_ci_date := to_char(rec.starts_at, 'FMDay, FMMonth FMDD');
        v_co_date := to_char(rec.ends_at, 'FMDay, FMMonth FMDD');
        IF v_lang = 'bn' THEN
            v_ci_date := public._localize_date_bn(v_ci_date);
            v_co_date := public._localize_date_bn(v_co_date);
        END IF;

        v_rendered := v_content;
        v_rendered := replace(v_rendered, '{{guest_name}}',
            COALESCE(rec.tenant_name, CASE WHEN v_lang = 'bn' THEN 'অতিথি' ELSE 'Guest' END));
        v_rendered := replace(v_rendered, '{{listing_title}}',
            COALESCE(rec.listing_title, CASE WHEN v_lang = 'bn' THEN 'আপনার থাকার জায়গা' ELSE 'your stay' END));
        v_rendered := replace(v_rendered, '{{listing_address}}',
            COALESCE(v_address, rec.listing_title, CASE WHEN v_lang = 'bn' THEN 'লিস্টিং' ELSE 'the listing' END));
        v_rendered := replace(v_rendered, '{{check_in_date}}', v_ci_date);
        v_rendered := replace(v_rendered, '{{check_out_date}}', v_co_date);
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
            v_access := v_access ||
                CASE WHEN v_lang = 'bn' THEN E'\n\n📍 দিকনির্দেশনা:\n' ELSE E'\n\n📍 Directions:\n' END
                || TRIM(rec.ci_directions);
        END IF;
        IF NULLIF(TRIM(rec.ci_wifi_name), '') IS NOT NULL THEN
            v_access := v_access ||
                CASE WHEN v_lang = 'bn' THEN E'\n\n📶 ওয়াই-ফাই: ' ELSE E'\n\n📶 Wi-Fi: ' END
                || TRIM(rec.ci_wifi_name)
                || CASE WHEN NULLIF(TRIM(rec.ci_wifi_password), '') IS NOT NULL
                        THEN (CASE WHEN v_lang = 'bn' THEN E'\nপাসওয়ার্ড: ' ELSE E'\nPassword: ' END)
                             || TRIM(rec.ci_wifi_password) ELSE '' END;
        END IF;
        IF NULLIF(TRIM(rec.ci_access_code), '') IS NOT NULL THEN
            v_access := v_access ||
                CASE WHEN v_lang = 'bn' THEN E'\n\n🔑 দরজা / অ্যাক্সেস কোড: ' ELSE E'\n\n🔑 Door / access code: ' END
                || TRIM(rec.ci_access_code);
        END IF;

        IF v_access <> '' THEN
            INSERT INTO public.messages (conversation_id, sender_id, content, content_type)
            VALUES (v_conv_id, rec.host_id,
                    (CASE WHEN v_lang = 'bn' THEN 'চেক-ইন বিবরণ' ELSE 'Check-in details' END)
                    || v_access, 'text');
        END IF;

        -- The exact map location, Airbnb-style, right after the instructions.
        -- Shape matches the app's LocationMetadata.toJson.
        IF rec.listing_lat IS NOT NULL AND rec.listing_lng IS NOT NULL THEN
            INSERT INTO public.messages
                (conversation_id, sender_id, content, content_type, metadata)
            VALUES (
                v_conv_id,
                rec.host_id,
                COALESCE(v_address, rec.listing_title,
                         CASE WHEN v_lang = 'bn' THEN 'লিস্টিং লোকেশন' ELSE 'Listing location' END),
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
