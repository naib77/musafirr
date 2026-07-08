-- =============================================================================
-- LIVE RLS BASELINE — public schema (regenerated from pg_policy)
-- Source of truth for deployed RLS. Current as of migrations through 064.
-- The repo's numbered migrations drifted from what actually ran; edit RLS via a
-- NEW migration, then regenerate this snapshot. Do not hand-edit.
-- =============================================================================

-- ---- app_secrets -------------------------------------------------------
alter table public.app_secrets enable row level security;
-- (no policies — reachable only via SECURITY DEFINER RPCs / service_role)

-- ---- app_settings ------------------------------------------------------
alter table public.app_settings enable row level security;
create policy "app_settings_select_all" on public.app_settings
  for select to public
  using (true);

-- ---- bookings ----------------------------------------------------------
alter table public.bookings enable row level security;
create policy "Hosts can update bookings for their listings" on public.bookings
  for update to public
  using ((EXISTS ( SELECT 1
   FROM listings
  WHERE ((listings.id = bookings.listing_id) AND (listings.owner_id = auth.uid())))))
  with check ((EXISTS ( SELECT 1
   FROM listings
  WHERE ((listings.id = bookings.listing_id) AND (listings.owner_id = auth.uid())))));
create policy "Hosts can view bookings for their listings" on public.bookings
  for select to public
  using ((EXISTS ( SELECT 1
   FROM listings
  WHERE ((listings.id = bookings.listing_id) AND (listings.owner_id = auth.uid())))));
create policy "Users can cancel their own bookings" on public.bookings
  for update to public
  using ((auth.uid() = tenant_id));
create policy "Users can create bookings" on public.bookings
  for insert to public
  with check ((auth.uid() = tenant_id));
create policy "Users can view their own bookings" on public.bookings
  for select to public
  using ((auth.uid() = tenant_id));

-- ---- conversation_participants -----------------------------------------
alter table public.conversation_participants enable row level security;
create policy "Users can add participants" on public.conversation_participants
  for insert to public
  with check (is_conversation_member(conversation_id, auth.uid()));
create policy "Users can leave conversations" on public.conversation_participants
  for update to public
  using ((user_id = auth.uid()));
create policy "Users can view participants in own conversations" on public.conversation_participants
  for select to public
  using (is_conversation_member(conversation_id, auth.uid()));

-- ---- conversations -----------------------------------------------------
alter table public.conversations enable row level security;
create policy "Users can insert conversations" on public.conversations
  for insert to public
  with check (((auth.uid() = participant_one_id) OR (auth.uid() = participant_two_id)));
create policy "Users can update own conversations" on public.conversations
  for update to public
  using (((auth.uid() = participant_one_id) OR (auth.uid() = participant_two_id)));
create policy "Users can view own conversations" on public.conversations
  for select to public
  using (((auth.uid() = participant_one_id) OR (auth.uid() = participant_two_id)));

-- ---- facilities --------------------------------------------------------
alter table public.facilities enable row level security;
create policy "facilities_read_authenticated" on public.facilities
  for select to authenticated
  using (true);

-- ---- favorites ---------------------------------------------------------
alter table public.favorites enable row level security;
create policy "favorites_delete_own" on public.favorites
  for delete to public
  using ((auth.uid() = user_id));
create policy "favorites_insert_own" on public.favorites
  for insert to public
  with check ((auth.uid() = user_id));
create policy "favorites_select_own" on public.favorites
  for select to public
  using ((auth.uid() = user_id));

-- ---- fcm_tokens --------------------------------------------------------
alter table public.fcm_tokens enable row level security;
create policy "Service role can read all fcm tokens" on public.fcm_tokens
  for select to service_role
  using (true);
create policy "Users can delete own fcm tokens" on public.fcm_tokens
  for delete to authenticated
  using ((auth.uid() = user_id));
create policy "Users can insert own fcm tokens" on public.fcm_tokens
  for insert to authenticated
  with check ((auth.uid() = user_id));
create policy "Users can update own fcm tokens" on public.fcm_tokens
  for update to authenticated
  using ((auth.uid() = user_id))
  with check ((auth.uid() = user_id));
create policy "Users can view own fcm tokens" on public.fcm_tokens
  for select to authenticated
  using ((auth.uid() = user_id));

-- ---- host_leaderboard_snapshots ----------------------------------------
alter table public.host_leaderboard_snapshots enable row level security;
-- (no policies — reachable only via SECURITY DEFINER RPCs / service_role)

-- ---- listing_checkin_details -------------------------------------------
alter table public.listing_checkin_details enable row level security;
create policy "owner_manages_checkin_details" on public.listing_checkin_details
  for all to authenticated
  using ((EXISTS ( SELECT 1
   FROM listings l
  WHERE ((l.id = listing_checkin_details.listing_id) AND (l.owner_id = auth.uid())))))
  with check ((EXISTS ( SELECT 1
   FROM listings l
  WHERE ((l.id = listing_checkin_details.listing_id) AND (l.owner_id = auth.uid())))));

-- ---- listing_facilities ------------------------------------------------
alter table public.listing_facilities enable row level security;
create policy "Anyone can view listing facilities" on public.listing_facilities
  for select to public
  using (true);
create policy "Owners can manage their listing facilities" on public.listing_facilities
  for all to public
  using ((EXISTS ( SELECT 1
   FROM listings
  WHERE ((listings.id = listing_facilities.listing_id) AND (listings.owner_id = auth.uid())))));

-- ---- listings ----------------------------------------------------------
alter table public.listings enable row level security;
create policy "Anyone can view active listings" on public.listings
  for select to public
  using (((is_active = true) OR (auth.uid() = owner_id)));
create policy "Owners can delete their own listings" on public.listings
  for delete to public
  using ((auth.uid() = owner_id));
create policy "Owners can insert their own listings" on public.listings
  for insert to public
  with check ((auth.uid() = owner_id));
create policy "Owners can update their own listings" on public.listings
  for update to public
  using ((auth.uid() = owner_id));

-- ---- message_templates -------------------------------------------------
alter table public.message_templates enable row level security;
create policy "Hosts manage own templates" on public.message_templates
  for all to public
  using ((auth.uid() = host_id))
  with check ((auth.uid() = host_id));

-- ---- messages ----------------------------------------------------------
alter table public.messages enable row level security;
create policy "Participants can send messages" on public.messages
  for insert to public
  with check (((auth.uid() = sender_id) AND (EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = messages.conversation_id) AND ((c.participant_one_id = auth.uid()) OR (c.participant_two_id = auth.uid())))))));
create policy "Users can update own messages" on public.messages
  for update to public
  using ((auth.uid() = sender_id));
create policy "Users can view messages in own conversations" on public.messages
  for select to public
  using ((EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = messages.conversation_id) AND ((c.participant_one_id = auth.uid()) OR (c.participant_two_id = auth.uid()))))));

-- ---- notification_preferences ------------------------------------------
alter table public.notification_preferences enable row level security;
create policy "notification_preferences_delete_own" on public.notification_preferences
  for delete to public
  using ((auth.uid() = user_id));
create policy "notification_preferences_insert_own" on public.notification_preferences
  for insert to public
  with check ((auth.uid() = user_id));
create policy "notification_preferences_select_own" on public.notification_preferences
  for select to public
  using ((auth.uid() = user_id));
create policy "notification_preferences_update_own" on public.notification_preferences
  for update to public
  using ((auth.uid() = user_id));

-- ---- notifications -----------------------------------------------------
alter table public.notifications enable row level security;
create policy "notifications_delete_own" on public.notifications
  for delete to public
  using ((auth.uid() = user_id));
create policy "notifications_select_own" on public.notifications
  for select to public
  using ((auth.uid() = user_id));
create policy "notifications_update_own" on public.notifications
  for update to public
  using ((auth.uid() = user_id));

-- ---- otp_attempts ------------------------------------------------------
alter table public.otp_attempts enable row level security;
-- (no policies — reachable only via SECURITY DEFINER RPCs / service_role)

-- ---- owner_documents ---------------------------------------------------
alter table public.owner_documents enable row level security;
create policy "owner_documents_admin_update" on public.owner_documents
  for update to authenticated
  using ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::app_role)))));
create policy "owner_documents_delete_own" on public.owner_documents
  for delete to authenticated
  using (((user_id = auth.uid()) AND (verified_at IS NULL)));
create policy "owner_documents_insert_own" on public.owner_documents
  for insert to authenticated
  with check ((user_id = auth.uid()));
create policy "owner_documents_select_own" on public.owner_documents
  for select to authenticated
  using (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::app_role))))));
create policy "owner_documents_update_own" on public.owner_documents
  for update to authenticated
  using (((user_id = auth.uid()) AND (verified_at IS NULL)))
  with check (((user_id = auth.uid()) AND (verified_at IS NULL)));

-- ---- profiles ----------------------------------------------------------
alter table public.profiles enable row level security;
create policy "Users can insert their own profile" on public.profiles
  for insert to public
  with check ((auth.uid() = id));
create policy "Users can update their own profile" on public.profiles
  for update to public
  using ((auth.uid() = id));
create policy "Users can view their own profile" on public.profiles
  for select to public
  using (((auth.uid() = id) OR is_admin()));
create policy "admins_update_any_profile" on public.profiles
  for update to authenticated
  using (is_admin())
  with check (is_admin());
create policy "profiles_insert_self" on public.profiles
  for insert to authenticated
  with check ((auth.uid() = id));

-- ---- push_tokens -------------------------------------------------------
alter table public.push_tokens enable row level security;
create policy "push_tokens_delete_own" on public.push_tokens
  for delete to public
  using ((auth.uid() = user_id));
create policy "push_tokens_insert_own" on public.push_tokens
  for insert to public
  with check ((auth.uid() = user_id));
create policy "push_tokens_select_own" on public.push_tokens
  for select to public
  using ((auth.uid() = user_id));
create policy "push_tokens_update_own" on public.push_tokens
  for update to public
  using ((auth.uid() = user_id));

-- ---- read_cursors ------------------------------------------------------
alter table public.read_cursors enable row level security;
create policy "Users can manage own read cursors" on public.read_cursors
  for all to public
  using ((auth.uid() = user_id));

-- ---- reviews -----------------------------------------------------------
alter table public.reviews enable row level security;
create policy "reviews_insert" on public.reviews
  for insert to public
  with check (((auth.uid() = reviewer_id) AND (EXISTS ( SELECT 1
   FROM bookings b
  WHERE ((b.id = reviews.booking_id) AND (b.booking_status = ANY (ARRAY['completed'::booking_status, 'active'::booking_status])) AND (((reviews.review_type = 'guest_to_host'::review_type) AND (b.tenant_id = auth.uid())) OR ((reviews.review_type = 'host_to_guest'::review_type) AND (EXISTS ( SELECT 1
           FROM listings l
          WHERE ((l.id = b.listing_id) AND (l.owner_id = auth.uid())))))))))));
create policy "reviews_select_own" on public.reviews
  for select to public
  using ((auth.uid() = reviewer_id));
create policy "reviews_select_revealed" on public.reviews
  for select to public
  using ((is_revealed = true));
create policy "reviews_service_insert" on public.reviews
  for all to public
  using (((auth.jwt() ->> 'role'::text) = 'service_role'::text))
  with check (((auth.jwt() ->> 'role'::text) = 'service_role'::text));
create policy "reviews_update_own" on public.reviews
  for update to public
  using (((auth.uid() = reviewer_id) AND (is_revealed = false)))
  with check ((auth.uid() = reviewer_id));

-- ---- scheduled_message_sends -------------------------------------------
alter table public.scheduled_message_sends enable row level security;
-- (no policies — reachable only via SECURITY DEFINER RPCs / service_role)

-- ---- spatial_ref_sys ---------------------------------------------------
-- RLS DISABLED on public.spatial_ref_sys
-- (no policies — reachable only via SECURITY DEFINER RPCs / service_role)

-- ---- typing_indicators -------------------------------------------------
alter table public.typing_indicators enable row level security;
create policy "Users can manage own typing" on public.typing_indicators
  for all to public
  using ((auth.uid() = user_id));
create policy "Users can view typing in own conversations" on public.typing_indicators
  for select to public
  using ((EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = typing_indicators.conversation_id) AND ((c.participant_one_id = auth.uid()) OR (c.participant_two_id = auth.uid()))))));
