-- Face-only review. No automated result grants approval or identity assurance.
begin;

-- Enable only after the capture assets, admin queue, and retention job are live.
insert into public.app_settings(key,value,is_public)
values('face_review_enabled','false',true) on conflict(key) do nothing;

create table public.face_verification_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  nonce uuid not null default gen_random_uuid(),
  method text not null check (method in ('guided', 'manual')),
  actions text[] not null,
  challenge_version integer not null default 1 check (challenge_version = 1),
  consent_version text not null default 'face-v1',
  status text not null default 'draft' check (status in
    ('draft', 'pending', 'approved', 'rejected', 'retry', 'superseded')),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default now() + interval '10 minutes',
  submitted_at timestamptz,
  clip_path text,
  selfie_path text,
  evidence_version uuid not null default gen_random_uuid(),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  review_note text check (length(review_note) <= 500),
  media_deleted_at timestamptz,
  check (status not in ('approved','rejected','retry') or
    (reviewed_by is not null and reviewed_at is not null)),
  check (status <> 'approved' or submitted_at is not null)
);
create index face_attempts_user_created on public.face_verification_attempts(user_id, created_at desc);
create index face_attempts_pending on public.face_verification_attempts(submitted_at) where status = 'pending';
alter table public.face_verification_attempts enable row level security;
revoke all on public.face_verification_attempts from public, anon, authenticated;
grant select on public.face_verification_attempts to authenticated;
grant all on public.face_verification_attempts to service_role;
create policy face_attempts_read on public.face_verification_attempts for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

create function public.has_approved_face_or_identity(p_user_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = p_user_id and verification_status = 'verified')
    or coalesce((select status = 'approved' from public.face_verification_attempts
      where user_id = p_user_id order by created_at desc, id desc limit 1), false);
$$;

create function public.face_verification_status()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a public.face_verification_attempts;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode='42501'; end if;
  select * into a from public.face_verification_attempts where user_id = auth.uid()
    order by created_at desc, id desc limit 1;
  if public.has_approved_face_or_identity(auth.uid()) then
    return jsonb_build_object('status','verified','method', case when a.status='approved' then a.method else 'legacy' end);
  end if;
  return jsonb_build_object('status', case when a.status in ('pending','rejected','retry') then a.status else 'none' end,
    'note',a.review_note,'method',a.method,
    'enabled',coalesce((select value='true' from public.app_settings where key='face_review_enabled'),false));
end;
$$;

create function public.start_face_verification(p_method text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.face_verification_attempts; sequence text[];
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode='42501'; end if;
  if not coalesce((select value='true' from public.app_settings where key='face_review_enabled'),false) then
    raise exception 'Face review is not available yet. Please try later'; end if;
  if p_method is null or p_method not in ('guided','manual') then raise exception 'Invalid capture method'; end if;
  -- Serialize starts/submission/review for a user, including simultaneous devices.
  perform 1 from public.profiles where id=auth.uid() and suspended_at is null for update;
  if not found then raise exception 'Account unavailable' using errcode='42501'; end if;
  if public.has_approved_face_or_identity(auth.uid()) then raise exception 'Already approved'; end if;
  if exists(select 1 from public.face_verification_attempts where user_id=auth.uid() and status='pending') then
    raise exception 'Your submission is already awaiting review'; end if;
  if (select count(*) from public.face_verification_attempts where user_id=auth.uid()
      and created_at > now()-interval '24 hours') >= 5 then
    raise exception 'Daily attempt limit reached. Please try tomorrow'; end if;
  update public.face_verification_attempts set status='superseded' where user_id=auth.uid() and status='draft';
  sequence := case when random() < 0.5 then array['blink','left','right'] else array['blink','right','left'] end;
  if random() < 0.5 then sequence := array[sequence[2],sequence[1],sequence[3]]; end if;
  if p_method='manual' then sequence := '{}'::text[]; end if;
  insert into public.face_verification_attempts(user_id,method,actions)
    values(auth.uid(),p_method,sequence) returning * into a;
  return to_jsonb(a);
end;
$$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('face-evidence','face-evidence',false,8388608,array['video/webm','video/mp4','image/jpeg'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

-- INSERT only: no overwrite/delete after capture, even before admin approval.
create policy face_evidence_insert on storage.objects for insert to authenticated with check (
  bucket_id='face-evidence' and exists(select 1 from public.face_verification_attempts a
    where a.user_id=auth.uid() and a.status='draft' and a.expires_at>now()
      and name in (a.user_id::text||'/'||a.id::text||'/selfie.jpg',
                   a.user_id::text||'/'||a.id::text||'/clip.webm',
                   a.user_id::text||'/'||a.id::text||'/clip.mp4')));
create policy face_evidence_read on storage.objects for select to authenticated using (
  bucket_id='face-evidence' and (public.is_admin() or (storage.foldername(name))[1]=auth.uid()::text));

create function public.submit_face_verification(p_attempt_id uuid, p_nonce uuid, p_clip_extension text default null)
returns void language plpgsql security definer set search_path = public as $$
declare a public.face_verification_attempts; clip text; selfie text;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode='42501'; end if;
  perform 1 from public.profiles where id=auth.uid() and suspended_at is null for update;
  if not found then raise exception 'Account unavailable' using errcode='42501'; end if;
  select * into a from public.face_verification_attempts where id=p_attempt_id and user_id=auth.uid() for update;
  if not found or a.nonce is distinct from p_nonce then raise exception 'Invalid attempt' using errcode='42501'; end if;
  if a.status='pending' then return; end if;
  if a.status<>'draft' or a.expires_at<=now() then raise exception 'Attempt expired. Start again'; end if;
  selfie := a.user_id::text||'/'||a.id::text||'/selfie.jpg';
  if not exists(select 1 from storage.objects where bucket_id='face-evidence' and name=selfie
    and (metadata->>'size')::bigint between 100 and 524288 and metadata->>'mimetype'='image/jpeg') then
    raise exception 'Selfie upload is missing or invalid'; end if;
  if a.method='guided' then
    if p_clip_extension is null or p_clip_extension not in ('webm','mp4') then raise exception 'Invalid video format'; end if;
    clip := a.user_id::text||'/'||a.id::text||'/clip.'||p_clip_extension;
    if not exists(select 1 from storage.objects where bucket_id='face-evidence' and name=clip
      and (metadata->>'size')::bigint between 100 and 8388608
      and metadata->>'mimetype'='video/'||p_clip_extension) then raise exception 'Video upload is missing or invalid'; end if;
  end if;
  -- No client liveness boolean is trusted. The admin must review the media.
  update public.face_verification_attempts set status='pending', submitted_at=now(),
    clip_path=clip, selfie_path=selfie where id=a.id;
end;
$$;

create function public.review_face_verification(p_attempt_id uuid, p_evidence_version uuid, p_decision text, p_note text default '')
returns void language plpgsql security definer set search_path = public as $$
declare a public.face_verification_attempts; target_user uuid;
begin
  if auth.uid() is null or not public.is_admin() then raise exception 'Admin approval required' using errcode='42501'; end if;
  if p_decision is null or p_decision not in ('approved','rejected','retry') then raise exception 'Invalid review decision'; end if;
  if length(coalesce(p_note,''))>500 then raise exception 'Keep the note under 500 characters'; end if;
  select user_id into target_user from public.face_verification_attempts where id=p_attempt_id;
  if target_user=auth.uid() then raise exception 'Another admin must review your submission' using errcode='42501'; end if;
  perform 1 from public.profiles where id=target_user for update;
  select * into a from public.face_verification_attempts where id=p_attempt_id for update;
  if not found or a.status<>'pending' or a.evidence_version is distinct from p_evidence_version
     or a.media_deleted_at is not null then raise exception 'Submission changed. Refresh the review queue'; end if;
  if exists(select 1 from public.face_verification_attempts where user_id=a.user_id and created_at>a.created_at) then
    raise exception 'A newer submission exists'; end if;
  if (p_decision<>'approved' or a.method='manual') and coalesce(btrim(p_note),'')='' then
    raise exception 'A reason is required, including for manual approval'; end if;
  update public.face_verification_attempts set status=p_decision, reviewed_by=auth.uid(),
    reviewed_at=now(),review_note=nullif(btrim(p_note),'') where id=a.id;
  -- Deliberately never writes profiles.verification_status or nid_verified.
end;
$$;

-- Document stamps must no longer implicitly finalize a person's verification.
drop trigger if exists on_document_verified on public.owner_documents;

create or replace function public.can_publish_listings()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles p where p.id=auth.uid()
    and p.role in ('owner','admin') and public.has_approved_face_or_identity(p.id));
$$;

revoke all on function public.has_approved_face_or_identity(uuid) from public, anon;
revoke all on function public.face_verification_status() from public, anon;
revoke all on function public.start_face_verification(text) from public, anon;
revoke all on function public.submit_face_verification(uuid,uuid,text) from public, anon;
revoke all on function public.review_face_verification(uuid,uuid,text,text) from public, anon;
grant execute on function public.has_approved_face_or_identity(uuid), public.face_verification_status(),
  public.start_face_verification(text), public.submit_face_verification(uuid,uuid,text),
  public.review_face_verification(uuid,uuid,text,text) to authenticated;

CREATE OR REPLACE FUNCTION public.create_marketplace_booking(p_listing_id uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_pricing_unit text, p_guest_count integer, p_tenant_name text DEFAULT NULL::text, p_coupon_code text DEFAULT NULL::text, p_listing_image_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid        uuid := auth.uid();
  v_listing    public.listings%rowtype;
  v_rate       numeric;
  v_qty        int;
  v_min        int;
  v_max        int;
  v_unit_word  text;
  v_gross      numeric;
  v_discount   numeric := 0;
  v_coupon_id  uuid;
  v_total      numeric;
  v_res        jsonb;
  v_booking    public.bookings%rowtype;
begin
  if v_uid is null then
    raise exception 'You must be signed in to book' using errcode = '42501';
  end if;

  -- Either historical identity approval or explicit current face-review approval.
  -- Keep the stable error hint consumed by the booking client.
  if not public.has_approved_face_or_identity(v_uid) then
    raise exception 'Admin face review is required before booking'
      using errcode = '42501', hint = 'identity_unverified';
  end if;

  -- Reserved interval must be forward-in-time.
  if p_ends_at is null or p_starts_at is null or p_ends_at <= p_starts_at then
    raise exception 'Invalid booking dates' using errcode = '22023';
  end if;

  -- 135: and it must not be in the past. Measured: a stay starting ten days
  -- ago was accepted and returned an id. Past slots are always "free", so the
  -- availability checks below never object, and `expire_stale_bookings` /
  -- the auto-complete sweep then walk the row straight to completed — which
  -- is a review prompt and a ledger entry for a stay nobody had.
  --
  -- The calendar already hides past dates. That is the "the booking form
  -- checks it" pattern this codebase has been bitten by four times: the form
  -- is skippable and the RPC is a public endpoint.
  --
  -- One hour of slack rather than a hard `>= now()`, because a guest booking
  -- a turf for *this* hour is the normal case for hourly listings, the
  -- client's clock is its own, and `now()` here is transaction time. The
  -- guard exists to stop last month, not to police the last minute.
  if p_starts_at < now() - interval '1 hour' then
    raise exception 'Choose a start time in the future'
      using errcode = '22023', hint = 'starts_in_past';
  end if;

  -- Load the listing. Must exist and be active.
  select * into v_listing from public.listings where id = p_listing_id;
  if not found then
    raise exception 'Listing not found' using errcode = 'P0002';
  end if;
  if not coalesce(v_listing.is_active, true) then
    raise exception 'This listing is no longer available' using errcode = '22023';
  end if;

  -- 135: a host must not book their own listing. Nothing checked this, and
  -- live already holds one such booking. Two things go wrong when it is
  -- allowed: the ledger posts the owner an earning against money that only
  -- moved between their own two pockets (or did not move at all, on the cash
  -- path), and a host can black out their own calendar through the booking
  -- path instead of listing_availability_blocks (110), which is the feature
  -- built for exactly that and the only one the host's own UI can undo.
  if v_listing.owner_id = v_uid then
    raise exception 'You cannot book your own listing'
      using errcode = '42501', hint = 'self_booking';
  end if;

  -- 138: a block is a wall, not a filter. `user_blocks` (SAFETY.md) only ever
  -- hid the other party's listings and threads in the CLIENT; measured
  -- 2026-09-19, a guest a host had blocked booked that host's listing and
  -- opened a conversation with them without a hitch. Either direction counts:
  -- a host who blocked a guest does not want their money, and a guest who
  -- blocked a host does not want to stay there.
  -- 140: a suspended account keeps its access token for up to an hour.
  if public.fn_is_suspended(v_uid) then
    raise exception 'This account is suspended'
      using errcode = '42501', hint = 'account_suspended';
  end if;
  -- And a suspended host's listings are hidden, but a deep link or a stale
  -- client can still name one.
  if public.fn_is_suspended(v_listing.owner_id) then
    raise exception 'This listing is no longer available' using errcode = '22023';
  end if;

  if public.fn_users_blocked(v_uid, v_listing.owner_id) then
    raise exception 'You cannot book this listing'
      using errcode = '42501', hint = 'blocked';
  end if;

  -- The host-wide Away switch (038). Only ever a search filter before this, so
  -- a guest who already had the page open could book straight past it.
  if not coalesce(v_listing.host_available, true) then
    raise exception 'This host isn''t accepting new bookings right now'
      using errcode = '22023';
  end if;

  -- Guest count within the listing's capacity.
  if p_guest_count is null or p_guest_count < 1 then
    raise exception 'At least one guest is required' using errcode = '22023';
  end if;
  if v_listing.max_guests is not null and p_guest_count > v_listing.max_guests then
    raise exception 'This place hosts up to % guests', v_listing.max_guests
      using errcode = '22023';
  end if;

  -- Server-side rate + quantity. Quantity is derived from the reserved interval
  -- so the client can't understate it; hour/day are exact epoch multiples,
  -- month is a calendar diff (monthly stays are booked whole-month, same day).
  -- The per-plan duration limits (055) are read here too, so the unit, the
  -- quantity and the bounds they are compared against always come from the same
  -- branch and cannot drift apart.
  case p_pricing_unit
    when 'hour' then
      v_rate := v_listing.hourly_rate;
      v_qty  := round(extract(epoch from (p_ends_at - p_starts_at)) / 3600.0);
      v_min  := v_listing.min_hours;
      v_max  := v_listing.max_hours;
      v_unit_word := 'hour';
    when 'day' then
      v_rate := v_listing.daily_rate;
      v_qty  := round(extract(epoch from (p_ends_at - p_starts_at)) / 86400.0);
      v_min  := v_listing.min_nights;
      v_max  := v_listing.max_nights;
      -- 'night', not 'day' — matches the word the booking form uses, so the
      -- guest doesn't get two different names for one number.
      v_unit_word := 'night';
    when 'month' then
      v_rate := v_listing.monthly_rate;
      v_qty  := (extract(year from p_ends_at) - extract(year from p_starts_at))::int * 12
              + (extract(month from p_ends_at) - extract(month from p_starts_at))::int;
      v_min  := v_listing.min_months;
      v_max  := v_listing.max_months;
      v_unit_word := 'month';
    else
      raise exception 'Unsupported booking type: %', p_pricing_unit using errcode = '22023';
  end case;

  if v_rate is null then
    raise exception 'This listing is not available for % bookings', p_pricing_unit
      using errcode = '22023';
  end if;
  if v_qty is null or v_qty < 1 then
    raise exception 'Booking must be at least one %', p_pricing_unit using errcode = '22023';
  end if;

  -- The host's per-plan minimum/maximum (055). `coalesce(v_min, 1)` mirrors
  -- BookingLimits.minFor's `?? 1` in lib/models/listing.dart — if those two ever
  -- disagree, the form and the server disagree about the floor and the guest
  -- gets refused for something the UI let them pick.
  if v_qty < coalesce(v_min, 1) then
    raise exception 'Minimum booking is % %', coalesce(v_min, 1),
      v_unit_word || case when coalesce(v_min, 1) = 1 then '' else 's' end
      using errcode = '22023';
  end if;
  if v_max is not null and v_qty > v_max then
    raise exception 'Maximum booking is % %', v_max,
      v_unit_word || case when v_max = 1 then '' else 's' end
      using errcode = '22023';
  end if;

  v_gross := round(v_rate * v_qty, 2);

  -- Conflict checks (authoritative backstop for the client's pre-flight checks;
  -- also catches races). Blocking statuses match BookingStatus.isActive. The
  -- `hint` is what the Dart layer reads to choose between the two guest-facing
  -- sentences; it used to grep this message for the words 'already have a
  -- booking', which meant rewording the line below silently changed the UI.
  if exists (
    select 1 from public.bookings b
    where b.listing_id = p_listing_id
      and b.booking_status in ('pending', 'confirmed', 'active')
      and p_starts_at < b.ends_at
      and b.starts_at < p_ends_at
  ) then
    raise exception 'This time slot is already booked'
      using errcode = '23P01', hint = 'listing_overlap';
  end if;

  -- Same user can't hold two overlapping bookings. Now backed by
  -- bookings_no_tenant_overlap, so losing the race here fails at COMMIT rather
  -- than slipping through.
  if exists (
    select 1 from public.bookings b
    where b.tenant_id = v_uid
      and b.booking_status in ('pending', 'confirmed', 'active')
      and p_starts_at < b.ends_at
      and b.starts_at < p_ends_at
  ) then
    raise exception 'You already have a booking during this time'
      using errcode = '23P01', hint = 'tenant_overlap';
  end if;

  -- Host-declared blocked dates (110). A block is not a bookings row, so no
  -- single exclusion constraint can cover both tables; a host blocking dates in
  -- the same millisecond a guest commits can lose this check. That window is
  -- accepted deliberately — the cost is one booking the host declines by hand,
  -- and the alternative (storing blocks AS bookings rows under a sentinel
  -- status) would drag them through earnings, commission, payouts and the host
  -- reservations list.
  if exists (
    select 1 from public.listing_availability_blocks blk
    where blk.listing_id = p_listing_id
      and tstzrange(blk.starts_at, blk.ends_at, '[)')
          && tstzrange(p_starts_at, p_ends_at, '[)')
  ) then
    raise exception 'The host has blocked these dates' using errcode = '22023';
  end if;

  -- Coupon (optional). Reuse the authoritative validator against the SERVER
  -- gross, so the discount can't be inflated against a fake amount either.
  if p_coupon_code is not null and length(trim(p_coupon_code)) > 0 then
    v_res := public.validate_coupon(p_coupon_code, v_gross);
    if (v_res->>'valid')::boolean is not true then
      raise exception '%', coalesce(v_res->>'message', 'Invalid coupon')
        using errcode = '22023';
    end if;
    v_discount  := coalesce((v_res->>'discount_amount')::numeric, 0);
    v_coupon_id := (v_res->>'coupon_id')::uuid;
  end if;

  v_total := greatest(v_gross - v_discount, 0);

  insert into public.bookings (
    listing_id, tenant_id, tenant_name,
    starts_at, ends_at, pricing_unit, unit_count,
    total_price, guest_count, booking_status,
    listing_title, listing_image_url, listing_city,
    coupon_code, discount_amount
  ) values (
    p_listing_id, v_uid, coalesce(p_tenant_name, ''),
    p_starts_at, p_ends_at, p_pricing_unit::pricing_unit, v_qty,
    v_total, p_guest_count, 'pending',
    v_listing.title, p_listing_image_url, v_listing.city,
    case when v_coupon_id is not null then upper(trim(p_coupon_code)) end,
    case when v_coupon_id is not null then v_discount else 0 end
  ) returning * into v_booking;

  -- Record redemption + bump usage atomically. If limits were exhausted between
  -- validate and here, redeem_coupon raises and the whole booking rolls back.
  if v_coupon_id is not null then
    perform public.redeem_coupon(v_coupon_id, v_booking.id, v_discount);
  end if;

  return to_jsonb(v_booking);
end;
$function$;

-- Called after Storage API deletion. Read status again atomically so retention
-- never overwrites an approval made while deletion was in flight.
create function public.record_face_evidence_deleted(p_attempt_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.fn_require_service_role();
  update public.face_verification_attempts set media_deleted_at=now(),
    status=case when status in ('draft','pending') then 'superseded' else status end
    where id=p_attempt_id;
end;
$$;
revoke all on function public.record_face_evidence_deleted(uuid) from public,anon,authenticated;
grant execute on function public.record_face_evidence_deleted(uuid) to service_role;

-- Account deletion cascades attempts, but storage bytes need their own cleanup.
create function public.orphan_face_evidence()
returns table(name text) language plpgsql security definer set search_path=public as $$
begin
  perform public.fn_require_service_role();
  return query select o.name from storage.objects o where o.bucket_id='face-evidence'
    and not exists(select 1 from public.face_verification_attempts a
      where a.id::text=split_part(o.name,'/',2) and a.user_id::text=split_part(o.name,'/',1))
    limit 100;
end;
$$;
revoke all on function public.orphan_face_evidence() from public,anon,authenticated;
grant execute on function public.orphan_face_evidence() to service_role;

notify pgrst, 'reload schema';
commit;
