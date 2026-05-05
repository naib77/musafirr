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
flutter create . --platforms=android,ios
flutter pub get
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

### 5. Future backend

When you replace in-memory data, use:

- Flutter frontend
- PostgreSQL database
- PostGIS for area/map queries
- a REST API or GraphQL API

Supabase is a strong online-first option because it combines PostgreSQL, auth, and hosted APIs.

## Backend-ready direction

The repository layer is already separated from the UI:

- `MusafirRepository` defines the contract
- `InMemoryMusafirRepository` powers the current app
- `SupabaseMusafirRepository` is a placeholder for the real implementation

When you move to Supabase/PostgreSQL, the next technical steps are:

1. Add `supabase_flutter` to `pubspec.yaml`.
2. Create tables for `users`, `listings`, `facilities`, and `bookings`.
3. Store listing coordinates with PostGIS-compatible fields.
4. Add booking conflict checks in SQL or RPC functions.
5. Swap the injected repository from in-memory to Supabase.

The initial backend artifacts are included here:

- [backend_schema.md](./docs/backend_schema.md)
- [001_initial_schema.sql](./supabase/migrations/001_initial_schema.sql)

## Suggested next steps

1. Add authentication by mobile OTP for house owners and tenants.
2. Replace the in-memory repository with a REST API.
3. Add real map support with Google Maps or Mapbox.
4. Add booking conflict checks against exact start/end times.
5. Add admin approval for new owner listings.
