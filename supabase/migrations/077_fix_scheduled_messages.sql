-- Migration 077: Fix automated check-in / check-out guest messages
--
-- Three defects were causing "Before check-in" / "After checkout" messages not
-- to reach guests even with the toggles ON:
--
--   1. REGRESSION (root cause of "no check-in message"): migration 075 hardened
--      get_or_create_conversation with an `auth.uid()` participant check that
--      raises 'Not authorized'. The hourly pre-check-in cron runs as `postgres`
--      with NO JWT, so auth.uid() is NULL and EVERY run since 075 failed with
--      "Not authorized" (verified in cron.job_run_details). Fix: only enforce
--      membership when a user is actually authenticated. A NULL auth.uid() is a
--      trusted server/cron context — and anon has no EXECUTE on this function
--      (075 revoked it), so this cannot be reached unauthenticated.
--
--   2. "On arrival day" (lead_days = 0) never sent: send_pre_checkin_messages
--      only considered bookings with `starts_at > NOW()`, while the per-booking
--      window guard skips while `starts_at > NOW() + lead_days`. At lead_days=0
--      those two are mutually exclusive, so nothing was ever sent. Broaden the
--      candidate filter to `ends_at > NOW()` (stay not fully over) so arrival-day
--      sends are possible; the per-booking guard still prevents early sends.
--
--   3. "After checkout" never sent on auto-completion: the checkout template was
--      only sent by the app's manual "Complete service" path
--      (onBookingCompleted). Stays that the host never manually completes are
--      finalized by auto_complete_elapsed_bookings(), which never sent the
--      checkout message. Add send_checkout_for_booking() and call it from the
--      auto-complete loop (dedup + defensive so a bad template can't break the
--      whole job — the lesson from defect #1).

-- ============================================================
-- 1. get_or_create_conversation — allow trusted server/cron callers
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_or_create_conversation(
    user_one uuid, user_two uuid,
    p_booking_id uuid DEFAULT NULL::uuid, p_listing_id uuid DEFAULT NULL::uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  conv_id uuid;
begin
  -- Enforce participant membership ONLY for a real authenticated user. A NULL
  -- auth.uid() means a trusted SECURITY DEFINER / cron caller (anon has no
  -- EXECUTE grant, so it can never reach here unauthenticated).
  if auth.uid() is not null and auth.uid() not in (user_one, user_two) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  select id into conv_id from public.conversations
  where least(participant_one_id, participant_two_id) = least(user_one, user_two)
    and greatest(participant_one_id, participant_two_id) = greatest(user_one, user_two)
  limit 1;

  if conv_id is null then
    insert into public.conversations (participant_one_id, participant_two_id, booking_id, listing_id)
    values (user_one, user_two, p_booking_id, p_listing_id)
    returning id into conv_id;
  elsif p_booking_id is not null or p_listing_id is not null then
    -- The single thread follows the latest booking/listing context.
    update public.conversations
    set booking_id = coalesce(p_booking_id, booking_id),
        listing_id = coalesce(p_listing_id, listing_id),
        status = 'active',
        updated_at = now()
    where id = conv_id;
  end if;

  return conv_id;
end;
$function$;

-- ============================================================
-- 2. send_pre_checkin_messages — fix lead_days=0 + per-booking resilience
-- ============================================================
CREATE OR REPLACE FUNCTION public.send_pre_checkin_messages()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    sent_count integer := 0;
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT b.id AS booking_id
        FROM public.bookings b
        WHERE b.booking_status = 'confirmed'
          AND b.tenant_id IS NOT NULL
          -- Candidate while the stay is not fully over. The per-booking window
          -- guard inside send_precheckin_for_booking enforces "not too early";
          -- using ends_at (not starts_at) is what lets lead_days=0 fire.
          AND b.ends_at > NOW()
          AND NOT EXISTS (
              SELECT 1 FROM public.scheduled_message_sends s
              WHERE s.booking_id = b.id AND s.trigger = 'check_in'
          )
    LOOP
        -- Isolate each booking: one bad render must not abort the whole run
        -- (defect #1 was exactly a single-call error cascading to every booking).
        BEGIN
            PERFORM public.send_precheckin_for_booking(rec.booking_id);
            sent_count := sent_count + 1;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'pre-checkin message failed for booking %: %', rec.booking_id, SQLERRM;
        END;
    END LOOP;
    RETURN sent_count;
END;
$function$;

-- ============================================================
-- 3a. send_checkout_for_booking — the "After checkout" template sender
--     Mirrors send_precheckin_for_booking's rendering. Idempotent per booking.
-- ============================================================
CREATE OR REPLACE FUNCTION public.send_checkout_for_booking(p_booking_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    rec RECORD;
    v_content TEXT;
    v_enabled BOOLEAN;
    v_conv_id UUID;
    v_rendered TEXT;
    v_nights INTEGER;
    v_units INTEGER;
    v_duration TEXT;
    v_lang TEXT;
    v_default_en TEXT;
    v_default_bn TEXT;
    v_ci_date TEXT;
    v_co_date TEXT;
BEGIN
    SELECT b.id AS booking_id, b.tenant_id, b.tenant_name, b.guest_count,
           b.starts_at, b.ends_at, b.pricing_unit,
           COALESCE(b.listing_title, l.title) AS listing_title,
           b.listing_id, l.owner_id AS host_id,
           COALESCE(p.full_name, 'Your host') AS host_name,
           COALESCE(p.message_language, 'en') AS message_language
    INTO rec
    FROM public.bookings b
    JOIN public.listings l ON l.id = b.listing_id
    LEFT JOIN public.profiles p ON p.id = l.owner_id
    WHERE b.id = p_booking_id AND b.tenant_id IS NOT NULL;

    IF NOT FOUND THEN RETURN; END IF;

    -- Deliver once per booking.
    IF EXISTS (SELECT 1 FROM public.scheduled_message_sends s
               WHERE s.booking_id = rec.booking_id AND s.trigger = 'check_out') THEN
        RETURN;
    END IF;

    v_lang := rec.message_language;

    -- Keep in sync with MessageTemplate.defaultContentFor(checkOut, en).
    v_default_en := E'Hi {{guest_name}},\n\n' ||
        'Thanks for staying at {{listing_title}} — I hope you enjoyed ' ||
        E'your visit! You are welcome back anytime.\n\n' ||
        E'Safe travels!\n\n' ||
        E'Thanks,\n{{host_name}}';
    -- Keep in sync with MessageTemplate.defaultContentFor(checkOut, bn).
    v_default_bn := E'হ্যালো {{guest_name}},\n\n' ||
        '{{listing_title}}-এ থাকার জন্য ধন্যবাদ — আশা করি আপনার সময়টা ' ||
        E'ভালো কেটেছে! আপনি যেকোনো সময় আবার স্বাগত।\n\n' ||
        E'শুভ যাত্রা!\n\n' ||
        E'ধন্যবাদ,\n{{host_name}}';

    SELECT t.content, t.enabled
    INTO v_content, v_enabled
    FROM public.message_templates t
    WHERE t.host_id = rec.host_id AND t.trigger = 'check_out';

    IF NOT FOUND THEN
        v_enabled := TRUE;
        v_content := CASE WHEN v_lang = 'bn' THEN v_default_bn ELSE v_default_en END;
    ELSIF v_content = v_default_en OR v_content = v_default_bn THEN
        -- Host stored an un-customized default; render it in their language.
        v_content := CASE WHEN v_lang = 'bn' THEN v_default_bn ELSE v_default_en END;
    END IF;

    IF NOT v_enabled THEN RETURN; END IF;

    v_conv_id := public.get_or_create_conversation(
        rec.tenant_id, rec.host_id, rec.booking_id, rec.listing_id);

    v_nights := GREATEST(1, (rec.ends_at::date - rec.starts_at::date));
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
    v_rendered := replace(v_rendered, '{{check_in_date}}', v_ci_date);
    v_rendered := replace(v_rendered, '{{check_out_date}}', v_co_date);
    v_rendered := replace(v_rendered, '{{duration}}', v_duration);
    v_rendered := replace(v_rendered, '{{nights}}', v_nights::text);
    v_rendered := replace(v_rendered, '{{guest_count}}', COALESCE(rec.guest_count, 1)::text);
    v_rendered := replace(v_rendered, '{{host_name}}', rec.host_name);

    INSERT INTO public.messages (conversation_id, sender_id, content, content_type)
    VALUES (v_conv_id, rec.host_id, v_rendered, 'text');

    INSERT INTO public.scheduled_message_sends (booking_id, trigger)
    VALUES (rec.booking_id, 'check_out');
END;
$function$;

GRANT EXECUTE ON FUNCTION public.send_checkout_for_booking(uuid) TO postgres, service_role;

-- ============================================================
-- 3b. auto_complete_elapsed_bookings — send the checkout message on completion
--     Body preserved from live; only adds the (defensive) checkout send.
-- ============================================================
CREATE OR REPLACE FUNCTION public.auto_complete_elapsed_bookings()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    completed_count integer;
    booking_record RECORD;
    listing_record RECORD;
    guest_record RECORD;
BEGIN
    completed_count := 0;

    FOR booking_record IN
        SELECT b.*
        FROM public.bookings b
        WHERE b.booking_status IN ('confirmed', 'active')
        AND b.ends_at < NOW() - INTERVAL '24 hours'
    LOOP
        -- Presume the stay happened: move to completed and stamp completed_at.
        UPDATE public.bookings
        SET
            booking_status = 'completed',
            completed_at = NOW()
        WHERE id = booking_record.id;

        -- Send the host's "After checkout" template to the guest. Auto-complete
        -- is the ONLY completion path for stays the host never marks done, so
        -- without this the checkout message never fires. Defensive: a bad
        -- template must not abort the whole completion job.
        BEGIN
            PERFORM public.send_checkout_for_booking(booking_record.id);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'checkout message failed for booking %: %', booking_record.id, SQLERRM;
        END;

        -- Listing info for notifications
        SELECT l.title, l.owner_id INTO listing_record
        FROM public.listings l
        WHERE l.id = booking_record.listing_id;

        -- Guest info
        SELECT p.full_name INTO guest_record
        FROM public.profiles p
        WHERE p.id = booking_record.tenant_id;

        -- Nudge the guest to leave a review (opens the review window)
        INSERT INTO public.notifications (
            user_id, type, title, body, priority, action_url, data
        ) VALUES (
            booking_record.tenant_id,
            'review_prompt'::notification_type,
            'How was your stay?',
            format('Your stay at %s is complete. Leave a review to help other travelers!',
                COALESCE(listing_record.title, 'the property')),
            'normal'::notification_priority,
            '/review/' || booking_record.id || '/guest',
            jsonb_build_object(
                'booking_id', booking_record.id,
                'listing_id', booking_record.listing_id,
                'reason', 'auto_completed',
                'completed_at', NOW()
            )
        );

        -- Nudge the host to review the guest
        INSERT INTO public.notifications (
            user_id, type, title, body, priority, action_url, data
        ) VALUES (
            listing_record.owner_id,
            'review_prompt'::notification_type,
            'Reservation completed',
            format('%s''s stay at %s is complete. Leave a review for your guest.',
                COALESCE(guest_record.full_name, 'Your guest'),
                COALESCE(listing_record.title, 'your property')),
            'normal'::notification_priority,
            '/review/' || booking_record.id || '/host',
            jsonb_build_object(
                'booking_id', booking_record.id,
                'listing_id', booking_record.listing_id,
                'reason', 'auto_completed',
                'completed_at', NOW()
            )
        );

        completed_count := completed_count + 1;
    END LOOP;

    IF completed_count > 0 THEN
        RAISE NOTICE 'Auto-completed % elapsed bookings', completed_count;
    END IF;

    RETURN completed_count;
END;
$function$;
