-- 160: a contact phone per listing / hotel, disclosed like the address.
--
-- Hosts asked for a place to put a contact number when creating a listing
-- or a hotel (a front desk, a caretaker — not always the login phone). Who
-- may see it was decided 2026-10-07 (Jev, 0.77): the same people who may see
-- the exact address — owner, admin, and a guest whose booking the host has
-- accepted (093/103). So it is a column on the gated address rows, not on
-- `listings` or `properties`, and no new policy or grant is needed: the
-- existing RLS on `listing_addresses` / `property_addresses` is the gate.
--
--  * A hotel's number is entered once on the hotel and copied onto its room
--    types with the address (153's fn_copy_property_address), the way
--    check-in times already are (Jev, 0.81).
--  * `get_booking_contacts` prefers the listing's number over the host's
--    login phone, so the contact card after booking dials the front desk,
--    not the owner's personal mobile. Rewritten from the LIVE definition
--    (pg_get_functiondef, 2026-10-07), which already differs from 138 by
--    `fn_identity_phone`; signature unchanged, grants kept.
--
-- The check is loose on purpose (E.164-ish: + and 8..15 digits); the app
-- normalises (lib/services/contact_phone.dart) and the row just refuses
-- prose. Stored as `+880…`, the shape `profiles.mobile` has on live, so the
-- coalesce above hands back one format.
--
-- Ordering: the Flutter address save sends `contact_phone` on every type,
-- so this must be live before a build that includes it (PGRST204 would
-- fail the whole exact-address upsert, which the app treats as non-fatal
-- and would silently drop the host's door address).

begin;

alter table public.listing_addresses
  add column if not exists contact_phone text;
alter table public.listing_addresses
  drop constraint if exists listing_addresses_contact_phone_shape;
alter table public.listing_addresses
  add constraint listing_addresses_contact_phone_shape
  check (contact_phone is null or contact_phone ~ '^\+[0-9]{8,15}$');

alter table public.property_addresses
  add column if not exists contact_phone text;
alter table public.property_addresses
  drop constraint if exists property_addresses_contact_phone_shape;
alter table public.property_addresses
  add constraint property_addresses_contact_phone_shape
  check (contact_phone is null or contact_phone ~ '^\+[0-9]{8,15}$');

-- 153's copy, plus the phone. Same signature, so the revoke from 153 holds.
create or replace function public.fn_copy_property_address(p_property_id uuid, p_listing_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.listing_addresses
    (listing_id, house_no, flat_floor, street, exact_address, latitude, longitude, contact_phone)
  select l.id, a.house_no, null, a.street, a.exact_address, a.latitude, a.longitude, a.contact_phone
    from public.property_addresses a
    join public.listings l on l.property_id = a.property_id
   where a.property_id = p_property_id
     and (p_listing_id is null or l.id = p_listing_id)
  on conflict (listing_id) do update
    set house_no = excluded.house_no, flat_floor = null, street = excluded.street,
        exact_address = excluded.exact_address,
        latitude = excluded.latitude, longitude = excluded.longitude,
        contact_phone = excluded.contact_phone;
end $$;

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
           coalesce(public.fn_identity_phone(gp.id), gp.mobile),
           coalesce(hp.full_name, 'Host'),
           -- 160: the number the host put on THIS listing first. Definer, so
           -- listing_addresses' RLS does not apply; the status check above is
           -- the gate, and it is the same gate can_see_listing_address uses.
           coalesce(la.contact_phone, public.fn_identity_phone(hp.id), hp.mobile)
    from public.bookings b
    join public.listings l on l.id = b.listing_id
    left join public.listing_addresses la on la.listing_id = l.id
    left join public.profiles gp on gp.id = b.tenant_id
    left join public.profiles hp on hp.id = l.owner_id
    where b.id = p_booking_id;
end;
$$;

commit;
