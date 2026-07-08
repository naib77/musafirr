# Live schema objects — public schema

Generated from the live database catalog as a reconciliation reference. The
repo's migration files drifted from what actually ran, so this reflects the
**deployed** state. For a canonical, restorable baseline run `supabase db pull`
(needs the DB password: Dashboard → Database → Connection).

- Tables with RLS: 24/25
- Policies: 61
- App functions: 53  ·  Triggers: 18  ·  Views: 5

## Views

- `geography_columns`
- `geometry_columns`
- `guest_ratings`
- `listing_ratings`
- `public_profiles`

## SECURITY DEFINER functions (run as owner, bypass RLS — audit these carefully)

- `admin_auto_complete_bookings()` → integer
- `admin_expire_bookings()` → integer
- `admin_reveal_reviews()` → integer
- `auto_complete_elapsed_bookings()` → integer
- `auto_reveal_old_reviews()` → integer
- `capture_monthly_leaderboard_snapshot()` → void
- `cleanup_old_otps()` → integer
- `enforce_booking_update_rules()` → trigger
- `expire_stale_bookings()` → integer
- `get_conversation_participants(p_conversation_id uuid)` → TABLE(user_id uuid, role text, joined_at timestamp with time zone, user_name text, avatar_url text)
- `get_host_leaderboard(p_period text DEFAULT 'all_time'::text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)` → TABLE(rank bigint, host_id uuid, name text, avatar_url text, score numeric, rating numeric, review_count bigint, completed_bookings bigint, prev_rank bigint)
- `get_host_rank(p_host_id uuid, p_period text DEFAULT 'all_time'::text)` → TABLE(rank bigint, host_id uuid, name text, avatar_url text, score numeric, rating numeric, review_count bigint, completed_bookings bigint, prev_rank bigint)
- `get_listing_owner(p_listing_id uuid)` → uuid
- `get_or_create_conversation(user_one uuid, user_two uuid, p_booking_id uuid DEFAULT NULL::uuid, p_listing_id uuid DEFAULT NULL::uuid)` → uuid
- `get_unread_count(p_conversation_id uuid, p_user_id uuid)` → integer
- `get_unread_notification_count(p_user_id uuid)` → integer
- `handle_new_user()` → trigger
- `host_leaderboard_ranked(p_period text)` → TABLE(rank bigint, host_id uuid, name text, avatar_url text, score numeric, rating numeric, review_count bigint, completed_bookings bigint, prev_rank bigint)
- `is_admin(p_uid uuid DEFAULT auth.uid())` → boolean
- `is_conversation_member(p_conversation_id uuid, p_user_id uuid)` → boolean
- `mark_all_notifications_read(p_user_id uuid)` → integer
- `migrate_conversation_participants()` → integer
- `notify_on_booking_change()` → trigger
- `notify_on_booking_lifecycle()` → trigger
- `notify_on_review_revealed()` → trigger
- `notify_recipient_on_new_message()` → trigger
- `otp_log_attempts(p_id uuid, p_attempts integer)` → void
- `otp_log_send(p_phone text, p_otp_hash text, p_expires_at timestamp with time zone)` → uuid
- `otp_log_verified(p_id uuid)` → void
- `rls_auto_enable()` → event_trigger
- `send_booking_accept_messages(p_booking_id uuid)` → void
- `send_booking_map(p_booking_id uuid)` → void
- `send_pre_checkin_messages()` → integer
- `send_precheckin_for_booking(p_booking_id uuid)` → void
- `send_push_on_notification_insert()` → trigger
- `send_review_reminders()` → integer
- `set_listing_host_available()` → trigger
- `set_verification_pending()` → trigger
- `sync_listings_host_available()` → trigger
- `update_conversation_last_message()` → trigger
- `update_profile_verification_status()` → trigger
- `upsert_fcm_token(p_user_id uuid, p_token text, p_device_type text DEFAULT 'android'::text, p_device_name text DEFAULT NULL::text)` → uuid

## SECURITY INVOKER functions (run under caller RLS)

- `_localize_date_bn(d text)` → text
- `check_and_reveal_reviews()` → trigger
- `is_booking_available(p_listing_id uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone)` → boolean
- `search_listings(p_property_types text[] DEFAULT NULL::text[], p_guest_count integer DEFAULT 1, p_min_price numeric DEFAULT NULL::numeric, p_max_price numeric DEFAULT NULL::numeric, p_amenities text[] DEFAULT NULL::text[], p_location text DEFAULT NULL::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)` → SETOF jsonb
- `search_listings_by_location(center_lat numeric, center_lng numeric, radius_meters integer DEFAULT 10000)` → SETOF listings
- `touch_message_templates_updated_at()` → trigger
- `update_fcm_token_timestamp()` → trigger
- `update_listing_location()` → trigger
- `update_listing_rating()` → trigger
- `update_notifications_updated_at()` → trigger
- `update_reviews_updated_at()` → trigger

## Triggers

- **bookings**: `booking_lifecycle_notifications`, `trg_enforce_booking_update_rules`
- **fcm_tokens**: `fcm_tokens_updated_at`
- **listings**: `listing_location_trigger`, `trg_set_listing_host_available`
- **message_templates**: `on_message_template_update`
- **messages**: `on_message_notify_recipient`, `trigger_update_conversation_last_message`
- **notification_preferences**: `notification_preferences_updated_at`
- **notifications**: `notifications_updated_at`, `on_notification_send_push`
- **owner_documents**: `on_document_uploaded`, `on_document_verified`
- **profiles**: `trg_sync_listings_host_available`
- **push_tokens**: `push_tokens_updated_at`
- **reviews**: `reveal_reviews_on_insert`, `review_revealed_notification`, `reviews_updated_at`
