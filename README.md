# Musafir

A Flutter rental marketplace application with support for property owners, tenants, and administrators.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Configuration](#configuration)
  - [Supabase Setup](#supabase-setup)
  - [Google Maps Setup](#google-maps-setup)
  - [SMS Provider Setup](#sms-provider-setup)
- [Authentication](#authentication)
  - [OTP Flow](#otp-flow)
  - [Development Mode](#development-mode)
  - [Release Mode](#release-mode)
  - [Master OTP](#master-otp)
- [File Storage](#file-storage)
  - [Storage Buckets](#storage-buckets)
  - [Image Upload Service](#image-upload-service)
  - [Owner Verification](#owner-verification)
- [Database Migrations](#database-migrations)
- [Building & Deployment](#building--deployment)
  - [Android APK](#android-apk)
  - [iOS IPA](#ios-ipa)
  - [Environment Variables](#environment-variables)
- [Architecture](#architecture)
- [Roadmap](#roadmap)

---

## Overview

Musafir is a rental marketplace with three user roles:

| Role | Capabilities |
|------|--------------|
| **Admin** | Manage listings, verify owners, view metrics |
| **Owner** | Create listings, manage bookings, upload property photos |
| **Tenant** | Search properties, book rentals, manage profile |

Key features:
- Mobile OTP authentication (no password required)
- Property listings with multiple images
- Booking flow for hourly, daily, and monthly rentals
- Owner NID verification system
- Real-time notifications

---

## Quick Start

### Prerequisites

- Flutter SDK 3.x+
- Dart 3.x+
- Android Studio / Xcode (for mobile builds)
- Supabase account (free tier available)

### Installation

```bash
# Clone and setup
git clone <your-repo-url>
cd musafir

# Install dependencies
flutter pub get

# Generate platform folders (first time only)
flutter create . --platforms=android,ios,web

# Run in development mode
flutter run

flutter run -d chrome
```

### Verify Setup

```bash
flutter doctor
flutter doctor --android-licenses  # Accept Android licenses
```

---

## Project Structure

```
lib/
├── app.dart                 # App shell and routing
├── config/                  # Configuration files
│   ├── supabase_config.dart
│   ├── otp_config.dart
│   └── sms_config.dart
├── models/                  # Domain models
├── repositories/            # Data layer
│   ├── musafir_repository.dart      # Abstract interface
│   ├── in_memory_repository.dart    # Demo mode
│   └── supabase_repository.dart     # Production mode
├── screens/                 # UI screens by role
│   ├── admin/
│   ├── auth/
│   ├── host/
│   ├── tenant/
│   └── verification/
├── services/                # Business logic
│   ├── auth/
│   ├── sms/
│   ├── otp_service.dart
│   └── image_upload_service.dart
├── state/                   # State management
└── widgets/                 # Reusable components
```

---

## Configuration

### Supabase Setup

The app supports both in-memory (demo) and Supabase (production) modes.

#### Option 1: Cloud (Recommended)

1. Create account at [supabase.com](https://supabase.com) (free tier available)
2. Create new project
3. Run migrations in SQL Editor (see [Database Migrations](#database-migrations))
4. Copy credentials from **Settings > API**
5. Update `lib/config/supabase_config.dart`:

```dart
static const String url = 'https://your-project.supabase.co';
static const String anonKey = 'your-anon-key';
```

#### Option 2: Local Development (Docker)

```bash
npm install -g supabase
supabase init
supabase start
```

Local endpoints:
- API: `http://localhost:54321`
- Studio: `http://localhost:54323`

#### Supabase CLI (npx)

Login and link your project using npx:

```bash
# Login to Supabase (opens browser for authentication)
npx supabase login

# Link to your project
npx supabase link --project-ref bojkmonskqlhuakxhzcb

# Useful commands after linking
npx supabase db pull      # Pull remote schema
npx supabase db push      # Push local migrations
npx supabase status       # Check project status
```

#### Option 3: Self-Hosted

See [Supabase Self-Hosting Guide](https://supabase.com/docs/guides/self-hosting).

### Google Maps Setup

#### Android

Add to `android/local.properties` (gitignored):

```properties
GOOGLE_MAPS_API_KEY=YOUR_ANDROID_KEY
```

#### iOS

```bash
cp ios/Flutter/Maps.local.xcconfig.example ios/Flutter/Maps.local.xcconfig
```

Edit with your iOS key:

```xcconfig
GOOGLE_MAPS_API_KEY=YOUR_IOS_KEY
```

> **Note:** Use separate restricted API keys for Android and iOS. Enable Maps SDK in Google Cloud Console.

### SMS Provider Setup

Configure in `lib/config/sms_config.dart`:

```dart
static const SmsProvider activeProvider = SmsProvider.bulkSmsBd;
static const String bulkSmsBdApiKey = 'YOUR_API_KEY';
static const String bulkSmsBdSenderId = 'YOUR_SENDER_ID';
```

Supported providers:
| Provider | Use Case |
|----------|----------|
| `console` | Development (prints to terminal) |
| `bulkSmsBd` | Production (Bangladesh) |
| `alphaSms` | Production (Bangladesh) |
| `zamanIt` | Production (Bangladesh) |

---

## Authentication

### OTP Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ Enter Phone │ ──> │ Receive OTP │ ──> │  Verified   │
└─────────────┘     └─────────────┘     └─────────────┘
                          │
                    SMS or Console
                    (based on mode)
```

### Development Mode

When running `flutter run` (debug build):

| Feature | Behavior |
|---------|----------|
| OTP delivery | Printed to console |
| OTP storage | Plaintext in database |
| SMS provider | Console (no real SMS) |

**How to get OTP in development:**

1. **Console output** - Look for the OTP box in your terminal:
   ```
   ╔════════════════════════════════════════╗
   ║  [DEV MODE] OTP for 01712345678: 5821
   ╚════════════════════════════════════════╝
   ```

2. **Database query** - OTPs are stored as plaintext in debug mode:
   ```sql
   SELECT otp_hash, phone, expires_at
   FROM otp_attempts
   WHERE phone = '01712345678'
   ORDER BY created_at DESC
   LIMIT 1;
   ```

### Release Mode

When building with `flutter build apk --release`:

| Feature | Behavior |
|---------|----------|
| OTP delivery | Real SMS provider |
| OTP storage | SHA-256 hashed |
| Console output | Disabled |

### Master OTP

For testing release builds without a real SMS provider:

```bash
flutter build apk --release \
  --dart-define=MASTER_OTP_ENABLED=true \
  --dart-define=MASTER_OTP=1234
```

```bash
flutter build apk --release \
    --dart-define=MASTER_OTP_ENABLED=true \
    --dart-define=MASTER_OTP=1234 \
    --dart-define=GOOGLE_MAPS_API_KEY=YOUR_API_KEY_HERE
    
flutter build apk --release \
    --dart-define=MASTER_OTP_ENABLED=true \
    --dart-define=MASTER_OTP=1234 \
    --dart-define=GOOGLE_MAPS_API_KEY=AIzaSyBw1uyOoZ2tS8-NS_83ov8rE3OusmmDWRM \
    --build-name=1.0.1 \
    --build-number=1 \
  && mv build/app/outputs/flutter-apk/app-release.apk \
        build/app/outputs/flutter-apk/app-release-v1.0.4.apk

    
npx supabase secrets set FCM_SERVER_KEY=AAAAvY_mLR8:APA91bEd_LXkSiW1QmBhDNPwYvwm7-lLXmSu7Q7N40_qrRr6YcTKYZzikat-Mh7THwob8xSeW88LlFm8MhnCuIxsSfprzqyMgCK6yB3OrTJ8i5UWyQz5mFitn_J2HwF68pBsdEAZ2HMO

```


Testers can use `1234` as OTP for any phone number.

> **Security Warning:** Never enable master OTP in production builds distributed to end users.

### OTP Configuration

Settings in `lib/config/otp_config.dart`:

| Setting | Default | Description |
|---------|---------|-------------|
| `otpLength` | 4 | Number of digits |
| `validityMinutes` | 5 | Expiration time |
| `maxAttempts` | 3 | Failed attempts before lockout |
| `resendCooldownSeconds` | 60 | Wait time between requests |

---

## File Storage

### Storage Buckets

Three Supabase Storage buckets with different access levels:

| Bucket | Purpose | Access | Max Size | Formats |
|--------|---------|--------|----------|---------|
| `listing-images` | Property photos | Public | 5 MB | JPEG, PNG, WebP |
| `avatars` | Profile photos | Public | 2 MB | JPEG, PNG |
| `documents` | NID verification | Private | 10 MB | JPEG, PNG, PDF |

Run migration `010_storage_buckets.sql` to create buckets and policies.

### Image Upload Service

Core service: `lib/services/image_upload_service.dart`

```dart
final service = ImageUploadService.instance;

// Listing images (up to 10)
final images = await service.pickMultipleImages(limit: 10);
final results = await service.uploadListingImages(
  images: images,
  listingId: 'listing_123',
);

// User avatar
final image = await service.pickImageFromGallery();
final result = await service.uploadAvatar(
  image: image!,
  userId: 'user_123',
);

// NID document
final file = await service.pickDocument();
final result = await service.uploadNidFront(
  file: file!,
  userId: 'user_123',
);
```

Features:
- Client-side compression (1920px max, 85% quality)
- Automatic MIME type detection
- Upsert mode (overwrites existing)
- Public URL generation

### Owner Verification

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Upload NID   │ ──> │ Admin Review │ ──> │  Verified    │
│ Front + Back │     │   Pending    │     │ Can List     │
└──────────────┘     └──────────────┘     └──────────────┘
                            │
                            v
                     ┌──────────────┐
                     │  Rejected    │
                     │ Re-upload    │
                     └──────────────┘
```

Verification statuses:
| Status | Description |
|--------|-------------|
| `none` | No documents uploaded |
| `pending` | Documents uploaded, awaiting review |
| `verified` | Approved, can create listings |
| `rejected` | Declined, can re-upload |

---

## Database Migrations

Run these migrations in order via Supabase SQL Editor or CLI:

| # | File | Purpose |
|---|------|---------|
| 001 | `001_initial_schema.sql` | Core tables (profiles, listings, bookings) |
| 002 | `002_notifications.sql` | Notification system |
| 003 | `003_messaging.sql` | Chat/messaging |
| 004 | `004_discounts.sql` | Discount codes |
| 005 | `005_loyalty_tier_upgrade.sql` | Loyalty program |
| 006 | `006_fix_booking_notification_trigger.sql` | Trigger fix |
| 007 | `007_extend_profiles_for_auth.sql` | Auth fields |
| 008 | `008_fix_profiles_insert_policy.sql` | RLS policy fix |
| 009 | `009_otp_attempts.sql` | OTP tracking table |
| 010 | `010_storage_buckets.sql` | Storage buckets + policies |
| 011 | `011_image_uploads_schema.sql` | Image/document schema |

**Using Supabase CLI:**

```bash
supabase db push
```

**Using SQL Editor:**

Copy and paste each migration file content into Supabase Dashboard > SQL Editor.

---

## Building & Deployment

### Android APK

```bash
# Debug (development, OTP in console)
flutter build apk --debug

# Release with master OTP (testing)
flutter build apk --release \
  --dart-define=MASTER_OTP_ENABLED=true \
  --dart-define=MASTER_OTP=1234

# Release for production (requires SMS provider)
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

**Install on device:**

```bash
flutter install              # Via USB
adb install app-release.apk  # Via ADB
```

### iOS IPA

Requires macOS with Xcode.

```bash
flutter build ipa
```

Output: `build/ios/ipa/musafir.ipa`

Requirements:
- Apple Developer account ($99/year)
- Signing certificate and provisioning profile
- Configure in `ios/Runner.xcworkspace`

### Environment Variables

Build-time configuration via `--dart-define`:

| Variable | Default | Description |
|----------|---------|-------------|
| `MASTER_OTP_ENABLED` | `false` | Enable master OTP bypass |
| `MASTER_OTP` | _(empty)_ | Master OTP code |
| `OTP_PERSIST_TO_DB` | `true` | Store OTPs in database |

Example:

```bash
flutter build apk --release \
  --dart-define=MASTER_OTP_ENABLED=true \
  --dart-define=MASTER_OTP=1234
```

---

## Architecture

### Repository Pattern

```
┌─────────────┐
│    UI       │
└──────┬──────┘
       │
┌──────▼──────┐
│  Repository │  ◄── Abstract interface
│  (Interface)│
└──────┬──────┘
       │
   ┌───┴───┐
   │       │
┌──▼──┐ ┌──▼──────┐
│Mock │ │Supabase │
└─────┘ └─────────┘
```

The app automatically switches between:
- **InMemoryMusafirRepository** - Demo mode with mock data
- **SupabaseMusafirRepository** - Production mode

Based on `SupabaseConfig.isConfigured`.

### Why PostgreSQL?

- Relational data (bookings, users, listings)
- Time-range conflict checks in SQL
- Geospatial queries with PostGIS
- ACID compliance for financial data

---

## Roadmap

- [x] Mobile OTP authentication
- [x] Image upload for listings and avatars
- [x] Owner NID verification system
- [ ] Replace in-memory repository with full Supabase integration
- [ ] Google Places Autocomplete for address search
- [ ] Booking conflict validation
- [ ] Admin approval workflow for new listings
- [ ] Real SMS provider integration
- [ ] Scheduled OTP cleanup via Edge Function
- [ ] Push notifications

---

## Demo Credentials

For testing with mock data:

- **Email:** demo@musafir.com
- **Password:** password123

---

## License

Private project. All rights reserved.
