# Musafir Architecture

## Overview

Musafir is a Flutter application for a rental marketplace with tenant, host, owner, and admin-facing flows. The current implementation is a client-side demo application with:

- a `MaterialApp` entry point
- in-memory domain state and repository storage
- local `ChangeNotifier`-based state management
- role-aware UI flows for authentication, browsing, booking, and hosting
- Google Maps rendering for map selection and area browsing
- a placeholder repository contract for future Supabase/PostgreSQL migration

The codebase currently contains two UI generations:

- a newer marketplace shell centered around `Explore`, `Wishlists`, `Trips`, `Inbox`, and `Profile`
- older role-specific dashboards for `Tenant`, `Owner`, and `Admin`

Both are part of the current codebase and should be treated as active architectural context.

## Entry Point And App Composition

Application startup is minimal:

- [lib/main.dart](/abs/path/C:/naib/projects/personal/musafir/lib/main.dart:1) calls `runApp(const MusafirApp())`
- [lib/app.dart](/abs/path/C:/naib/projects/personal/musafir/lib/app.dart:1) creates the app-level objects and decides whether to show auth screens or the main logged-in shell

`MusafirApp` owns these long-lived runtime objects:

- `InMemoryMusafirRepository`
- `AuthStateNotifier`
- `FavoritesStateNotifier`
- `SearchStateNotifier`

The repository is the central data source. `MusafirApp` listens to repository changes and refreshes `SearchStateNotifier` with the latest listings so search results stay in sync with add/update/delete operations.

## High-Level Layering

The current architecture is intentionally simple and mostly feature-oriented:

- `lib/models/`
  Domain entities and enums
- `lib/data/`
  Static catalogs and seeded mock content
- `lib/repositories/`
  Data access contract plus in-memory and future backend implementations
- `lib/state/`
  UI-facing state containers using `ChangeNotifier`
- `lib/services/`
  Device or platform services such as location and geocoding
- `lib/widgets/`
  Reusable UI building blocks and map widgets
- `lib/screens/`
  Top-level feature screens and navigation entry points

There is no dependency injection framework. Dependencies are passed through constructors from the app root downward.

## Runtime Navigation Model

### Unauthenticated flow

Before login, `MusafirApp` shows `AuthNavigator` from [lib/app.dart](/abs/path/C:/naib/projects/personal/musafir/lib/app.dart:55). `AuthNavigator` toggles between:

- [lib/screens/auth/login_screen.dart](/abs/path/C:/naib/projects/personal/musafir/lib/screens/auth/login_screen.dart:1)
- [lib/screens/auth/signup_screen.dart](/abs/path/C:/naib/projects/personal/musafir/lib/screens/auth/signup_screen.dart:1)

Authentication is local-only and driven by `AuthStateNotifier`.

### Authenticated flow

After login, [lib/screens/main_shell.dart](/abs/path/C:/naib/projects/personal/musafir/lib/screens/main_shell.dart:1) becomes the root shell. It uses:

- a `Scaffold`
- an `IndexedStack`
- a bottom `NavigationBar`

The shell hosts five primary tabs:

1. `ExploreScreen`
2. `WishlistsScreen`
3. `TripsScreen`
4. `InboxScreen`
5. `ProfileScreen`

Navigation to deeper flows is done with `Navigator.push` and `MaterialPageRoute`.

## Domain Model

The main business entities are:

- [Listing](/abs/path/C:/naib/projects/personal/musafir/lib/models/listing.dart:1)
- [Booking](/abs/path/C:/naib/projects/personal/musafir/lib/models/booking.dart:1)
- [User](/abs/path/C:/naib/projects/personal/musafir/lib/models/user.dart:1)
- [Review](/abs/path/C:/naib/projects/personal/musafir/lib/models/review.dart:1)
- [SearchFilters](/abs/path/C:/naib/projects/personal/musafir/lib/models/search_filters.dart:1)
- [OwnerRegistrationDraft](/abs/path/C:/naib/projects/personal/musafir/lib/models/owner_registration_draft.dart:1)

Supporting enums and value objects include:

- `UserRole`
- `ListingType`
- `BookingStatus`
- `BookingDuration`
- `Facility`

### Listing

`Listing` is the most central entity. It mixes older rental fields and newer marketplace fields:

- identity, title, address, coordinates
- listing type and facilities
- hourly, daily, and monthly rates
- marketplace metadata such as images, host, guests, and reviews
- mutable `available` state

The model also exposes convenience properties such as:

- `displayPrice`
- `amenityNames`
- `primaryImage`

### Booking

`Booking` supports both:

- legacy duration-based bookings using `startAt`, `endAt`, and `unitLabel`
- marketplace-style date-range bookings using optional `checkIn` and `checkOut`

This is why `Booking` exposes normalized computed properties:

- `effectiveCheckIn`
- `effectiveCheckOut`
- `numberOfNights`
- `isUpcoming`
- `isPast`
- `isOngoing`

### User

`User` holds both account identity and host-related profile data. The current implementation supports tenant, owner, and admin roles, plus a separate `isHost` flag used by the marketplace hosting UX.

## Data Layer

### Repository contract

[lib/repositories/musafir_repository.dart](/abs/path/C:/naib/projects/personal/musafir/lib/repositories/musafir_repository.dart:1) defines the data boundary for:

- listings
- bookings
- users
- reviews
- availability checks
- area search
- host listing management

This contract is broader than the currently used UI surface, which is useful for backend migration but means some methods exist before all screens rely on them.

### In-memory repository

[lib/repositories/in_memory_musafir_repository.dart](/abs/path/C:/naib/projects/personal/musafir/lib/repositories/in_memory_musafir_repository.dart:1) is the current source of truth.

It stores:

- `_listings`
- `_bookings`
- `_reviews`
- `_users`

Key responsibilities:

- seed mock data from [lib/data/mock_data.dart](/abs/path/C:/naib/projects/personal/musafir/lib/data/mock_data.dart:1)
- register owner listings
- create legacy tenant bookings
- create marketplace bookings
- update, delete, and search listings
- aggregate reviews into listing ratings
- compute booking conflicts and time slot availability
- notify listeners after mutations

This repository extends `ChangeNotifier`, so the UI can rebuild directly from repository events.

### Supabase repository placeholder

[lib/repositories/supabase_musafir_repository.dart](/abs/path/C:/naib/projects/personal/musafir/lib/repositories/supabase_musafir_repository.dart:1) is intentionally unimplemented. It documents the intended backend responsibilities but currently throws `UnimplementedError` everywhere.

Architecturally, this means:

- the app has a repository abstraction
- the app does not yet have backend integration
- backend migration should replace constructor wiring in `MusafirApp`

## State Management

State management is based on plain `ChangeNotifier` objects instead of Provider, Riverpod, Bloc, or Redux.

### AuthStateNotifier

[lib/state/auth_state.dart](/abs/path/C:/naib/projects/personal/musafir/lib/state/auth_state.dart:1) owns:

- current logged-in user
- auth loading state
- auth errors
- mock login and signup behavior
- host upgrade flow via `becomeHost`

This state object acts like a lightweight local auth/session layer and also contains a separate in-memory user map for auth purposes.

### FavoritesStateNotifier

[lib/state/favorites_state.dart](/abs/path/C:/naib/projects/personal/musafir/lib/state/favorites_state.dart:1) stores favorite listing IDs only. It is a pure UI/session state object with no persistence.

### SearchStateNotifier

[lib/state/search_state.dart](/abs/path/C:/naib/projects/personal/musafir/lib/state/search_state.dart:1) owns:

- current `SearchFilters`
- `_allListings`
- filtered search `_results`
- transient searching/error flags

Filtering logic currently runs in memory over the listing list provided by `MusafirApp`.

### HostStateNotifier

[lib/state/host_state.dart](/abs/path/C:/naib/projects/personal/musafir/lib/state/host_state.dart:1) exists as a local host flow state container, but it is not the primary driver of the current host dashboard UX. The newer host flows mostly derive their state directly from `AuthStateNotifier` and `InMemoryMusafirRepository`.

## Service Layer

### LocationService

[lib/services/location_service.dart](/abs/path/C:/naib/projects/personal/musafir/lib/services/location_service.dart:1) is the only explicit service class today.

It wraps:

- `geolocator` for location permissions and current device position
- `geocoding` for address lookup and reverse geocoding

Important architectural detail:

- map rendering is done with `google_maps_flutter`
- address search is still done with `geocoding`, not Google Places Autocomplete

## UI Modules

### Authentication

The auth module is intentionally simple:

- login and signup screens
- mock credential flow
- no token storage
- no secure persistence
- no backend session management

### Marketplace browsing

The primary user-facing browsing experience is centered on:

- [lib/screens/explore/explore_screen.dart](/abs/path/C:/naib/projects/personal/musafir/lib/screens/explore/explore_screen.dart:1)
- [lib/screens/explore/listing_detail_screen.dart](/abs/path/C:/naib/projects/personal/musafir/lib/screens/explore/listing_detail_screen.dart:1)

`ExploreScreen` combines:

- free-text location entry through `SearchStateNotifier`
- category filtering by `ListingType`
- listing grid rendering through `ListingCardModern`
- navigation to detailed listing pages

`ListingDetailScreen` shows:

- image gallery
- host summary
- amenities and reviews
- marketplace booking modal

### Wishlists

[lib/screens/wishlists/wishlists_screen.dart](/abs/path/C:/naib/projects/personal/musafir/lib/screens/wishlists/wishlists_screen.dart:1) is driven by `FavoritesStateNotifier` plus repository listings. It is a read-only view over the favorite ID set and currently has a placeholder detail navigation path.

### Trips

[lib/screens/trips/trips_screen.dart](/abs/path/C:/naib/projects/personal/musafir/lib/screens/trips/trips_screen.dart:1) merges:

- repository bookings for the logged-in user
- sample bookings from `MockData`

It then splits them into `Upcoming` and `Past` tabs. This is a pragmatic demo choice, but it also means trip data currently comes from two sources.

### Profile and host entry

[lib/screens/profile/profile_screen.dart](/abs/path/C:/naib/projects/personal/musafir/lib/screens/profile/profile_screen.dart:1) is the main account hub. It:

- shows user profile data from `AuthStateNotifier`
- routes non-host users to `BecomeHostScreen`
- routes hosts to `HostDashboardScreen`

[lib/screens/host/become_host_screen.dart](/abs/path/C:/naib/projects/personal/musafir/lib/screens/host/become_host_screen.dart:1) upgrades the logged-in user to host status by calling `authState.becomeHost()`.

### Host flows

The host feature set currently includes:

- [HostDashboardScreen](/abs/path/C:/naib/projects/personal/musafir/lib/screens/host/host_dashboard_screen.dart:1)
- [CreateListingScreen](/abs/path/C:/naib/projects/personal/musafir/lib/screens/host/create_listing_screen.dart:1)
- [HostListingsScreen](/abs/path/C:/naib/projects/personal/musafir/lib/screens/host/host_listings_screen.dart:1)
- [HostReservationsScreen](/abs/path/C:/naib/projects/personal/musafir/lib/screens/host/host_reservations_screen.dart:1)

These screens derive host-specific data by filtering repository listings using:

- `listing.hostId == currentUser.id`
- or `listing.ownerName == currentUser.name`

This is a notable compatibility bridge between older and newer listing creation semantics.

`CreateListingScreen` is a multi-step listing wizard that collects:

- type
- basics
- location
- details
- pricing

It writes directly into the in-memory repository.

### Legacy role dashboards

The following older role-oriented screens still exist:

- [lib/screens/tenant_dashboard.dart](/abs/path/C:/naib/projects/personal/musafir/lib/screens/tenant_dashboard.dart:1)
- [lib/screens/owner_dashboard.dart](/abs/path/C:/naib/projects/personal/musafir/lib/screens/owner_dashboard.dart:1)
- [lib/screens/admin_dashboard.dart](/abs/path/C:/naib/projects/personal/musafir/lib/screens/admin_dashboard.dart:1)

These represent an earlier architecture where the product was organized around explicit role dashboards instead of the newer bottom-nav marketplace shell.

They still matter because:

- they exercise repository functionality that the newer shell may not
- they contain map-based owner and tenant workflows
- they document earlier product intent for admin and owner operations

## Maps And Location Architecture

There are three map/location pieces:

1. `MusafirMap`
2. `LocationPicker`
3. `PlaceSearchField`

### MusafirMap

[lib/widgets/musafir_map.dart](/abs/path/C:/naib/projects/personal/musafir/lib/widgets/musafir_map.dart:1) wraps `GoogleMap` and supports:

- centering on coordinates
- listing markers
- map tap selection
- my-location camera movement

This is used in the tenant area-search flow.

### LocationPicker

[lib/widgets/location_picker.dart](/abs/path/C:/naib/projects/personal/musafir/lib/widgets/location_picker.dart:1) provides a full-screen map picker used by owner and host flows. It supports:

- draggable-map location selection
- reverse geocoding
- current location jump
- text-based address search

### PlaceSearchField

[lib/widgets/place_search_field.dart](/abs/path/C:/naib/projects/personal/musafir/lib/widgets/place_search_field.dart:1) is a lightweight address search field for tenant area search. It uses geocoding results rather than a production autocomplete service.

### Native configuration

The codebase now includes native Android and iOS map SDK setup for local API keys, but the actual secrets remain intentionally outside version control.

## Data Flow

The most common runtime data paths are:

### App startup

1. `main.dart` runs `MusafirApp`
2. `MusafirApp` creates repository and state notifiers
3. repository seeds in-memory data
4. `SearchStateNotifier` receives repository listings
5. auth state decides between auth flow and main shell

### Explore search

1. user changes filters in `ExploreScreen`
2. `SearchStateNotifier` updates `SearchFilters`
3. filters are applied locally over cached repository listings
4. `ExploreScreen` rebuilds from notifier output

### Tenant map booking

1. user selects a place or taps a map point
2. `TenantDashboard` updates center coordinates
3. repository `searchByArea` returns local matches
4. user books a listing
5. repository mutates bookings and listing availability
6. repository notifies listeners

### Host listing creation

1. host opens `CreateListingScreen`
2. wizard collects listing data and optional map-picked coordinates
3. screen creates a `Listing`
4. repository `addListing` stores it in memory
5. repository notifies listeners
6. shell/search views indirectly refresh through `MusafirApp`

### Marketplace booking

1. user opens listing detail
2. user selects dates and guests
3. screen calls `createMarketplaceBooking`
4. repository stores booking
5. trips and host reservation views observe the new data

## Mock Data Strategy

Static demo content is centralized in [lib/data/mock_data.dart](/abs/path/C:/naib/projects/personal/musafir/lib/data/mock_data.dart:1) and related helpers:

- `MockData.users`
- `MockData.listings`
- `MockData.reviews`
- `MockData.getSampleBookings(...)`
- facility catalog and placeholder image helpers

This keeps the demo visually rich and makes the in-memory repository useful without backend setup.

## Architectural Strengths

The current design has several practical strengths:

- clear separation between UI, state, repository, and models
- repository abstraction already prepared for backend replacement
- small amount of framework complexity
- constructor-based dependency flow that is easy to trace
- reusable widgets around cards, forms, and maps
- enough mock data to support realistic product demos

## Current Architectural Limitations

The most important limitations in the current codebase are:

- no real persistence across app restarts
- auth state and repository user state are separate local stores
- some screens mix old and new product directions
- trips currently merge repository data with hardcoded sample bookings
- map search uses geocoding instead of production-grade Places autocomplete
- no backend conflict enforcement outside the in-memory repository logic
- no dependency injection container or scoped state provider
- some navigation stubs still use snackbars instead of full flows

## Recommended Backend Migration Path

The current codebase is positioned for an incremental backend migration:

1. Keep `MusafirRepository` as the primary contract.
2. Replace `InMemoryMusafirRepository` with a real implementation backed by Supabase/PostgreSQL.
3. Move user management out of `AuthStateNotifier` into the backend/auth provider.
4. Replace local search filtering with backend search and geospatial queries.
5. Replace geocoding-only place search with Google Places or an equivalent autocomplete API.
6. Normalize bookings around a single production booking model and move overlap checks server-side.

## Suggested Future Refactors

If the product continues to grow, the next structural refactors should likely be:

- split legacy dashboards from the newer marketplace shell or retire one path
- introduce feature folders with tighter local ownership
- centralize session/user data into one source of truth
- move booking and listing mapping logic into dedicated mappers or services
- add persistent state or backend caching where needed
- formalize navigation with a router if route complexity grows

## File Reference Summary

Core runtime files:

- [lib/main.dart](/abs/path/C:/naib/projects/personal/musafir/lib/main.dart:1)
- [lib/app.dart](/abs/path/C:/naib/projects/personal/musafir/lib/app.dart:1)
- [lib/screens/main_shell.dart](/abs/path/C:/naib/projects/personal/musafir/lib/screens/main_shell.dart:1)

Core data/state files:

- [lib/repositories/musafir_repository.dart](/abs/path/C:/naib/projects/personal/musafir/lib/repositories/musafir_repository.dart:1)
- [lib/repositories/in_memory_musafir_repository.dart](/abs/path/C:/naib/projects/personal/musafir/lib/repositories/in_memory_musafir_repository.dart:1)
- [lib/state/auth_state.dart](/abs/path/C:/naib/projects/personal/musafir/lib/state/auth_state.dart:1)
- [lib/state/search_state.dart](/abs/path/C:/naib/projects/personal/musafir/lib/state/search_state.dart:1)
- [lib/state/favorites_state.dart](/abs/path/C:/naib/projects/personal/musafir/lib/state/favorites_state.dart:1)

Core feature files:

- [lib/screens/explore/explore_screen.dart](/abs/path/C:/naib/projects/personal/musafir/lib/screens/explore/explore_screen.dart:1)
- [lib/screens/explore/listing_detail_screen.dart](/abs/path/C:/naib/projects/personal/musafir/lib/screens/explore/listing_detail_screen.dart:1)
- [lib/screens/profile/profile_screen.dart](/abs/path/C:/naib/projects/personal/musafir/lib/screens/profile/profile_screen.dart:1)
- [lib/screens/host/host_dashboard_screen.dart](/abs/path/C:/naib/projects/personal/musafir/lib/screens/host/host_dashboard_screen.dart:1)
- [lib/screens/host/create_listing_screen.dart](/abs/path/C:/naib/projects/personal/musafir/lib/screens/host/create_listing_screen.dart:1)
- [lib/widgets/musafir_map.dart](/abs/path/C:/naib/projects/personal/musafir/lib/widgets/musafir_map.dart:1)
- [lib/widgets/location_picker.dart](/abs/path/C:/naib/projects/personal/musafir/lib/widgets/location_picker.dart:1)
