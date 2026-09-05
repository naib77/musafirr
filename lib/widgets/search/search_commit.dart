import '../../models/listing_purpose.dart';
import '../../models/listing_type.dart';
import '../../models/search_filters.dart';
import 'search_draft.dart';

/// Turns the edited [draft] into the [SearchFilters] to run, layered over the
/// filters currently in force ([base]).
///
/// This is the one function in the search bar worth being careful about, so it
/// is pure and has a test table rather than being reachable only by clicking
/// through four panels.
///
/// ## Why it layers over [base] instead of building from scratch
///
/// `SearchFilters` carries fields no panel edits — `minPrice`, `maxPrice`,
/// `amenities`, `radiusMeters`. Constructing a fresh one would silently drop
/// them the first time anyone builds a UI for them. Going through `copyWith`
/// means a field nobody here knows about survives by default, which is the
/// right default for a projection of a partial edit.
///
/// ## The date matrix, which is the part that breaks
///
/// The two date modes are mutually exclusive, and `SearchFilters` stores both
/// shapes side by side. The sheet this replaces handled that by passing `null`
/// for the inactive mode's fields — which does **not** clear them, because
/// `copyWith` reads `null` as "unchanged" and falls through to the old value.
/// So a range picked after an hourly window left the stale `singleDate` in
/// place, keeping `hasActiveFilters` true for a selection no longer on screen.
///
/// Hence the two steps below: wipe every date-shaped field first, then write
/// back only what the active mode actually uses. It reads as a wipe-and-set
/// rather than as a matrix of flags, and there is no combination that can leak.
SearchFilters filtersFromDraft(SearchDraft draft, SearchFilters base) {
  final text = draft.locationText.trim();

  // Step 1 — clear both modes' date fields together. `clearDates` covers
  // checkIn/checkOut/singleDate and `clearTime` covers start/end, so after this
  // nothing date-shaped can survive from a previous search.
  var next = base.copyWith(clearDates: true, clearTime: true);

  // Step 2 — write back only the active mode's selection.
  if (draft.dateMode == SearchDateMode.dateRange) {
    final range = draft.dateRange;
    next = next.copyWith(
      dateMode: SearchDateMode.dateRange,
      checkIn: range?.start,
      checkOut: range?.end,
    );
  } else {
    next = next.copyWith(
      dateMode: SearchDateMode.singleDateWithTime,
      singleDate: draft.singleDate,
      startTime: draft.startTime,
      endTime: draft.endTime,
    );
  }

  // Where. An empty field clears the place entirely — text, point and box —
  // which is what `clearLocation` does in one flag.
  if (text.isEmpty) {
    next = next.copyWith(clearLocation: true);
  } else {
    final lat = draft.latitude;
    final lng = draft.longitude;
    // A landmark search is anchored on the landmark, so any place box must go
    // or it would keep framing the map on the previous search's extent.
    final bounds = draft.landmark == null ? draft.bounds : null;
    next = next.copyWith(
      location: text,
      latitude: lat,
      longitude: lng,
      // Both or neither: half a coordinate pair is not a point, and the old
      // one must not survive a resolve that produced only a box.
      clearCoordinates: lat == null || lng == null,
      bounds: bounds,
      clearBounds: bounds == null,
    );
  }

  return next.copyWith(
    // Both the breakdown and the number derived from it. guestCount is what
    // reaches search_listings; the three parts exist so reopening the panel
    // shows what was chosen rather than a re-split sum.
    guestCount: draft.guestCount,
    adults: draft.adults,
    children: draft.children,
    infants: draft.infants,
    propertyTypes: List<ListingType>.unmodifiable(draft.propertyTypes),
    purposeTags: draft.purpose == null
        ? const <ListingPurpose>[]
        : <ListingPurpose>[draft.purpose!],
    landmark: draft.landmark,
    clearLandmark: draft.landmark == null,
    // No radiusMeters on purpose: the landmark ring is admin-configured
    // (`search_landmark_radius_m`) and resolved in the repository, so the
    // search bar never carries a second copy of it.
  );
}
