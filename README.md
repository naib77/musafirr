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

supabase secrets set MASTER_OTP='1234' MASTER_OTP_PHONES='01673293543'

npx supabase secrets set MASTER_OTP='1234' MASTER_OTP_PHONES='1673293542' --project-ref bojkmonskqlhuakxhzcb



flutter build apk --release \
  --dart-define=MASTER_OTP_ENABLED=true \
  --dart-define=MASTER_OTP=1234

  flutter build apk --release \
    --dart-define=MASTER_OTP_ENABLED=true \
    --dart-define=MASTER_OTP=1234 \
    --dart-define=GOOGLE_MAPS_API_KEY=AIzaSyBw1uyOoZ2tS8-NS_83ov8rE3OusmmDWRM \
    --build-name=1.0.1 \
    --build-number=1 \
  && mv build/app/outputs/flutter-apk/app-release.apk \
        build/app/outputs/flutter-apk/app-release-v1.0.6.apk
```

```bash
# ── TESTER build — master OTP 1234 enabled. QA ONLY. Never give to real users. ──
flutter build apk --release --split-per-abi \
    --dart-define=MASTER_OTP_ENABLED=true \
    --dart-define=MASTER_OTP=1234 \
    --dart-define=GOOGLE_MAPS_API_KEY=AIzaSyBw1uyOoZ2tS8-NS_83ov8rE3OusmmDWRM \
    --build-name=1.0.1 --build-number=1
```

```bash
# ── PRODUCTION build — NO master OTP. This is what real users get. ──
# No GenNet token needed here: OTP SMS goes through the `send-otp` Edge
# Function, which holds the token server-side (see "SMS provider" below).
flutter build apk --release --split-per-abi \
    --dart-define=GOOGLE_MAPS_API_KEY=AIzaSyBw1uyOoZ2tS8-NS_83ov8rE3OusmmDWRM \
    --build-name=1.0.1 --build-number=1
```

### Phone auth & SMS (server-side)

Phone OTP is **fully server-side** via two Supabase Edge Functions — the client
never generates, sees, or verifies the code, and no SMS credential is compiled
into the APK:

- **`send-otp`** — generates + hashes the OTP, stores it in `otp_attempts`,
  rate-limits per phone, and sends the SMS via GenNet's v3 API
  (`https://isms.gennet.com.bd/api/v3/send-sms`) using the server-held token.
- **`verify-otp`** — checks the stored hash, ensures the auth user exists
  (rotating its password to a random value), and returns a single-use
  magic-link `token_hash` that the client exchanges for a real session via
  `auth.verifyOTP`. This replaced the old deterministic phone→password sign-in
  (an account-takeover bypass); see migration `067`.

Deploy both and set the secrets **once** (server-side, never in git):

```bash
supabase functions deploy send-otp
supabase functions deploy verify-otp
supabase secrets set \
  GENNET_API_TOKEN='<your-gennet-api-token>' \
  GENNET_SID='IOBYTESNONMASK'
# optional:
#   GENNET_BASE_URL='https://isms.gennet.com.bd/api/v3/send-sms'
#   OTP_MAX_PER_HOUR='5'                     # per-phone rate limit (0 disables)
```

**Test logins (master OTP).** Set both secrets to let numbers log in with a
fixed code and no SMS; leave them unset in production → no bypass exists at all.
This is decided purely from server config — no APK rebuild needed, and it takes
effect the moment the secrets change.

```bash
# Only these numbers accept the master code; everyone else needs a real OTP.
supabase secrets set MASTER_OTP='1234' MASTER_OTP_PHONES='01673293542,01XXXXXXXXX'

# ALL phone numbers accept the master code (full test/demo build — no real SMS
# is sent to anyone). Use the "*" wildcard for MASTER_OTP_PHONES.
supabase secrets set MASTER_OTP='1234' MASTER_OTP_PHONES='*'

# Turn it fully off (production): remove both secrets.
supabase secrets unset MASTER_OTP MASTER_OTP_PHONES
```

> ⚠️ `MASTER_OTP_PHONES='*'` means **anyone** can log into **any** number with
> the master code. Only use it for a throwaway test/demo deployment, never for a
> build handed to real users.

Local `flutter run` (debug) hits the same live functions, so add your dev number
to `MASTER_OTP_PHONES` to log in without real SMS. (The client `SmsProvider`
gateway in [lib/config/sms_config.dart](lib/config/sms_config.dart) is now only
a fallback for the no-Supabase / mock mode.)

`--split-per-abi` produces one APK per CPU (~22 MB each) instead of one fat
62 MB APK, in `build/app/outputs/flutter-apk/`:

| File | Distribute? |
|------|-------------|
| `app-arm64-v8a-release.apk`   | ✅ **Yes — ~all modern phones** |
| `app-armeabi-v7a-release.apk` | Only for old 32-bit devices |
| `app-x86_64-release.apk`      | Emulators only — ignore |

Hand out the **arm64-v8a** file. Rename it for a release, e.g.:

```bash
mv build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
   build/app/outputs/flutter-apk/musafir-v1.0.6-arm64.apk
```

Push notifications (Supabase Edge Function secret — run once, not part of the build):

```bash
npx supabase secrets set FCM_SERVER_KEY=<your-fcm-server-key>
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

#### ⭐ Build my APK — step by step (production, for real users)

This is the current, recommended way to build the APK you hand out to users.
OTP SMS goes through the `send-otp` Edge Function (token held server-side), so
**no GenNet token is compiled into the APK** and master OTP stays off.

```bash
cd /Users/naib/workspaces/personal/projects/musafirr

# 1. Get dependencies (safe to run every time)
flutter pub get

# 2. Build one APK per CPU architecture (smaller downloads)
#    Bump --build-name / --build-number for each release.
flutter build apk --release --split-per-abi \
    --dart-define=GOOGLE_MAPS_API_KEY=AIzaSyBw1uyOoZ2tS8-NS_83ov8rE3OusmmDWRM \
    --build-name=1.0.6 --build-number=6

# 3. Grab the arm64 APK (works on ~all modern phones) and rename it
mv build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
   build/app/outputs/flutter-apk/musafir-v1.0.6-arm64.apk
```

Result: `build/app/outputs/flutter-apk/musafir-v1.0.6-arm64.apk` — this is the
file you send to users / upload.

**Which file to hand out** (from `--split-per-abi`):

| File | Distribute? |
|------|-------------|
| `app-arm64-v8a-release.apk`   | ✅ **Yes — ~all modern phones** |
| `app-armeabi-v7a-release.apk` | Only for old 32-bit devices |
| `app-x86_64-release.apk`      | Emulators only — ignore |

**Prerequisites, once per machine / once per release:**
- Edge Functions deployed and secrets set (only if not already done — see
  [Phone auth & SMS (server-side)](#phone-auth--sms-server-side)):
  ```bash
  supabase functions deploy send-otp
  supabase functions deploy verify-otp
  supabase secrets set GENNET_API_TOKEN='<your-gennet-api-token>' GENNET_SID='IOBYTESNONMASK'
  ```
- Make sure `MASTER_OTP` is **unset** on the server for a true production build
  (`supabase secrets unset MASTER_OTP MASTER_OTP_PHONES`), otherwise the listed
  numbers can still log in with the fixed code.

> ⚠️ **Existing users must reinstall.** The move to server-side OTP rotated every
> phone user's password, so APKs built before that change can no longer log those
> users in. Distribute a freshly-built APK and have users update.

**Install the built APK on a connected device:**

```bash
adb install -r build/app/outputs/flutter-apk/musafir-v1.0.6-arm64.apk
# or, to build + install the debug build in one step over USB:
flutter install
```

---

#### 🏪 Publish to the Google Play Store — step by step

The APK section above is for **direct/sideload** distribution. The Play Store
needs a **signed App Bundle (`.aab`)**, not an APK. Do these once, then repeat
steps 6–9 for every release.

**One-time setup**

1. **Create a Play Console account** — https://play.google.com/console (one-time
   US$25 fee). Create the app: name "Musafir", default language, app (not game),
   free/paid.

2. **Generate your upload keystore** (do this once, keep it forever — losing it
   means you can't ship updates):
   ```bash
   keytool -genkey -v -keystore ~/musafir-upload.jks \
       -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
   Store `~/musafir-upload.jks` and its passwords somewhere safe (password
   manager + a backup). **Never commit it.**

3. **Create `android/key.properties`** (already git-ignored — see
   `android/.gitignore`):
   ```properties
   storePassword=<password from step 2>
   keyPassword=<password from step 2>
   keyAlias=upload
   storeFile=/Users/naib/musafir-upload.jks
   ```
   The Gradle config ([android/app/build.gradle.kts](android/app/build.gradle.kts))
   reads this automatically; with it present, release builds are signed with your
   upload key.

4. **Add a real app icon** (the project still uses the default Flutter icon). Add
   `flutter_launcher_icons` to `pubspec.yaml`, point it at a 1024×1024 PNG, then
   `dart run flutter_launcher_icons`. Play requires a proper icon.

5. **Prepare store listing assets** (in Play Console → Grow → Store presence):
   - App icon 512×512, feature graphic 1024×500
   - At least 2 phone screenshots
   - Short + full description
   - **Privacy policy URL** (required — the app uses location, camera, and photo
     access). Host a simple policy page and paste the URL.
   - **Data safety form** — declare: location (fine/coarse), camera, photos/media,
     and that data is sent to your Supabase backend.
   - Content rating questionnaire + target audience.

**Every release**

6. **Server prerequisites** (same as the APK build — deploy functions, set
   secrets, and make sure `MASTER_OTP` is **unset** for production). See
   [Phone auth & SMS (server-side)](#phone-auth--sms-server-side).

7. **Bump the version** in `pubspec.yaml` (`version: 1.0.6+6`) — the build number
   after `+` **must increase on every upload** or Play rejects it. (You can also
   pass `--build-name`/`--build-number` on the command line instead.)

8. **Build the signed App Bundle:**
   ```bash
   cd /Users/naib/workspaces/personal/projects/musafirr
   flutter pub get
   flutter build appbundle --release \
       --dart-define=GOOGLE_MAPS_API_KEY=AIzaSyBw1uyOoZ2tS8-NS_83ov8rE3OusmmDWRM
   ```
   Output: `build/app/outputs/bundle/release/app-release.aab`

   Verify it is **not** debug-signed (the SHA should not be the Android debug key):
   ```bash
   # key.properties must exist, or this bundle is unshippable
   test -f android/key.properties && echo "signed with upload key ✓" || echo "MISSING key.properties — do NOT upload"
   ```

9. **Upload to Play Console** → Release → pick a track (start with **Internal
   testing** → then **Production**) → **Create new release** → upload the `.aab`.
   - First upload: accept **Play App Signing** (Google manages the app signing key;
     your keystore stays the *upload* key). This is the default and recommended.
   - Add release notes → Review → **Start rollout**.

> ⚠️ **Google Maps API key:** once Play App Signing is on, add the **app-signing
> SHA-1** (Play Console → Setup → App integrity) to your Maps API key restrictions
> in Google Cloud Console, or the map will render blank in the store build.

> ⚠️ **Existing sideloaded users:** the Play build is signed with a different key
> than any APK you handed out directly, so users must uninstall the sideloaded app
> before installing the Play version (Android blocks same-package different-signer
> updates).

---

#### Other build variants

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
| `GENNET_API_TOKEN` | _(empty)_ | GenNet iSMS API token (empty → console fallback, no SMS) |
| `GENNET_SID` | _(empty)_ | GenNet brand/masking SID, e.g. `IOBYTESNONMASK` |
| `GENNET_BASE_URL` | `https://isms.gennet.com.bd/api/v3/send-sms` | GenNet send-SMS endpoint |

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
