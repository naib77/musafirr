# Musafir

Musafir is a Flutter starter app for a rental marketplace with three user roles:

- Admin
- House owner
- Tenant

The current version uses an in-memory repository so the UI and flows work without backend setup. The app includes:

- Owner property registration with mobile number, coordinates, rental type, facilities, and pricing
- Tenant area search based on latitude/longitude and a lightweight map-style preview
- Booking flow for hourly, daily, and monthly rental periods
- Admin dashboard with listing and booking metrics

## Project structure

The codebase is now split so backend integration is straightforward:

- `lib/app.dart`: app shell and role switching
- `lib/models/`: domain models and enums
- `lib/repositories/`: repository contract, in-memory implementation, and Supabase placeholder
- `lib/screens/`: admin, owner, and tenant screens
- `lib/widgets/`: reusable UI building blocks
- `lib/data/`: shared app data such as facility definitions

## Online-first workflow

You can build this project mostly online with:

- GitHub for source control
- a browser Flutter IDE such as Project IDX
- Codemagic for Android and iOS cloud builds

Recommended flow:

1. Push this folder to a new GitHub repository named `musafir`.
2. Open the repo in your online Flutter IDE.
3. Run `flutter create . --platforms=android,ios` once to generate native wrappers.
4. Commit the generated `android` and `ios` folders.
5. Connect the repo to Codemagic and use the included `codemagic.yaml`.
6. Trigger Android and iOS builds from Codemagic.

## Why in-memory first

This keeps the first version simple and reduces setup risk on Android and iPhone. The code is structured so the repository can later be replaced by a real API-backed implementation.

## Database recommendation

Use `PostgreSQL` when you move past the in-memory phase.

Why PostgreSQL is the better fit than MongoDB here:

- booking, availability, owner, and tenant data are strongly relational
- time-range conflict checks are safer in SQL
- geospatial search is strong with `PostGIS`
- pricing, filtering, and reporting are easier to keep consistent

MongoDB can work, but this product has booking rules and search patterns that fit PostgreSQL better.

## Project status

This workspace does not have the Flutter SDK installed, so the native Android and iOS wrapper projects could not be generated here.

After installing Flutter, run these commands inside `musafir`:

```bash
flutter create . --platforms=android,ios
flutter pub get
flutter run
```

That will generate the standard Android and iOS project folders around the existing Dart app code.

## Online setup checklist

### 1. Create the native platform folders

Run:

```bash
flutter clean
flutter create . --platforms=android,ios
flutter pub get
flutter run -d chrome
```

### 2. Push to GitHub

Example:

```bash
git init
git add .
git commit -m "Initial Musafir scaffold"
git branch -M main
git remote add origin <your-github-repo-url>
git push -u origin main
```

### 3. Connect Codemagic

- Open Codemagic
- connect your GitHub repository
- choose `codemagic.yaml`
- start with the `analyze_and_test` workflow
- then run `android_debug`
- run `ios_debug` after Apple signing is ready

### 4. iPhone build requirements

For real iPhone builds, you still need:

- Apple Developer account
- bundle identifier
- provisioning profile
- signing certificate

### 5. Supabase backend

The app supports both in-memory (demo) and Supabase (production) modes. See the Supabase setup section below.

## Supabase setup

Supabase is a Backend-as-a-Service that provides PostgreSQL + Authentication + REST API + Realtime subscriptions. The app automatically uses in-memory mode if Supabase is not configured.

### Option 1: Supabase Cloud (Easiest)

Free tier at [supabase.com](https://supabase.com):

1. Create account and new project
2. Go to SQL Editor and run the schema from `docs/supabase_schema.sql`
3. Copy your **URL** and **anon key** from Settings → API
4. Update `lib/config/supabase_config.dart`:

```dart
static const String url = 'https://your-project.supabase.co';
static const String anonKey = 'your-anon-key';
```

5. Run the app - it will use Supabase automatically

**Free tier includes:** 500MB database, 1GB storage, 50k monthly active users

### Option 2: Local Development (Docker)

Requires Docker Desktop installed.

```bash
# Install Supabase CLI
npm install -g supabase

# Initialize in your project
supabase init

# Start local Supabase (PostgreSQL + Auth + API + Studio)
supabase start
```

This gives you:

- API URL: `http://localhost:54321`
- anon key: shown in terminal output
- Studio (web dashboard): `http://localhost:54323`

Update `lib/config/supabase_config.dart`:

```dart
static const String url = 'http://localhost:54321';
static const String anonKey = 'eyJhbG...';  // from terminal output
```

To stop: `supabase stop`

### Option 3: Self-Hosted Server

For production on your own server (VPS, AWS, DigitalOcean, etc.):

```bash
# Clone Supabase Docker setup
git clone https://github.com/supabase/supabase
cd supabase/docker

# Copy and edit environment variables
cp .env.example .env
# Edit .env with your secrets and domain

# Start all services
docker compose up -d
```

This runs PostgreSQL, Auth, REST API, Realtime, and Studio on your server.

### Which option to use?

| Stage | Recommendation |
|-------|----------------|
| Getting started | Cloud free tier (no setup) |
| Local development | Docker or Cloud free tier |
| Production | Cloud paid tier or Self-hosted |

## Backend architecture

The repository layer is separated from the UI:

- `MusafirRepository` - abstract interface
- `InMemoryMusafirRepository` - demo mode with mock data
- `SupabaseMusafirRepository` - production mode with real database

The app automatically switches based on whether Supabase credentials are configured in `lib/config/supabase_config.dart`.

Backend documentation:

- [docs/backend_schema.md](./docs/backend_schema.md) - database design
- [docs/supabase_schema.sql](./docs/supabase_schema.sql) - SQL to create tables

## Google Maps setup

The app now uses `google_maps_flutter` for:

- tenant area browsing
- owner listing location picking
- host listing location picking

To make map rendering work on device, add platform API keys locally.

### Android

`android/app/build.gradle.kts` reads `GOOGLE_MAPS_API_KEY` from `local.properties`, which is already gitignored.

Add this line to `android/local.properties`:

```properties
GOOGLE_MAPS_API_KEY=YOUR_ANDROID_GOOGLE_MAPS_API_KEY
```

### iOS

Copy the example file and add your iOS key:

```bash
cp ios/Flutter/Maps.local.xcconfig.example ios/Flutter/Maps.local.xcconfig
```

Then set:

```xcconfig
GOOGLE_MAPS_API_KEY=YOUR_IOS_GOOGLE_MAPS_API_KEY
```

`ios/Flutter/Maps.local.xcconfig` is gitignored.

### Notes

- Android and iOS should use separate restricted API keys.
- Enable the Maps SDK for Android and Maps SDK for iOS in Google Cloud.
- The place search field still uses the `geocoding` package, not Google Places Autocomplete.

## Suggested next steps

1. Add authentication by mobile OTP for house owners and tenants.
2. Replace the in-memory repository with a REST API.
3. Replace the basic address search with Google Places Autocomplete.
4. Add booking conflict checks against exact start/end times.
5. Add admin approval for new owner listings.


Demo Credentials

- Email: demo@musafir.com
- Password: password123
