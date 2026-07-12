-- 066 — Share contact phone numbers between host and guest once confirmed
--
-- Product need: when a host accepts a request, both parties should be able to
-- reach each other. The guest already receives the full (structured) address
-- via send_booking_map / send_precheckin_for_booking. This adds the phone side:
--
--   1. send_booking_contacts(booking): posts a one-time "Contact details"
--      message into the booking conversation with BOTH parties' login phone
--      numbers (profiles.mobile). Called from send_booking_accept_messages.
--   2. get_booking_contacts(booking): lets a participant of a CONFIRMED (or
--      active/completed) booking read the counterparty's name + phone, for the
--      reservation/trip detail screens.
--
-- Both are SECURITY DEFINER so they can read profiles.mobile, which the PII
-- lockdown (migration 061) otherwise hides from other users. Access is strictly
-- limited: only the booking's host or tenant, and only after confirmation.

-- ── 1. Chat message on accept ────────────────────────────────────────────────
create or replace function public.send_booking_contacts(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
    rec RECORD;
    v_conv_id UUID;
    v_lang TEXT;
    v_header TEXT;
    v_msg TEXT;
begin
    select b.id as booking_id, b.tenant_id, b.listing_id,
           coalesce(b.tenant_name, gp.full_name, 'Guest') as guest_name,
           gp.mobile as guest_phone,
           l.owner_id as host_id,
           coalesce(hp.full_name, 'Host') as host_name,
           hp.mobile as host_phone,
           coalesce(hp.message_language, gp.message_language, 'en') as lang
    into rec
    from public.bookings b
    join public.listings l on l.id = b.listing_id
    left join public.profiles gp on gp.id = b.tenant_id
    left join public.profiles hp on hp.id = l.owner_id
    where b.id = p_booking_id
      and b.booking_status = 'confirmed'
      and b.tenant_id is not null;

    if not found then return; end if;

    -- Deliver only once per booking.
    if exists (select 1 from public.scheduled_message_sends s
               where s.booking_id = rec.booking_id and s.trigger = 'contacts') then
        return;
    end if;

    v_lang := rec.lang;
    v_header := case when v_lang = 'bn' then '📞 যোগাযোগের তথ্য' else '📞 Contact details' end;
    v_msg := v_header;

    if nullif(trim(rec.guest_phone), '') is not null then
        v_msg := v_msg || E'\n'
            || (case when v_lang = 'bn' then 'অতিথি: ' else 'Guest: ' end)
            || rec.guest_name || ' — ' || trim(rec.guest_phone);
    end if;
    if nullif(trim(rec.host_phone), '') is not null then
        v_msg := v_msg || E'\n'
            || (case when v_lang = 'bn' then 'হোস্ট: ' else 'Host: ' end)
            || rec.host_name || ' — ' || trim(rec.host_phone);
    end if;

    v_conv_id := public.get_or_create_conversation(
        rec.tenant_id, rec.host_id, rec.booking_id, rec.listing_id);

    -- Only post if at least one phone was present.
    if v_msg <> v_header then
        insert into public.messages (conversation_id, sender_id, content, content_type)
        values (v_conv_id, rec.host_id, v_msg, 'text');
    end if;

    insert into public.scheduled_message_sends (booking_id, trigger)
    values (rec.booking_id, 'contacts');
end;
$$;

-- Wire the contact message into the existing on-accept fan-out.
create or replace function public.send_booking_accept_messages(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
DECLARE
    v_host_id UUID;
BEGIN
    SELECT l.owner_id INTO v_host_id
    FROM public.bookings b
    JOIN public.listings l ON l.id = b.listing_id
    WHERE b.id = p_booking_id;

    IF v_host_id IS NULL THEN RETURN; END IF;
    -- Only the listing's host may trigger these sends (null uid = server/cron).
    IF auth.uid() IS NOT NULL AND auth.uid() <> v_host_id THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;

    PERFORM public.send_booking_map(p_booking_id);
    PERFORM public.send_precheckin_for_booking(p_booking_id);
    PERFORM public.send_booking_contacts(p_booking_id);
END;
$$;

-- ── 2. Read counterparty contact for the detail screens ──────────────────────
create or replace function public.get_booking_contacts(p_booking_id uuid)
returns table (
    guest_name  text,
    guest_phone text,
    host_name   text,
    host_phone  text
)
language plpgsql
security definer
set search_path to 'public'
as $$
declare
    v_tenant UUID;
    v_host UUID;
    v_status TEXT;
begin
    select b.tenant_id, l.owner_id, b.booking_status::text
    into v_tenant, v_host, v_status
    from public.bookings b
    join public.listings l on l.id = b.listing_id
    where b.id = p_booking_id;

    if v_tenant is null then return; end if;

    -- Only the two participants may read contacts.
    if auth.uid() is null or auth.uid() not in (v_tenant, v_host) then
        raise exception 'Not authorized';
    end if;

    -- Contacts are revealed only once the booking is locked in.
    if v_status not in ('confirmed', 'active', 'completed') then
        return;
    end if;

    return query
    select coalesce(b.tenant_name, gp.full_name, 'Guest'),
           gp.mobile,
           coalesce(hp.full_name, 'Host'),
           hp.mobile
    from public.bookings b
    join public.listings l on l.id = b.listing_id
    left join public.profiles gp on gp.id = b.tenant_id
    left join public.profiles hp on hp.id = l.owner_id
    where b.id = p_booking_id;
end;
$$;

grant execute on function public.get_booking_contacts(uuid) to authenticated;
