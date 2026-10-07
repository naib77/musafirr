-- 162: several contact phones per listing / hotel, not one.
--
-- Hosts asked to list more than one number -- a front desk, a manager, a
-- caretaker. 160 gave the address rows a single `contact_phone`; this turns
-- it into `contact_phones text[]` on the same rows, so who may see the
-- numbers is unchanged: the RLS on `listing_addresses` /
-- `property_addresses` (owner, admin, accepted guest -- 093/103) still gates
-- them, and no new policy or grant is needed. Decided 2026-10-07 with Jev:
-- an array on the gated rows over a child table (0.59, which would have
-- needed its own RLS), repeatable fields in the form (0.98).
--
--  * At most 5 numbers (Jev unsure at 0.28; Claude's call -- enough for a
--    front desk, a manager and a night line, few enough that a guest reads
--    them all). Every element is the 160 shape, `+` and 8..15 digits; null
--    elements are refused because array_to_string would skip them silently.
--    An empty list is stored as null, so "no numbers" has one spelling.
--  * The single column is dropped (Jev unsure at 0.62; Claude's call): it
--    held no value on live (measured 2026-10-07, 0 rows in either table) and
--    no released build reads or writes it, so keeping it would only leave two
--    columns to drift. Any value is carried over first all the same.
--  * The guest's contact card (`get_booking_contacts`) still returns one
--    `host_phone` -- the first number -- so its signature and grants are
--    unchanged (Jev unsure at 0.49 on showing all; Claude's call). The full
--    list is on the listing page's address section, behind the same gate.
--
-- Both functions were rewritten from 160 as applied to live (the only two
-- that mention the column, checked through prosrc).
--
-- Ordering: a build that sends `contact_phones` needs this live first
-- (PGRST204 fails the exact-address upsert, which the app treats as
-- non-fatal and would silently drop the host's door address).

begin;

alter table public.listing_addresses
  add column if not exists contact_phones text[];
alter table public.property_addresses
  add column if not exists contact_phones text[];

update public.listing_addresses
   set contact_phones = array[contact_phone]
 where contact_phone is not null and contact_phones is null;
update public.property_addresses
   set contact_phones = array[contact_phone]
 where contact_phone is not null and contact_phones is null;

alter table public.listing_addresses
  drop constraint if exists listing_addresses_contact_phones_shape;
alter table public.listing_addresses
  add constraint listing_addresses_contact_phones_shape check (
    contact_phones is null
    or (cardinality(contact_phones) between 1 and 5
        and array_position(contact_phones, null) is null
        and array_to_string(contact_phones, ',') ~ '^\+[0-9]{8,15}(,\+[0-9]{8,15})*$'));

alter table public.property_addresses
  drop constraint if exists property_addresses_contact_phones_shape;
alter table public.property_addresses
  add constraint property_addresses_contact_phones_shape check (
    contact_phones is null
    or (cardinality(contact_phones) between 1 and 5
        and array_position(contact_phones, null) is null
        and array_to_string(contact_phones, ',') ~ '^\+[0-9]{8,15}(,\+[0-9]{8,15})*$'));

-- 160's copy with the list. Same signature, so 153's revoke holds.
create or replace function public.fn_copy_property_address(p_property_id uuid, p_listing_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.listing_addresses
    (listing_id, house_no, flat_floor, street, exact_address, latitude, longitude, contact_phones)
  select l.id, a.house_no, null, a.street, a.exact_address, a.latitude, a.longitude, a.contact_phones
    from public.property_addresses a
    join public.listings l on l.property_id = a.property_id
   where a.property_id = p_property_id
     and (p_listing_id is null or l.id = p_listing_id)
  on conflict (listing_id) do update
    set house_no = excluded.house_no, flat_floor = null, street = excluded.street,
        exact_address = excluded.exact_address,
        latitude = excluded.latitude, longitude = excluded.longitude,
        contact_phones = excluded.contact_phones;
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
           -- 160/162: the first number the host put on THIS listing. Definer,
           -- so listing_addresses' RLS does not apply; the status check above
           -- is the gate, and it is the same gate can_see_listing_address uses.
           coalesce(la.contact_phones[1], public.fn_identity_phone(hp.id), hp.mobile)
    from public.bookings b
    join public.listings l on l.id = b.listing_id
    left join public.listing_addresses la on la.listing_id = l.id
    left join public.profiles gp on gp.id = b.tenant_id
    left join public.profiles hp on hp.id = l.owner_id
    where b.id = p_booking_id;
end;
$$;

alter table public.listing_addresses
  drop constraint if exists listing_addresses_contact_phone_shape;
alter table public.listing_addresses drop column if exists contact_phone;
alter table public.property_addresses
  drop constraint if exists property_addresses_contact_phone_shape;
alter table public.property_addresses drop column if exists contact_phone;

commit;
