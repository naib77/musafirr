# Musafir - First MVP Plan

An Airbnb-like rental marketplace app for Bangladesh built with Flutter.

## Executive Summary

Musafir is a property rental marketplace connecting guests with hosts. The MVP focuses on the core booking flow: users can browse listings, make bookings, and hosts can manage their properties.

---

## Current State Analysis

### Already Implemented
- Phone OTP authentication flow
- User model with roles (guest/host/admin)
- Listing model with pricing tiers (hourly/daily/monthly)
- Booking model with status management
- Repository pattern (in-memory + Supabase)
- Main navigation shell (Explore, Wishlists, Trips, Inbox, Profile)
- Search and filter functionality
- Favorites/Wishlists
- Messaging system (conversations)
- Notification system
- Currency support (BDT)
- Google Maps integration
- Host dashboard screens

### Needs Completion for MVP
- Listing detail screen with booking flow
- Payment integration
- Reviews and ratings flow
- Profile editing
- Backend integration (Supabase)

---

## MVP Feature Set

### Phase 1: Core Guest Experience

#### 1.1 Listing Discovery
- [x] Browse listings on Explore screen
- [x] Search by location
- [x] Filter by price, type, amenities
- [x] Map view of listings
- [ ] **Listing Detail Screen** - Full property details with images, amenities, host info
- [ ] **Image Gallery** - Swipeable full-screen image viewer
- [ ] **Availability Calendar** - Show booked/available dates

#### 1.2 Booking Flow
- [ ] **Date Selection** - Check-in/check-out picker
- [ ] **Guest Count Selector** - Number of guests
- [ ] **Price Breakdown** - Nightly rate, service fee, total
- [ ] **Booking Confirmation Screen** - Review booking details
- [ ] **Booking Success Screen** - Confirmation with booking details

#### 1.3 Guest Account
- [x] Phone OTP login/signup
- [ ] **Profile Editing** - Name, photo, bio
- [x] View upcoming/past trips
- [x] Wishlists management
- [x] Message hosts

### Phase 2: Core Host Experience

#### 2.1 Become a Host
- [x] Host registration flow
- [ ] **NID Verification** - National ID upload and verification
- [ ] **Phone Verification** - Already implemented via OTP

#### 2.2 Listing Management
- [x] Create new listing
- [ ] **Listing Editor** - Edit existing listings
- [ ] **Photo Upload** - Multiple images per listing
- [ ] **Pricing Setup** - Set daily/weekly/monthly rates
- [ ] **Availability Management** - Block dates, set minimum stay
- [ ] **Listing Preview** - See how guests view the listing

#### 2.3 Reservation Management
- [x] View reservations (host dashboard)
- [ ] **Accept/Decline Requests** - Booking request workflow
- [ ] **Calendar View** - Visual booking calendar
- [ ] **Guest Communication** - In-app messaging

### Phase 3: Trust & Safety

#### 3.1 Reviews & Ratings
- [ ] **Leave Review** - Guest reviews host after stay
- [ ] **Review Display** - Show reviews on listing detail
- [ ] **Host Response** - Hosts can respond to reviews
- [ ] **Rating Summary** - Average rating, category breakdown

#### 3.2 Verification
- [ ] **Phone Verification Badge** - Show verified status
- [ ] **NID Verification Badge** - Show verified status
- [ ] **Superhost Badge** - Recognition for top hosts

### Phase 4: Payments (Post-MVP)

#### 4.1 Payment Processing
- [ ] Payment gateway integration (bKash/Nagad/Card)
- [ ] Secure payment flow
- [ ] Payout to hosts
- [ ] Refund handling

---

## Technical Architecture

### Data Models (Existing)

```
User
├── id, name, email, phone
├── role (guest/host/admin)
├── avatarUrl, bio
├── nidVerified, phoneVerified
└── isHost, hostSince

Listing
├── id, hostId, title, description
├── address, city, country, lat/lng
├── type (apartment/house/room/etc)
├── hourlyRate, dailyRate, monthlyRate
├── facilities[], imageUrls[]
├── maxGuests, bedrooms, beds, bathrooms
├── rating, reviewCount, isSuperhost
└── available

Booking
├── id, listingId, userId
├── checkIn, checkOut
├── guestCount, totalPrice
├── status (pending/confirmed/cancelled/completed)
├── serviceFee, discount
└── createdAt

Review
├── id, listingId, userId
├── rating, comment
├── hostResponse
└── createdAt
```

### Screen Flow

```
App Start
    │
    ▼
┌─────────────────┐
│  Phone Entry    │
│  (OTP Login)    │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────────────────┐
│                    Main Shell                        │
├──────────┬──────────┬──────────┬──────────┬────────┤
│ Explore  │Wishlists │  Trips   │  Inbox   │Profile │
└──────────┴──────────┴──────────┴──────────┴────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│ Listing Detail  │────▶│ Booking Flow    │
└─────────────────┘     └────────┬────────┘
                                 │
                                 ▼
                        ┌─────────────────┐
                        │ Confirmation    │
                        └─────────────────┘
```

### Repository Pattern

```dart
abstract class MusafirRepository {
  // Listings
  List<Listing> get listings;
  Listing? getListingById(String id);
  List<Listing> searchListings(SearchFilters filters);
  void addListing(Listing listing);
  void updateListing(Listing listing);

  // Bookings
  List<Booking> get bookings;
  Booking createMarketplaceBooking({...});
  bool isTimeSlotAvailable({...});

  // Users
  User? getUserById(String id);
  void addUser(User user);

  // Reviews
  List<Review> getReviewsForListing(String listingId);
  void addReview(Review review);
}
```

---

## MVP Screens to Build

### Priority 1 (Critical Path)

| Screen | Description | Dependencies |
|--------|-------------|--------------|
| `ListingDetailScreen` | Full listing view with images, amenities, reviews | Listing model |
| `BookingScreen` | Date selection, guest count, price breakdown | Booking model |
| `BookingConfirmationScreen` | Final review before booking | BookingScreen |
| `BookingSuccessScreen` | Success state with booking details | BookingConfirmationScreen |

### Priority 2 (Complete Experience)

| Screen | Description | Dependencies |
|--------|-------------|--------------|
| `ProfileEditScreen` | Edit user profile | User model |
| `ListingEditScreen` | Edit existing listing | Host flow |
| `ReviewScreen` | Leave a review after stay | Review model |
| `AvailabilityCalendarScreen` | Host availability management | Booking model |

### Priority 3 (Nice to Have)

| Screen | Description | Dependencies |
|--------|-------------|--------------|
| `ImageGalleryScreen` | Full-screen image viewer | ListingDetailScreen |
| `HostCalendarScreen` | Visual booking calendar | Host dashboard |
| `SearchFiltersScreen` | Advanced search filters | Explore |

---

## API Integration (Supabase)

### Database Tables

```sql
-- Users table
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  email TEXT UNIQUE,
  phone TEXT UNIQUE,
  avatar_url TEXT,
  role TEXT DEFAULT 'guest',
  is_host BOOLEAN DEFAULT FALSE,
  nid TEXT,
  nid_verified BOOLEAN DEFAULT FALSE,
  phone_verified BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Listings table
CREATE TABLE listings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  host_id UUID REFERENCES users(id),
  title TEXT NOT NULL,
  description TEXT,
  address TEXT NOT NULL,
  city TEXT,
  country TEXT DEFAULT 'Bangladesh',
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  type TEXT NOT NULL,
  daily_rate DECIMAL(10,2) NOT NULL,
  monthly_rate DECIMAL(10,2),
  max_guests INTEGER DEFAULT 2,
  bedrooms INTEGER DEFAULT 1,
  bathrooms INTEGER DEFAULT 1,
  available BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Bookings table
CREATE TABLE bookings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  listing_id UUID REFERENCES listings(id),
  user_id UUID REFERENCES users(id),
  check_in DATE NOT NULL,
  check_out DATE NOT NULL,
  guest_count INTEGER DEFAULT 1,
  total_price DECIMAL(10,2) NOT NULL,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Reviews table
CREATE TABLE reviews (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  listing_id UUID REFERENCES listings(id),
  user_id UUID REFERENCES users(id),
  booking_id UUID REFERENCES bookings(id),
  rating INTEGER CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  host_response TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## Implementation Checklist

### Week 1-2: Core Booking Flow
- [ ] Create `ListingDetailScreen` with image carousel
- [ ] Add amenities and facilities display
- [ ] Show host information section
- [ ] Display reviews section
- [ ] Implement date picker for check-in/check-out
- [ ] Add guest selector
- [ ] Create price breakdown widget
- [ ] Build `BookingConfirmationScreen`
- [ ] Create `BookingSuccessScreen`

### Week 3: Host Features
- [ ] Complete listing creation flow
- [ ] Add photo upload functionality
- [ ] Implement listing edit screen
- [ ] Add availability calendar
- [ ] Build booking request accept/decline UI

### Week 4: Polish & Backend
- [ ] Connect to Supabase backend
- [ ] Add loading states and error handling
- [ ] Implement pull-to-refresh
- [ ] Add empty states
- [ ] Performance optimization
- [ ] Basic analytics

---

## Success Metrics

### MVP Launch Goals
- Users can complete full booking flow
- Hosts can list properties
- Basic messaging between guests and hosts
- Mobile-first responsive design

### Key Metrics to Track
- Number of listings created
- Booking conversion rate
- User registration rate
- Average booking value
- Host response time

---

## Out of Scope for MVP

The following features are intentionally excluded from MVP:

- Payment processing (manual coordination initially)
- Push notifications (in-app only)
- Multi-language support
- Advanced search (AI-powered)
- Instant booking vs. request-based
- Cancellation policies
- Price discounts and promotions
- Social login (Google, Facebook)
- Admin dashboard
- Analytics dashboard
- Email notifications

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Payment complexity | Start with manual payment coordination |
| Backend scaling | Use Supabase with proper indexing |
| Image storage | Use Supabase Storage or Cloudinary |
| Map API costs | Limit API calls, cache results |
| User trust | Prioritize verification badges |

---

## Next Steps

1. **Immediate**: Build `ListingDetailScreen` with booking flow
2. **Short-term**: Complete host listing management
3. **Medium-term**: Add reviews and ratings
4. **Long-term**: Payment integration

---

*Last updated: May 2025*
