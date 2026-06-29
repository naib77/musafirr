-- Host-wide availability switch. When false, the host is "away" and is not
-- accepting new bookings (enforced at the Reserve step). Independent of each
-- listing's own is_active hide/show state.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_available BOOLEAN NOT NULL DEFAULT TRUE;
