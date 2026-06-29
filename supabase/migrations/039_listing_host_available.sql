-- Denormalized host availability on each listing so guest browse/search can
-- hide listings whose host is currently "away" (profiles.is_available = false).
-- Kept in sync by triggers. The host's own management views ignore this flag,
-- so an away host can still see and manage (and un-away) their listings.

ALTER TABLE public.listings
  ADD COLUMN IF NOT EXISTS host_available BOOLEAN NOT NULL DEFAULT TRUE;

-- Backfill from current profile availability.
UPDATE public.listings l
SET host_available = p.is_available
FROM public.profiles p
WHERE l.owner_id = p.id;

-- When a host flips their availability, cascade it to all their listings.
CREATE OR REPLACE FUNCTION public.sync_listings_host_available()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_available IS DISTINCT FROM OLD.is_available THEN
    UPDATE public.listings
    SET host_available = NEW.is_available
    WHERE owner_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_listings_host_available ON public.profiles;
CREATE TRIGGER trg_sync_listings_host_available
AFTER UPDATE OF is_available ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.sync_listings_host_available();

-- Stamp host availability on newly created listings from the owner's status.
CREATE OR REPLACE FUNCTION public.set_listing_host_available()
RETURNS TRIGGER AS $$
BEGIN
  SELECT is_available INTO NEW.host_available
  FROM public.profiles WHERE id = NEW.owner_id;
  IF NEW.host_available IS NULL THEN
    NEW.host_available := TRUE;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_set_listing_host_available ON public.listings;
CREATE TRIGGER trg_set_listing_host_available
BEFORE INSERT ON public.listings
FOR EACH ROW EXECUTE FUNCTION public.set_listing_host_available();
