-- 156: a host can delete a room type, and a whole hotel.
--
-- 153 left listings.property_id with no ON DELETE action on purpose ("the
-- host removes the types first"), but the UI never offered either step, so a
-- hotel could not be deleted at all. These two functions are that path.
--
-- Why RPCs and not a client-side `.delete()`:
--   * The live-booking refusal must be enforcement, not the dashboard's
--     check (CLAUDE.md: "the booking form checks it" is not enforcement).
--     The listing rows are locked first, so a booking cannot slip in between
--     the check and the delete.
--   * The hotel's trade licence (152) is filed on ONE room type (the oldest;
--     listing_licence_verified answers for the whole hotel through
--     property_id). It cascades with that listing, so deleting the oldest
--     type would silently drop the hotel's verified licence. delete_room_type
--     hands it to the next-oldest type instead.
--   * Deleting a hotel is N listing deletes plus the property; one
--     transaction means a refusal half way leaves nothing half-deleted.
--
-- What still refuses, by hint (mapped in propertyRefusalMessage):
--   listing_has_bookings / property_has_bookings — a pending, confirmed or
--     active booking exists. Same set as 150's shrink and deleteListing.
--   listing_has_history / property_has_history — a booking has money
--     history (host_ledger_entries / disbursements are ON DELETE RESTRICT,
--     23503). The host can hide the listing instead.
--   not_a_room_type — delete_room_type on a standalone listing; those keep
--     the existing deleteListing path.
--
-- Storage objects (photos) are not removed: the listing-images bucket is
-- keyed by path and deleteListing has never cleaned them either.

begin;

create or replace function public.delete_room_type(p_listing_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v       public.listings;
  v_heir  uuid;
begin
  -- Ownership + row lock (153). The lock serialises with booking creation,
  -- which reads the listing row.
  v := public.fn_lock_own_listing(p_listing_id);

  if v.property_id is null then
    raise exception 'This is not a hotel room type'
      using errcode = '22023', hint = 'not_a_room_type';
  end if;

  if exists (
    select 1 from public.bookings b
     where b.listing_id = p_listing_id
       and b.booking_status in ('pending', 'confirmed', 'active')
  ) then
    raise exception 'This room type has upcoming or current bookings'
      using errcode = '23514', hint = 'listing_has_bookings';
  end if;

  -- Hand the hotel's licence to the next-oldest type, so the "oldest type
  -- holds it" rule the dashboard reads keeps holding. Only when the heir has
  -- none of its own (listing_id is the primary key).
  if exists (select 1 from public.listing_trade_licences where listing_id = p_listing_id) then
    select l.id into v_heir
      from public.listings l
     where l.property_id = v.property_id
       and l.id <> p_listing_id
     order by l.created_at, l.id
     limit 1;
    if v_heir is not null
       and not exists (select 1 from public.listing_trade_licences where listing_id = v_heir) then
      update public.listing_trade_licences
         set listing_id = v_heir
       where listing_id = p_listing_id;
    end if;
  end if;

  begin
    delete from public.listings where id = p_listing_id;
  exception when foreign_key_violation then
    raise exception 'This room type has payment history and cannot be deleted'
      using errcode = '23503', hint = 'listing_has_history';
  end;
end $$;

create or replace function public.delete_property(p_property_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid;
begin
  select owner_id into v_owner
    from public.properties where id = p_property_id for update;
  if not found then
    raise exception 'Hotel not found' using errcode = 'P0002', hint = 'property_not_found';
  end if;
  if v_owner is distinct from auth.uid() and not public.is_admin() then
    raise exception 'Only the host can delete this hotel'
      using errcode = '42501', hint = 'property_owner_mismatch';
  end if;

  -- Lock every room type before the booking check, same reason as above.
  perform 1 from public.listings where property_id = p_property_id for update;

  if exists (
    select 1 from public.bookings b
      join public.listings l on l.id = b.listing_id
     where l.property_id = p_property_id
       and b.booking_status in ('pending', 'confirmed', 'active')
  ) then
    raise exception 'This hotel has upcoming or current bookings'
      using errcode = '23514', hint = 'property_has_bookings';
  end if;

  begin
    -- Types first: property_id has no ON DELETE action (153). Their
    -- licences, units, addresses and blocks cascade with them; the hotel's
    -- address and facilities cascade with the property.
    delete from public.listings where property_id = p_property_id;
    delete from public.properties where id = p_property_id;
  exception when foreign_key_violation then
    raise exception 'This hotel has payment history and cannot be deleted'
      using errcode = '23503', hint = 'property_has_history';
  end;
end $$;

-- Definer functions are public endpoints: closed by default, opened to
-- signed-in users only. Both bodies check ownership themselves.
revoke all on function public.delete_room_type(uuid) from public, anon, authenticated;
grant execute on function public.delete_room_type(uuid) to authenticated, service_role;
revoke all on function public.delete_property(uuid) from public, anon, authenticated;
grant execute on function public.delete_property(uuid) to authenticated, service_role;

commit;
