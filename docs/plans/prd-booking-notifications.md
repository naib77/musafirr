# PRD: Database-Triggered Booking Notifications

**Status**: Ready for Implementation
**Priority**: High
**Label**: `ready-for-agent`

---

## Problem Statement

When a guest books a seat/room, the host has no way of knowing about it unless they manually check the app. Hosts who log in via phone (OTP) need to receive real-time notifications both in-app (notification bell badge) and via external channels (SMS, WhatsApp) so they can respond promptly to booking requests.

---

## Solution

Implement database-triggered notifications that automatically notify hosts when booking events occur. The system will:

1. **Database trigger** inserts a notification row when a booking is created/updated
2. **Supabase Realtime** pushes the notification to the Flutter app instantly
3. **Edge Function** delivers to external channels (SMS, WhatsApp, Push) based on user preferences
4. **NotificationBell widget** updates badge count in real-time

---

## User Stories

1. As a host logged in via phone OTP, I want to see a notification badge on the bell icon when a guest requests a booking, so that I know to check my reservations
2. As a host, I want to receive an SMS when someone books my listing, so that I can respond even when not actively using the app
3. As a host, I want to receive a WhatsApp message for booking requests, so that I can quickly view details and respond
4. As a host, I want to tap a notification and go directly to the booking details, so that I can review and confirm/reject quickly
5. As a host, I want to configure which channels I receive notifications on (in-app, SMS, WhatsApp), so that I'm not overwhelmed
6. As a guest, I want to be notified when my booking is confirmed, so that I know my reservation is secured
7. As a guest, I want to be notified if my booking is cancelled, so that I can make alternative arrangements
8. As a host, I want notifications grouped by booking, so that I don't see duplicate alerts for the same booking
9. As a user, I want to mark notifications as read, so that the badge count reflects actual unread items
10. As a user, I want to set quiet hours for notifications, so that I'm not disturbed at night (except urgent ones)
11. As a host with multiple listings, I want notifications to specify which listing was booked, so that I can manage them efficiently
12. As a user, I want notifications to persist even if I close the app, so that I see them when I return
13. As a host, I want high-priority styling for booking requests, so that they stand out from promotional notifications
14. As a user logged in on multiple devices, I want notifications synced across devices, so that marking read on one device updates others
15. As a host, I want to see the guest's name in the notification, so that I have context before opening
16. As a user, I want check-in/check-out reminders before my booking dates, so that I don't forget

---

## Implementation Decisions

### 1. Trigger Architecture

**Decision**: Use PostgreSQL database trigger + Edge Function for multi-channel delivery

- **Booking insert/update** → `notify_on_booking_change()` trigger fires
- Trigger inserts row into `notifications` table with host's `user_id`
- Supabase Realtime detects insert, pushes to subscribed clients
- Separate Edge Function `send-notification-channels` reads from a queue/webhook and delivers to SMS/WhatsApp/Push

### 2. Realtime Subscription Flow

The existing architecture supports this:

```
NotificationStateNotifier.initialize(userId)
  → _service.subscribeToNotifications(userId)
  → Stream<AppNotification>
  → _onNewNotification() updates list + badge
  → NotificationBell rebuilds with new unreadCount
```

**Required**: Implement `SupabaseNotificationService` that wraps Supabase client with Realtime subscription to `notifications` table filtered by `user_id`.

### 3. External Channel Delivery

Create Edge Function `send-notification-channels`:

```
1. Triggered by: database webhook OR pg_notify
2. Reads user's notification_preferences
3. Checks quiet hours + channel preferences
4. Dispatches to enabled channels:
   - Push: via FCM using push_tokens table
   - SMS: via configured SMS gateway (BulkSMS, AlphaSMS, etc.)
   - WhatsApp: via WhatsApp Cloud API with template messages
```

### 4. Phone OTP Users

Users who sign up/login with phone OTP:

- `auth.users.phone` is set
- Profile created via `handle_new_user()` trigger
- `notification_preferences.phone_number` populated from auth
- SMS delivery uses this phone number
- In-app notifications work identically (same `user_id` reference)

### 5. Booking Trigger Enhancements

Current trigger in `002_notifications.sql` is commented out. Needs:

1. Uncomment the trigger
2. Fix column references (`host_id` should be `owner_id`, `user_id` should be `tenant_id`, `guest_name` should be `tenant_name`)
3. Add `pg_notify` call for Edge Function webhook

### 6. Schema Alignment

The `bookings` table uses:
- `owner_id` (via listings join) for host
- `tenant_id` for guest
- `tenant_name` for guest name

The trigger must be updated to match this schema.

### 7. Deep Link Handling

Existing `NotificationDeepLinkHandler` supports:
- `/host/reservations/{booking_id}` → Host views booking
- `/trips/{booking_id}` → Guest views booking

These are already in the `action_url` field set by the trigger.

### 8. Modules to Build/Modify

| Module | Action | Purpose |
|--------|--------|---------|
| `SupabaseNotificationService` | **Create** | Production implementation with Realtime subscription |
| `002_notifications.sql` | **Modify** | Uncomment trigger, fix column names |
| `send-notification-channels` Edge Function | **Create** | Multi-channel delivery orchestrator |
| `NotificationServiceFactory` | **Create** | Switch between InMemory and Supabase implementations |
| `main.dart` | **Modify** | Initialize correct NotificationService based on config |

---

## Testing Decisions

### What Makes a Good Test

- Test external behavior, not implementation details
- Mock external services (Supabase, SMS gateway, WhatsApp API)
- Test the contract: "when X happens, Y should be observable"
- Integration tests for the full flow in demo mode

### Modules to Test

1. **SupabaseNotificationService**
   - Subscription lifecycle (subscribe, receive, unsubscribe)
   - Notification CRUD operations
   - Preference persistence

2. **Booking notification trigger** (SQL)
   - INSERT creates host notification
   - UPDATE to 'confirmed' creates guest notification
   - UPDATE to 'cancelled' creates both notifications
   - Correct data payload in notification

3. **NotificationStateNotifier**
   - Already has in-memory tests as prior art
   - Add tests for real-time update handling

4. **Edge Function send-notification-channels**
   - Respects quiet hours
   - Respects channel preferences
   - Handles delivery failures gracefully

### Prior Art

- `InMemoryNotificationService` serves as reference implementation
- Existing stub services (`StubWhatsAppService`, `StubPushNotificationService`) show testing patterns

---

## Out of Scope

1. **Email notifications** - Not a priority channel for BD market; SMS/WhatsApp preferred
2. **Push notification certificates** - FCM setup is separate infrastructure task
3. **Notification scheduling** (check-in reminders) - Future enhancement
4. **Rich push with images** - Basic text notifications first
5. **Notification analytics** - Track open rates, etc. - Future enhancement
6. **Web push notifications** - Mobile-first approach
7. **Batch/digest notifications** - Real-time individual notifications first

---

## Further Notes

### Existing Infrastructure

The notification system is extensively built out:
- 18 notification types defined
- 5 delivery channels supported
- Full preference system with quiet hours
- UI components (NotificationBell, NotificationCenterScreen, NotificationSettingsScreen)
- Deep linking to specific screens
- State management with real-time streams

### What's Missing

The main gap is the **Supabase implementation** of `NotificationService`. Currently only `InMemoryNotificationService` exists. The production `SupabaseNotificationService` needs to:

1. Query `notifications` table with RLS
2. Subscribe to Supabase Realtime for INSERT events
3. Map database rows to `AppNotification` model
4. Handle CRUD operations via Supabase client

### Delivery Timing

For SMS/WhatsApp delivery:
- Supabase database webhooks can trigger Edge Functions
- Alternative: Use `pg_notify` + Supabase Realtime to trigger client-side delivery (not recommended - unreliable)
- Recommended: Database webhook to Edge Function with retry logic

### Cost Considerations

- SMS: ~0.50 BDT per message (BulkSMS.bd)
- WhatsApp: Free for template messages in 24-hour window
- Push (FCM): Free

Recommend defaulting to WhatsApp + Push, with SMS as fallback for critical notifications only.
