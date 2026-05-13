# Musafir Feature Roadmap v2.0

## BDT Currency System, Real-time Notifications, Multi-channel Messaging & Discount System

> Comprehensive architectural design for enhancing Musafir with professional-grade features inspired by Uber, Pathao, Airbnb, and industry best practices.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Feature 1: BDT Currency System](#feature-1-bdt-currency-system)
3. [Feature 2: Real-time Notification System](#feature-2-real-time-notification-system)
4. [Feature 3: Multi-channel Messaging System](#feature-3-multi-channel-messaging-system)
5. [Feature 4: Discount & Promotion System](#feature-4-discount--promotion-system)
6. [Database Schema Changes](#database-schema-changes)
7. [Integration Architecture](#integration-architecture)
8. [Security Considerations](#security-considerations)
9. [Migration Strategy](#migration-strategy)
10. [Testing Strategy](#testing-strategy)
11. [Implementation Plan](#implementation-plan)

---

## Executive Summary

This document outlines the architectural design for four major feature additions to the Musafir rental marketplace:

| Feature | Priority | Complexity | Dependencies |
|---------|----------|------------|--------------|
| BDT Currency System | High | Medium | intl package |
| Real-time Notifications | High | High | Supabase Realtime, FCM |
| Multi-channel Messaging | Medium | High | WhatsApp API, Messenger API, Supabase |
| Discount System | Medium | High | None |

### Current State Analysis

```
Current Pricing:
- Prices stored as plain `double` values
- "BDT" hardcoded in UI strings
- No currency formatting utilities
- No discount infrastructure

Current Messaging:
- Inbox screen is placeholder
- SMS gateway exists for OTP only
- No real-time capabilities

Current Notifications:
- Only SnackBar for in-app feedback
- No push notifications
- No event-driven alerts
```

---

## Feature 1: BDT Currency System

### 1.1 Overview

Standardize all monetary values to Bangladesh Taka (BDT) with proper formatting, localization, and future multi-currency support architecture.

### 1.2 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Currency Layer                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐ │
│  │   Money     │    │  Currency   │    │  CurrencyFormatter  │ │
│  │   Model     │───▶│   Config    │───▶│      Service        │ │
│  └─────────────┘    └─────────────┘    └─────────────────────┘ │
│         │                                        │              │
│         ▼                                        ▼              │
│  ┌─────────────┐                      ┌─────────────────────┐  │
│  │   Price     │                      │    PriceDisplay     │  │
│  │ Calculator  │                      │      Widget         │  │
│  └─────────────┘                      └─────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 Data Models

#### Money Value Object
```dart
/// Immutable value object representing monetary amount
class Money {
  final int amountInMinorUnits;  // Store in paisa (smallest unit)
  final Currency currency;

  // Factory constructors
  Money.bdt(double amount);
  Money.fromMinorUnits(int paisa, Currency currency);

  // Operations (return new Money instances)
  Money add(Money other);
  Money subtract(Money other);
  Money multiply(double factor);
  Money applyDiscount(Discount discount);

  // Formatting
  String format({bool showSymbol = true, bool compact = false});
  String toCompactString();  // "৳1.2K" for large amounts

  // Comparison
  bool operator >(Money other);
  bool operator <(Money other);
}
```

#### Currency Configuration
```dart
/// Currency definitions
class Currency {
  final String code;           // "BDT"
  final String symbol;         // "৳"
  final String name;           // "Bangladeshi Taka"
  final int decimalPlaces;     // 2
  final String locale;         // "bn_BD"
  final bool symbolBefore;     // true (৳500 vs 500৳)

  static const Currency BDT = Currency(
    code: 'BDT',
    symbol: '৳',
    name: 'Bangladeshi Taka',
    decimalPlaces: 2,
    locale: 'bn_BD',
    symbolBefore: true,
  );
}
```

### 1.4 Formatting Rules

| Amount Range | Display Format | Example |
|--------------|----------------|---------|
| < 1,000 | Full amount | ৳850 |
| 1,000 - 99,999 | With comma | ৳12,500 |
| 100,000 - 9,999,999 | Lakh notation | ৳1.5L |
| >= 10,000,000 | Crore notation | ৳1.2Cr |

#### Formatting Service
```dart
class CurrencyFormatter {
  // Singleton
  static CurrencyFormatter get instance;

  // Configuration
  void setDefaultCurrency(Currency currency);
  void setLocale(String locale);

  // Formatting methods
  String format(Money money, {
    bool showSymbol = true,
    bool useCompact = false,
    bool showDecimal = true,
  });

  String formatRange(Money min, Money max);  // "৳500 - ৳1,200"
  String formatPerUnit(Money amount, String unit);  // "৳500/night"

  // Parsing
  Money? parse(String input);
}
```

### 1.5 Widget Library

#### PriceDisplay Widget
```dart
class PriceDisplay extends StatelessWidget {
  final Money amount;
  final PriceDisplayStyle style;  // normal, compact, large, badge
  final String? perUnit;          // "night", "hour", "month"
  final Money? originalPrice;     // For showing strikethrough
  final bool showCurrency;
}

// Usage examples:
PriceDisplay(amount: Money.bdt(1500), perUnit: "night")
// Output: ৳1,500/night

PriceDisplay(
  amount: Money.bdt(1200),
  originalPrice: Money.bdt(1500),
  perUnit: "night"
)
// Output: ৳1,500 ৳1,200/night (with strikethrough)
```

#### PriceRangeSlider Widget
```dart
class PriceRangeSlider extends StatelessWidget {
  final Money minValue;
  final Money maxValue;
  final Money currentMin;
  final Money currentMax;
  final ValueChanged<RangeValues> onChanged;
  final List<Money>? snapPoints;  // Common price points
}
```

### 1.6 Model Updates

#### Listing Model Changes
```dart
class Listing {
  // Replace double with Money
  final Money hourlyRate;
  final Money dailyRate;
  final Money monthlyRate;
  final Money? pricePerNight;

  // Computed
  Money get displayPrice => pricePerNight ?? dailyRate;
  Money get minimumPrice => [hourlyRate, dailyRate, monthlyRate]
      .reduce((a, b) => a < b ? a : b);
}
```

#### Booking Model Changes
```dart
class Booking {
  final Money subtotal;
  final Money? discountAmount;
  final Money serviceFee;
  final Money totalPrice;

  // Breakdown
  PriceBreakdown get breakdown => PriceBreakdown(
    basePrice: subtotal,
    discount: discountAmount,
    serviceFee: serviceFee,
    total: totalPrice,
  );
}
```

### 1.7 Corner Cases

| Scenario | Handling |
|----------|----------|
| Null/zero prices | Show "Price on request" or "Free" |
| Negative amounts | Throw `InvalidAmountException` |
| Overflow (> 999 Cr) | Cap display at "৳999Cr+" |
| Decimal precision loss | Always store as integer paisa |
| Currency mismatch in operations | Throw `CurrencyMismatchException` |
| RTL display (Arabic) | Symbol position respects locale |

### 1.8 File Structure

```
lib/
├── core/
│   └── currency/
│       ├── money.dart
│       ├── currency.dart
│       ├── currency_formatter.dart
│       └── currency_config.dart
├── widgets/
│   ├── price_display.dart
│   ├── price_range_slider.dart
│   └── price_breakdown_card.dart
```

---

## Feature 2: Real-time Notification System

### 2.1 Overview

Event-driven notification system supporting push notifications, in-app alerts, and SMS fallback for critical events.

### 2.2 Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Notification Architecture                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌──────────────┐     ┌──────────────┐     ┌──────────────────────┐   │
│   │   Event      │     │ Notification │     │   Delivery           │   │
│   │   Sources    │────▶│   Engine     │────▶│   Channels           │   │
│   └──────────────┘     └──────────────┘     └──────────────────────┘   │
│          │                    │                       │                 │
│          ▼                    ▼                       ▼                 │
│   ┌──────────────┐     ┌──────────────┐     ┌──────────────────────┐   │
│   │ • Booking    │     │ • Template   │     │ • Push (FCM)         │   │
│   │ • Message    │     │   Engine     │     │ • In-App             │   │
│   │ • Review     │     │ • Priority   │     │ • SMS (Critical)     │   │
│   │ • Payment    │     │   Router     │     │ • Email              │   │
│   │ • System     │     │ • Batching   │     │                      │   │
│   └──────────────┘     └──────────────┘     └──────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.3 Notification Types

#### By Event Category
```dart
enum NotificationCategory {
  // Booking lifecycle
  bookingCreated,        // "New booking request from [Guest]"
  bookingConfirmed,      // "Your booking is confirmed!"
  bookingCancelled,      // "Booking cancelled"
  bookingReminder,       // "Check-in tomorrow at [Property]"
  checkInReminder,       // "Check-in starts in 2 hours"
  checkOutReminder,      // "Check-out in 3 hours"

  // Messaging
  newMessage,            // "New message from [User]"
  messageRead,           // (Silent - no push)

  // Reviews
  reviewReceived,        // "[Guest] left you a review"
  reviewReminder,        // "Rate your stay at [Property]"

  // Payments
  paymentReceived,       // "Payment of ৳X received"
  paymentFailed,         // "Payment failed - action required"
  payoutProcessed,       // "৳X transferred to your account"

  // Host-specific
  newListingView,        // "Your listing got 10 views today"
  priceRecommendation,   // "Increase bookings: lower price by 10%"

  // System
  accountSecurity,       // "New login from [Device]"
  appUpdate,             // "New version available"
  promotional,           // "Weekend sale: 20% off"
}
```

#### Priority Levels
```dart
enum NotificationPriority {
  critical,   // SMS + Push + In-App (e.g., security alerts)
  high,       // Push + In-App (e.g., new booking)
  medium,     // Push + In-App (batched) (e.g., messages)
  low,        // In-App only (e.g., promotions)
  silent,     // No alert, badge update only
}
```

### 2.4 Data Models

#### Notification Model
```dart
class AppNotification {
  final String id;
  final String userId;
  final NotificationCategory category;
  final NotificationPriority priority;
  final String title;
  final String body;
  final Map<String, dynamic> data;  // Deep link data
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? expiresAt;
  final String? imageUrl;
  final List<NotificationAction>? actions;

  bool get isRead => readAt != null;
  bool get isExpired => expiresAt?.isBefore(DateTime.now()) ?? false;
}

class NotificationAction {
  final String id;
  final String label;
  final String actionType;  // 'deeplink', 'dismiss', 'api_call'
  final Map<String, dynamic>? actionData;
}
```

#### Notification Template
```dart
class NotificationTemplate {
  final NotificationCategory category;
  final String titleTemplate;      // "New booking from {{guest_name}}"
  final String bodyTemplate;       // "{{property_name}} • {{dates}}"
  final NotificationPriority defaultPriority;
  final List<String> channels;     // ['push', 'in_app', 'sms']
  final Duration? ttl;             // Time to live
  final bool canBatch;             // Group similar notifications
  final Duration? batchWindow;     // 5 minutes window
}
```

### 2.5 Service Architecture

#### Notification Service
```dart
abstract class NotificationService {
  // Subscription
  Stream<AppNotification> get notificationStream;
  Stream<int> get unreadCountStream;

  // Fetching
  Future<List<AppNotification>> getNotifications({
    int limit = 20,
    String? cursor,
    NotificationCategory? category,
  });

  // Actions
  Future<void> markAsRead(String notificationId);
  Future<void> markAllAsRead();
  Future<void> delete(String notificationId);
  Future<void> clearAll();

  // Settings
  Future<void> updatePreferences(NotificationPreferences prefs);
  Future<NotificationPreferences> getPreferences();

  // Push token management
  Future<void> registerPushToken(String token, DevicePlatform platform);
  Future<void> unregisterPushToken(String token);
}
```

#### Notification Preferences
```dart
class NotificationPreferences {
  final bool pushEnabled;
  final bool emailEnabled;
  final bool smsEnabled;
  final Map<NotificationCategory, ChannelPreference> categorySettings;
  final QuietHours? quietHours;
  final String preferredLanguage;
}

class QuietHours {
  final TimeOfDay start;  // 22:00
  final TimeOfDay end;    // 07:00
  final List<int> daysOfWeek;  // [1,2,3,4,5,6,7]
}

class ChannelPreference {
  final bool push;
  final bool inApp;
  final bool email;
  final bool sms;
}
```

### 2.6 Real-time Implementation

#### Supabase Realtime Integration
```dart
class RealtimeNotificationService implements NotificationService {
  final SupabaseClient _client;

  // Subscribe to user's notifications
  RealtimeChannel _subscribeToNotifications(String userId) {
    return _client
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: _handleNewNotification,
        )
        .subscribe();
  }
}
```

#### Push Notification (FCM) Integration
```dart
class PushNotificationService {
  final FirebaseMessaging _fcm;

  Future<void> initialize() async {
    // Request permissions
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,  // For critical notifications
    );

    // Get token
    final token = await _fcm.getToken();
    await _registerToken(token);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background/terminated messages
    FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);

    // Handle notification tap
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
  }
}
```

### 2.7 Notification UI Components

```dart
// Notification Bell with Badge
class NotificationBell extends StatelessWidget {
  // Shows unread count badge
  // Animated when new notification arrives
}

// Notification Center (Full screen)
class NotificationCenter extends StatelessWidget {
  // Grouped by date (Today, Yesterday, This Week, Earlier)
  // Pull to refresh
  // Swipe to delete
  // Category filters
}

// Notification Toast (In-app)
class NotificationToast extends StatelessWidget {
  // Slides in from top
  // Auto-dismiss after 4 seconds
  // Tap to navigate
  // Swipe to dismiss
}

// Notification Settings Screen
class NotificationSettingsScreen extends StatelessWidget {
  // Category-wise toggles
  // Quiet hours configuration
  // Channel preferences
}
```

### 2.8 Backend Triggers (Supabase)

```sql
-- Trigger function for booking notifications
CREATE OR REPLACE FUNCTION notify_booking_created()
RETURNS TRIGGER AS $$
BEGIN
  -- Notify host about new booking
  INSERT INTO notifications (user_id, category, title, body, data)
  VALUES (
    (SELECT host_id FROM listings WHERE id = NEW.listing_id),
    'booking_created',
    'New booking request',
    'You have a new booking request for ' ||
      (SELECT title FROM listings WHERE id = NEW.listing_id),
    jsonb_build_object(
      'booking_id', NEW.id,
      'listing_id', NEW.listing_id,
      'guest_id', NEW.user_id
    )
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_booking_created
  AFTER INSERT ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION notify_booking_created();
```

### 2.9 Corner Cases

| Scenario | Handling |
|----------|----------|
| User has push disabled | Fall back to in-app + SMS for critical |
| Notification during quiet hours | Queue and deliver after quiet hours end |
| Duplicate notifications | Dedupe by category + entity_id within 1 min |
| Expired notifications | Don't deliver, mark as expired |
| User offline | Store and deliver when online |
| Token refresh | Re-register on app launch |
| Mass notifications (system) | Batch and rate-limit |
| Deep link to deleted content | Show "Content unavailable" screen |

### 2.10 File Structure

```
lib/
├── services/
│   └── notifications/
│       ├── notification_service.dart
│       ├── realtime_notification_service.dart
│       ├── push_notification_service.dart
│       ├── notification_templates.dart
│       └── notification_scheduler.dart
├── models/
│   ├── notification.dart
│   └── notification_preferences.dart
├── state/
│   └── notification_state.dart
├── screens/
│   └── notifications/
│       ├── notification_center_screen.dart
│       └── notification_settings_screen.dart
└── widgets/
    ├── notification_bell.dart
    ├── notification_toast.dart
    └── notification_item.dart
```

---

## Feature 3: Multi-channel Messaging System

### 3.1 Overview

Unified messaging system supporting in-app chat, WhatsApp, and Facebook Messenger with conversation threading and media support.

### 3.2 Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Multi-Channel Messaging Architecture                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│                        ┌──────────────────┐                             │
│                        │  Unified Inbox   │                             │
│                        │    (Flutter)     │                             │
│                        └────────┬─────────┘                             │
│                                 │                                        │
│              ┌──────────────────┼──────────────────┐                    │
│              ▼                  ▼                  ▼                    │
│    ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐        │
│    │   In-App Chat   │ │    WhatsApp     │ │   Messenger     │        │
│    │   (Supabase)    │ │  Business API   │ │   Platform      │        │
│    └────────┬────────┘ └────────┬────────┘ └────────┬────────┘        │
│             │                   │                   │                   │
│             └───────────────────┼───────────────────┘                   │
│                                 ▼                                        │
│                      ┌──────────────────┐                               │
│                      │  Message Router  │                               │
│                      │   (Backend)      │                               │
│                      └──────────────────┘                               │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Channel Comparison

| Feature | In-App | WhatsApp | Messenger |
|---------|--------|----------|-----------|
| Real-time | Yes (Supabase) | Webhooks | Webhooks |
| Media support | Images, Files | Images, Docs, Location | Images, Files |
| Read receipts | Yes | Yes | Yes |
| Typing indicators | Yes | No | Yes |
| Message templates | Custom | Pre-approved | Custom |
| Cost | Free | Per-message fee | Free |
| User reach | App users only | 98% BD users | 30% BD users |
| Bot support | Custom | Yes | Yes |

### 3.4 Data Models

#### Conversation Model
```dart
class Conversation {
  final String id;
  final ConversationType type;  // booking, support, general
  final List<String> participantIds;
  final String? bookingId;      // If booking-related
  final String? listingId;
  final Message? lastMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, DateTime> readCursors;  // userId -> lastReadAt
  final ConversationStatus status;  // active, archived, blocked

  int get unreadCount;
  bool get hasUnread;
}

enum ConversationType {
  booking,    // Host-Guest for specific booking
  inquiry,    // Pre-booking inquiry
  support,    // Customer support
  system,     // System messages
}
```

#### Message Model
```dart
class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final MessageContent content;
  final DateTime sentAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final MessageStatus status;
  final MessageChannel channel;  // in_app, whatsapp, messenger
  final String? replyToId;       // For threaded replies
  final Map<String, dynamic>? metadata;

  bool get isFromCurrentUser;
  bool get isDelivered;
  bool get isRead;
}

abstract class MessageContent {
  MessageContentType get type;
  String get preview;  // For notification/list display
}

class TextContent extends MessageContent {
  final String text;
  final List<MessageMention>? mentions;
}

class ImageContent extends MessageContent {
  final String imageUrl;
  final String? thumbnailUrl;
  final int? width;
  final int? height;
  final String? caption;
}

class LocationContent extends MessageContent {
  final double latitude;
  final double longitude;
  final String? address;
  final String? placeName;
}

class BookingCardContent extends MessageContent {
  final String bookingId;
  final String listingTitle;
  final String imageUrl;
  final DateTime checkIn;
  final DateTime checkOut;
  final Money totalPrice;
  final BookingStatus status;
}

class SystemContent extends MessageContent {
  final SystemMessageType type;  // booking_confirmed, review_reminder
  final Map<String, dynamic> data;
}
```

### 3.5 Service Architecture

#### Messaging Service Interface
```dart
abstract class MessagingService {
  // Conversations
  Stream<List<Conversation>> watchConversations();
  Future<Conversation> getOrCreateConversation({
    required String otherUserId,
    String? bookingId,
    ConversationType type = ConversationType.general,
  });
  Future<void> archiveConversation(String conversationId);

  // Messages
  Stream<List<Message>> watchMessages(String conversationId);
  Future<Message> sendMessage({
    required String conversationId,
    required MessageContent content,
    MessageChannel channel = MessageChannel.inApp,
  });
  Future<void> markAsRead(String conversationId);
  Future<void> deleteMessage(String messageId);

  // Typing indicators
  Future<void> setTyping(String conversationId, bool isTyping);
  Stream<Map<String, bool>> watchTypingStatus(String conversationId);

  // Media
  Future<String> uploadMedia(File file, MediaType type);
}
```

#### Channel-Specific Services

```dart
// WhatsApp Business API Service
class WhatsAppService {
  // Template messages (pre-approved)
  Future<void> sendBookingConfirmation(String phone, Booking booking);
  Future<void> sendCheckInReminder(String phone, Booking booking);
  Future<void> sendPaymentReceipt(String phone, Payment payment);

  // Session messages (within 24h window)
  Future<void> sendTextMessage(String phone, String text);
  Future<void> sendImage(String phone, String imageUrl, String? caption);
  Future<void> sendLocation(String phone, double lat, double lng);

  // Webhook handling
  Future<void> handleIncomingMessage(Map<String, dynamic> webhook);
  Future<void> handleStatusUpdate(Map<String, dynamic> webhook);
}

// Messenger Platform Service
class MessengerService {
  Future<void> sendTextMessage(String recipientId, String text);
  Future<void> sendQuickReplies(String recipientId, List<QuickReply> replies);
  Future<void> sendGenericTemplate(String recipientId, GenericTemplate template);

  // Webhook handling
  Future<void> handleIncomingMessage(Map<String, dynamic> webhook);
}
```

### 3.6 User Preferences

```dart
class MessagingPreferences {
  final MessageChannel preferredChannel;  // Default channel
  final bool whatsappEnabled;
  final String? whatsappNumber;           // Verified WhatsApp number
  final bool messengerEnabled;
  final String? messengerPsid;            // Page-scoped ID
  final bool inAppEnabled;

  // Auto-responses
  final bool autoResponseEnabled;
  final String? autoResponseMessage;
  final AutoResponseSchedule? schedule;

  // Privacy
  final bool showReadReceipts;
  final bool showOnlineStatus;
  final bool allowMediaDownload;
}
```

### 3.7 UI Components

```dart
// Unified Inbox
class InboxScreen extends StatelessWidget {
  // Conversation list with:
  // - Avatar, name, last message preview
  // - Unread badge
  // - Time/date
  // - Channel indicator icon (WhatsApp/Messenger/In-app)
  // - Booking badge if booking-related
}

// Chat Screen
class ChatScreen extends StatelessWidget {
  // Header: User info, channel indicator, options menu
  // Message list: Grouped by date, read receipts
  // Input bar: Text, attachments, send button
  // Typing indicator
  // Quick actions: Share location, send booking card
}

// Channel Selector
class ChannelSelector extends StatelessWidget {
  // Shows available channels for user
  // WhatsApp (if number linked)
  // Messenger (if account linked)
  // In-App (always available)
}

// Message Bubbles
class MessageBubble extends StatelessWidget {
  // Text, image, location, booking card, system message
  // Delivery/read status
  // Reply indicator
  // Long-press menu: Reply, Copy, Delete
}
```

### 3.8 Message Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Message Flow (Send)                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  User Types Message                                                      │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────────┐                                                    │
│  │ Channel Router  │──▶ Determine best channel based on:                │
│  └────────┬────────┘    • User preference                               │
│           │             • Recipient availability                         │
│           │             • Message type (template required?)              │
│           │             • 24h session window (WhatsApp)                  │
│           │                                                              │
│     ┌─────┼─────┬─────────────┐                                         │
│     ▼     ▼     ▼             ▼                                         │
│  In-App  WA   Messenger   Fallback                                      │
│     │     │       │           │                                         │
│     │     │       │           ▼                                         │
│     │     │       │    SMS (if critical)                                │
│     │     │       │                                                     │
│     └─────┴───────┴───────────┘                                         │
│                   │                                                      │
│                   ▼                                                      │
│         Store in unified inbox                                           │
│         (regardless of channel)                                          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.9 WhatsApp Business API Integration

#### Template Messages (Pre-approved)
```dart
// Templates must be pre-approved by WhatsApp
class WhatsAppTemplates {
  static const bookingConfirmation = WhatsAppTemplate(
    name: 'booking_confirmation',
    language: 'en',
    components: [
      HeaderComponent(type: 'image'),
      BodyComponent(
        text: 'Your booking at {{1}} is confirmed!\n\n'
              'Check-in: {{2}}\nCheck-out: {{3}}\n'
              'Total: {{4}}\n\n'
              'Your host {{5}} is expecting you.',
        parameters: ['property_name', 'check_in', 'check_out', 'total', 'host_name'],
      ),
      ButtonComponent(type: 'url', text: 'View Booking', url: '{{1}}'),
    ],
  );

  static const checkInReminder = WhatsAppTemplate(...);
  static const reviewRequest = WhatsAppTemplate(...);
  static const paymentReceipt = WhatsAppTemplate(...);
}
```

#### Session Messages
```dart
// Can only send within 24h of user's last message
class WhatsAppSession {
  final String recipientPhone;
  final DateTime lastUserMessage;

  bool get isActive =>
    DateTime.now().difference(lastUserMessage) < Duration(hours: 24);

  // If session expired, must use template message
}
```

### 3.10 Corner Cases

| Scenario | Handling |
|----------|----------|
| WhatsApp 24h window expired | Fall back to template or in-app |
| User blocked on WhatsApp | Fall back to in-app, notify sender |
| Messenger account not linked | Prompt to link or use alternative |
| Media upload fails | Retry 3x, then show error with retry button |
| Message delivery fails | Show "Not delivered" with retry option |
| User switches channels mid-conversation | Continue in unified thread |
| Offensive content | Auto-flag, warn sender, option to report |
| User deletes account | Archive conversations, anonymize |
| Multiple devices | Sync read status across devices |
| Network offline | Queue messages, send when online |

### 3.11 File Structure

```
lib/
├── services/
│   └── messaging/
│       ├── messaging_service.dart
│       ├── in_app_messaging_service.dart
│       ├── whatsapp_service.dart
│       ├── messenger_service.dart
│       ├── message_router.dart
│       └── media_upload_service.dart
├── models/
│   ├── conversation.dart
│   ├── message.dart
│   └── messaging_preferences.dart
├── state/
│   └── messaging_state.dart
├── screens/
│   └── messaging/
│       ├── inbox_screen.dart
│       ├── chat_screen.dart
│       └── messaging_settings_screen.dart
└── widgets/
    └── messaging/
        ├── conversation_tile.dart
        ├── message_bubble.dart
        ├── message_input.dart
        ├── channel_selector.dart
        └── typing_indicator.dart
```

---

## Feature 4: Discount & Promotion System

### 4.1 Overview

Comprehensive discount system inspired by Uber, Pathao, and Airbnb with support for promo codes, automatic discounts, referrals, and dynamic pricing.

### 4.2 Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Discount System Architecture                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────┐     ┌──────────────────┐     ┌────────────────┐  │
│  │  Discount Types  │     │  Discount Engine │     │  Application   │  │
│  │                  │────▶│                  │────▶│    Layer       │  │
│  └──────────────────┘     └──────────────────┘     └────────────────┘  │
│          │                        │                        │            │
│          ▼                        ▼                        ▼            │
│  ┌──────────────────┐     ┌──────────────────┐     ┌────────────────┐  │
│  │ • Promo Codes    │     │ • Validation     │     │ • Booking      │  │
│  │ • Auto Discounts │     │ • Stacking Rules │     │ • Checkout     │  │
│  │ • Referrals      │     │ • Calculation    │     │ • Price Display│  │
│  │ • Loyalty        │     │ • Fraud Detection│     │                │  │
│  │ • Seasonal       │     │                  │     │                │  │
│  └──────────────────┘     └──────────────────┘     └────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.3 Discount Types

#### Type Hierarchy
```dart
enum DiscountType {
  // Promo Codes (User enters code)
  promoCode,          // General promotional code
  referralCode,       // Referral reward code
  influencerCode,     // Influencer/partner codes

  // Automatic Discounts (Applied automatically)
  firstBooking,       // New user first booking
  earlyBird,          // Book X days in advance
  lastMinute,         // Book within 24h of check-in
  longStay,           // Stay 7+ days
  repeatGuest,        // Returning to same property
  loyaltyTier,        // Based on user tier

  // Seasonal/Campaign
  seasonal,           // Eid, Pohela Boishakh, etc.
  flash,              // Time-limited flash sale
  bundleDiscount,     // Multiple bookings

  // Host Discounts
  hostWeekly,         // Host sets weekly discount
  hostMonthly,        // Host sets monthly discount
  hostCustom,         // Host creates custom offer
}
```

### 4.4 Data Models

#### Discount Model
```dart
class Discount {
  final String id;
  final String? code;               // Null for auto-discounts
  final DiscountType type;
  final String name;
  final String? description;

  // Value
  final DiscountValueType valueType;  // percentage, fixed, freeNights
  final double value;                  // 20 (%), 500 (BDT), 1 (night)
  final Money? maxDiscount;           // Cap for percentage discounts

  // Eligibility
  final DiscountEligibility eligibility;

  // Validity
  final DateTime? startDate;
  final DateTime? endDate;
  final int? maxUsesTotal;           // Total redemptions allowed
  final int? maxUsesPerUser;         // Per user limit
  final int currentUses;

  // Stacking
  final bool stackable;              // Can combine with other discounts
  final List<DiscountType>? excludedTypes;  // Can't stack with these
  final int priority;                // Higher = applied first

  // Metadata
  final String? campaignId;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final bool isActive;

  // Computed
  bool get isValid;
  bool get isExpired;
  bool get isExhausted;
}

enum DiscountValueType {
  percentage,    // 20% off
  fixed,         // ৳500 off
  freeNights,    // 1 night free (for 7+ nights)
}
```

#### Discount Eligibility
```dart
class DiscountEligibility {
  // User criteria
  final bool newUsersOnly;
  final List<String>? specificUserIds;
  final UserTier? minUserTier;
  final int? minPastBookings;

  // Booking criteria
  final Money? minBookingAmount;
  final Money? maxBookingAmount;
  final int? minNights;
  final int? maxNights;
  final int? minGuests;
  final List<String>? applicableListingIds;
  final List<ListingType>? applicableListingTypes;
  final List<String>? applicableCities;

  // Time criteria
  final List<int>? applicableDaysOfWeek;  // [6, 7] for weekends
  final DateRange? bookingDateRange;       // When booking is made
  final DateRange? stayDateRange;          // When stay occurs
  final int? minDaysInAdvance;             // Early bird
  final int? maxDaysInAdvance;             // Last minute

  // Payment criteria
  final List<PaymentMethod>? applicablePaymentMethods;

  bool isEligible(User user, Booking booking, Listing listing);
}
```

#### Applied Discount
```dart
class AppliedDiscount {
  final Discount discount;
  final Money originalAmount;
  final Money discountAmount;
  final Money finalAmount;
  final String? code;              // If promo code was used
  final DateTime appliedAt;

  String get description;          // "20% off (৳500 saved)"
}
```

### 4.5 Discount Engine

```dart
class DiscountEngine {
  // Validate and apply promo code
  Future<DiscountResult> applyPromoCode({
    required String code,
    required User user,
    required Booking booking,
    required Listing listing,
  });

  // Get all applicable automatic discounts
  Future<List<Discount>> getAutoDiscounts({
    required User user,
    required Booking booking,
    required Listing listing,
  });

  // Calculate best discount combination
  Future<DiscountCalculation> calculateBestDiscounts({
    required User user,
    required Booking booking,
    required Listing listing,
    String? promoCode,
  });

  // Validate discount eligibility
  Future<ValidationResult> validateDiscount({
    required Discount discount,
    required User user,
    required Booking booking,
    required Listing listing,
  });
}

class DiscountResult {
  final bool success;
  final AppliedDiscount? discount;
  final String? errorMessage;
  final DiscountErrorCode? errorCode;
}

enum DiscountErrorCode {
  invalidCode,
  expired,
  exhausted,
  notEligible,
  minAmountNotMet,
  alreadyUsed,
  notStackable,
}

class DiscountCalculation {
  final Money subtotal;
  final List<AppliedDiscount> appliedDiscounts;
  final Money totalDiscount;
  final Money serviceFee;
  final Money finalTotal;
  final List<Discount> availableButNotApplied;  // User could use these
  final String? savingsMessage;  // "You're saving ৳500!"
}
```

### 4.6 Stacking Rules (Uber/Pathao Style)

```
Discount Stacking Priority:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  1. Host Discounts (Weekly/Monthly)     ← Always applied first  │
│            │                                                     │
│            ▼                                                     │
│  2. Platform Auto-Discounts             ← Applied to reduced    │
│     (First booking, Loyalty, etc.)         amount               │
│            │                                                     │
│            ▼                                                     │
│  3. Promo Code                          ← Only ONE allowed      │
│            │                                                     │
│            ▼                                                     │
│  4. Referral Credit                     ← Applied as credit     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

Rules:
• Host discounts ALWAYS stack with platform discounts
• Only ONE promo code per booking
• Auto-discounts may or may not stack (configured per discount)
• Max total discount capped at 50% of subtotal (fraud prevention)
• Referral credits applied after all discounts
```

```dart
class StackingRules {
  static const maxTotalDiscountPercent = 50;  // Cap at 50%
  static const maxPromoCodesPerBooking = 1;

  static bool canStack(Discount a, Discount b) {
    // Host discounts always stack with platform discounts
    if (a.type.isHostDiscount && b.type.isPlatformDiscount) return true;
    if (b.type.isHostDiscount && a.type.isPlatformDiscount) return true;

    // Check individual stackable flags
    if (!a.stackable || !b.stackable) return false;

    // Check exclusion lists
    if (a.excludedTypes?.contains(b.type) ?? false) return false;
    if (b.excludedTypes?.contains(a.type) ?? false) return false;

    return true;
  }
}
```

### 4.7 Referral System

```dart
class ReferralSystem {
  // Referral codes
  final String Function(User user) generateCode;  // "JOHN2024"

  // Rewards
  static const Money referrerReward = Money.bdt(200);
  static const Money refereeReward = Money.bdt(300);  // First booking discount

  // Rules
  static const int maxReferralsPerUser = 50;
  static const Duration refereeValidityPeriod = Duration(days: 30);
  static const bool requiresCompletedBooking = true;  // Referee must complete booking
}

class ReferralCode {
  final String code;
  final String referrerId;
  final DateTime createdAt;
  final int usageCount;
  final Money totalEarnings;
  final List<ReferralUsage> usages;
}

class ReferralUsage {
  final String refereeId;
  final DateTime usedAt;
  final String? bookingId;        // First booking by referee
  final ReferralStatus status;    // pending, completed, expired
  final Money? referrerReward;
  final Money? refereeDiscount;
}
```

### 4.8 Loyalty Program (Pathao-Style Tiers)

```dart
enum UserTier {
  bronze,     // 0-2 bookings
  silver,     // 3-5 bookings
  gold,       // 6-10 bookings
  platinum,   // 11+ bookings
}

class LoyaltyProgram {
  static const tierBenefits = {
    UserTier.bronze: TierBenefits(
      discountPercent: 0,
      prioritySupport: false,
      freeUpgrades: false,
      exclusiveDeals: false,
    ),
    UserTier.silver: TierBenefits(
      discountPercent: 5,
      prioritySupport: false,
      freeUpgrades: false,
      exclusiveDeals: true,
    ),
    UserTier.gold: TierBenefits(
      discountPercent: 10,
      prioritySupport: true,
      freeUpgrades: false,
      exclusiveDeals: true,
    ),
    UserTier.platinum: TierBenefits(
      discountPercent: 15,
      prioritySupport: true,
      freeUpgrades: true,
      exclusiveDeals: true,
    ),
  };

  static UserTier calculateTier(int completedBookings) {
    if (completedBookings >= 11) return UserTier.platinum;
    if (completedBookings >= 6) return UserTier.gold;
    if (completedBookings >= 3) return UserTier.silver;
    return UserTier.bronze;
  }
}
```

### 4.9 Seasonal Campaigns (Uber-Style)

```dart
class Campaign {
  final String id;
  final String name;                    // "Eid Special"
  final String description;
  final CampaignType type;
  final DateTime startDate;
  final DateTime endDate;
  final List<Discount> discounts;
  final Money? totalBudget;
  final Money spentBudget;
  final String? bannerImageUrl;
  final String? termsUrl;
  final bool isActive;

  bool get isBudgetExhausted =>
    totalBudget != null && spentBudget >= totalBudget!;
}

enum CampaignType {
  seasonal,     // Eid, Pohela Boishakh, etc.
  flash,        // 24-hour flash sale
  partnership,  // Bank/card partnerships
  geographic,   // City-specific campaigns
}

// Example: Eid Campaign
final eidCampaign = Campaign(
  name: 'Eid Special 2024',
  type: CampaignType.seasonal,
  startDate: DateTime(2024, 4, 8),
  endDate: DateTime(2024, 4, 15),
  totalBudget: Money.bdt(500000),
  discounts: [
    Discount(
      type: DiscountType.seasonal,
      valueType: DiscountValueType.percentage,
      value: 25,
      maxDiscount: Money.bdt(2000),
      eligibility: DiscountEligibility(
        stayDateRange: DateRange(
          start: DateTime(2024, 4, 8),
          end: DateTime(2024, 4, 15),
        ),
      ),
    ),
  ],
);
```

### 4.10 Host Discount Settings

```dart
class HostDiscountSettings {
  final String listingId;

  // Length of stay discounts (Airbnb-style)
  final int? weeklyDiscountPercent;     // 7+ nights
  final int? monthlyDiscountPercent;    // 28+ nights

  // Custom discounts
  final List<HostCustomDiscount> customDiscounts;

  // Early bird
  final int? earlyBirdDays;             // Book X days in advance
  final int? earlyBirdDiscountPercent;

  // Last minute
  final int? lastMinuteHours;           // Book within X hours
  final int? lastMinuteDiscountPercent;

  // New listing promotion
  final bool newListingPromoEnabled;    // Auto 20% for first 3 bookings
}

class HostCustomDiscount {
  final String id;
  final String name;                    // "Summer Special"
  final DateRange validDates;
  final int discountPercent;
  final int? minNights;
  final bool isActive;
}
```

### 4.11 Price Breakdown UI

```dart
class PriceBreakdown {
  final Money basePrice;               // ৳1,000 x 5 nights
  final Money? weeklyDiscount;         // -৳500 (10% weekly discount)
  final Money? promoDiscount;          // -৳300 (FIRST20)
  final Money? loyaltyDiscount;        // -৳200 (Gold member)
  final Money subtotalAfterDiscounts;
  final Money serviceFee;              // ৳350
  final Money? taxes;                  // ৳0 (if applicable)
  final Money total;
  final Money? youSaved;               // ৳1,000 total savings

  List<PriceLineItem> get lineItems;
}

class PriceLineItem {
  final String label;
  final Money amount;
  final bool isDiscount;
  final String? tooltip;               // Explains the discount
}

// UI Widget
class PriceBreakdownCard extends StatelessWidget {
  final PriceBreakdown breakdown;
  final bool expanded;                 // Show all line items
  final VoidCallback? onPromoCodeTap;

  // Displays:
  // ৳1,000 x 5 nights              ৳5,000
  // Weekly discount (10%)           -৳500
  // Promo code (FIRST20)           -৳300  [Remove]
  // Gold member discount           -৳200
  // ─────────────────────────────────────
  // Subtotal                       ৳4,000
  // Service fee                      ৳350
  // ─────────────────────────────────────
  // Total                          ৳4,350
  //
  // 🎉 You're saving ৳1,000!
}
```

### 4.12 Fraud Prevention

```dart
class DiscountFraudPrevention {
  // Rules
  static const maxDiscountPerDay = Money.bdt(5000);
  static const maxDiscountPercentage = 50;
  static const minTimeBetweenCodes = Duration(hours: 24);

  // Checks
  Future<FraudCheckResult> checkForFraud({
    required User user,
    required Discount discount,
    required Booking booking,
  }) async {
    final checks = [
      _checkVelocity(user),           // Too many discounts too fast
      _checkDeviceFingerprint(user),  // Multiple accounts, same device
      _checkPaymentPattern(user),     // Suspicious payment behavior
      _checkGeoAnomaly(user),         // Location inconsistencies
      _checkAccountAge(user),         // New account + high discount
      _checkReferralAbuse(user),      // Self-referral patterns
    ];

    return FraudCheckResult(
      passed: checks.every((c) => c.passed),
      flags: checks.where((c) => !c.passed).toList(),
    );
  }
}

class FraudCheckResult {
  final bool passed;
  final List<FraudFlag> flags;
  final FraudAction recommendedAction;  // allow, review, block
}

enum FraudFlag {
  velocityExceeded,
  multipleAccountsSameDevice,
  suspiciousPaymentPattern,
  geoAnomaly,
  newAccountHighDiscount,
  selfReferralPattern,
}
```

### 4.13 Corner Cases

| Scenario | Handling |
|----------|----------|
| Discount code case sensitivity | Normalize to uppercase |
| Expired code entered | Show "Code expired" with expiry date |
| Code already used by user | Show "You've already used this code" |
| Discount > booking amount | Cap at booking amount, no negative |
| Host discount + platform conflict | Platform discount takes precedence |
| Partial refund with discount | Prorate discount proportionally |
| Code reveals confidential promo | Validate server-side, generic error |
| Timezone issues | Use user's local timezone for validity |
| Currency conversion | All discounts calculated in BDT |
| Discount on service fee | Never - only on base price |
| Multiple valid auto-discounts | Apply best combination automatically |
| Referrer's account deleted | Referral still valid, reward to platform |

### 4.14 File Structure

```
lib/
├── core/
│   └── discount/
│       ├── discount.dart
│       ├── discount_eligibility.dart
│       ├── discount_engine.dart
│       ├── stacking_rules.dart
│       └── fraud_prevention.dart
├── models/
│   ├── discount.dart
│   ├── applied_discount.dart
│   ├── referral.dart
│   ├── campaign.dart
│   └── loyalty_tier.dart
├── services/
│   └── discount/
│       ├── discount_service.dart
│       ├── promo_code_service.dart
│       ├── referral_service.dart
│       └── loyalty_service.dart
├── state/
│   ├── discount_state.dart
│   └── referral_state.dart
├── screens/
│   └── discount/
│       ├── promo_code_screen.dart
│       ├── referral_screen.dart
│       └── loyalty_screen.dart
└── widgets/
    └── discount/
        ├── promo_code_input.dart
        ├── price_breakdown_card.dart
        ├── discount_badge.dart
        ├── savings_banner.dart
        └── referral_card.dart
```

---

## Database Schema Changes

### New Tables

```sql
-- Notifications table
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  category TEXT NOT NULL,
  priority TEXT NOT NULL DEFAULT 'medium',
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB DEFAULT '{}',
  image_url TEXT,
  actions JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  read_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,

  CONSTRAINT valid_category CHECK (category IN (
    'booking_created', 'booking_confirmed', 'booking_cancelled',
    'booking_reminder', 'new_message', 'review_received',
    'payment_received', 'payment_failed', 'system', 'promotional'
  )),
  CONSTRAINT valid_priority CHECK (priority IN (
    'critical', 'high', 'medium', 'low', 'silent'
  ))
);

CREATE INDEX idx_notifications_user_unread
  ON notifications(user_id, read_at)
  WHERE read_at IS NULL;

-- Notification preferences
CREATE TABLE notification_preferences (
  user_id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  push_enabled BOOLEAN DEFAULT TRUE,
  email_enabled BOOLEAN DEFAULT TRUE,
  sms_enabled BOOLEAN DEFAULT FALSE,
  quiet_hours_start TIME,
  quiet_hours_end TIME,
  category_settings JSONB DEFAULT '{}',
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Push tokens
CREATE TABLE push_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  platform TEXT NOT NULL,  -- 'ios', 'android', 'web'
  device_info JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_used_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id, token)
);

-- Conversations table
CREATE TABLE conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL DEFAULT 'general',
  booking_id UUID REFERENCES bookings(id),
  listing_id UUID REFERENCES listings(id),
  participant_ids UUID[] NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT valid_type CHECK (type IN ('booking', 'inquiry', 'support', 'system')),
  CONSTRAINT valid_status CHECK (status IN ('active', 'archived', 'blocked'))
);

CREATE INDEX idx_conversations_participants ON conversations USING GIN(participant_ids);

-- Messages table
CREATE TABLE messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES profiles(id),
  content_type TEXT NOT NULL,
  content JSONB NOT NULL,
  channel TEXT NOT NULL DEFAULT 'in_app',
  reply_to_id UUID REFERENCES messages(id),
  sent_at TIMESTAMPTZ DEFAULT NOW(),
  delivered_at TIMESTAMPTZ,
  read_at TIMESTAMPTZ,
  metadata JSONB,

  CONSTRAINT valid_content_type CHECK (content_type IN (
    'text', 'image', 'location', 'booking_card', 'system'
  )),
  CONSTRAINT valid_channel CHECK (channel IN ('in_app', 'whatsapp', 'messenger'))
);

CREATE INDEX idx_messages_conversation ON messages(conversation_id, sent_at DESC);

-- Read cursors
CREATE TABLE conversation_read_cursors (
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  last_read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  PRIMARY KEY (conversation_id, user_id)
);

-- Discounts table
CREATE TABLE discounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE,
  type TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  value_type TEXT NOT NULL,
  value NUMERIC(10, 2) NOT NULL,
  max_discount NUMERIC(12, 2),
  eligibility JSONB NOT NULL DEFAULT '{}',
  start_date TIMESTAMPTZ,
  end_date TIMESTAMPTZ,
  max_uses_total INTEGER,
  max_uses_per_user INTEGER DEFAULT 1,
  current_uses INTEGER DEFAULT 0,
  stackable BOOLEAN DEFAULT FALSE,
  excluded_types TEXT[],
  priority INTEGER DEFAULT 0,
  campaign_id UUID,
  metadata JSONB,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT valid_type CHECK (type IN (
    'promo_code', 'referral_code', 'influencer_code',
    'first_booking', 'early_bird', 'last_minute', 'long_stay',
    'repeat_guest', 'loyalty_tier', 'seasonal', 'flash',
    'host_weekly', 'host_monthly', 'host_custom'
  )),
  CONSTRAINT valid_value_type CHECK (value_type IN ('percentage', 'fixed', 'free_nights')),
  CONSTRAINT positive_value CHECK (value > 0)
);

CREATE INDEX idx_discounts_code ON discounts(UPPER(code)) WHERE code IS NOT NULL;
CREATE INDEX idx_discounts_active ON discounts(is_active, start_date, end_date);

-- Discount usage tracking
CREATE TABLE discount_usages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  discount_id UUID NOT NULL REFERENCES discounts(id),
  user_id UUID NOT NULL REFERENCES profiles(id),
  booking_id UUID REFERENCES bookings(id),
  discount_amount NUMERIC(12, 2) NOT NULL,
  used_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(discount_id, user_id, booking_id)
);

-- Referrals table
CREATE TABLE referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id UUID NOT NULL REFERENCES profiles(id),
  code TEXT NOT NULL UNIQUE,
  usage_count INTEGER DEFAULT 0,
  total_earnings NUMERIC(12, 2) DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Referral usages
CREATE TABLE referral_usages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referral_id UUID NOT NULL REFERENCES referrals(id),
  referee_id UUID NOT NULL REFERENCES profiles(id),
  booking_id UUID REFERENCES bookings(id),
  status TEXT NOT NULL DEFAULT 'pending',
  referrer_reward NUMERIC(12, 2),
  referee_discount NUMERIC(12, 2),
  used_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,

  CONSTRAINT valid_status CHECK (status IN ('pending', 'completed', 'expired')),
  UNIQUE(referral_id, referee_id)
);

-- User tiers (loyalty)
CREATE TABLE user_tiers (
  user_id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  tier TEXT NOT NULL DEFAULT 'bronze',
  completed_bookings INTEGER DEFAULT 0,
  total_spent NUMERIC(12, 2) DEFAULT 0,
  tier_updated_at TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT valid_tier CHECK (tier IN ('bronze', 'silver', 'gold', 'platinum'))
);

-- Campaigns
CREATE TABLE campaigns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  type TEXT NOT NULL,
  start_date TIMESTAMPTZ NOT NULL,
  end_date TIMESTAMPTZ NOT NULL,
  total_budget NUMERIC(12, 2),
  spent_budget NUMERIC(12, 2) DEFAULT 0,
  banner_image_url TEXT,
  terms_url TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT valid_type CHECK (type IN ('seasonal', 'flash', 'partnership', 'geographic'))
);

-- Messaging preferences
CREATE TABLE messaging_preferences (
  user_id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  preferred_channel TEXT DEFAULT 'in_app',
  whatsapp_enabled BOOLEAN DEFAULT FALSE,
  whatsapp_number TEXT,
  messenger_enabled BOOLEAN DEFAULT FALSE,
  messenger_psid TEXT,
  auto_response_enabled BOOLEAN DEFAULT FALSE,
  auto_response_message TEXT,
  show_read_receipts BOOLEAN DEFAULT TRUE,
  show_online_status BOOLEAN DEFAULT TRUE,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Modify bookings table
ALTER TABLE bookings ADD COLUMN subtotal NUMERIC(12, 2);
ALTER TABLE bookings ADD COLUMN discount_amount NUMERIC(12, 2) DEFAULT 0;
ALTER TABLE bookings ADD COLUMN service_fee NUMERIC(12, 2);
ALTER TABLE bookings ADD COLUMN applied_discounts JSONB DEFAULT '[]';
```

### Database Triggers

```sql
-- Trigger: Update conversation timestamp on new message
CREATE OR REPLACE FUNCTION update_conversation_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE conversations
  SET updated_at = NOW()
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_message_insert
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION update_conversation_timestamp();

-- Trigger: Increment discount usage
CREATE OR REPLACE FUNCTION increment_discount_usage()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE discounts
  SET current_uses = current_uses + 1
  WHERE id = NEW.discount_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_discount_used
  AFTER INSERT ON discount_usages
  FOR EACH ROW
  EXECUTE FUNCTION increment_discount_usage();

-- Trigger: Update user tier on booking completion
CREATE OR REPLACE FUNCTION update_user_tier()
RETURNS TRIGGER AS $$
DECLARE
  booking_count INTEGER;
  new_tier TEXT;
BEGIN
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    -- Update completed bookings count
    UPDATE user_tiers
    SET completed_bookings = completed_bookings + 1,
        total_spent = total_spent + NEW.total_price
    WHERE user_id = NEW.user_id;

    -- Get new count
    SELECT completed_bookings INTO booking_count
    FROM user_tiers
    WHERE user_id = NEW.user_id;

    -- Calculate new tier
    new_tier := CASE
      WHEN booking_count >= 11 THEN 'platinum'
      WHEN booking_count >= 6 THEN 'gold'
      WHEN booking_count >= 3 THEN 'silver'
      ELSE 'bronze'
    END;

    -- Update tier if changed
    UPDATE user_tiers
    SET tier = new_tier, tier_updated_at = NOW()
    WHERE user_id = NEW.user_id AND tier != new_tier;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_booking_status_change
  AFTER UPDATE OF status ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION update_user_tier();
```

---

## Integration Architecture

### System Integration Map

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Musafir Integration Architecture                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│                         ┌──────────────────┐                            │
│                         │   Flutter App    │                            │
│                         └────────┬─────────┘                            │
│                                  │                                       │
│              ┌───────────────────┼───────────────────┐                  │
│              │                   │                   │                  │
│              ▼                   ▼                   ▼                  │
│    ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐        │
│    │   Supabase      │ │  Firebase FCM   │ │  External APIs  │        │
│    │   (Primary DB)  │ │  (Push Notif)   │ │                 │        │
│    └────────┬────────┘ └────────┬────────┘ └────────┬────────┘        │
│             │                   │                   │                  │
│             │                   │          ┌────────┴────────┐         │
│             │                   │          │                 │         │
│             │                   │          ▼                 ▼         │
│             │                   │   ┌───────────┐    ┌───────────┐    │
│             │                   │   │ WhatsApp  │    │ Messenger │    │
│             │                   │   │ Business  │    │ Platform  │    │
│             │                   │   └───────────┘    └───────────┘    │
│             │                   │                                      │
│             ▼                   ▼                                      │
│    ┌─────────────────────────────────────────────────────────────┐    │
│    │                    Supabase Edge Functions                   │    │
│    │  • Webhook handlers (WhatsApp, Messenger)                   │    │
│    │  • Push notification dispatcher                              │    │
│    │  • Discount validation                                       │    │
│    │  • Message routing                                           │    │
│    └─────────────────────────────────────────────────────────────┘    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### API Endpoints (Edge Functions)

```
POST /notifications/send          - Send notification to user
POST /notifications/broadcast     - Send to multiple users
GET  /notifications/preferences   - Get user preferences
PUT  /notifications/preferences   - Update preferences

POST /messages/send               - Send message (routes to appropriate channel)
POST /messages/whatsapp/webhook   - WhatsApp incoming webhook
POST /messages/messenger/webhook  - Messenger incoming webhook

POST /discounts/validate          - Validate promo code
POST /discounts/calculate         - Calculate best discounts
GET  /discounts/available         - Get available discounts for user

POST /referrals/generate          - Generate referral code
POST /referrals/apply             - Apply referral code
GET  /referrals/stats             - Get referral statistics
```

---

## Security Considerations

### Data Security

| Area | Measure |
|------|---------|
| Promo codes | Server-side validation only |
| Discount amounts | Calculated server-side, never trusted from client |
| Message encryption | End-to-end for sensitive conversations |
| Phone numbers | Encrypted at rest, masked in UI |
| Payment data | Never stored, tokenized via payment gateway |

### Access Control

```sql
-- RLS policies for notifications
CREATE POLICY "Users can only see their notifications"
  ON notifications FOR SELECT
  USING (auth.uid() = user_id);

-- RLS policies for messages
CREATE POLICY "Users can only see messages in their conversations"
  ON messages FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM conversations
      WHERE id = messages.conversation_id
      AND auth.uid() = ANY(participant_ids)
    )
  );

-- RLS policies for discounts (admin only for mutations)
CREATE POLICY "Anyone can read active discounts"
  ON discounts FOR SELECT
  USING (is_active = true);
```

### Rate Limiting

| Endpoint | Limit |
|----------|-------|
| Promo code validation | 10/minute/user |
| Message sending | 60/minute/user |
| Notification preferences | 10/minute/user |
| Referral code generation | 1/day/user |

---

## Migration Strategy

### Phase 1: Currency System (Week 1-2)
1. Add `intl` package to dependencies
2. Create `Money` value object and `CurrencyFormatter`
3. Create `PriceDisplay` widget
4. Update `Listing` and `Booking` models
5. Migrate all price displays to use new widgets
6. Update search filters to use `Money`

### Phase 2: Notification System (Week 3-4)
1. Create database tables and triggers
2. Implement `NotificationService` with Supabase Realtime
3. Integrate Firebase FCM
4. Create notification UI components
5. Add notification preferences screen
6. Test end-to-end notification flow

### Phase 3: Messaging System (Week 5-7)
1. Create conversation and message tables
2. Implement in-app messaging service
3. Create chat UI components
4. Integrate WhatsApp Business API
5. Integrate Messenger Platform
6. Implement message routing logic
7. Add messaging preferences

### Phase 4: Discount System (Week 8-10)
1. Create discount tables and triggers
2. Implement `DiscountEngine`
3. Create promo code input and price breakdown UI
4. Implement referral system
5. Implement loyalty tiers
6. Add host discount settings
7. Implement fraud prevention
8. Create admin discount management

### Rollout Strategy

```
Phase 1: Internal Testing
└── Test with team accounts
└── Verify all corner cases
└── Performance testing

Phase 2: Beta Release (5% users)
└── Feature flags enabled
└── Monitor error rates
└── Collect feedback

Phase 3: Gradual Rollout
└── 25% → 50% → 75% → 100%
└── Monitor metrics at each stage
└── Quick rollback capability

Phase 4: Full Release
└── Remove feature flags
└── Documentation update
└── Marketing announcement
```

---

## Testing Strategy

### Unit Tests

```dart
// Currency tests
test('Money addition works correctly', () {
  final a = Money.bdt(100);
  final b = Money.bdt(50);
  expect(a.add(b), equals(Money.bdt(150)));
});

test('Money formatting with BDT symbol', () {
  expect(Money.bdt(1500).format(), equals('৳1,500'));
});

// Discount tests
test('Percentage discount calculates correctly', () {
  final discount = Discount(
    valueType: DiscountValueType.percentage,
    value: 20,
  );
  final result = discount.apply(Money.bdt(1000));
  expect(result, equals(Money.bdt(200)));
});

test('Discount stacking respects priority', () {
  // Test that higher priority discounts apply first
});

test('Expired discount returns error', () {
  // Test validation
});
```

### Integration Tests

```dart
// Notification flow
testWidgets('Notification appears when booking created', (tester) async {
  // Create booking
  // Verify notification received
  // Verify push notification triggered
});

// Messaging flow
testWidgets('Message syncs across channels', (tester) async {
  // Send message via in-app
  // Verify appears in conversation
  // Verify delivered to WhatsApp if linked
});

// Discount flow
testWidgets('Promo code applies to booking', (tester) async {
  // Enter promo code
  // Verify discount applied
  // Complete booking
  // Verify discount recorded
});
```

### E2E Tests

```
Scenario: First-time user booking with discount
  Given a new user
  When they apply first booking discount
  And complete a booking
  Then they should receive confirmation notification
  And host should receive booking notification
  And discount should be recorded
  And user tier should update
```

---

## Success Metrics

| Feature | Metric | Target |
|---------|--------|--------|
| Currency | Price display consistency | 100% |
| Notifications | Delivery rate | >98% |
| Notifications | Open rate | >40% |
| Messaging | Response time | <5min avg |
| Messaging | Channel adoption | 30% WhatsApp |
| Discounts | Promo code redemption | 15% of bookings |
| Discounts | Referral conversion | 10% |
| Discounts | Fraud rate | <0.1% |

---

## Implementation Plan

### Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    IMPLEMENTATION TIMELINE (12 WEEKS)                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Week 1-2    │  Week 3-4    │  Week 5-7      │  Week 8-10     │  Week 11-12 │
│  ─────────   │  ─────────   │  ──────────    │  ──────────    │  ────────── │
│  Currency    │  Notifications│  Messaging    │  Discounts     │  Polish &   │
│  System      │  System       │  System       │  System        │  Launch     │
│              │               │               │                │             │
│  ▪ Money     │  ▪ DB Schema │  ▪ In-app     │  ▪ Discount    │  ▪ Bug fixes│
│  ▪ Formatter │  ▪ Realtime  │  ▪ WhatsApp   │  ▪ Referrals   │  ▪ Perf opt │
│  ▪ Widgets   │  ▪ FCM       │  ▪ Messenger  │  ▪ Loyalty     │  ▪ Docs     │
│  ▪ Migration │  ▪ UI        │  ▪ Routing    │  ▪ Campaigns   │  ▪ Release  │
│              │               │               │                │             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Sprint Breakdown

---

### Sprint 1: BDT Currency System - Core (Week 1)

#### Goals
- Implement Money value object and Currency configuration
- Create CurrencyFormatter service
- Add intl package dependency

#### Tasks

| ID | Task | Priority | Est. Hours | Dependencies |
|----|------|----------|------------|--------------|
| 1.1 | Add `intl` package to pubspec.yaml | High | 0.5 | None |
| 1.2 | Create `lib/core/currency/currency.dart` - Currency class | High | 2 | None |
| 1.3 | Create `lib/core/currency/money.dart` - Money value object | High | 4 | 1.2 |
| 1.4 | Create `lib/core/currency/currency_formatter.dart` | High | 3 | 1.2, 1.3 |
| 1.5 | Create `lib/core/currency/currency_config.dart` | Medium | 1 | 1.2 |
| 1.6 | Write unit tests for Money class | High | 3 | 1.3 |
| 1.7 | Write unit tests for CurrencyFormatter | High | 2 | 1.4 |
| 1.8 | Create `lib/core/currency/price_calculator.dart` | Medium | 3 | 1.3 |

#### Files to Create
```
lib/
└── core/
    └── currency/
        ├── currency.dart
        ├── money.dart
        ├── currency_formatter.dart
        ├── currency_config.dart
        ├── price_calculator.dart
        └── currency_exceptions.dart

test/
└── core/
    └── currency/
        ├── money_test.dart
        ├── currency_formatter_test.dart
        └── price_calculator_test.dart
```

#### Acceptance Criteria
- [ ] `Money.bdt(1500).format()` returns `"৳1,500"`
- [ ] `Money.bdt(150000).format(useCompact: true)` returns `"৳1.5L"`
- [ ] `Money.bdt(100).add(Money.bdt(50))` returns `Money` with 150 BDT
- [ ] All operations throw `CurrencyMismatchException` for mismatched currencies
- [ ] All unit tests pass with >90% coverage

---

### Sprint 2: BDT Currency System - UI & Migration (Week 2)

#### Goals
- Create price display widgets
- Migrate existing models to use Money
- Update all screens to use new price widgets

#### Tasks

| ID | Task | Priority | Est. Hours | Dependencies |
|----|------|----------|------------|--------------|
| 2.1 | Create `lib/widgets/price_display.dart` | High | 3 | Sprint 1 |
| 2.2 | Create `lib/widgets/price_range_slider.dart` | Medium | 3 | Sprint 1 |
| 2.3 | Create `lib/widgets/price_breakdown_card.dart` | Medium | 4 | Sprint 1 |
| 2.4 | Update `lib/models/listing.dart` - Add Money fields | High | 2 | Sprint 1 |
| 2.5 | Update `lib/models/booking.dart` - Add Money fields | High | 2 | Sprint 1 |
| 2.6 | Create backward compatibility helpers | High | 2 | 2.4, 2.5 |
| 2.7 | Update `ExploreScreen` price displays | High | 2 | 2.1 |
| 2.8 | Update `ListingDetailScreen` price displays | High | 2 | 2.1 |
| 2.9 | Update `CreateListingScreen` price inputs | High | 3 | 2.1 |
| 2.10 | Update `TripsScreen` price displays | Medium | 1 | 2.1 |
| 2.11 | Update `HostDashboardScreen` price displays | Medium | 2 | 2.1 |
| 2.12 | Update `SearchFilters` to use Money | Medium | 2 | Sprint 1 |
| 2.13 | Integration testing for price displays | High | 3 | 2.7-2.12 |

#### Files to Modify
```
lib/models/listing.dart          # Add Money fields, keep double for backward compat
lib/models/booking.dart          # Add Money fields
lib/models/search_filters.dart   # Update price range to Money
lib/screens/explore/explore_screen.dart
lib/screens/explore/listing_detail_screen.dart
lib/screens/host/create_listing_screen.dart
lib/screens/host/host_dashboard_screen.dart
lib/screens/trips/trips_screen.dart
lib/widgets/listing_card.dart
lib/widgets/listing_card_modern.dart
```

#### Acceptance Criteria
- [ ] All price displays use `PriceDisplay` widget
- [ ] No hardcoded "BDT" strings in UI
- [ ] Price inputs show ৳ symbol
- [ ] Large amounts display in lakh/crore notation
- [ ] Existing functionality unchanged
- [ ] All integration tests pass

---

### Sprint 3: Notification System - Backend (Week 3)

#### Goals
- Create notification database schema
- Implement Supabase Realtime integration
- Create notification service and state

#### Tasks

| ID | Task | Priority | Est. Hours | Dependencies |
|----|------|----------|------------|--------------|
| 3.1 | Create notification tables migration | High | 3 | None |
| 3.2 | Create notification preferences table | High | 1 | 3.1 |
| 3.3 | Create push_tokens table | High | 1 | 3.1 |
| 3.4 | Create database triggers for booking notifications | High | 4 | 3.1 |
| 3.5 | Create `lib/models/notification.dart` | High | 2 | None |
| 3.6 | Create `lib/models/notification_preferences.dart` | Medium | 1 | None |
| 3.7 | Create `lib/services/notifications/notification_service.dart` (interface) | High | 2 | 3.5 |
| 3.8 | Create `lib/services/notifications/realtime_notification_service.dart` | High | 6 | 3.7 |
| 3.9 | Create `lib/services/notifications/notification_templates.dart` | Medium | 2 | 3.5 |
| 3.10 | Create `lib/state/notification_state.dart` | High | 3 | 3.7 |
| 3.11 | Write unit tests for notification service | High | 3 | 3.8 |
| 3.12 | Create RLS policies for notifications | High | 2 | 3.1 |

#### Files to Create
```
supabase/
└── migrations/
    └── 002_notifications.sql

lib/
├── models/
│   ├── notification.dart
│   └── notification_preferences.dart
├── services/
│   └── notifications/
│       ├── notification_service.dart
│       ├── realtime_notification_service.dart
│       ├── notification_templates.dart
│       └── notification_scheduler.dart
└── state/
    └── notification_state.dart
```

#### Acceptance Criteria
- [ ] Notifications table created with proper indexes
- [ ] RLS policies prevent cross-user access
- [ ] Realtime subscription receives new notifications
- [ ] Notification templates render correctly
- [ ] Unread count updates in real-time

---

### Sprint 4: Notification System - Push & UI (Week 4)

#### Goals
- Integrate Firebase Cloud Messaging
- Create notification UI components
- Implement notification preferences screen

#### Tasks

| ID | Task | Priority | Est. Hours | Dependencies |
|----|------|----------|------------|--------------|
| 4.1 | Add `firebase_messaging` package | High | 1 | None |
| 4.2 | Configure Firebase for Android | High | 2 | 4.1 |
| 4.3 | Configure Firebase for iOS | High | 2 | 4.1 |
| 4.4 | Create `lib/services/notifications/push_notification_service.dart` | High | 4 | 4.1 |
| 4.5 | Implement push token registration | High | 2 | 4.4 |
| 4.6 | Create `lib/widgets/notification_bell.dart` | High | 2 | Sprint 3 |
| 4.7 | Create `lib/widgets/notification_toast.dart` | Medium | 2 | Sprint 3 |
| 4.8 | Create `lib/widgets/notification_item.dart` | High | 2 | Sprint 3 |
| 4.9 | Create `lib/screens/notifications/notification_center_screen.dart` | High | 4 | 4.8 |
| 4.10 | Create `lib/screens/notifications/notification_settings_screen.dart` | Medium | 3 | Sprint 3 |
| 4.11 | Add notification bell to MainShell app bar | High | 1 | 4.6 |
| 4.12 | Implement quiet hours logic | Low | 2 | 4.4 |
| 4.13 | Handle notification tap deep linking | High | 3 | 4.4, 4.9 |
| 4.14 | End-to-end notification testing | High | 4 | All above |

#### Files to Create/Modify
```
android/app/google-services.json
ios/Runner/GoogleService-Info.plist
ios/Runner/Info.plist                    # Add push notification entitlements

lib/
├── services/
│   └── notifications/
│       └── push_notification_service.dart
├── screens/
│   └── notifications/
│       ├── notification_center_screen.dart
│       └── notification_settings_screen.dart
├── widgets/
│   ├── notification_bell.dart
│   ├── notification_toast.dart
│   └── notification_item.dart
└── screens/main_shell.dart              # Add notification bell
```

#### Acceptance Criteria
- [ ] Push notifications received on Android
- [ ] Push notifications received on iOS
- [ ] Notification bell shows unread count badge
- [ ] Notification center displays grouped notifications
- [ ] Tapping notification navigates to relevant screen
- [ ] Quiet hours prevent notifications during set times
- [ ] Preferences persist across app restarts

---

### Sprint 5: Messaging System - In-App (Week 5)

#### Goals
- Create messaging database schema
- Implement in-app real-time messaging
- Create conversation list UI

#### Tasks

| ID | Task | Priority | Est. Hours | Dependencies |
|----|------|----------|------------|--------------|
| 5.1 | Create conversations table migration | High | 2 | None |
| 5.2 | Create messages table migration | High | 2 | 5.1 |
| 5.3 | Create read cursors table | Medium | 1 | 5.1 |
| 5.4 | Create messaging RLS policies | High | 2 | 5.1, 5.2 |
| 5.5 | Create `lib/models/conversation.dart` | High | 2 | None |
| 5.6 | Create `lib/models/message.dart` with content types | High | 3 | None |
| 5.7 | Create `lib/services/messaging/messaging_service.dart` (interface) | High | 2 | 5.5, 5.6 |
| 5.8 | Create `lib/services/messaging/in_app_messaging_service.dart` | High | 6 | 5.7 |
| 5.9 | Implement typing indicators | Medium | 2 | 5.8 |
| 5.10 | Create `lib/state/messaging_state.dart` | High | 3 | 5.7 |
| 5.11 | Create `lib/widgets/messaging/conversation_tile.dart` | High | 2 | 5.5 |
| 5.12 | Update `lib/screens/inbox/inbox_screen.dart` | High | 4 | 5.11 |
| 5.13 | Create media upload service | Medium | 3 | None |
| 5.14 | Unit tests for messaging service | High | 3 | 5.8 |

#### Files to Create
```
supabase/
└── migrations/
    └── 003_messaging.sql

lib/
├── models/
│   ├── conversation.dart
│   ├── message.dart
│   └── messaging_preferences.dart
├── services/
│   └── messaging/
│       ├── messaging_service.dart
│       ├── in_app_messaging_service.dart
│       └── media_upload_service.dart
├── state/
│   └── messaging_state.dart
└── widgets/
    └── messaging/
        └── conversation_tile.dart
```

#### Acceptance Criteria
- [ ] Conversations list loads with real-time updates
- [ ] New messages appear instantly
- [ ] Unread counts update correctly
- [ ] Typing indicators work
- [ ] Conversation auto-creates for new booking

---

### Sprint 6: Messaging System - Chat UI (Week 6)

#### Goals
- Create chat screen with message bubbles
- Implement rich message types
- Add media sharing capability

#### Tasks

| ID | Task | Priority | Est. Hours | Dependencies |
|----|------|----------|------------|--------------|
| 6.1 | Create `lib/screens/messaging/chat_screen.dart` | High | 6 | Sprint 5 |
| 6.2 | Create `lib/widgets/messaging/message_bubble.dart` | High | 4 | Sprint 5 |
| 6.3 | Create `lib/widgets/messaging/message_input.dart` | High | 3 | Sprint 5 |
| 6.4 | Create `lib/widgets/messaging/typing_indicator.dart` | Medium | 1 | Sprint 5 |
| 6.5 | Implement text message rendering | High | 1 | 6.2 |
| 6.6 | Implement image message rendering | High | 2 | 6.2 |
| 6.7 | Implement location message rendering | Medium | 2 | 6.2 |
| 6.8 | Implement booking card message rendering | High | 3 | 6.2 |
| 6.9 | Implement system message rendering | Medium | 1 | 6.2 |
| 6.10 | Add image picker integration | High | 2 | 6.3 |
| 6.11 | Add location sharing | Medium | 2 | 6.3 |
| 6.12 | Implement message read receipts | Medium | 2 | 6.2 |
| 6.13 | Add reply-to-message feature | Low | 3 | 6.2 |
| 6.14 | Implement message deletion | Low | 2 | 6.2 |
| 6.15 | Chat screen integration testing | High | 3 | All above |

#### Files to Create
```
lib/
├── screens/
│   └── messaging/
│       ├── chat_screen.dart
│       └── messaging_settings_screen.dart
└── widgets/
    └── messaging/
        ├── message_bubble.dart
        ├── message_input.dart
        ├── typing_indicator.dart
        ├── image_message.dart
        ├── location_message.dart
        ├── booking_card_message.dart
        └── system_message.dart
```

#### Acceptance Criteria
- [ ] Messages display in chronological order
- [ ] Images load with thumbnails
- [ ] Location messages show mini map
- [ ] Booking cards show booking details
- [ ] Read receipts (✓✓) appear correctly
- [ ] Pull to load older messages works

---

### Sprint 7: Messaging System - External Channels (Week 7)

#### Goals
- Integrate WhatsApp Business API
- Integrate Messenger Platform
- Implement message routing

#### Tasks

| ID | Task | Priority | Est. Hours | Dependencies |
|----|------|----------|------------|--------------|
| 7.1 | Create `lib/config/whatsapp_config.dart` | High | 1 | None |
| 7.2 | Create `lib/config/messenger_config.dart` | High | 1 | None |
| 7.3 | Create `lib/services/messaging/whatsapp_service.dart` | High | 6 | 7.1 |
| 7.4 | Create WhatsApp message templates | High | 3 | 7.3 |
| 7.5 | Create `lib/services/messaging/messenger_service.dart` | Medium | 5 | 7.2 |
| 7.6 | Create `lib/services/messaging/message_router.dart` | High | 4 | 7.3, 7.5 |
| 7.7 | Create Supabase Edge Function for WhatsApp webhook | High | 4 | 7.3 |
| 7.8 | Create Supabase Edge Function for Messenger webhook | Medium | 4 | 7.5 |
| 7.9 | Create `lib/widgets/messaging/channel_selector.dart` | Medium | 2 | 7.6 |
| 7.10 | Create `lib/models/messaging_preferences.dart` | Medium | 1 | None |
| 7.11 | Update chat screen with channel indicator | Medium | 2 | 7.6, 7.9 |
| 7.12 | Handle WhatsApp 24h session window | High | 3 | 7.3 |
| 7.13 | End-to-end external messaging testing | High | 4 | All above |

#### Files to Create
```
lib/
├── config/
│   ├── whatsapp_config.dart
│   └── messenger_config.dart
├── services/
│   └── messaging/
│       ├── whatsapp_service.dart
│       ├── messenger_service.dart
│       └── message_router.dart
└── widgets/
    └── messaging/
        └── channel_selector.dart

supabase/
└── functions/
    ├── whatsapp-webhook/
    │   └── index.ts
    └── messenger-webhook/
        └── index.ts
```

#### Acceptance Criteria
- [ ] WhatsApp messages send successfully
- [ ] WhatsApp template messages work for booking confirmations
- [ ] Incoming WhatsApp messages appear in unified inbox
- [ ] Messenger messages send successfully
- [ ] Channel selector shows available channels
- [ ] Fallback to in-app when external channels unavailable

---

### Sprint 8: Discount System - Core (Week 8)

#### Goals
- Create discount database schema
- Implement discount engine
- Create promo code validation

#### Tasks

| ID | Task | Priority | Est. Hours | Dependencies |
|----|------|----------|------------|--------------|
| 8.1 | Create discounts table migration | High | 3 | None |
| 8.2 | Create discount_usages table | High | 2 | 8.1 |
| 8.3 | Create RLS policies for discounts | High | 2 | 8.1 |
| 8.4 | Create `lib/models/discount.dart` | High | 3 | None |
| 8.5 | Create `lib/models/discount_eligibility.dart` | High | 3 | 8.4 |
| 8.6 | Create `lib/models/applied_discount.dart` | High | 1 | 8.4 |
| 8.7 | Create `lib/core/discount/discount_engine.dart` | High | 6 | 8.4-8.6 |
| 8.8 | Create `lib/core/discount/stacking_rules.dart` | High | 3 | 8.7 |
| 8.9 | Create `lib/services/discount/discount_service.dart` | High | 4 | 8.7 |
| 8.10 | Create `lib/services/discount/promo_code_service.dart` | High | 3 | 8.9 |
| 8.11 | Create `lib/state/discount_state.dart` | High | 2 | 8.9 |
| 8.12 | Create discount validation Edge Function | High | 4 | 8.9 |
| 8.13 | Unit tests for discount engine | High | 4 | 8.7 |
| 8.14 | Unit tests for stacking rules | High | 2 | 8.8 |

#### Files to Create
```
supabase/
└── migrations/
    └── 004_discounts.sql

lib/
├── models/
│   ├── discount.dart
│   ├── discount_eligibility.dart
│   └── applied_discount.dart
├── core/
│   └── discount/
│       ├── discount_engine.dart
│       ├── stacking_rules.dart
│       └── fraud_prevention.dart
├── services/
│   └── discount/
│       ├── discount_service.dart
│       └── promo_code_service.dart
└── state/
    └── discount_state.dart

supabase/
└── functions/
    └── validate-discount/
        └── index.ts
```

#### Acceptance Criteria
- [ ] Promo code validation works correctly
- [ ] Percentage discounts calculate correctly
- [ ] Fixed amount discounts work
- [ ] Eligibility rules enforce correctly
- [ ] Stacking rules respected
- [ ] Max discount cap enforced
- [ ] Usage limits tracked

---

### Sprint 9: Discount System - Referrals & Loyalty (Week 9)

#### Goals
- Implement referral system
- Implement loyalty tiers
- Create auto-discount engine

#### Tasks

| ID | Task | Priority | Est. Hours | Dependencies |
|----|------|----------|------------|--------------|
| 9.1 | Create referrals table migration | High | 2 | None |
| 9.2 | Create user_tiers table migration | High | 2 | None |
| 9.3 | Create tier update trigger | High | 3 | 9.2 |
| 9.4 | Create `lib/models/referral.dart` | High | 2 | None |
| 9.5 | Create `lib/models/loyalty_tier.dart` | High | 2 | None |
| 9.6 | Create `lib/services/discount/referral_service.dart` | High | 4 | 9.4 |
| 9.7 | Create `lib/services/discount/loyalty_service.dart` | High | 3 | 9.5 |
| 9.8 | Create referral code generation | High | 2 | 9.6 |
| 9.9 | Create `lib/state/referral_state.dart` | Medium | 2 | 9.6 |
| 9.10 | Implement auto-discount detection | High | 4 | Sprint 8 |
| 9.11 | Implement first booking discount | High | 2 | 9.10 |
| 9.12 | Implement early bird discount | Medium | 2 | 9.10 |
| 9.13 | Implement long stay discount | Medium | 2 | 9.10 |
| 9.14 | Implement loyalty tier discount | High | 2 | 9.7, 9.10 |
| 9.15 | Unit tests for referral system | High | 3 | 9.6 |
| 9.16 | Unit tests for loyalty system | High | 2 | 9.7 |

#### Files to Create
```
supabase/
└── migrations/
    └── 005_referrals_loyalty.sql

lib/
├── models/
│   ├── referral.dart
│   └── loyalty_tier.dart
├── services/
│   └── discount/
│       ├── referral_service.dart
│       └── loyalty_service.dart
└── state/
    └── referral_state.dart
```

#### Acceptance Criteria
- [ ] Referral code generates with user name
- [ ] Referral rewards credited on completed booking
- [ ] User tier updates automatically
- [ ] Tier benefits apply correctly
- [ ] Auto-discounts detected and applied
- [ ] Best discount combination calculated

---

### Sprint 10: Discount System - UI & Campaigns (Week 10)

#### Goals
- Create discount UI components
- Implement campaign management
- Add host discount settings

#### Tasks

| ID | Task | Priority | Est. Hours | Dependencies |
|----|------|----------|------------|--------------|
| 10.1 | Create `lib/widgets/discount/promo_code_input.dart` | High | 3 | Sprint 8 |
| 10.2 | Update `lib/widgets/price_breakdown_card.dart` with discounts | High | 3 | Sprint 8 |
| 10.3 | Create `lib/widgets/discount/discount_badge.dart` | Medium | 1 | Sprint 8 |
| 10.4 | Create `lib/widgets/discount/savings_banner.dart` | Medium | 2 | Sprint 8 |
| 10.5 | Create `lib/screens/discount/referral_screen.dart` | High | 4 | Sprint 9 |
| 10.6 | Create `lib/screens/discount/loyalty_screen.dart` | Medium | 3 | Sprint 9 |
| 10.7 | Create `lib/widgets/discount/referral_card.dart` | High | 2 | Sprint 9 |
| 10.8 | Create `lib/widgets/discount/tier_progress.dart` | Medium | 2 | Sprint 9 |
| 10.9 | Update booking flow with discount UI | High | 4 | 10.1, 10.2 |
| 10.10 | Create `lib/models/campaign.dart` | Medium | 2 | None |
| 10.11 | Implement campaign banner display | Medium | 2 | 10.10 |
| 10.12 | Create host discount settings in CreateListingScreen | Medium | 3 | Sprint 8 |
| 10.13 | Implement fraud prevention checks | High | 3 | Sprint 8 |
| 10.14 | Integration testing for full booking with discount | High | 4 | All above |

#### Files to Create/Modify
```
lib/
├── models/
│   └── campaign.dart
├── screens/
│   └── discount/
│       ├── referral_screen.dart
│       └── loyalty_screen.dart
├── widgets/
│   └── discount/
│       ├── promo_code_input.dart
│       ├── discount_badge.dart
│       ├── savings_banner.dart
│       ├── referral_card.dart
│       └── tier_progress.dart
└── screens/
    └── host/
        └── create_listing_screen.dart  # Add discount settings
```

#### Acceptance Criteria
- [ ] Promo code input with validation feedback
- [ ] Price breakdown shows all applied discounts
- [ ] "You saved ৳X" banner displays
- [ ] Referral screen shows code and stats
- [ ] Loyalty screen shows tier progress
- [ ] Host can set weekly/monthly discounts
- [ ] Campaign banners display on explore

---

### Sprint 11: Polish & Testing (Week 11)

#### Goals
- Bug fixes and edge case handling
- Performance optimization
- Comprehensive testing

#### Tasks

| ID | Task | Priority | Est. Hours | Dependencies |
|----|------|----------|------------|--------------|
| 11.1 | Fix identified bugs from previous sprints | High | 8 | All sprints |
| 11.2 | Handle all edge cases documented | High | 6 | All sprints |
| 11.3 | Performance audit - identify bottlenecks | High | 4 | All sprints |
| 11.4 | Optimize database queries | High | 4 | 11.3 |
| 11.5 | Optimize image loading | Medium | 2 | 11.3 |
| 11.6 | Reduce bundle size | Medium | 2 | 11.3 |
| 11.7 | Write E2E tests for critical flows | High | 8 | All sprints |
| 11.8 | Cross-platform testing (Android/iOS) | High | 4 | All sprints |
| 11.9 | Accessibility audit and fixes | Medium | 4 | All sprints |
| 11.10 | Error handling improvements | High | 3 | All sprints |
| 11.11 | Loading state improvements | Medium | 2 | All sprints |
| 11.12 | Offline support improvements | Low | 4 | All sprints |

#### Acceptance Criteria
- [ ] All critical bugs resolved
- [ ] App startup time < 2 seconds
- [ ] No memory leaks detected
- [ ] E2E tests pass on CI/CD
- [ ] Works on Android 8+ and iOS 13+
- [ ] Accessibility score > 90%

---

### Sprint 12: Documentation & Launch (Week 12)

#### Goals
- Complete documentation
- Final QA
- Production deployment

#### Tasks

| ID | Task | Priority | Est. Hours | Dependencies |
|----|------|----------|------------|--------------|
| 12.1 | Update architecture.md with new features | High | 4 | All sprints |
| 12.2 | Create API documentation | High | 4 | All sprints |
| 12.3 | Create user guide for new features | Medium | 3 | All sprints |
| 12.4 | Create admin guide for discount management | Medium | 2 | Sprint 8-10 |
| 12.5 | Final QA testing | High | 6 | All sprints |
| 12.6 | Security audit | High | 4 | All sprints |
| 12.7 | Load testing | High | 3 | All sprints |
| 12.8 | Configure production environment | High | 3 | All sprints |
| 12.9 | Set up monitoring and alerts | High | 3 | All sprints |
| 12.10 | Deploy database migrations | High | 2 | All sprints |
| 12.11 | Deploy Edge Functions | High | 2 | All sprints |
| 12.12 | Deploy mobile app updates | High | 2 | All sprints |
| 12.13 | Post-launch monitoring | High | 4 | 12.12 |

#### Deliverables
- [ ] Updated architecture documentation
- [ ] API documentation
- [ ] User guide
- [ ] Admin guide
- [ ] Security audit report
- [ ] Load test results
- [ ] Production deployment checklist
- [ ] Rollback procedure

---

### Resource Allocation

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         TEAM ALLOCATION                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Role              │ Sprint 1-2 │ Sprint 3-4 │ Sprint 5-7 │ Sprint 8-12│
│  ─────────────────────────────────────────────────────────────────────  │
│  Flutter Dev 1     │ Currency   │ Notif UI   │ Chat UI    │ Discount UI│
│  Flutter Dev 2     │ Currency   │ Push Notif │ Messaging  │ Referral   │
│  Backend Dev       │ -          │ DB/Realtime│ Webhooks   │ Discount   │
│  QA Engineer       │ Unit Tests │ Integ Test │ E2E Tests  │ Final QA   │
│  Designer          │ UI Review  │ Notif Des  │ Chat Design│ Discount   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### Risk Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| WhatsApp API approval delay | Medium | High | Start approval process in Week 1 |
| Firebase quota limits | Low | Medium | Set up budget alerts, plan upgrade path |
| Complex discount edge cases | High | Medium | Extensive unit testing, gradual rollout |
| Performance issues at scale | Medium | High | Load testing in Week 11, caching strategy |
| External API downtime | Low | Medium | Graceful degradation, retry logic |
| Scope creep | High | Medium | Strict sprint goals, defer to backlog |

---

### Dependencies Checklist

#### External Services Setup (Do in Week 0)

- [ ] **Firebase Project**
  - [ ] Create Firebase project
  - [ ] Enable Cloud Messaging
  - [ ] Download config files
  - [ ] Set up service account

- [ ] **WhatsApp Business API**
  - [ ] Create Meta Business account
  - [ ] Apply for WhatsApp Business API access
  - [ ] Get phone number verified
  - [ ] Submit message templates for approval

- [ ] **Facebook Messenger**
  - [ ] Create Facebook App
  - [ ] Enable Messenger Platform
  - [ ] Create/link Facebook Page
  - [ ] Set up app review (if needed)

- [ ] **Supabase**
  - [ ] Enable Realtime
  - [ ] Set up Edge Functions
  - [ ] Configure webhooks

#### Package Dependencies

```yaml
# pubspec.yaml additions
dependencies:
  intl: ^0.18.0                    # Currency formatting
  firebase_core: ^2.24.0           # Firebase
  firebase_messaging: ^14.7.0      # Push notifications
  image_picker: ^1.0.4             # Media sharing
  geolocator: ^10.1.0              # Location sharing (existing)
  url_launcher: ^6.2.0             # Deep linking
  share_plus: ^7.2.0               # Sharing referral codes
  cached_network_image: ^3.3.0     # Image caching
  flutter_local_notifications: ^16.0.0  # Local notifications
```

---

### Definition of Done

Each sprint must meet these criteria before completion:

1. **Code Quality**
   - [ ] All code reviewed and approved
   - [ ] No linting errors
   - [ ] No compiler warnings
   - [ ] Follows project coding standards

2. **Testing**
   - [ ] Unit tests written and passing
   - [ ] Integration tests passing
   - [ ] Manual QA completed
   - [ ] Edge cases tested

3. **Documentation**
   - [ ] Code documented with comments
   - [ ] API documentation updated
   - [ ] README updated if needed

4. **Deployment**
   - [ ] Merged to development branch
   - [ ] CI/CD pipeline passing
   - [ ] No breaking changes

---

### Post-Launch Roadmap

After initial release, consider these enhancements:

| Phase | Feature | Timeline |
|-------|---------|----------|
| 2.1 | Multi-currency support (USD, EUR) | +4 weeks |
| 2.2 | Voice messages in chat | +2 weeks |
| 2.3 | Video calling integration | +6 weeks |
| 2.4 | AI-powered smart pricing | +4 weeks |
| 2.5 | Advanced analytics dashboard | +3 weeks |
| 2.6 | Subscription/membership plans | +4 weeks |

---

## Appendix

### A. WhatsApp Business API Setup

1. Create Meta Business Account
2. Set up WhatsApp Business API
3. Get phone number verified
4. Create message templates
5. Set up webhook endpoint
6. Configure in `lib/config/whatsapp_config.dart`

### B. Messenger Platform Setup

1. Create Facebook App
2. Set up Messenger Platform
3. Create Facebook Page
4. Link Page to App
5. Set up webhook endpoint
6. Configure in `lib/config/messenger_config.dart`

### C. Firebase FCM Setup

1. Create Firebase project
2. Add Android/iOS apps
3. Download config files
4. Initialize in Flutter
5. Request notification permissions
6. Handle token refresh

### D. Localization Keys

```yaml
# BDT currency
currency_bdt_symbol: "৳"
currency_bdt_name: "Bangladeshi Taka"
price_per_night: "{{price}}/night"
price_per_hour: "{{price}}/hour"
price_range: "{{min}} - {{max}}"

# Notifications
notification_booking_created_title: "New booking request"
notification_booking_confirmed_title: "Booking confirmed!"
notification_new_message_title: "New message from {{name}}"

# Discounts
discount_applied: "{{code}} applied"
discount_saved: "You saved {{amount}}!"
discount_invalid: "Invalid promo code"
discount_expired: "This code has expired"
discount_first_booking: "First booking discount"
```

---

**Document Version:** 2.0
**Last Updated:** 2024
**Authors:** System Architecture Team
**Status:** Design Complete - Ready for Implementation
