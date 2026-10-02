-- Musafir Supabase Database Schema
-- Run this SQL in your Supabase SQL Editor to set up the database

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- ============== ENUMS ==============

CREATE TYPE app_role AS ENUM ('admin', 'owner', 'tenant');
CREATE TYPE listing_type AS ENUM ('seat', 'room', 'fullHouse');
CREATE TYPE booking_status AS ENUM ('pending', 'confirmed', 'completed', 'cancelled');
CREATE TYPE pricing_unit AS ENUM ('hour', 'day', 'month');

-- ============== PROFILES TABLE ==============
-- Stores user profile data linked to Supabase Auth

CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    email TEXT,
    mobile TEXT,
    role app_role DEFAULT 'tenant',
    avatar_url TEXT,
    is_host BOOLEAN DEFAULT FALSE,
    host_since TIMESTAMPTZ,
    bio TEXT,
    response_rate INTEGER,
    response_time TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Profiles policies
CREATE POLICY "Users can view their own profile"
    ON profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
    ON profiles FOR UPDATE
    USING (auth.uid() = id);

CREATE POLICY "Users can insert their own profile"
    ON profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

-- ============== FACILITIES TABLE ==============
-- Catalog of available facilities/amenities

CREATE TABLE facilities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL UNIQUE,
    icon TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed default facilities
INSERT INTO facilities (name, icon) VALUES
    ('Wi-Fi', 'wifi'),
    ('AC', 'ac_unit'),
    ('Attached Bath', 'bathtub_outlined'),
    ('Kitchen', 'soup_kitchen_outlined'),
    ('Parking', 'local_parking_outlined');

-- ============== LISTINGS TABLE ==============
-- Rental properties/spaces

CREATE TABLE listings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    owner_name TEXT,
    title TEXT NOT NULL,
    description TEXT,
    address TEXT,
    city TEXT,
    country TEXT,
    listing_type listing_type DEFAULT 'room',
    latitude NUMERIC(10, 7),
    longitude NUMERIC(10, 7),
    location GEOGRAPHY(Point, 4326),
    hourly_rate NUMERIC(10, 2) DEFAULT 0,
    daily_rate NUMERIC(10, 2) DEFAULT 0,
    monthly_rate NUMERIC(10, 2) DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    host_avatar_url TEXT,
    image_urls TEXT[] DEFAULT '{}',
    max_guests INTEGER DEFAULT 2,
    bedrooms INTEGER DEFAULT 1,
    beds INTEGER DEFAULT 1,
    bathrooms INTEGER DEFAULT 1,
    rating NUMERIC(2, 1),
    review_count INTEGER DEFAULT 0,
    is_superhost BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index for geospatial queries
CREATE INDEX listings_location_idx ON listings USING GIST (location);

-- Enable RLS
ALTER TABLE listings ENABLE ROW LEVEL SECURITY;

-- Listings policies
CREATE POLICY "Anyone can view active listings"
    ON listings FOR SELECT
    USING (is_active = TRUE);

CREATE POLICY "Owners can insert their own listings"
    ON listings FOR INSERT
    WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Owners can update their own listings"
    ON listings FOR UPDATE
    USING (auth.uid() = owner_id);

CREATE POLICY "Owners can delete their own listings"
    ON listings FOR DELETE
    USING (auth.uid() = owner_id);

-- Trigger to update location geography from lat/lng
CREATE OR REPLACE FUNCTION update_listing_location()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL THEN
        NEW.location = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER listing_location_trigger
    BEFORE INSERT OR UPDATE ON listings
    FOR EACH ROW
    EXECUTE FUNCTION update_listing_location();

-- ============== LISTING_FACILITIES TABLE ==============
-- Join table for listings and facilities

CREATE TABLE listing_facilities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    listing_id UUID REFERENCES listings(id) ON DELETE CASCADE,
    facility_id UUID REFERENCES facilities(id) ON DELETE CASCADE,
    UNIQUE(listing_id, facility_id)
);

-- Enable RLS
ALTER TABLE listing_facilities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view listing facilities"
    ON listing_facilities FOR SELECT
    USING (TRUE);

CREATE POLICY "Owners can manage their listing facilities"
    ON listing_facilities FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM listings
            WHERE listings.id = listing_facilities.listing_id
            AND listings.owner_id = auth.uid()
        )
    );

-- ============== BOOKINGS TABLE ==============
-- Reservations

CREATE TABLE bookings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    listing_id UUID REFERENCES listings(id) ON DELETE CASCADE,
    tenant_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    tenant_name TEXT,
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    booking_status booking_status DEFAULT 'pending',
    pricing_unit pricing_unit DEFAULT 'day',
    unit_count INTEGER DEFAULT 1,
    total_price NUMERIC(10, 2) NOT NULL,
    guest_count INTEGER DEFAULT 1,
    listing_title TEXT,
    listing_image_url TEXT,
    listing_city TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Ensure ends_at is after starts_at
    CONSTRAINT valid_booking_dates CHECK (ends_at > starts_at)
);

-- Exclusion constraint to prevent overlapping active bookings
-- Requires btree_gist extension
CREATE INDEX bookings_overlap_idx ON bookings
    USING GIST (listing_id, tstzrange(starts_at, ends_at, '[)'))
    WHERE booking_status IN ('pending', 'confirmed');

-- Enable RLS
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;

-- Bookings policies
CREATE POLICY "Users can view their own bookings"
    ON bookings FOR SELECT
    USING (auth.uid() = tenant_id);

CREATE POLICY "Hosts can view bookings for their listings"
    ON bookings FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM listings
            WHERE listings.id = bookings.listing_id
            AND listings.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can create bookings"
    ON bookings FOR INSERT
    WITH CHECK (auth.uid() = tenant_id);

CREATE POLICY "Users can cancel their own bookings"
    ON bookings FOR UPDATE
    USING (auth.uid() = tenant_id);

-- ============== REVIEWS TABLE ==============

CREATE TABLE reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    listing_id UUID REFERENCES listings(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    user_name TEXT,
    user_avatar_url TEXT,
    rating NUMERIC(2, 1) NOT NULL CHECK (rating >= 0 AND rating <= 5),
    comment TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view reviews"
    ON reviews FOR SELECT
    USING (TRUE);

CREATE POLICY "Users can create reviews"
    ON reviews FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Trigger to update listing rating when review is added
CREATE OR REPLACE FUNCTION update_listing_rating()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE listings
    SET
        rating = (SELECT AVG(rating) FROM reviews WHERE listing_id = NEW.listing_id),
        review_count = (SELECT COUNT(*) FROM reviews WHERE listing_id = NEW.listing_id)
    WHERE id = NEW.listing_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER review_rating_trigger
    AFTER INSERT OR UPDATE OR DELETE ON reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_listing_rating();

-- ============== HELPER FUNCTIONS ==============

-- Function to search listings within radius (in meters)
CREATE OR REPLACE FUNCTION search_listings_by_location(
    center_lat NUMERIC,
    center_lng NUMERIC,
    radius_meters INTEGER DEFAULT 10000
)
RETURNS SETOF listings AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM listings
    WHERE is_active = TRUE
    AND ST_DWithin(
        location,
        ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography,
        radius_meters
    )
    ORDER BY ST_Distance(
        location,
        ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography
    );
END;
$$ LANGUAGE plpgsql;

-- Function to check booking availability
CREATE OR REPLACE FUNCTION is_booking_available(
    p_listing_id UUID,
    p_starts_at TIMESTAMPTZ,
    p_ends_at TIMESTAMPTZ
)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN NOT EXISTS (
        SELECT 1
        FROM bookings
        WHERE listing_id = p_listing_id
        AND booking_status IN ('pending', 'confirmed')
        AND tstzrange(starts_at, ends_at, '[)') && tstzrange(p_starts_at, p_ends_at, '[)')
    );
END;
$$ LANGUAGE plpgsql;

-- ============== AUTO-CREATE PROFILE ON SIGNUP ==============

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO profiles (id, email, full_name)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email)
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_user();
