-- ============================================================
-- LIVE SCHEMA SNAPSHOT — public schema of Supabase project bojkmonskqlhuakxhzcb
-- Source of truth for the live database. Generated from the live
-- catalog via the Management API (NOT hand-written, NOT from the
-- migration files — which have drifted). Reference-grade: faithful to
-- live, but not guaranteed to replay cleanly as-is. Regenerate with
-- `python3 scripts/dump_live_schema.py` (uses the Supabase CLI keychain
-- token; no DB password or Docker needed).
-- ============================================================

-- ========================= ENUM TYPES =========================
create type public.app_role as enum ('admin', 'owner', 'tenant');
create type public.booking_status as enum ('pending', 'confirmed', 'rejected', 'active', 'completed', 'cancelled');
create type public.listing_type as enum ('seat', 'room', 'fullHouse');
create type public.notification_priority as enum ('low', 'normal', 'high', 'urgent');
create type public.notification_status as enum ('unread', 'read', 'archived', 'deleted');
create type public.notification_type as enum ('booking_request', 'booking_confirmed', 'booking_cancelled', 'booking_reminder', 'check_in_reminder', 'check_out_reminder', 'payment_received', 'payment_failed', 'refund_processed', 'review_received', 'review_reminder', 'promotion_available', 'discount_expiring', 'referral_reward', 'new_message', 'message_read', 'system_alert', 'account_update', 'security_alert', 'booking_rejected', 'checked_in', 'review_prompt');
create type public.pricing_unit as enum ('hour', 'day', 'month');
create type public.review_type as enum ('guest_to_host', 'host_to_guest');
create type public.verification_status as enum ('none', 'pending', 'verified', 'rejected');

-- ========================= TABLES =========================

create table public.app_secrets (
  key text not null,
  value text not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

create table public.app_settings (
  key text not null,
  value text,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
  is_public boolean default true not null
);

create table public.audit_log (
  id bigint not null,
  occurred_at timestamp with time zone default now() not null,
  table_name text not null,
  record_id uuid,
  action text not null,
  actor_id uuid,
  actor_role text,
  source text default 'app'::text not null,
  category text not null,
  amount numeric,
  currency text,
  changed_cols _text,
  old_data jsonb,
  new_data jsonb,
  note text
);

create table public.bookings (
  id uuid default uuid_generate_v4() not null,
  listing_id uuid,
  tenant_id uuid,
  tenant_name text,
  starts_at timestamp with time zone not null,
  ends_at timestamp with time zone not null,
  booking_status booking_status default 'pending'::booking_status,
  pricing_unit pricing_unit default 'day'::pricing_unit,
  unit_count integer default 1,
  total_price numeric not null,
  guest_count integer default 1,
  listing_title text,
  listing_image_url text,
  listing_city text,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),
  host_message text,
  rejection_reason text,
  confirmed_at timestamp with time zone,
  actual_check_in timestamp with time zone,
  completed_at timestamp with time zone,
  cancelled_by uuid,
  cancelled_at timestamp with time zone,
  coupon_code text,
  discount_amount numeric default 0 not null,
  payment_status text default 'unpaid'::text not null,
  paid_at timestamp with time zone,
  payment_method text
);

create table public.conversation_participants (
  id uuid default gen_random_uuid() not null,
  conversation_id uuid not null,
  user_id uuid not null,
  role text default 'guest'::text not null,
  joined_at timestamp with time zone default now() not null,
  left_at timestamp with time zone,
  is_active boolean default true not null
);

create table public.conversations (
  id uuid default gen_random_uuid() not null,
  participant_one_id uuid not null,
  participant_two_id uuid not null,
  booking_id uuid,
  listing_id uuid,
  status text default 'active'::text not null,
  last_message_at timestamp with time zone,
  last_message_preview text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  listing_title text,
  booking_start timestamp with time zone,
  booking_end timestamp with time zone,
  listing_type text,
  last_message_id uuid,
  last_message_text text,
  last_message_sender_id uuid
);

create table public.coupon_redemptions (
  id uuid default gen_random_uuid() not null,
  coupon_id uuid not null,
  user_id uuid not null,
  booking_id uuid,
  discount_amount numeric default 0 not null,
  redeemed_at timestamp with time zone default now() not null
);

create table public.coupons (
  id uuid default gen_random_uuid() not null,
  code text not null,
  discount_type text not null,
  discount_value numeric not null,
  max_discount_amount numeric,
  min_booking_amount numeric default 0 not null,
  usage_limit integer,
  used_count integer default 0 not null,
  per_user_limit integer default 1,
  is_active boolean default true not null,
  starts_at timestamp with time zone,
  expires_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone default now() not null
);

create table public.facilities (
  id uuid default uuid_generate_v4() not null,
  name text not null,
  icon text,
  created_at timestamp with time zone default now()
);

create table public.favorites (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  listing_id uuid not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

create table public.fcm_tokens (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  token text not null,
  device_type text default 'android'::text,
  device_name text,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),
  last_used_at timestamp with time zone default now(),
  is_active boolean default true
);

create table public.host_leaderboard_snapshots (
  period text not null,
  host_id uuid not null,
  rank bigint not null,
  score numeric not null,
  captured_at timestamp with time zone default timezone('utc'::text, now()) not null
);

create table public.landmarks (
  id uuid default gen_random_uuid() not null,
  name text not null,
  type text not null,
  city text,
  area text,
  latitude double precision not null,
  longitude double precision not null,
  geog geography,
  is_active boolean default true not null,
  created_at timestamp with time zone default now() not null
);

create table public.listing_addresses (
  listing_id uuid not null,
  house_no text,
  flat_floor text,
  street text,
  exact_address text,
  latitude numeric,
  longitude numeric,
  updated_at timestamp with time zone default now() not null
);

create table public.listing_checkin_details (
  listing_id uuid not null,
  directions text,
  wifi_name text,
  wifi_password text,
  access_code text,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

create table public.listing_facilities (
  id uuid default uuid_generate_v4() not null,
  listing_id uuid,
  facility_id uuid
);

create table public.listings (
  id uuid default uuid_generate_v4() not null,
  owner_id uuid,
  owner_name text,
  title text not null,
  description text,
  address text,
  city text,
  country text,
  listing_type listing_type default 'room'::listing_type,
  latitude numeric,
  longitude numeric,
  location geography,
  hourly_rate numeric,
  daily_rate numeric,
  monthly_rate numeric,
  is_active boolean default true,
  host_avatar_url text,
  image_urls _text default '{}'::text[],
  max_guests integer default 2,
  bedrooms integer default 1,
  beds integer default 1,
  bathrooms integer default 1,
  rating numeric,
  review_count integer default 0,
  is_superhost boolean default false,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),
  host_available boolean default true not null,
  check_in_time text,
  check_out_time text,
  smoking_allowed boolean default false not null,
  pets_allowed boolean default false not null,
  parties_allowed boolean default false not null,
  quiet_hours text,
  additional_rules text,
  min_hours integer,
  max_hours integer,
  min_nights integer,
  max_nights integer,
  min_months integer,
  max_months integer,
  area text,
  postal_code text,
  landmark text,
  purpose_tags _text default '{}'::text[] not null,
  geog geography
);

create table public.message_templates (
  id uuid default gen_random_uuid() not null,
  host_id uuid not null,
  trigger text not null,
  content text not null,
  enabled boolean default true not null,
  lead_days integer default 2 not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table public.messages (
  id uuid default gen_random_uuid() not null,
  conversation_id uuid not null,
  sender_id uuid not null,
  content text not null,
  content_type text default 'text'::text not null,
  metadata jsonb default '{}'::jsonb,
  status text default 'sent'::text not null,
  reply_to_id uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now(),
  deleted_at timestamp with time zone
);

create table public.notification_preferences (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  global_enabled boolean default true not null,
  quiet_hours_enabled boolean default false not null,
  quiet_hours_start time without time zone default '22:00:00'::time without time zone,
  quiet_hours_end time without time zone default '07:00:00'::time without time zone,
  quiet_hours_allow_urgent boolean default true not null,
  category_preferences jsonb default '{}'::jsonb not null,
  email text,
  phone_number text,
  whatsapp_number text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table public.notifications (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  type notification_type not null,
  title text not null,
  body text not null,
  status notification_status default 'unread'::notification_status not null,
  priority notification_priority default 'normal'::notification_priority not null,
  data jsonb,
  image_url text,
  action_url text,
  group_key text,
  read_at timestamp with time zone,
  expires_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table public.otp_attempts (
  id uuid default gen_random_uuid() not null,
  phone text not null,
  otp_hash text not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  expires_at timestamp with time zone not null,
  verified_at timestamp with time zone,
  attempts integer default 0 not null,
  is_used boolean default false not null
);

create table public.owner_documents (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  document_type text not null,
  file_path text not null,
  file_name text,
  file_size integer,
  mime_type text,
  uploaded_at timestamp with time zone default timezone('utc'::text, now()) not null,
  verified_at timestamp with time zone,
  verified_by uuid,
  rejection_reason text
);

create table public.payments (
  id uuid default gen_random_uuid() not null,
  booking_id uuid not null,
  user_id uuid not null,
  tran_id text not null,
  amount numeric not null,
  currency text default 'BDT'::text not null,
  status text default 'initiated'::text not null,
  val_id text,
  card_type text,
  bank_tran_id text,
  gateway_response jsonb,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  card_no text,
  card_issuer text,
  card_brand text,
  store_amount numeric,
  currency_amount numeric,
  risk_level text,
  risk_title text,
  tran_date text,
  validated_at timestamp with time zone
);

create table public.profiles (
  id uuid not null,
  full_name text,
  email text,
  mobile text,
  role app_role default 'tenant'::app_role,
  avatar_url text,
  is_host boolean default false,
  host_since timestamp with time zone,
  bio text,
  response_rate integer,
  response_time text,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),
  nid text,
  nid_verified boolean default false,
  phone_verified boolean default false,
  registration_method text default 'phone'::text,
  verification_status verification_status default 'none'::verification_status,
  id_document_type text,
  address_proof_path text,
  is_available boolean default true not null,
  leaderboard_opt_out boolean default false not null,
  message_language text default 'en'::text not null,
  signup_completed boolean default false not null,
  address_verification_status verification_status default 'none'::verification_status not null,
  address_line text,
  address_submitted_at timestamp with time zone,
  address_verified_at timestamp with time zone,
  address_verified_by uuid,
  address_rejection_reason text,
  address_visit_notes text
);

create table public.push_tokens (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  token text not null,
  platform text not null,
  device_id text not null,
  device_name text,
  is_active boolean default true not null,
  last_used_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table public.read_cursors (
  conversation_id uuid not null,
  user_id uuid not null,
  last_read_message_id uuid,
  last_read_at timestamp with time zone default now() not null
);

create table public.reports (
  id uuid default gen_random_uuid() not null,
  reporter_id uuid not null,
  reported_user_id uuid,
  listing_id uuid,
  booking_id uuid,
  category text not null,
  details text,
  status text default 'open'::text not null,
  resolution_note text,
  created_at timestamp with time zone default now() not null,
  resolved_at timestamp with time zone,
  resolved_by uuid
);

create table public.reviews (
  id uuid default gen_random_uuid() not null,
  booking_id uuid not null,
  listing_id uuid,
  reviewer_id uuid not null,
  reviewer_name text not null,
  reviewer_avatar_url text,
  reviewee_id uuid not null,
  review_type review_type not null,
  overall_rating numeric not null,
  cleanliness_rating numeric,
  accuracy_rating numeric,
  communication_rating numeric,
  location_rating numeric,
  value_rating numeric,
  comment text,
  is_revealed boolean default false not null,
  revealed_at timestamp with time zone,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

create table public.scheduled_message_sends (
  booking_id uuid not null,
  trigger text not null,
  sent_at timestamp with time zone default now() not null
);

create table public.typing_indicators (
  conversation_id uuid not null,
  user_id uuid not null,
  started_at timestamp with time zone default now() not null
);

create table public.user_blocks (
  blocker_id uuid not null,
  blocked_id uuid not null,
  created_at timestamp with time zone default now() not null
);

-- ========================= INDEXES =========================
CREATE INDEX idx_audit_log_actor ON public.audit_log USING btree (actor_id);
CREATE INDEX idx_audit_log_category_time ON public.audit_log USING btree (category, occurred_at DESC);
CREATE INDEX idx_audit_log_occurred ON public.audit_log USING btree (occurred_at DESC);
CREATE INDEX idx_audit_log_table_record ON public.audit_log USING btree (table_name, record_id);
CREATE INDEX bookings_overlap_idx ON public.bookings USING gist (listing_id, tstzrange(starts_at, ends_at, '[)'::text)) WHERE (booking_status = ANY (ARRAY['pending'::booking_status, 'confirmed'::booking_status]));
CREATE INDEX idx_conv_participants_active ON public.conversation_participants USING btree (is_active) WHERE (is_active = true);
CREATE INDEX idx_conv_participants_conversation ON public.conversation_participants USING btree (conversation_id);
CREATE INDEX idx_conv_participants_user ON public.conversation_participants USING btree (user_id);
CREATE INDEX idx_conversations_participant_one ON public.conversations USING btree (participant_one_id);
CREATE INDEX idx_conversations_participant_two ON public.conversations USING btree (participant_two_id);
CREATE UNIQUE INDEX uniq_conversation_per_pair ON public.conversations USING btree (LEAST(participant_one_id, participant_two_id), GREATEST(participant_one_id, participant_two_id));
CREATE INDEX coupon_redemptions_coupon_user_idx ON public.coupon_redemptions USING btree (coupon_id, user_id);
CREATE INDEX favorites_by_listing ON public.favorites USING btree (listing_id);
CREATE INDEX favorites_by_user ON public.favorites USING btree (user_id);
CREATE INDEX idx_fcm_tokens_active ON public.fcm_tokens USING btree (user_id, is_active) WHERE (is_active = true);
CREATE INDEX idx_fcm_tokens_user_id ON public.fcm_tokens USING btree (user_id);
CREATE INDEX idx_landmarks_geog ON public.landmarks USING gist (geog);
CREATE INDEX idx_landmarks_type ON public.landmarks USING btree (type) WHERE is_active;
CREATE INDEX idx_listings_geog ON public.listings USING gist (geog);
CREATE INDEX idx_listings_purpose_tags ON public.listings USING gin (purpose_tags);
CREATE INDEX listings_location_idx ON public.listings USING gist (location);
CREATE INDEX idx_messages_conversation ON public.messages USING btree (conversation_id);
CREATE INDEX idx_messages_created_at ON public.messages USING btree (created_at DESC);
CREATE INDEX idx_notification_preferences_user ON public.notification_preferences USING btree (user_id);
CREATE INDEX idx_notifications_expires ON public.notifications USING btree (expires_at) WHERE (expires_at IS NOT NULL);
CREATE INDEX idx_notifications_group_key ON public.notifications USING btree (group_key) WHERE (group_key IS NOT NULL);
CREATE INDEX idx_notifications_type ON public.notifications USING btree (type);
CREATE INDEX idx_notifications_user_created ON public.notifications USING btree (user_id, created_at DESC);
CREATE INDEX idx_notifications_user_id ON public.notifications USING btree (user_id);
CREATE INDEX idx_notifications_user_status ON public.notifications USING btree (user_id, status);
CREATE INDEX otp_attempts_expires_at_idx ON public.otp_attempts USING btree (expires_at);
CREATE INDEX otp_attempts_phone_idx ON public.otp_attempts USING btree (phone);
CREATE INDEX owner_documents_user_id_idx ON public.owner_documents USING btree (user_id);
CREATE INDEX owner_documents_verified_at_idx ON public.owner_documents USING btree (verified_at) WHERE (verified_at IS NULL);
CREATE INDEX payments_booking_id_idx ON public.payments USING btree (booking_id);
CREATE INDEX payments_user_id_idx ON public.payments USING btree (user_id);
CREATE INDEX profiles_address_verification_status_idx ON public.profiles USING btree (address_verification_status) WHERE (address_verification_status <> 'none'::verification_status);
CREATE INDEX profiles_is_host_idx ON public.profiles USING btree (is_host) WHERE (is_host = true);
CREATE INDEX idx_push_tokens_active ON public.push_tokens USING btree (user_id, is_active) WHERE (is_active = true);
CREATE INDEX idx_push_tokens_token ON public.push_tokens USING btree (token);
CREATE INDEX idx_push_tokens_user ON public.push_tokens USING btree (user_id);
CREATE INDEX idx_reports_reported_user ON public.reports USING btree (reported_user_id);
CREATE INDEX idx_reports_status ON public.reports USING btree (status, created_at DESC);
CREATE INDEX reviews_by_booking ON public.reviews USING btree (booking_id);
CREATE INDEX reviews_by_listing ON public.reviews USING btree (listing_id) WHERE (listing_id IS NOT NULL);
CREATE INDEX reviews_by_reviewee ON public.reviews USING btree (reviewee_id);
CREATE INDEX reviews_revealed ON public.reviews USING btree (is_revealed, review_type);
CREATE UNIQUE INDEX reviews_unique_per_booking ON public.reviews USING btree (booking_id, reviewer_id, review_type);

-- ==================== ROW LEVEL SECURITY ====================
alter table public.app_secrets enable row level security;
alter table public.app_settings enable row level security;
alter table public.audit_log enable row level security;
alter table public.bookings enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.conversations enable row level security;
alter table public.coupon_redemptions enable row level security;
alter table public.coupons enable row level security;
alter table public.facilities enable row level security;
alter table public.favorites enable row level security;
alter table public.fcm_tokens enable row level security;
alter table public.host_leaderboard_snapshots enable row level security;
alter table public.landmarks enable row level security;
alter table public.listing_addresses enable row level security;
alter table public.listing_checkin_details enable row level security;
alter table public.listing_facilities enable row level security;
alter table public.listings enable row level security;
alter table public.message_templates enable row level security;
alter table public.messages enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.notifications enable row level security;
alter table public.otp_attempts enable row level security;
alter table public.owner_documents enable row level security;
alter table public.payments enable row level security;
alter table public.profiles enable row level security;
alter table public.push_tokens enable row level security;
alter table public.read_cursors enable row level security;
alter table public.reports enable row level security;
alter table public.reviews enable row level security;
alter table public.scheduled_message_sends enable row level security;
alter table public.typing_indicators enable row level security;
alter table public.user_blocks enable row level security;

-- Policies
create policy "app_settings_admin_insert" on public.app_settings
  as permissive for insert to authenticated
  with check ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::app_role)))));
create policy "app_settings_admin_update" on public.app_settings
  as permissive for update to authenticated
  using ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::app_role)))))
  with check ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::app_role)))));
create policy "app_settings_select_public" on public.app_settings
  as permissive for select to public
  using (is_public);
create policy "audit_log_admin_select" on public.audit_log
  as permissive for select to authenticated
  using ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::app_role)))));
create policy "Admins can view all bookings" on public.bookings
  as permissive for select to authenticated
  using (is_admin());
create policy "Hosts can update bookings for their listings" on public.bookings
  as permissive for update to public
  using ((EXISTS ( SELECT 1
   FROM listings
  WHERE ((listings.id = bookings.listing_id) AND (listings.owner_id = auth.uid())))))
  with check ((EXISTS ( SELECT 1
   FROM listings
  WHERE ((listings.id = bookings.listing_id) AND (listings.owner_id = auth.uid())))));
create policy "Hosts can view bookings for their listings" on public.bookings
  as permissive for select to public
  using ((EXISTS ( SELECT 1
   FROM listings
  WHERE ((listings.id = bookings.listing_id) AND (listings.owner_id = auth.uid())))));
create policy "Users can cancel their own bookings" on public.bookings
  as permissive for update to public
  using ((auth.uid() = tenant_id));
create policy "Users can view their own bookings" on public.bookings
  as permissive for select to public
  using ((auth.uid() = tenant_id));
create policy "Users can add participants" on public.conversation_participants
  as permissive for insert to public
  with check (is_conversation_member(conversation_id, auth.uid()));
create policy "Users can leave conversations" on public.conversation_participants
  as permissive for update to public
  using ((user_id = auth.uid()));
create policy "Users can view participants in own conversations" on public.conversation_participants
  as permissive for select to public
  using (is_conversation_member(conversation_id, auth.uid()));
create policy "Users can insert conversations" on public.conversations
  as permissive for insert to public
  with check (((auth.uid() = participant_one_id) OR (auth.uid() = participant_two_id)));
create policy "Users can update own conversations" on public.conversations
  as permissive for update to public
  using (((auth.uid() = participant_one_id) OR (auth.uid() = participant_two_id)));
create policy "Users can view own conversations" on public.conversations
  as permissive for select to public
  using (((auth.uid() = participant_one_id) OR (auth.uid() = participant_two_id)));
create policy "coupon_redemptions_select" on public.coupon_redemptions
  as permissive for select to authenticated
  using (((user_id = auth.uid()) OR is_admin()));
create policy "coupons_admin_all" on public.coupons
  as permissive for all to authenticated
  using (is_admin())
  with check (is_admin());
create policy "facilities_read_authenticated" on public.facilities
  as permissive for select to authenticated
  using (true);
create policy "favorites_delete_own" on public.favorites
  as permissive for delete to public
  using ((auth.uid() = user_id));
create policy "favorites_insert_own" on public.favorites
  as permissive for insert to public
  with check ((auth.uid() = user_id));
create policy "favorites_select_own" on public.favorites
  as permissive for select to public
  using ((auth.uid() = user_id));
create policy "Service role can read all fcm tokens" on public.fcm_tokens
  as permissive for select to service_role
  using (true);
create policy "Users can delete own fcm tokens" on public.fcm_tokens
  as permissive for delete to authenticated
  using ((auth.uid() = user_id));
create policy "Users can insert own fcm tokens" on public.fcm_tokens
  as permissive for insert to authenticated
  with check ((auth.uid() = user_id));
create policy "Users can update own fcm tokens" on public.fcm_tokens
  as permissive for update to authenticated
  using ((auth.uid() = user_id))
  with check ((auth.uid() = user_id));
create policy "Users can view own fcm tokens" on public.fcm_tokens
  as permissive for select to authenticated
  using ((auth.uid() = user_id));
create policy "landmarks_public_read" on public.landmarks
  as permissive for select to public
  using ((is_active = true));
create policy "listing_addresses_owner_delete" on public.listing_addresses
  as permissive for delete to authenticated
  using ((EXISTS ( SELECT 1
   FROM listings l
  WHERE ((l.id = listing_addresses.listing_id) AND (l.owner_id = auth.uid())))));
create policy "listing_addresses_owner_insert" on public.listing_addresses
  as permissive for insert to authenticated
  with check ((EXISTS ( SELECT 1
   FROM listings l
  WHERE ((l.id = listing_addresses.listing_id) AND (l.owner_id = auth.uid())))));
create policy "listing_addresses_owner_update" on public.listing_addresses
  as permissive for update to authenticated
  using ((EXISTS ( SELECT 1
   FROM listings l
  WHERE ((l.id = listing_addresses.listing_id) AND (l.owner_id = auth.uid())))))
  with check ((EXISTS ( SELECT 1
   FROM listings l
  WHERE ((l.id = listing_addresses.listing_id) AND (l.owner_id = auth.uid())))));
create policy "listing_addresses_select_entitled" on public.listing_addresses
  as permissive for select to authenticated
  using (can_see_listing_address(listing_id));
create policy "owner_manages_checkin_details" on public.listing_checkin_details
  as permissive for all to authenticated
  using ((EXISTS ( SELECT 1
   FROM listings l
  WHERE ((l.id = listing_checkin_details.listing_id) AND (l.owner_id = auth.uid())))))
  with check ((EXISTS ( SELECT 1
   FROM listings l
  WHERE ((l.id = listing_checkin_details.listing_id) AND (l.owner_id = auth.uid())))));
create policy "Anyone can view listing facilities" on public.listing_facilities
  as permissive for select to public
  using (true);
create policy "Owners can manage their listing facilities" on public.listing_facilities
  as permissive for all to public
  using ((EXISTS ( SELECT 1
   FROM listings
  WHERE ((listings.id = listing_facilities.listing_id) AND (listings.owner_id = auth.uid())))));
create policy "Anyone can view active listings" on public.listings
  as permissive for select to public
  using (((is_active = true) OR (auth.uid() = owner_id)));
create policy "Owners can delete their own listings" on public.listings
  as permissive for delete to public
  using ((auth.uid() = owner_id));
create policy "Owners can insert their own listings" on public.listings
  as permissive for insert to public
  with check ((auth.uid() = owner_id));
create policy "Owners can update their own listings" on public.listings
  as permissive for update to public
  using ((auth.uid() = owner_id));
create policy "Hosts manage own templates" on public.message_templates
  as permissive for all to public
  using ((auth.uid() = host_id))
  with check ((auth.uid() = host_id));
create policy "Participants can send messages" on public.messages
  as permissive for insert to public
  with check (((auth.uid() = sender_id) AND (EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = messages.conversation_id) AND ((c.participant_one_id = auth.uid()) OR (c.participant_two_id = auth.uid())))))));
create policy "Users can update own messages" on public.messages
  as permissive for update to public
  using ((auth.uid() = sender_id));
create policy "Users can view messages in own conversations" on public.messages
  as permissive for select to public
  using ((EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = messages.conversation_id) AND ((c.participant_one_id = auth.uid()) OR (c.participant_two_id = auth.uid()))))));
create policy "notification_preferences_delete_own" on public.notification_preferences
  as permissive for delete to public
  using ((auth.uid() = user_id));
create policy "notification_preferences_insert_own" on public.notification_preferences
  as permissive for insert to public
  with check ((auth.uid() = user_id));
create policy "notification_preferences_select_own" on public.notification_preferences
  as permissive for select to public
  using ((auth.uid() = user_id));
create policy "notification_preferences_update_own" on public.notification_preferences
  as permissive for update to public
  using ((auth.uid() = user_id));
create policy "notifications_delete_own" on public.notifications
  as permissive for delete to public
  using ((auth.uid() = user_id));
create policy "notifications_select_own" on public.notifications
  as permissive for select to public
  using ((auth.uid() = user_id));
create policy "notifications_update_own" on public.notifications
  as permissive for update to public
  using ((auth.uid() = user_id));
create policy "owner_documents_admin_update" on public.owner_documents
  as permissive for update to authenticated
  using ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::app_role)))));
create policy "owner_documents_delete_own" on public.owner_documents
  as permissive for delete to authenticated
  using (((user_id = auth.uid()) AND (verified_at IS NULL)));
create policy "owner_documents_insert_own" on public.owner_documents
  as permissive for insert to authenticated
  with check ((user_id = auth.uid()));
create policy "owner_documents_select_own" on public.owner_documents
  as permissive for select to authenticated
  using (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::app_role))))));
create policy "owner_documents_update_own" on public.owner_documents
  as permissive for update to authenticated
  using (((user_id = auth.uid()) AND (verified_at IS NULL)))
  with check (((user_id = auth.uid()) AND (verified_at IS NULL)));
create policy "payments_select" on public.payments
  as permissive for select to authenticated
  using (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM (bookings b
     JOIN listings l ON ((l.id = b.listing_id)))
  WHERE ((b.id = payments.booking_id) AND (l.owner_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::app_role))))));
create policy "Users can insert their own profile" on public.profiles
  as permissive for insert to public
  with check ((auth.uid() = id));
create policy "Users can update their own profile" on public.profiles
  as permissive for update to public
  using ((auth.uid() = id));
create policy "Users can view their own profile" on public.profiles
  as permissive for select to public
  using (((auth.uid() = id) OR is_admin()));
create policy "admins_update_any_profile" on public.profiles
  as permissive for update to authenticated
  using (is_admin())
  with check (is_admin());
create policy "profiles_insert_self" on public.profiles
  as permissive for insert to authenticated
  with check ((auth.uid() = id));
create policy "push_tokens_delete_own" on public.push_tokens
  as permissive for delete to public
  using ((auth.uid() = user_id));
create policy "push_tokens_insert_own" on public.push_tokens
  as permissive for insert to public
  with check ((auth.uid() = user_id));
create policy "push_tokens_select_own" on public.push_tokens
  as permissive for select to public
  using ((auth.uid() = user_id));
create policy "push_tokens_update_own" on public.push_tokens
  as permissive for update to public
  using ((auth.uid() = user_id));
create policy "Users can manage own read cursors" on public.read_cursors
  as permissive for all to public
  using ((auth.uid() = user_id));
create policy "reports_admin_update" on public.reports
  as permissive for update to authenticated
  using (is_admin())
  with check (is_admin());
create policy "reports_insert_own" on public.reports
  as permissive for insert to authenticated
  with check ((reporter_id = auth.uid()));
create policy "reports_select_own_or_admin" on public.reports
  as permissive for select to authenticated
  using (((reporter_id = auth.uid()) OR is_admin()));
create policy "reviews_insert" on public.reviews
  as permissive for insert to public
  with check (((auth.uid() = reviewer_id) AND (EXISTS ( SELECT 1
   FROM bookings b
  WHERE ((b.id = reviews.booking_id) AND (b.booking_status = ANY (ARRAY['completed'::booking_status, 'active'::booking_status])) AND (((reviews.review_type = 'guest_to_host'::review_type) AND (b.tenant_id = auth.uid())) OR ((reviews.review_type = 'host_to_guest'::review_type) AND (EXISTS ( SELECT 1
           FROM listings l
          WHERE ((l.id = b.listing_id) AND (l.owner_id = auth.uid())))))))))));
create policy "reviews_select_own" on public.reviews
  as permissive for select to public
  using ((auth.uid() = reviewer_id));
create policy "reviews_select_revealed" on public.reviews
  as permissive for select to public
  using ((is_revealed = true));
create policy "reviews_service_insert" on public.reviews
  as permissive for all to public
  using (((auth.jwt() ->> 'role'::text) = 'service_role'::text))
  with check (((auth.jwt() ->> 'role'::text) = 'service_role'::text));
create policy "reviews_update_own" on public.reviews
  as permissive for update to public
  using (((auth.uid() = reviewer_id) AND (is_revealed = false)))
  with check ((auth.uid() = reviewer_id));
create policy "Users can manage own typing" on public.typing_indicators
  as permissive for all to public
  using ((auth.uid() = user_id));
create policy "Users can view typing in own conversations" on public.typing_indicators
  as permissive for select to public
  using ((EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = typing_indicators.conversation_id) AND ((c.participant_one_id = auth.uid()) OR (c.participant_two_id = auth.uid()))))));
create policy "user_blocks_delete_own" on public.user_blocks
  as permissive for delete to authenticated
  using ((blocker_id = auth.uid()));
create policy "user_blocks_insert_own" on public.user_blocks
  as permissive for insert to authenticated
  with check ((blocker_id = auth.uid()));
create policy "user_blocks_select_involved" on public.user_blocks
  as permissive for select to authenticated
  using (((blocker_id = auth.uid()) OR (blocked_id = auth.uid()) OR is_admin()));

-- ========================= VIEWS =========================
create or replace view public.financial_audit as
 SELECT id,
    occurred_at,
    table_name,
    record_id,
    action,
    actor_id,
    actor_role,
    source,
    amount,
    currency,
    changed_cols
   FROM audit_log
  WHERE category = 'financial'::text;
create or replace view public.guest_ratings as
 SELECT reviewee_id AS guest_id,
    count(*) AS review_count,
    round(avg(overall_rating), 1) AS average_rating
   FROM reviews
  WHERE review_type = 'host_to_guest'::review_type AND is_revealed = true
  GROUP BY reviewee_id;
create or replace view public.listing_ratings as
 SELECT listing_id,
    count(*) AS review_count,
    round(avg(overall_rating), 1) AS average_rating,
    round(avg(cleanliness_rating), 1) AS average_cleanliness,
    round(avg(accuracy_rating), 1) AS average_accuracy,
    round(avg(communication_rating), 1) AS average_communication,
    round(avg(location_rating), 1) AS average_location,
    round(avg(value_rating), 1) AS average_value
   FROM reviews
  WHERE review_type = 'guest_to_host'::review_type AND listing_id IS NOT NULL
  GROUP BY listing_id;
create or replace view public.public_profiles as
 SELECT id,
    full_name,
    avatar_url,
    role,
    is_host,
    host_since,
    bio,
    response_rate,
    response_time,
    is_available,
    message_language,
    created_at,
    COALESCE(phone_verified, false) AS phone_verified,
    verification_status = 'verified'::verification_status AS identity_verified,
    address_verification_status = 'verified'::verification_status AS address_verified
   FROM profiles;

-- ========================= FUNCTIONS =========================
CREATE OR REPLACE FUNCTION public._localize_date_bn(d text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.admin_auto_complete_bookings()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    IF current_setting('role') != 'service_role' THEN
        RAISE EXCEPTION 'Only service_role can execute this function';
    END IF;
    RETURN public.auto_complete_elapsed_bookings();
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_expire_bookings()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    -- Only allow service_role to execute
    IF current_setting('role') != 'service_role' THEN
        RAISE EXCEPTION 'Only service_role can execute this function';
    END IF;

    RETURN public.expire_stale_bookings();
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_reveal_reviews()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    -- Only allow service_role to execute
    IF current_setting('role') != 'service_role' THEN
        RAISE EXCEPTION 'Only service_role can execute this function';
    END IF;

    RETURN public.auto_reveal_old_reviews();
END;
$function$;

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

CREATE OR REPLACE FUNCTION public.auto_reveal_old_reviews()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    revealed_count integer;
    review_record RECORD;
    booking_record RECORD;
    listing_record RECORD;
BEGIN
    revealed_count := 0;

    -- Find reviews older than 14 days that haven't been revealed
    FOR review_record IN
        SELECT r.*
        FROM public.reviews r
        WHERE r.is_revealed = false
        AND r.created_at < NOW() - INTERVAL '14 days'
    LOOP
        -- Reveal the review
        UPDATE public.reviews
        SET
            is_revealed = true,
            revealed_at = NOW()
        WHERE id = review_record.id;

        -- Get booking and listing info for notification
        SELECT b.*, l.title AS listing_title, l.owner_id AS host_id
        INTO booking_record
        FROM public.bookings b
        LEFT JOIN public.listings l ON l.id = b.listing_id
        WHERE b.id = review_record.booking_id;

        -- Notify the reviewee that they received a review
        INSERT INTO public.notifications (
            user_id, type, title, body, priority, action_url, data
        ) VALUES (
            review_record.reviewee_id,
            'review_received'::notification_type,
            'New Review Available',
            CASE
                WHEN review_record.review_type = 'guest_to_host' THEN
                    format('You received a %s star review for %s',
                        review_record.overall_rating,
                        COALESCE(booking_record.listing_title, 'your property'))
                ELSE
                    format('You received a %s star review from a host', review_record.overall_rating)
            END,
            'normal'::notification_priority,
            CASE
                WHEN review_record.review_type = 'guest_to_host' THEN '/listing/' || review_record.listing_id || '/reviews'
                ELSE '/profile/reviews'
            END,
            jsonb_build_object(
                'review_id', review_record.id,
                'booking_id', review_record.booking_id,
                'rating', review_record.overall_rating,
                'review_type', review_record.review_type,
                'auto_revealed', true
            )
        );

        revealed_count := revealed_count + 1;
    END LOOP;

    -- Log the result
    IF revealed_count > 0 THEN
        RAISE NOTICE 'Auto-revealed % reviews', revealed_count;
    END IF;

    RETURN revealed_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.can_see_listing_address(p_listing_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    -- Admins run the safety/verification queues and need the real address.
    public.is_admin()
    -- The host knows their own address.
    or exists (
      select 1 from public.listings l
      where l.id = p_listing_id and l.owner_id = auth.uid()
    )
    -- A guest the host has ACCEPTED. `pending` is excluded on purpose: asking
    -- to stay somewhere must not be enough to learn where it is. `rejected` and
    -- `cancelled` are excluded too — an acceptance that fell through is not a
    -- standing invitation.
    or exists (
      select 1 from public.bookings b
      where b.listing_id = p_listing_id
        and b.tenant_id = auth.uid()
        and b.booking_status in ('confirmed', 'active', 'completed')
    );
$function$;

CREATE OR REPLACE FUNCTION public.capture_monthly_leaderboard_snapshot()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  INSERT INTO public.host_leaderboard_snapshots (period, host_id, rank, score, captured_at)
  SELECT to_char(timezone('utc', now()), 'YYYY-MM'), host_id, rank, score, timezone('utc', now())
  FROM public.host_leaderboard_ranked('monthly')
  ON CONFLICT (period, host_id) DO UPDATE
    SET rank = EXCLUDED.rank,
        score = EXCLUDED.score,
        captured_at = EXCLUDED.captured_at;
$function$;

CREATE OR REPLACE FUNCTION public.check_and_reveal_reviews()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    other_review_exists boolean;
BEGIN
    -- Check if the other party has already submitted a review
    SELECT EXISTS (
        SELECT 1 FROM public.reviews
        WHERE booking_id = NEW.booking_id
        AND review_type != NEW.review_type
        AND is_revealed = false
    ) INTO other_review_exists;

    -- If both reviews exist, reveal them both
    IF other_review_exists THEN
        UPDATE public.reviews
        SET is_revealed = true, revealed_at = timezone('utc', now())
        WHERE booking_id = NEW.booking_id AND is_revealed = false;
    END IF;

    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.cleanup_old_otps()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  deleted_count integer;
begin
  with deleted as (
    delete from public.otp_attempts
    where
      -- Remove verified OTPs after 24 hours
      (verified_at is not null and verified_at < now() - interval '24 hours')
      -- Remove expired unverified OTPs after 24 hours
      or (verified_at is null and expires_at < now() - interval '24 hours')
      -- Hard limit: remove anything older than 7 days
      or created_at < now() - interval '7 days'
    returning 1
  )
  select count(*) into deleted_count from deleted;

  return deleted_count;
end;
$function$;

CREATE OR REPLACE FUNCTION public.coupons_normalize_code()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.code := upper(trim(new.code));
  return new;
end;
$function$;

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

  -- Reserved interval must be forward-in-time.
  if p_ends_at is null or p_starts_at is null or p_ends_at <= p_starts_at then
    raise exception 'Invalid booking dates' using errcode = '22023';
  end if;

  -- Load the listing. Must exist and be active.
  select * into v_listing from public.listings where id = p_listing_id;
  if not found then
    raise exception 'Listing not found' using errcode = 'P0002';
  end if;
  if not coalesce(v_listing.is_active, true) then
    raise exception 'This listing is no longer available' using errcode = '22023';
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
  case p_pricing_unit
    when 'hour' then
      v_rate := v_listing.hourly_rate;
      v_qty  := round(extract(epoch from (p_ends_at - p_starts_at)) / 3600.0);
    when 'day' then
      v_rate := v_listing.daily_rate;
      v_qty  := round(extract(epoch from (p_ends_at - p_starts_at)) / 86400.0);
    when 'month' then
      v_rate := v_listing.monthly_rate;
      v_qty  := (extract(year from p_ends_at) - extract(year from p_starts_at))::int * 12
              + (extract(month from p_ends_at) - extract(month from p_starts_at))::int;
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

  v_gross := round(v_rate * v_qty, 2);

  -- Conflict checks (authoritative backstop for the client's pre-flight checks;
  -- also catches races). Blocking statuses match BookingStatus.isActive.
  if exists (
    select 1 from public.bookings b
    where b.listing_id = p_listing_id
      and b.booking_status in ('pending', 'confirmed', 'active')
      and p_starts_at < b.ends_at
      and b.starts_at < p_ends_at
  ) then
    raise exception 'This time slot is already booked' using errcode = '23P01';
  end if;

  -- Same user can't hold two overlapping bookings.
  if exists (
    select 1 from public.bookings b
    where b.tenant_id = v_uid
      and b.booking_status in ('pending', 'confirmed', 'active')
      and p_starts_at < b.ends_at
      and b.starts_at < p_ends_at
  ) then
    raise exception 'You already have a booking during this time' using errcode = '23P01';
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

CREATE OR REPLACE FUNCTION public.enforce_booking_update_rules()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_is_owner boolean;
  v_is_admin boolean;
  v_is_tenant boolean;
begin
  -- Server-side (service_role / cron) has no auth context; trust it.
  if v_uid is null then
    return new;
  end if;

  select exists (
    select 1 from public.profiles p where p.id = v_uid and p.role = 'admin'
  ) into v_is_admin;
  if v_is_admin then
    return new;
  end if;

  -- Financial / identity fields never change after creation for non-admins.
  if new.tenant_id  is distinct from old.tenant_id
     or new.listing_id  is distinct from old.listing_id
     or new.total_price is distinct from old.total_price
     or new.starts_at   is distinct from old.starts_at
     or new.ends_at     is distinct from old.ends_at then
    raise exception
      'Booking amount, dates and parties cannot be modified after creation';
  end if;

  select exists (
    select 1 from public.listings l
    where l.id = new.listing_id and l.owner_id = v_uid
  ) into v_is_owner;
  v_is_tenant := (new.tenant_id = v_uid);

  -- Guest: cancellation only.
  if v_is_tenant and not v_is_owner then
    if new.booking_status is distinct from old.booking_status then
      if new.booking_status <> 'cancelled' then
        raise exception
          'Guests may only cancel a booking (attempted % -> %)',
          old.booking_status, new.booking_status;
      end if;
      if old.booking_status not in ('pending', 'confirmed') then
        raise exception 'Cannot cancel a booking in % state', old.booking_status;
      end if;
    end if;
    return new;
  end if;

  -- Host (listing owner) drives accept/reject/check-in/complete/cancel.
  if v_is_owner then
    return new;
  end if;

  -- Not tenant, owner, or admin — RLS should already have blocked this.
  raise exception 'Not authorized to update this booking';
end;
$function$;

CREATE OR REPLACE FUNCTION public.enforce_listing_public_location()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  -- Derived, never client-supplied: whatever `address` a client sends is
  -- discarded in favour of the area-level form.
  new.address   := public.listing_area_address(new.area, new.city, new.postal_code);
  new.latitude  := public.snap_coordinate(new.latitude);
  new.longitude := public.snap_coordinate(new.longitude);

  -- Re-derive the PostGIS columns from the SNAPPED coordinates. The existing
  -- listing_location_trigger / trg_set_listing_geog do this too, but they fire
  -- in trigger-name order and `listing_location_trigger` sorts before this one,
  -- so it would otherwise stamp `location` with the exact point. Doing it here
  -- as well makes the outcome independent of trigger ordering.
  if new.latitude is not null and new.longitude is not null then
    new.location := ST_SetSRID(ST_MakePoint(new.longitude, new.latitude), 4326)::geography;
    new.geog     := ST_SetSRID(ST_MakePoint(new.longitude, new.latitude), 4326)::geography;
  else
    new.location := null;
    new.geog     := null;
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.expire_stale_bookings()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    expired_count integer;
    booking_record RECORD;
    listing_record RECORD;
    guest_record RECORD;
BEGIN
    expired_count := 0;

    -- Find and expire stale bookings
    FOR booking_record IN
        SELECT b.*
        FROM public.bookings b
        WHERE b.booking_status = 'pending'
        AND b.created_at < NOW() - INTERVAL '24 hours'
    LOOP
        -- Update booking to rejected
        UPDATE public.bookings
        SET
            booking_status = 'rejected',
            rejection_reason = 'Booking request expired after 24 hours without host response'
        WHERE id = booking_record.id;

        -- Get listing info for notification
        SELECT l.title, l.owner_id INTO listing_record
        FROM public.listings l
        WHERE l.id = booking_record.listing_id;

        -- Get guest info
        SELECT p.full_name INTO guest_record
        FROM public.profiles p
        WHERE p.id = booking_record.tenant_id;

        -- Notify guest about expiration
        INSERT INTO public.notifications (
            user_id, type, title, body, priority, action_url, data
        ) VALUES (
            booking_record.tenant_id,
            'booking_rejected'::notification_type,
            'Booking Request Expired',
            format('Your booking request for %s expired. The host did not respond within 24 hours.',
                COALESCE(listing_record.title, 'the property')),
            'normal'::notification_priority,
            '/trips/' || booking_record.id,
            jsonb_build_object(
                'booking_id', booking_record.id,
                'listing_id', booking_record.listing_id,
                'reason', 'expired',
                'expired_at', NOW()
            )
        );

        -- Notify host about missed booking
        INSERT INTO public.notifications (
            user_id, type, title, body, priority, action_url, data
        ) VALUES (
            listing_record.owner_id,
            'booking_cancelled'::notification_type,
            'Booking Request Expired',
            format('A booking request from %s for %s expired because you did not respond within 24 hours.',
                COALESCE(guest_record.full_name, 'a guest'),
                COALESCE(listing_record.title, 'your property')),
            'normal'::notification_priority,
            '/host/reservations/' || booking_record.id,
            jsonb_build_object(
                'booking_id', booking_record.id,
                'listing_id', booking_record.listing_id,
                'reason', 'expired',
                'expired_at', NOW()
            )
        );

        expired_count := expired_count + 1;
    END LOOP;

    -- Log the result
    IF expired_count > 0 THEN
        RAISE NOTICE 'Expired % pending bookings', expired_count;
    END IF;

    RETURN expired_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_audit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_old      jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  v_new      jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  v_row      jsonb := coalesce(v_new, v_old);
  v_actor    uuid  := auth.uid();
  v_role     text;
  v_source   text  := coalesce(
                        nullif(current_setting('app.audit_source', true), ''),
                        case when auth.uid() is null then 'system' else 'app' end);
  v_category text  := tg_argv[0];
  v_amount   numeric;
  v_currency text;
  v_changed  text[];
begin
  if tg_op = 'UPDATE' then
    select array_agg(k)
      into v_changed
      from jsonb_object_keys(v_new) k
     where (v_new -> k) is distinct from (v_old -> k);
    -- Nothing we care about actually changed → skip the row.
    if v_changed is null then
      return null;
    end if;
  end if;

  if v_actor is not null then
    select role::text into v_role from public.profiles where id = v_actor;
  end if;

  if tg_table_name = 'payments' then
    v_amount   := (v_row ->> 'amount')::numeric;
    v_currency := coalesce(v_row ->> 'currency', 'BDT');
  elsif tg_table_name = 'bookings' then
    v_amount   := (v_row ->> 'total_price')::numeric;
    v_currency := 'BDT';
  end if;

  insert into public.audit_log (
    table_name, record_id, action, actor_id, actor_role, source,
    category, amount, currency, changed_cols, old_data, new_data)
  values (
    tg_table_name,
    (v_row ->> 'id')::uuid,
    lower(tg_op),
    v_actor, v_role, v_source,
    v_category, v_amount, v_currency, v_changed, v_old, v_new);

  return null; -- AFTER trigger; return value ignored
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_audit_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  raise exception 'audit_log is append-only (% blocked)', tg_op
    using errcode = '42501';
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_guard_verification_verdicts()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- A NULL uid is a trusted server caller: service_role, an Edge Function, or
  -- a pg_cron job running as postgres with no JWT. (Lesson from migration 077:
  -- any auth.uid() guard that a cron job reaches must allow NULL.)
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;

  -- Awarding a verdict is admin-only, in both directions of the flow.
  if new.address_verification_status = 'verified'
     and old.address_verification_status is distinct from 'verified' then
    raise exception 'address verification is granted by an admin visit, not by the host'
      using errcode = '42501';
  end if;

  if new.verification_status = 'verified'
     and old.verification_status is distinct from 'verified' then
    raise exception 'identity verification is granted by an admin, not by the user'
      using errcode = '42501';
  end if;

  if new.nid_verified and not coalesce(old.nid_verified, false) then
    raise exception 'nid_verified is set by an admin, not by the user'
      using errcode = '42501';
  end if;

  -- The paper trail of a visit belongs to whoever made it.
  if new.address_verified_at is distinct from old.address_verified_at
     or new.address_verified_by is distinct from old.address_verified_by
     or new.address_visit_notes is distinct from old.address_visit_notes
     or new.address_rejection_reason is distinct from old.address_rejection_reason then
    raise exception 'address verification audit fields are admin-only'
      using errcode = '42501';
  end if;

  -- Everything else a host may do to their own row is untouched: uploading a
  -- bill, declaring an address, and moving their own submission to 'pending'
  -- (or back to 'none') are all still theirs.
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_auth_user_id_by_email(p_email text)
 RETURNS uuid
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select id from auth.users where email = p_email limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.get_booking_contacts(p_booking_id uuid)
 RETURNS TABLE(guest_name text, guest_phone text, host_name text, host_phone text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.get_conversation_participants(p_conversation_id uuid)
 RETURNS TABLE(user_id uuid, role text, joined_at timestamp with time zone, user_name text, avatar_url text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    cp.user_id,
    cp.role,
    cp.joined_at,
    p.full_name as user_name,
    p.avatar_url
  FROM public.conversation_participants cp
  LEFT JOIN public.profiles p ON p.id = cp.user_id
  WHERE cp.conversation_id = p_conversation_id
    AND cp.is_active = true
  ORDER BY cp.joined_at;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_host_leaderboard(p_period text DEFAULT 'all_time'::text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS TABLE(rank bigint, host_id uuid, name text, avatar_url text, score numeric, rating numeric, review_count bigint, completed_bookings bigint, prev_rank bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT * FROM public.host_leaderboard_ranked(p_period)
  ORDER BY rank
  LIMIT GREATEST(p_limit, 0) OFFSET GREATEST(p_offset, 0);
$function$;

CREATE OR REPLACE FUNCTION public.get_host_rank(p_host_id uuid, p_period text DEFAULT 'all_time'::text)
 RETURNS TABLE(rank bigint, host_id uuid, name text, avatar_url text, score numeric, rating numeric, review_count bigint, completed_bookings bigint, prev_rank bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT * FROM public.host_leaderboard_ranked(p_period)
  WHERE host_id = p_host_id;
$function$;

CREATE OR REPLACE FUNCTION public.get_listing_owner(p_listing_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT l.owner_id
    FROM public.listings l
    WHERE l.id = p_listing_id
    AND (
        l.is_active
        OR EXISTS (
            SELECT 1 FROM public.bookings b
            WHERE b.listing_id = l.id
            AND b.tenant_id = auth.uid()
        )
    );
$function$;

CREATE OR REPLACE FUNCTION public.get_or_create_conversation(user_one uuid, user_two uuid, p_booking_id uuid DEFAULT NULL::uuid, p_listing_id uuid DEFAULT NULL::uuid)
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

CREATE OR REPLACE FUNCTION public.get_unread_count(p_conversation_id uuid, p_user_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  last_read_at TIMESTAMPTZ;
  unread INTEGER;
BEGIN
  SELECT rc.last_read_at INTO last_read_at
  FROM public.read_cursors rc
  WHERE rc.conversation_id = p_conversation_id AND rc.user_id = p_user_id;

  IF last_read_at IS NULL THEN
    SELECT COUNT(*) INTO unread
    FROM public.messages m
    WHERE m.conversation_id = p_conversation_id
      AND m.sender_id != p_user_id
      AND m.deleted_at IS NULL;
  ELSE
    SELECT COUNT(*) INTO unread
    FROM public.messages m
    WHERE m.conversation_id = p_conversation_id
      AND m.sender_id != p_user_id
      AND m.created_at > last_read_at
      AND m.deleted_at IS NULL;
  END IF;

  RETURN COALESCE(unread, 0);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_unread_notification_count(p_user_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  if auth.uid() is not null and auth.uid() <> p_user_id then
    raise exception 'Not authorized';
  end if;
  return (
    select count(*)::integer
    from notifications
    where user_id = p_user_id and status = 'unread'
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mobile TEXT;
BEGIN
  -- Get mobile from metadata, phone, or generate a unique placeholder
  v_mobile := COALESCE(
    new.raw_user_meta_data ->> 'mobile',
    new.phone,
    'pending_' || new.id::text  -- Unique placeholder using user ID
  );

  INSERT INTO public.profiles (
    id,
    role,
    full_name,
    mobile,
    registration_method,
    phone_verified,
    nid,
    nid_verified
  )
  VALUES (
    new.id,
    COALESCE((new.raw_user_meta_data ->> 'role')::public.app_role, 'tenant'),
    COALESCE(new.raw_user_meta_data ->> 'full_name', 'New User'),
    v_mobile,
    COALESCE(new.raw_user_meta_data ->> 'registration_method', 'phone'),
    CASE WHEN new.phone IS NOT NULL OR new.raw_user_meta_data ->> 'mobile' IS NOT NULL THEN TRUE ELSE FALSE END,
    new.raw_user_meta_data ->> 'nid',
    COALESCE((new.raw_user_meta_data ->> 'nid_verified')::boolean, FALSE)
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(EXCLUDED.full_name, profiles.full_name),
    mobile = COALESCE(EXCLUDED.mobile, profiles.mobile),
    updated_at = timezone('utc', now());
  RETURN new;
END;
$function$;

CREATE OR REPLACE FUNCTION public.host_leaderboard_ranked(p_period text)
 RETURNS TABLE(rank bigint, host_id uuid, name text, avatar_url text, score numeric, rating numeric, review_count bigint, completed_bookings bigint, prev_rank bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH params AS (
    SELECT
      CASE WHEN p_period = 'monthly'
        THEN date_trunc('month', timezone('utc', now())) END AS start_ts,
      CASE WHEN p_period = 'monthly'
        THEN to_char(
          date_trunc('month', timezone('utc', now())) - interval '1 month',
          'YYYY-MM') END AS prev_period
  ),
  rev AS (
    SELECT r.reviewee_id AS host_id, COUNT(*) AS review_count,
           AVG(r.overall_rating) AS avg_rating
    FROM public.reviews r, params
    WHERE r.review_type = 'guest_to_host'
      AND (params.start_ts IS NULL OR r.created_at >= params.start_ts)
    GROUP BY r.reviewee_id
  ),
  bk AS (
    SELECT l.owner_id AS host_id, COUNT(*) AS completed_bookings
    FROM public.bookings b
    JOIN public.listings l ON l.id = b.listing_id, params
    WHERE b.booking_status = 'completed'
      AND (params.start_ts IS NULL OR b.ends_at >= params.start_ts)
    GROUP BY l.owner_id
  ),
  gmean AS (
    SELECT COALESCE(AVG(r.overall_rating), 4.5) AS m
    FROM public.reviews r, params
    WHERE r.review_type = 'guest_to_host'
      AND (params.start_ts IS NULL OR r.created_at >= params.start_ts)
  ),
  scored AS (
    SELECT
      p.id AS host_id, p.full_name AS name, p.avatar_url,
      COALESCE(rev.review_count, 0) AS review_count,
      COALESCE(rev.avg_rating, 0) AS avg_rating,
      COALESCE(bk.completed_bookings, 0) AS completed_bookings,
      COALESCE(p.response_rate, 0) AS response_rate,
      ((5 * gmean.m) + COALESCE(rev.avg_rating, 0) * COALESCE(rev.review_count, 0))
        / (5 + COALESCE(rev.review_count, 0)) AS bayes
    FROM public.profiles p
    CROSS JOIN gmean
    LEFT JOIN rev ON rev.host_id = p.id
    LEFT JOIN bk ON bk.host_id = p.id
    WHERE p.is_host = TRUE
      AND COALESCE(p.leaderboard_opt_out, FALSE) = FALSE
      AND COALESCE(bk.completed_bookings, 0) >= 1
  ),
  ranked AS (
    SELECT
      ROW_NUMBER() OVER (
        ORDER BY score_calc DESC, review_count DESC, completed_bookings DESC
      ) AS rank,
      host_id, name, avatar_url, score_calc AS score,
      ROUND(avg_rating, 1) AS rating, review_count, completed_bookings
    FROM (
      SELECT host_id, name, avatar_url, review_count, completed_bookings, avg_rating,
        ROUND(
            50 * (bayes / 5.0)
          + 30 * (LEAST(completed_bookings, 50)::numeric / 50.0)
          + 20 * (response_rate / 100.0)
        , 1) AS score_calc
      FROM scored
    ) s
  )
  SELECT
    r.rank, r.host_id, r.name, r.avatar_url, r.score, r.rating,
    r.review_count, r.completed_bookings,
    snap.rank AS prev_rank
  FROM ranked r
  CROSS JOIN params
  LEFT JOIN public.host_leaderboard_snapshots snap
    ON snap.host_id = r.host_id AND snap.period = params.prev_period;
$function$;

CREATE OR REPLACE FUNCTION public.is_admin(p_uid uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.profiles where id = p_uid and role = 'admin'
  );
$function$;

CREATE OR REPLACE FUNCTION public.is_booking_available(p_listing_id uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN NOT EXISTS (
        SELECT 1
        FROM public.bookings
        WHERE listing_id = p_listing_id
          AND booking_status IN ('pending', 'confirmed', 'active')
          AND tstzrange(starts_at, ends_at, '[)') && tstzrange(p_starts_at, p_ends_at, '[)')
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.is_conversation_member(p_conversation_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = p_conversation_id
      and cp.user_id = p_user_id
      and cp.is_active = true
  );
$function$;

CREATE OR REPLACE FUNCTION public.listing_area_address(p_area text, p_city text, p_postal_code text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select nullif(
    concat_ws(', ',
      nullif(btrim(coalesce(p_area, '')), ''),
      nullif(btrim(concat_ws(' ',
        nullif(btrim(coalesce(p_city, '')), ''),
        nullif(btrim(coalesce(p_postal_code, '')), '')
      )), '')
    ),
  '');
$function$;

CREATE OR REPLACE FUNCTION public.mark_all_notifications_read(p_user_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  affected_rows integer;
begin
  if auth.uid() is not null and auth.uid() <> p_user_id then
    raise exception 'Not authorized';
  end if;
  update notifications
  set status = 'read', read_at = now()
  where user_id = p_user_id and status = 'unread';
  get diagnostics affected_rows = row_count;
  return affected_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION public.mark_cash_payment(p_booking_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_tenant uuid;
  v_listing uuid;
  v_total numeric;
  v_pay_status text;
  v_owner uuid;
  v_title text;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;

  select tenant_id, listing_id, total_price, payment_status
    into v_tenant, v_listing, v_total, v_pay_status
    from public.bookings where id = p_booking_id;
  if v_tenant is null then raise exception 'Booking not found'; end if;

  select owner_id, title into v_owner, v_title
    from public.listings where id = v_listing;
  if v_owner is null or v_owner <> v_uid then
    raise exception 'Only the host can confirm a cash payment' using errcode = '42501';
  end if;

  -- Idempotent: already settled (online or a prior cash confirm) → no-op.
  if v_pay_status = 'paid' then return; end if;

  insert into public.payments (
    booking_id, user_id, tran_id, amount, currency, status,
    card_type, validated_at, gateway_response
  ) values (
    p_booking_id, v_tenant, 'CASH-' || p_booking_id::text,
    coalesce(v_total, 0), 'BDT', 'paid',
    'cash', now(), jsonb_build_object('method', 'cash', 'confirmed_by', v_uid)
  )
  on conflict (tran_id) do nothing;

  update public.bookings set payment_status = 'paid' where id = p_booking_id;

  -- Let the guest see the confirmation live (reliable notifications channel).
  insert into public.notifications (user_id, type, title, body, action_url)
  values (
    v_tenant, 'payment_received', 'Cash payment confirmed',
    'The host confirmed your cash payment for ' || coalesce(v_title, 'your booking') || '.',
    '/trips'
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.migrate_conversation_participants()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  migrated INTEGER := 0;
  conv RECORD;
BEGIN
  FOR conv IN SELECT id, participant_one_id, participant_two_id FROM public.conversations LOOP
    -- Insert participant one if not exists
    INSERT INTO public.conversation_participants (conversation_id, user_id, role)
    VALUES (conv.id, conv.participant_one_id, 'guest')
    ON CONFLICT (conversation_id, user_id) DO NOTHING;

    -- Insert participant two if not exists
    INSERT INTO public.conversation_participants (conversation_id, user_id, role)
    VALUES (conv.id, conv.participant_two_id, 'guest')
    ON CONFLICT (conversation_id, user_id) DO NOTHING;

    migrated := migrated + 1;
  END LOOP;

  RETURN migrated;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nearby_landmarks(p_lat double precision, p_lng double precision, p_limit integer DEFAULT 5, p_type text DEFAULT NULL::text)
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select to_jsonb(x) from (
    select id, name, type, city, area, latitude, longitude,
           ST_Distance(geog, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography) as distance_m
    from public.landmarks
    where is_active and (p_type is null or type = p_type)
    order by geog <-> ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    limit greatest(coalesce(p_limit, 5), 0)
  ) x;
$function$;

CREATE OR REPLACE FUNCTION public.notify_on_booking_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_host_id UUID;
    v_guest_id UUID;
    v_listing_title TEXT;
    v_guest_name TEXT;
    v_starts_at TEXT;
    v_ends_at TEXT;
BEGIN
    -- Get listing owner (host) and title
    SELECT l.owner_id, l.title
    INTO v_host_id, v_listing_title
    FROM public.listings l
    WHERE l.id = NEW.listing_id;

    -- Get guest name from profiles
    SELECT COALESCE(p.full_name, p.mobile, 'A guest')
    INTO v_guest_name
    FROM public.profiles p
    WHERE p.id = NEW.tenant_id;

    v_guest_id := NEW.tenant_id;

    -- Format dates
    v_starts_at := to_char(NEW.starts_at, 'Mon DD, YYYY');
    v_ends_at := to_char(NEW.ends_at, 'Mon DD, YYYY');

    -- Determine notification type based on operation
    IF TG_OP = 'INSERT' THEN
        -- New booking request - notify host
        INSERT INTO public.notifications (user_id, type, title, body, priority, data, action_url, group_key)
        VALUES (
            v_host_id,
            'booking_request',
            'New Booking Request',
            v_guest_name || ' wants to book "' || v_listing_title || '" from ' || v_starts_at || ' to ' || v_ends_at,
            'high',
            jsonb_build_object(
                'booking_id', NEW.id,
                'listing_id', NEW.listing_id,
                'tenant_id', NEW.tenant_id,
                'guest_name', v_guest_name,
                'starts_at', NEW.starts_at,
                'ends_at', NEW.ends_at,
                'total_price', NEW.total_price
            ),
            '/host/reservations/' || NEW.id,
            'booking_' || NEW.id
        );

        RAISE NOTICE 'Created booking notification for host %', v_host_id;

    ELSIF TG_OP = 'UPDATE' THEN
        -- Status changed
        IF OLD.booking_status IS DISTINCT FROM NEW.booking_status THEN
            CASE NEW.booking_status
                WHEN 'confirmed' THEN
                    -- Notify guest of confirmation
                    INSERT INTO public.notifications (user_id, type, title, body, priority, data, action_url, group_key)
                    VALUES (
                        v_guest_id,
                        'booking_confirmed',
                        'Booking Confirmed!',
                        'Your booking at "' || v_listing_title || '" has been confirmed. Check-in: ' || v_starts_at,
                        'high',
                        jsonb_build_object(
                            'booking_id', NEW.id,
                            'listing_id', NEW.listing_id,
                            'starts_at', NEW.starts_at,
                            'ends_at', NEW.ends_at
                        ),
                        '/trips/' || NEW.id,
                        'booking_' || NEW.id
                    );

                WHEN 'cancelled' THEN
                    -- Notify guest
                    INSERT INTO public.notifications (user_id, type, title, body, priority, data, action_url, group_key)
                    VALUES (
                        v_guest_id,
                        'booking_cancelled',
                        'Booking Cancelled',
                        'Your booking at "' || v_listing_title || '" has been cancelled',
                        'high',
                        jsonb_build_object('booking_id', NEW.id, 'listing_id', NEW.listing_id),
                        '/trips/' || NEW.id,
                        'booking_' || NEW.id
                    );

                    -- Also notify host
                    INSERT INTO public.notifications (user_id, type, title, body, priority, data, action_url, group_key)
                    VALUES (
                        v_host_id,
                        'booking_cancelled',
                        'Booking Cancelled',
                        'A booking for "' || v_listing_title || '" has been cancelled',
                        'normal',
                        jsonb_build_object('booking_id', NEW.id, 'listing_id', NEW.listing_id),
                        '/host/reservations/' || NEW.id,
                        'booking_' || NEW.id
                    );

                WHEN 'completed' THEN
                    -- Notify guest to leave a review
                    INSERT INTO public.notifications (user_id, type, title, body, priority, data, action_url, group_key)
                    VALUES (
                        v_guest_id,
                        'review_reminder',
                        'How was your stay?',
                        'Share your experience at "' || v_listing_title || '"',
                        'normal',
                        jsonb_build_object('booking_id', NEW.id, 'listing_id', NEW.listing_id),
                        '/review/' || NEW.id,
                        'booking_' || NEW.id
                    );

                ELSE
                    -- No notification for other status changes
                    NULL;
            END CASE;
        END IF;
    END IF;

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Log error but don't fail the booking
        RAISE WARNING 'Notification trigger error: %', SQLERRM;
        RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_on_booking_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    listing_record RECORD;
    guest_record RECORD;
    notification_title text;
    notification_body text;
    notification_type text;
    notification_priority text;
    target_user_id uuid;
    action_url text;
BEGIN
    -- Get listing info (using owner_id, not host_id)
    SELECT l.title, l.owner_id INTO listing_record
    FROM public.listings l
    WHERE l.id = NEW.listing_id;

    -- Get guest info from profiles
    SELECT p.full_name INTO guest_record
    FROM public.profiles p
    WHERE p.id = NEW.tenant_id;

    -- Handle different status transitions
    CASE
        -- New booking request
        WHEN TG_OP = 'INSERT' AND NEW.booking_status = 'pending' THEN
            notification_title := 'New Booking Request';
            notification_body := format('%s wants to book %s',
                COALESCE(guest_record.full_name, 'A guest'),
                COALESCE(listing_record.title, 'your property'));
            notification_type := 'booking_request';
            notification_priority := 'high';
            target_user_id := listing_record.owner_id;
            action_url := '/host/reservations/' || NEW.id;

        -- Booking confirmed
        WHEN TG_OP = 'UPDATE' AND OLD.booking_status = 'pending' AND NEW.booking_status = 'confirmed' THEN
            notification_title := 'Booking Confirmed!';
            notification_body := format('Your booking at %s has been confirmed',
                COALESCE(listing_record.title, 'the property'));
            notification_type := 'booking_confirmed';
            notification_priority := 'high';
            target_user_id := NEW.tenant_id;
            action_url := '/trips/' || NEW.id;

        -- Booking rejected
        WHEN TG_OP = 'UPDATE' AND OLD.booking_status = 'pending' AND NEW.booking_status = 'rejected' THEN
            notification_title := 'Booking Declined';
            notification_body := CASE
                WHEN NEW.rejection_reason IS NOT NULL THEN
                    format('Your booking was declined: %s', NEW.rejection_reason)
                ELSE
                    format('Your booking at %s was declined', COALESCE(listing_record.title, 'the property'))
            END;
            notification_type := 'booking_rejected';
            notification_priority := 'normal';
            target_user_id := NEW.tenant_id;
            action_url := '/trips/' || NEW.id;

        -- Guest checked in
        WHEN TG_OP = 'UPDATE' AND OLD.booking_status = 'confirmed' AND NEW.booking_status = 'active' THEN
            notification_title := 'Enjoy Your Stay!';
            notification_body := format('You are now checked in at %s',
                COALESCE(listing_record.title, 'the property'));
            notification_type := 'checked_in';
            notification_priority := 'normal';
            target_user_id := NEW.tenant_id;
            action_url := '/trips/' || NEW.id;

        -- Service completed
        WHEN TG_OP = 'UPDATE' AND OLD.booking_status = 'active' AND NEW.booking_status = 'completed' THEN
            -- Notify guest to leave review
            notification_title := 'How Was Your Stay?';
            notification_body := format('Your stay at %s is complete. Leave a review!',
                COALESCE(listing_record.title, 'the property'));
            notification_type := 'review_prompt';
            notification_priority := 'normal';
            target_user_id := NEW.tenant_id;
            action_url := '/review/' || NEW.id || '/guest';

            -- Insert notification for guest
            INSERT INTO public.notifications (
                user_id, type, title, body, priority, action_url, data
            ) VALUES (
                target_user_id,
                notification_type::notification_type,
                notification_title,
                notification_body,
                notification_priority::notification_priority,
                action_url,
                jsonb_build_object(
                    'booking_id', NEW.id,
                    'listing_id', NEW.listing_id,
                    'listing_title', listing_record.title
                )
            );

            -- Also notify host to leave review
            notification_title := 'Leave a Guest Review';
            notification_body := format('Your guest %s has checked out. Leave a review!',
                COALESCE(guest_record.full_name, 'your guest'));
            target_user_id := listing_record.owner_id;
            action_url := '/review/' || NEW.id || '/host';

        -- Booking cancelled by guest
        WHEN TG_OP = 'UPDATE' AND NEW.booking_status = 'cancelled' AND NEW.cancelled_by = NEW.tenant_id THEN
            notification_title := 'Booking Cancelled';
            notification_body := format('%s cancelled their booking at %s',
                COALESCE(guest_record.full_name, 'A guest'),
                COALESCE(listing_record.title, 'your property'));
            notification_type := 'booking_cancelled';
            notification_priority := 'high';
            target_user_id := listing_record.owner_id;
            action_url := '/host/reservations/' || NEW.id;

        -- Booking cancelled by host
        WHEN TG_OP = 'UPDATE' AND NEW.booking_status = 'cancelled' AND NEW.cancelled_by != NEW.tenant_id THEN
            notification_title := 'Booking Cancelled by Host';
            notification_body := format('Your booking at %s was cancelled by the host',
                COALESCE(listing_record.title, 'the property'));
            notification_type := 'booking_cancelled';
            notification_priority := 'high';
            target_user_id := NEW.tenant_id;
            action_url := '/trips/' || NEW.id;

        ELSE
            -- No notification needed for other cases
            RETURN NEW;
    END CASE;

    -- Insert notification
    INSERT INTO public.notifications (
        user_id, type, title, body, priority, action_url, data
    ) VALUES (
        target_user_id,
        notification_type::notification_type,
        notification_title,
        notification_body,
        notification_priority::notification_priority,
        action_url,
        jsonb_build_object(
            'booking_id', NEW.id,
            'listing_id', NEW.listing_id,
            'tenant_id', NEW.tenant_id,
            'listing_title', listing_record.title,
            'guest_name', guest_record.full_name,
            'check_in', NEW.starts_at,
            'check_out', NEW.ends_at,
            'total_price', NEW.total_price
        )
    );

    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_on_review_revealed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    booking_record RECORD;
    listing_record RECORD;
BEGIN
    -- Only trigger when review is revealed
    IF NEW.is_revealed = true AND (OLD.is_revealed = false OR OLD IS NULL) THEN
        -- Get booking and listing info
        SELECT b.*, l.title AS listing_title, l.owner_id
        INTO booking_record
        FROM public.bookings b
        LEFT JOIN public.listings l ON l.id = b.listing_id
        WHERE b.id = NEW.booking_id;

        -- Notify the reviewee that they received a review
        INSERT INTO public.notifications (
            user_id, type, title, body, priority, action_url, data
        ) VALUES (
            NEW.reviewee_id,
            'review_received'::notification_type,
            'New Review',
            CASE
                WHEN NEW.review_type = 'guest_to_host' THEN
                    format('You received a %s star review for %s',
                        NEW.overall_rating,
                        COALESCE(booking_record.listing_title, 'your property'))
                ELSE
                    format('You received a %s star review from a host', NEW.overall_rating)
            END,
            'normal'::notification_priority,
            CASE
                WHEN NEW.review_type = 'guest_to_host' THEN '/listing/' || NEW.listing_id || '/reviews'
                ELSE '/profile/reviews'
            END,
            jsonb_build_object(
                'review_id', NEW.id,
                'booking_id', NEW.booking_id,
                'rating', NEW.overall_rating,
                'review_type', NEW.review_type
            )
        );
    END IF;

    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_recipient_on_new_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_recipient_id UUID;
    v_sender_name TEXT;
    v_preview TEXT;
BEGIN
    -- The recipient is the conversation participant who isn't the sender.
    SELECT CASE
             WHEN c.participant_one_id = NEW.sender_id THEN c.participant_two_id
             ELSE c.participant_one_id
           END
    INTO v_recipient_id
    FROM public.conversations c
    WHERE c.id = NEW.conversation_id;

    IF v_recipient_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT COALESCE(p.full_name, 'New message')
    INTO v_sender_name
    FROM public.profiles p
    WHERE p.id = NEW.sender_id;

    v_preview := CASE
        WHEN NEW.content_type = 'text' THEN LEFT(NEW.content, 140)
        WHEN NEW.content_type = 'booking_card' THEN LEFT(NEW.content, 140)
        WHEN NEW.content_type = 'image' THEN '📷 Sent a photo'
        WHEN NEW.content_type = 'location' THEN '📍 Shared a location'
        WHEN NEW.content_type = 'file' THEN '📎 Sent a file'
        ELSE 'Sent a message'
    END;

    -- The on_notification_send_push trigger (migration 015) picks this row
    -- up and delivers the FCM push.
    INSERT INTO public.notifications (
        user_id,
        type,
        title,
        body,
        data,
        group_key,
        action_url
    ) VALUES (
        v_recipient_id,
        'new_message',
        COALESCE(v_sender_name, 'New message'),
        v_preview,
        jsonb_build_object(
            'conversation_id', NEW.conversation_id,
            'message_id', NEW.id,
            'sender_id', NEW.sender_id
        ),
        'conversation_' || NEW.conversation_id,
        '/messages/' || NEW.conversation_id
    );

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Never block the message insert because notifying failed.
        RAISE WARNING 'new-message notification error: %', SQLERRM;
        RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.otp_log_attempts(p_id uuid, p_attempts integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.otp_attempts set attempts = p_attempts where id = p_id;
end $function$;

CREATE OR REPLACE FUNCTION public.otp_log_send(p_phone text, p_otp_hash text, p_expires_at timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid;
begin
  insert into public.otp_attempts (phone, otp_hash, expires_at)
  values (p_phone, p_otp_hash, p_expires_at)
  returning id into v_id;
  return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.otp_log_verified(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.otp_attempts
  set verified_at = now(), is_used = true
  where id = p_id;
end $function$;

CREATE OR REPLACE FUNCTION public.redeem_coupon(p_coupon_id uuid, p_booking_id uuid, p_discount_amount numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c public.coupons%rowtype;
  v_uid uuid := auth.uid();
  v_booking_owner uuid;
  v_user_uses int;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;

  -- Redemptions may only be recorded for the caller's own booking.
  select tenant_id into v_booking_owner from public.bookings where id = p_booking_id;
  if v_booking_owner is null or v_booking_owner <> v_uid then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  -- One redemption per booking (idempotent no-op on repeat).
  if exists (select 1 from public.coupon_redemptions where booking_id = p_booking_id) then
    return;
  end if;

  select * into c from public.coupons where id = p_coupon_id for update;
  if not found or not c.is_active then raise exception 'Coupon unavailable'; end if;
  if c.usage_limit is not null and c.used_count >= c.usage_limit then
    raise exception 'Coupon usage limit reached';
  end if;
  if c.per_user_limit is not null then
    select count(*) into v_user_uses from public.coupon_redemptions
      where coupon_id = c.id and user_id = v_uid;
    if v_user_uses >= c.per_user_limit then raise exception 'Coupon already used'; end if;
  end if;

  insert into public.coupon_redemptions (coupon_id, user_id, booking_id, discount_amount)
    values (c.id, v_uid, p_booking_id, coalesce(p_discount_amount, 0));
  update public.coupons set used_count = used_count + 1 where id = c.id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.search_landmarks(p_query text DEFAULT NULL::text, p_type text DEFAULT NULL::text, p_limit integer DEFAULT 20)
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select to_jsonb(x) from (
    select id, name, type, city, area, latitude, longitude
    from public.landmarks
    where is_active
      and (p_type is null or type = p_type)
      and (p_query is null or p_query = '' or
           name ilike '%' || p_query || '%' or
           area ilike '%' || p_query || '%' or
           city ilike '%' || p_query || '%')
    order by name
    limit greatest(coalesce(p_limit, 20), 0)
  ) x;
$function$;

CREATE OR REPLACE FUNCTION public.search_listings(p_property_types text[] DEFAULT NULL::text[], p_guest_count integer DEFAULT 1, p_min_price numeric DEFAULT NULL::numeric, p_max_price numeric DEFAULT NULL::numeric, p_amenities text[] DEFAULT NULL::text[], p_location text DEFAULT NULL::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0, p_purpose_tags text[] DEFAULT NULL::text[], p_center_lat double precision DEFAULT NULL::double precision, p_center_lng double precision DEFAULT NULL::double precision, p_radius_m integer DEFAULT NULL::integer, p_radii integer[] DEFAULT NULL::integer[], p_ne_lat double precision DEFAULT NULL::double precision, p_ne_lng double precision DEFAULT NULL::double precision, p_sw_lat double precision DEFAULT NULL::double precision, p_sw_lng double precision DEFAULT NULL::double precision)
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with center as (
    select case
             when p_center_lat is not null and p_center_lng is not null
             then ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
           end as g
  ),
  -- The bounding box is active only when all four corners are present and the
  -- box is non-degenerate (north-east actually north-east of south-west).
  bbox as (
    select (p_ne_lat is not null and p_ne_lng is not null
            and p_sw_lat is not null and p_sw_lng is not null
            and p_ne_lat > p_sw_lat and p_ne_lng > p_sw_lng) as active
  ),
  -- Every filter except the expanding radius. dist is non-null whenever a
  -- center is set and the listing has coordinates.
  base as (
    select l.id as lid, l as row_l, lr.average_rating as rating,
           coalesce(lr.review_count, 0) as review_count,
           -- Live host avatar (public_profiles is anon-readable, no PII). The
           -- listings.host_avatar_url column is dead (never written), so we
           -- source the real, current picture from the owner's profile. (091)
           pp.avatar_url as host_avatar,
           case when c.g is not null and l.geog is not null
                then ST_Distance(l.geog, c.g) end as dist
    from public.listings l
    left join public.listing_ratings lr on lr.listing_id = l.id
    left join public.public_profiles pp on pp.id = l.owner_id
    cross join center c
    cross join bbox bb
    where l.is_active = true
      and l.host_available = true
      and (p_property_types is null or l.listing_type::text = any(p_property_types))
      and l.max_guests >= coalesce(p_guest_count, 1)
      and (p_min_price is null or least(l.hourly_rate, l.daily_rate, l.monthly_rate) >= p_min_price)
      and (p_max_price is null or least(l.hourly_rate, l.daily_rate, l.monthly_rate) <= p_max_price)
      and (p_location is null or p_location = '' or
           l.city    ilike '%' || p_location || '%' or
           l.address ilike '%' || p_location || '%' or
           l.title   ilike '%' || p_location || '%')
      and (p_amenities is null or (
        select count(distinct f.name)
        from public.listing_facilities lf
        join public.facilities f on f.id = lf.facility_id
        where lf.listing_id = l.id and f.name = any(p_amenities)
      ) = array_length(p_amenities, 1))
      and (p_purpose_tags is null or l.purpose_tags && p_purpose_tags)
      -- bounding-box search: the listing must sit inside the place's extent.
      -- This is the exact area the guest searched, so it supersedes both radius
      -- paths (which are passed null in box mode anyway).
      and (not bb.active or
           (l.latitude between p_sw_lat and p_ne_lat and
            l.longitude between p_sw_lng and p_ne_lng))
      -- single fixed radius (purpose/landmark search) — unchanged
      and (c.g is null or p_radius_m is null or
           (l.geog is not null and ST_DWithin(l.geog, c.g, p_radius_m)))
      -- tiered search ranks by distance; listings without a pin can't qualify
      and (c.g is null or p_radii is null or l.geog is not null)
  ),
  -- Smallest tier that contains at least one match (null → nearest fallback).
  chosen as (
    select min(r) as radius
    from unnest(coalesce(p_radii, '{}'::integer[])) r
    where (select min(dist) from base) <= r
  )
  select to_jsonb(b.row_l) || jsonb_build_object(
    'host_avatar_url', b.host_avatar,
    'rating', b.rating,
    'review_count', b.review_count,
    'distance_m', b.dist,
    'search_radius_m', (select radius from chosen),
    'radius_fallback',
      (p_radii is not null and (select radius from chosen) is null),
    'listing_facilities',
    coalesce((
      select jsonb_agg(jsonb_build_object(
               'facility_id', lf.facility_id,
               'facilities', jsonb_build_object('name', f.name)))
      from public.listing_facilities lf
      join public.facilities f on f.id = lf.facility_id
      where lf.listing_id = b.lid
    ), '[]'::jsonb)
  )
  from base b
  where p_radii is null
     or (select radius from chosen) is null            -- fallback: nearest N
     or b.dist <= (select radius from chosen)
  order by b.dist asc nulls last,
           coalesce(b.rating, 0) desc,
           b.review_count desc,
           (b.row_l).created_at desc
  limit case
          when p_radii is not null and (select radius from chosen) is null
          then least(greatest(coalesce(p_limit, 20), 0), 20)
          else greatest(coalesce(p_limit, 20), 0)
        end
  offset greatest(coalesce(p_offset, 0), 0);
$function$;

CREATE OR REPLACE FUNCTION public.search_listings_by_location(center_lat numeric, center_lng numeric, radius_meters integer DEFAULT 10000)
 RETURNS SETOF listings
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT *
    FROM listings
    WHERE is_active = TRUE
    AND ST_DWithin(
        location,
        ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography,
        radius_meters
    )
    ORDER BY ST_Distance(
        location,
        ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.send_booking_accept_messages(p_booking_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.send_booking_contacts(p_booking_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.send_booking_map(p_booking_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    rec RECORD;
    v_conv_id UUID;
    v_address TEXT;
    v_lang TEXT;
BEGIN
    SELECT b.id AS booking_id, b.tenant_id, b.listing_id,
           COALESCE(b.listing_title, l.title) AS listing_title,
           -- Exact address + coordinates from the gated table, falling back to
           -- the listing's public (area-level) values so a listing with no
           -- listing_addresses row still gets a usable map pin.
           COALESCE(la.exact_address, l.address) AS listing_address,
           l.city AS listing_city,
           COALESCE(la.latitude, l.latitude) AS listing_lat,
           COALESCE(la.longitude, l.longitude) AS listing_lng,
           l.owner_id AS host_id,
           COALESCE(p.message_language, 'en') AS message_language
    INTO rec
    FROM public.bookings b
    JOIN public.listings l ON l.id = b.listing_id
    LEFT JOIN public.listing_addresses la ON la.listing_id = l.id
    LEFT JOIN public.profiles p ON p.id = l.owner_id
    WHERE b.id = p_booking_id AND b.booking_status = 'confirmed'
      AND b.tenant_id IS NOT NULL;

    IF NOT FOUND THEN RETURN; END IF;
    IF rec.listing_lat IS NULL OR rec.listing_lng IS NULL THEN RETURN; END IF;
    IF EXISTS (SELECT 1 FROM public.scheduled_message_sends s
               WHERE s.booking_id = rec.booking_id AND s.trigger = 'map') THEN
        RETURN;
    END IF;

    v_lang := rec.message_language;
    v_address := NULLIF(TRIM(BOTH ', ' FROM
        COALESCE(rec.listing_address, '') ||
        CASE WHEN rec.listing_city IS NOT NULL
                  AND (rec.listing_address IS NULL
                       OR rec.listing_address NOT ILIKE '%' || rec.listing_city || '%')
             THEN ', ' || rec.listing_city ELSE '' END), '');

    v_conv_id := public.get_or_create_conversation(
        rec.tenant_id, rec.host_id, rec.booking_id, rec.listing_id);

    INSERT INTO public.messages
        (conversation_id, sender_id, content, content_type, metadata)
    VALUES (
        v_conv_id, rec.host_id,
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

    INSERT INTO public.scheduled_message_sends (booking_id, trigger)
    VALUES (rec.booking_id, 'map');
END;
$function$;

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

CREATE OR REPLACE FUNCTION public.send_precheckin_for_booking(p_booking_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
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
    SELECT b.id AS booking_id, b.tenant_id, b.tenant_name, b.guest_count,
           b.starts_at, b.ends_at, b.pricing_unit,
           COALESCE(b.listing_title, l.title) AS listing_title,
           b.listing_id, l.address AS listing_address, l.city AS listing_city,
           l.owner_id AS host_id,
           COALESCE(p.full_name, 'Your host') AS host_name,
           COALESCE(p.message_language, 'en') AS message_language,
           cd.directions AS ci_directions, cd.wifi_name AS ci_wifi_name,
           cd.wifi_password AS ci_wifi_password, cd.access_code AS ci_access_code
    INTO rec
    FROM public.bookings b
    JOIN public.listings l ON l.id = b.listing_id
    LEFT JOIN public.profiles p ON p.id = l.owner_id
    LEFT JOIN public.listing_checkin_details cd ON cd.listing_id = b.listing_id
    WHERE b.id = p_booking_id AND b.booking_status = 'confirmed'
      AND b.tenant_id IS NOT NULL;

    IF NOT FOUND THEN RETURN; END IF;

    -- Already delivered for this booking?
    IF EXISTS (SELECT 1 FROM public.scheduled_message_sends s
               WHERE s.booking_id = rec.booking_id AND s.trigger = 'check_in') THEN
        RETURN;
    END IF;

    v_lang := rec.message_language;

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

    SELECT t.content, t.enabled, t.lead_days
    INTO v_content, v_enabled, v_lead_days
    FROM public.message_templates t
    WHERE t.host_id = rec.host_id AND t.trigger = 'check_in';

    IF NOT FOUND THEN
        v_enabled := TRUE;
        v_lead_days := 2;
        v_content := CASE WHEN v_lang = 'bn' THEN v_default_bn ELSE v_default_en END;
    ELSIF v_content = v_default_en OR v_content = v_default_bn THEN
        v_content := CASE WHEN v_lang = 'bn' THEN v_default_bn ELSE v_default_en END;
    END IF;

    IF NOT v_enabled THEN RETURN; END IF;
    -- Not yet within the near-check-in window — the cron will pick it up later.
    IF rec.starts_at > NOW() + make_interval(days => v_lead_days) THEN RETURN; END IF;

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

    v_address := NULLIF(TRIM(BOTH ', ' FROM
        COALESCE(rec.listing_address, '') ||
        CASE WHEN rec.listing_city IS NOT NULL
                  AND (rec.listing_address IS NULL
                       OR rec.listing_address NOT ILIKE '%' || rec.listing_city || '%')
             THEN ', ' || rec.listing_city ELSE '' END), '');

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
    v_rendered := replace(v_rendered, '{{directions}}', COALESCE(rec.ci_directions, ''));
    v_rendered := replace(v_rendered, '{{wifi_name}}', COALESCE(rec.ci_wifi_name, ''));
    v_rendered := replace(v_rendered, '{{wifi_password}}', COALESCE(rec.ci_wifi_password, ''));
    v_rendered := replace(v_rendered, '{{access_code}}', COALESCE(rec.ci_access_code, ''));

    INSERT INTO public.messages (conversation_id, sender_id, content, content_type)
    VALUES (v_conv_id, rec.host_id, v_rendered, 'text');

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

    INSERT INTO public.scheduled_message_sends (booking_id, trigger)
    VALUES (rec.booking_id, 'check_in');
END;
$function$;

CREATE OR REPLACE FUNCTION public.send_push_on_notification_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  perform net.http_post(
    url := 'https://bojkmonskqlhuakxhzcb.supabase.co/functions/v1/send-push-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJvamttb25za3FsaHVha3hoemNiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDcwNTcwMTQsImV4cCI6MjA2MjYzMzAxNH0.gPd0QWSQ2XNjBccqEST97fqAV2HP9NMqwShTqpJlilk',
      'x-push-secret',
      coalesce((select value from public.app_secrets where key = 'push_secret'), '')
    ),
    body := jsonb_build_object(
      'user_id', NEW.user_id,
      'title', NEW.title,
      'body', NEW.body,
      'data', coalesce(NEW.data, '{}'::jsonb) || jsonb_build_object(
        'type', NEW.type::text,
        'notification_id', NEW.id::text,
        'action_url', coalesce(NEW.action_url, '')
      )
    )
  );
  return NEW;
exception
  when others then
    raise warning 'Push notification error: %', SQLERRM;
    return NEW;
end;
$function$;

CREATE OR REPLACE FUNCTION public.send_review_reminders()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    reminder_count integer;
    booking_record RECORD;
    listing_record RECORD;
    existing_guest_review boolean;
    existing_host_review boolean;
BEGIN
    reminder_count := 0;

    -- Find completed bookings that are 3 or 7 days old
    FOR booking_record IN
        SELECT b.*
        FROM public.bookings b
        WHERE b.booking_status = 'completed'
        AND b.completed_at IS NOT NULL
        AND (
            -- 3-day reminder
            (b.completed_at >= NOW() - INTERVAL '3 days 1 hour'
             AND b.completed_at < NOW() - INTERVAL '3 days')
            OR
            -- 7-day reminder
            (b.completed_at >= NOW() - INTERVAL '7 days 1 hour'
             AND b.completed_at < NOW() - INTERVAL '7 days')
        )
    LOOP
        -- Get listing info
        SELECT l.title, l.owner_id INTO listing_record
        FROM public.listings l
        WHERE l.id = booking_record.listing_id;

        -- Check if guest has already reviewed
        SELECT EXISTS (
            SELECT 1 FROM public.reviews r
            WHERE r.booking_id = booking_record.id
            AND r.review_type = 'guest_to_host'
        ) INTO existing_guest_review;

        -- Check if host has already reviewed
        SELECT EXISTS (
            SELECT 1 FROM public.reviews r
            WHERE r.booking_id = booking_record.id
            AND r.review_type = 'host_to_guest'
        ) INTO existing_host_review;

        -- Send reminder to guest if they haven't reviewed
        IF NOT existing_guest_review THEN
            INSERT INTO public.notifications (
                user_id, type, title, body, priority, action_url, data
            ) VALUES (
                booking_record.tenant_id,
                'review_reminder'::notification_type,
                'Don''t Forget to Review!',
                format('Share your experience at %s. Your review helps other travelers!',
                    COALESCE(listing_record.title, 'your recent stay')),
                'normal'::notification_priority,
                '/review/' || booking_record.id || '/guest',
                jsonb_build_object(
                    'booking_id', booking_record.id,
                    'listing_id', booking_record.listing_id,
                    'reminder_type', 'guest'
                )
            );
            reminder_count := reminder_count + 1;
        END IF;

        -- Send reminder to host if they haven't reviewed
        IF NOT existing_host_review THEN
            INSERT INTO public.notifications (
                user_id, type, title, body, priority, action_url, data
            ) VALUES (
                listing_record.owner_id,
                'review_reminder'::notification_type,
                'Review Your Guest',
                format('Don''t forget to review your guest from %s. Your feedback helps the community!',
                    COALESCE(listing_record.title, 'your property')),
                'normal'::notification_priority,
                '/review/' || booking_record.id || '/host',
                jsonb_build_object(
                    'booking_id', booking_record.id,
                    'listing_id', booking_record.listing_id,
                    'reminder_type', 'host'
                )
            );
            reminder_count := reminder_count + 1;
        END IF;
    END LOOP;

    IF reminder_count > 0 THEN
        RAISE NOTICE 'Sent % review reminders', reminder_count;
    END IF;

    RETURN reminder_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_address_verification(p_user_id uuid, p_status verification_status, p_visit_notes text DEFAULT NULL::text, p_rejection_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_admin uuid := auth.uid();
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  if p_status not in ('pending', 'verified', 'rejected') then
    raise exception 'status must be pending, verified or rejected'
      using errcode = '22023';
  end if;
  if p_status = 'rejected'
     and coalesce(btrim(p_rejection_reason), '') = '' then
    raise exception 'a rejection reason is required' using errcode = '22023';
  end if;

  update public.profiles
     set address_verification_status = p_status,
         -- Stamped only on approval; cleared otherwise, so verified_at can
         -- never outlive the verdict it belongs to.
         address_verified_at = case when p_status = 'verified' then now() end,
         address_verified_by = case when p_status = 'verified' then v_admin end,
         address_visit_notes = coalesce(btrim(p_visit_notes), address_visit_notes),
         address_rejection_reason =
           case when p_status = 'rejected' then btrim(p_rejection_reason) end
   where id = p_user_id;

  if not found then
    raise exception 'no such profile' using errcode = 'P0002';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_booking_paid_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.payment_status = 'paid' AND NEW.paid_at IS NULL THEN
        NEW.paid_at := now();
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_booking_payment_method(p_booking_id uuid, p_method text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_tenant uuid;
  v_pay_status text;
  v_status text;
  v_cash_enabled boolean;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;

  if p_method not in ('online', 'cash') then
    raise exception 'Invalid payment method: %', p_method using errcode = '22023';
  end if;

  select tenant_id, payment_status, booking_status
    into v_tenant, v_pay_status, v_status
    from public.bookings where id = p_booking_id;
  if v_tenant is null then raise exception 'Booking not found'; end if;

  -- Only the guest who owns the booking may choose its payment method.
  if v_tenant <> v_uid then
    raise exception 'Only the guest can choose the payment method'
      using errcode = '42501';
  end if;

  -- Nothing to choose once it's already settled.
  if v_pay_status = 'paid' then
    raise exception 'This booking is already paid' using errcode = '42501';
  end if;

  -- Payment is only arranged after the host accepts and before completion.
  if v_status not in ('confirmed', 'active') then
    raise exception 'Payment can only be arranged after the host accepts'
      using errcode = '42501';
  end if;

  -- 'cash' requires the admin toggle. Defence in depth: the client hides the
  -- option, but never trust the client.
  if p_method = 'cash' then
    select lower(coalesce(value, '')) = 'true' into v_cash_enabled
      from public.app_settings where key = 'cash_payment_enabled';
    if not coalesce(v_cash_enabled, false) then
      raise exception 'Cash payment is not available' using errcode = '42501';
    end if;
  end if;

  update public.bookings set payment_method = p_method where id = p_booking_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_landmark_geog()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.geog := ST_SetSRID(ST_MakePoint(new.longitude, new.latitude), 4326)::geography;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_listing_geog()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.latitude is not null and new.longitude is not null then
    new.geog := ST_SetSRID(ST_MakePoint(new.longitude, new.latitude), 4326)::geography;
  else
    new.geog := null;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_listing_host_available()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  SELECT is_available INTO NEW.host_available
  FROM public.profiles WHERE id = NEW.owner_id;
  IF NEW.host_available IS NULL THEN
    NEW.host_available := TRUE;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_verification_pending()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- Set profile to pending if both documents exist
  IF EXISTS (
    SELECT 1 FROM public.owner_documents
    WHERE user_id = NEW.user_id
      AND document_type = 'nid_front'
  ) AND EXISTS (
    SELECT 1 FROM public.owner_documents
    WHERE user_id = NEW.user_id
      AND document_type = 'nid_back'
  ) THEN
    UPDATE public.profiles
    SET verification_status = 'pending'
    WHERE id = NEW.user_id AND verification_status = 'none';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.snap_coordinate(p_degrees numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select round(p_degrees / 0.001) * 0.001;
$function$;

CREATE OR REPLACE FUNCTION public.submit_address_verification(p_address_line text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if coalesce(btrim(p_address_line), '') = '' then
    raise exception 'a full address is required' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.profiles
     where id = v_uid and address_proof_path is not null
  ) then
    raise exception 'upload a proof-of-address document first'
      using errcode = '22023';
  end if;

  update public.profiles
     set address_line = btrim(p_address_line),
         address_verification_status = 'pending',
         address_submitted_at = now()
   where id = v_uid;
end;
$function$;

CREATE OR REPLACE FUNCTION public.sync_listings_host_available()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  IF NEW.is_available IS DISTINCT FROM OLD.is_available THEN
    UPDATE public.listings
    SET host_available = NEW.is_available
    WHERE owner_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.touch_listing_address()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.touch_message_templates_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.touch_payments_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_conversation_last_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.conversations
  SET
    last_message_id = NEW.id,
    last_message_text = CASE
      WHEN NEW.content_type = 'text' THEN LEFT(NEW.content, 100)
      WHEN NEW.content_type = 'booking_card' THEN 'Booking details'
      WHEN NEW.content_type = 'image' THEN 'Sent an image'
      WHEN NEW.content_type = 'location' THEN 'Shared a location'
      WHEN NEW.content_type = 'file' THEN 'Sent a file'
      ELSE LEFT(NEW.content, 100)
    END,
    last_message_at = NEW.created_at,
    last_message_sender_id = NEW.sender_id,
    last_message_preview = LEFT(NEW.content, 100),
    updated_at = NOW()
  WHERE id = NEW.conversation_id;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_fcm_token_timestamp()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_listing_location()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL THEN
        NEW.location = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_listing_rating()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE listings
    SET
        rating = (SELECT AVG(rating) FROM reviews WHERE listing_id = NEW.listing_id),
        review_count = (SELECT COUNT(*) FROM reviews WHERE listing_id = NEW.listing_id)
    WHERE id = NEW.listing_id;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_notifications_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
  BEGIN
      NEW.updated_at = NOW();
      RETURN NEW;
  END;
  $function$;

CREATE OR REPLACE FUNCTION public.update_profile_verification_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- Check if both NID documents are verified
  IF NEW.verified_at IS NOT NULL THEN
    -- Check if both front and back are now verified
    IF EXISTS (
      SELECT 1 FROM public.owner_documents
      WHERE user_id = NEW.user_id
        AND document_type = 'nid_front'
        AND verified_at IS NOT NULL
    ) AND EXISTS (
      SELECT 1 FROM public.owner_documents
      WHERE user_id = NEW.user_id
        AND document_type = 'nid_back'
        AND verified_at IS NOT NULL
    ) THEN
      UPDATE public.profiles
      SET verification_status = 'verified'
      WHERE id = NEW.user_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_reviews_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = timezone('utc', now());
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.upsert_fcm_token(p_user_id uuid, p_token text, p_device_type text DEFAULT 'android'::text, p_device_name text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  insert into public.fcm_tokens (user_id, token, device_type, device_name)
  values (p_user_id, p_token, p_device_type, p_device_name)
  on conflict (user_id, token)
  do update set
    is_active = true,
    last_used_at = now(),
    updated_at = now(),
    device_type = coalesce(excluded.device_type, fcm_tokens.device_type),
    device_name = coalesce(excluded.device_name, fcm_tokens.device_name)
  returning id into v_id;

  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.validate_coupon(p_code text, p_amount numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c public.coupons%rowtype;
  v_uid uuid := auth.uid();
  v_user_uses int;
  v_discount numeric;
begin
  if v_uid is null then
    return jsonb_build_object('valid', false, 'message', 'Please sign in to use a coupon');
  end if;

  select * into c from public.coupons where code = upper(trim(p_code));
  if not found then
    return jsonb_build_object('valid', false, 'message', 'Coupon not found');
  end if;
  if not c.is_active then
    return jsonb_build_object('valid', false, 'message', 'This coupon is no longer active');
  end if;
  if c.starts_at is not null and now() < c.starts_at then
    return jsonb_build_object('valid', false, 'message', 'This coupon is not active yet');
  end if;
  if c.expires_at is not null and now() > c.expires_at then
    return jsonb_build_object('valid', false, 'message', 'This coupon has expired');
  end if;
  if c.usage_limit is not null and c.used_count >= c.usage_limit then
    return jsonb_build_object('valid', false, 'message', 'This coupon has reached its usage limit');
  end if;
  if p_amount < c.min_booking_amount then
    return jsonb_build_object('valid', false, 'message',
      'Minimum booking amount for this coupon is ' || c.min_booking_amount::text);
  end if;
  if c.per_user_limit is not null then
    select count(*) into v_user_uses from public.coupon_redemptions
      where coupon_id = c.id and user_id = v_uid;
    if v_user_uses >= c.per_user_limit then
      return jsonb_build_object('valid', false, 'message', 'You have already used this coupon');
    end if;
  end if;

  if c.discount_type = 'percentage' then
    v_discount := round(p_amount * c.discount_value / 100.0, 2);
    if c.max_discount_amount is not null and v_discount > c.max_discount_amount then
      v_discount := c.max_discount_amount;
    end if;
  else
    v_discount := c.discount_value;
  end if;
  if v_discount > p_amount then v_discount := p_amount; end if;

  return jsonb_build_object(
    'valid', true,
    'coupon_id', c.id,
    'code', c.code,
    'discount_type', c.discount_type,
    'discount_value', c.discount_value,
    'discount_amount', v_discount,
    'final_amount', p_amount - v_discount,
    'message', 'Coupon applied'
  );
end;
$function$;

-- ========================= TRIGGERS =========================
CREATE TRIGGER trg_audit_app_settings AFTER INSERT OR UPDATE ON public.app_settings FOR EACH ROW EXECUTE FUNCTION fn_audit('admin');
CREATE TRIGGER trg_audit_immutable BEFORE DELETE OR UPDATE ON public.audit_log FOR EACH ROW EXECUTE FUNCTION fn_audit_immutable();
CREATE TRIGGER booking_lifecycle_notifications AFTER INSERT OR UPDATE OF booking_status, cancelled_by ON public.bookings FOR EACH ROW EXECUTE FUNCTION notify_on_booking_lifecycle();
CREATE TRIGGER trg_audit_bookings_ins AFTER INSERT ON public.bookings FOR EACH ROW EXECUTE FUNCTION fn_audit('financial');
CREATE TRIGGER trg_audit_bookings_upd AFTER UPDATE ON public.bookings FOR EACH ROW WHEN (((old.payment_status IS DISTINCT FROM new.payment_status) OR (old.payment_method IS DISTINCT FROM new.payment_method) OR (old.booking_status IS DISTINCT FROM new.booking_status) OR (old.total_price IS DISTINCT FROM new.total_price))) EXECUTE FUNCTION fn_audit('financial');
CREATE TRIGGER trg_enforce_booking_update_rules BEFORE UPDATE ON public.bookings FOR EACH ROW EXECUTE FUNCTION enforce_booking_update_rules();
CREATE TRIGGER trg_set_booking_paid_at BEFORE INSERT OR UPDATE OF payment_status ON public.bookings FOR EACH ROW EXECUTE FUNCTION set_booking_paid_at();
CREATE TRIGGER trg_audit_coupon_redemptions_ins AFTER INSERT ON public.coupon_redemptions FOR EACH ROW EXECUTE FUNCTION fn_audit('discount');
CREATE TRIGGER coupons_normalize_code_trg BEFORE INSERT OR UPDATE ON public.coupons FOR EACH ROW EXECUTE FUNCTION coupons_normalize_code();
CREATE TRIGGER trg_audit_coupons_del AFTER DELETE ON public.coupons FOR EACH ROW EXECUTE FUNCTION fn_audit('discount');
CREATE TRIGGER trg_audit_coupons_ins AFTER INSERT ON public.coupons FOR EACH ROW EXECUTE FUNCTION fn_audit('discount');
CREATE TRIGGER trg_audit_coupons_upd AFTER UPDATE ON public.coupons FOR EACH ROW WHEN (((old.is_active IS DISTINCT FROM new.is_active) OR (old.discount_type IS DISTINCT FROM new.discount_type) OR (old.discount_value IS DISTINCT FROM new.discount_value) OR (old.max_discount_amount IS DISTINCT FROM new.max_discount_amount) OR (old.min_booking_amount IS DISTINCT FROM new.min_booking_amount) OR (old.usage_limit IS DISTINCT FROM new.usage_limit) OR (old.per_user_limit IS DISTINCT FROM new.per_user_limit) OR (old.starts_at IS DISTINCT FROM new.starts_at) OR (old.expires_at IS DISTINCT FROM new.expires_at))) EXECUTE FUNCTION fn_audit('discount');
CREATE TRIGGER fcm_tokens_updated_at BEFORE UPDATE ON public.fcm_tokens FOR EACH ROW EXECUTE FUNCTION update_fcm_token_timestamp();
CREATE TRIGGER trg_set_landmark_geog BEFORE INSERT OR UPDATE OF latitude, longitude ON public.landmarks FOR EACH ROW EXECUTE FUNCTION set_landmark_geog();
CREATE TRIGGER trg_touch_listing_address BEFORE UPDATE ON public.listing_addresses FOR EACH ROW EXECUTE FUNCTION touch_listing_address();
CREATE TRIGGER enforce_listing_public_location BEFORE INSERT OR UPDATE ON public.listings FOR EACH ROW EXECUTE FUNCTION enforce_listing_public_location();
CREATE TRIGGER listing_location_trigger BEFORE INSERT OR UPDATE ON public.listings FOR EACH ROW EXECUTE FUNCTION update_listing_location();
CREATE TRIGGER trg_set_listing_geog BEFORE INSERT OR UPDATE OF latitude, longitude ON public.listings FOR EACH ROW EXECUTE FUNCTION set_listing_geog();
CREATE TRIGGER trg_set_listing_host_available BEFORE INSERT ON public.listings FOR EACH ROW EXECUTE FUNCTION set_listing_host_available();
CREATE TRIGGER on_message_template_update BEFORE UPDATE ON public.message_templates FOR EACH ROW EXECUTE FUNCTION touch_message_templates_updated_at();
CREATE TRIGGER on_message_notify_recipient AFTER INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION notify_recipient_on_new_message();
CREATE TRIGGER trigger_update_conversation_last_message AFTER INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION update_conversation_last_message();
CREATE TRIGGER notification_preferences_updated_at BEFORE UPDATE ON public.notification_preferences FOR EACH ROW EXECUTE FUNCTION update_notifications_updated_at();
CREATE TRIGGER notifications_updated_at BEFORE UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION update_notifications_updated_at();
CREATE TRIGGER on_notification_send_push AFTER INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION send_push_on_notification_insert();
CREATE TRIGGER on_document_uploaded AFTER INSERT ON public.owner_documents FOR EACH ROW EXECUTE FUNCTION set_verification_pending();
CREATE TRIGGER on_document_verified AFTER UPDATE OF verified_at ON public.owner_documents FOR EACH ROW WHEN (((new.verified_at IS NOT NULL) AND (old.verified_at IS NULL))) EXECUTE FUNCTION update_profile_verification_status();
CREATE TRIGGER trg_audit_owner_documents_upd AFTER UPDATE ON public.owner_documents FOR EACH ROW WHEN (((old.verified_at IS DISTINCT FROM new.verified_at) OR (old.verified_by IS DISTINCT FROM new.verified_by) OR (old.rejection_reason IS DISTINCT FROM new.rejection_reason))) EXECUTE FUNCTION fn_audit('verification');
CREATE TRIGGER payments_touch_updated_at BEFORE UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION touch_payments_updated_at();
CREATE TRIGGER trg_audit_payments_ins AFTER INSERT ON public.payments FOR EACH ROW EXECUTE FUNCTION fn_audit('financial');
CREATE TRIGGER trg_audit_payments_upd AFTER UPDATE ON public.payments FOR EACH ROW WHEN (((old.status IS DISTINCT FROM new.status) OR (old.validated_at IS DISTINCT FROM new.validated_at))) EXECUTE FUNCTION fn_audit('financial');
CREATE TRIGGER trg_audit_profiles_address_verification AFTER UPDATE ON public.profiles FOR EACH ROW WHEN (((old.address_verification_status IS DISTINCT FROM new.address_verification_status) OR (old.address_verified_by IS DISTINCT FROM new.address_verified_by))) EXECUTE FUNCTION fn_audit('verification');
CREATE TRIGGER trg_audit_profiles_upd AFTER UPDATE ON public.profiles FOR EACH ROW WHEN (((old.role IS DISTINCT FROM new.role) OR (old.is_host IS DISTINCT FROM new.is_host))) EXECUTE FUNCTION fn_audit('auth');
CREATE TRIGGER trg_guard_verification_verdicts BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION fn_guard_verification_verdicts();
CREATE TRIGGER trg_sync_listings_host_available AFTER UPDATE OF is_available ON public.profiles FOR EACH ROW EXECUTE FUNCTION sync_listings_host_available();
CREATE TRIGGER push_tokens_updated_at BEFORE UPDATE ON public.push_tokens FOR EACH ROW EXECUTE FUNCTION update_notifications_updated_at();
CREATE TRIGGER trg_audit_reports_ins AFTER INSERT ON public.reports FOR EACH ROW EXECUTE FUNCTION fn_audit('safety');
CREATE TRIGGER trg_audit_reports_upd AFTER UPDATE ON public.reports FOR EACH ROW WHEN (((old.status IS DISTINCT FROM new.status) OR (old.resolution_note IS DISTINCT FROM new.resolution_note) OR (old.resolved_by IS DISTINCT FROM new.resolved_by))) EXECUTE FUNCTION fn_audit('safety');
CREATE TRIGGER reveal_reviews_on_insert AFTER INSERT ON public.reviews FOR EACH ROW EXECUTE FUNCTION check_and_reveal_reviews();
CREATE TRIGGER review_revealed_notification AFTER UPDATE OF is_revealed ON public.reviews FOR EACH ROW EXECUTE FUNCTION notify_on_review_revealed();
CREATE TRIGGER reviews_updated_at BEFORE UPDATE ON public.reviews FOR EACH ROW EXECUTE FUNCTION update_reviews_updated_at();

