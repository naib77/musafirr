import 'package:flutter/material.dart';

import '../../models/geo_bounds.dart';
import '../../models/landmark.dart';
import '../../models/listing_purpose.dart';
import '../../models/listing_type.dart';
import '../../models/search_filters.dart';

/// The search being *edited*, as distinct from the search that is running.
///
/// ## Why a draft exists at all
///
/// Every mutator on `SearchStateNotifier` runs a search the moment it is called
/// — `updateLocation`, `updateDates`, `updateGuestCount`, all of them end in
/// `_runSearch()`. That is fine for one form with one Search button, which is
/// what the app had. It is wrong for a bar whose three segments are each their
/// own panel: closing Where, then When, then Who would fire three
/// `search_listings` round trips for one search, and the guest would watch the
/// feed rearrange itself twice before they had finished asking.
///
/// So the panels write here, nothing observes this but the bar, and exactly one
/// `updateFilters` fires when Search is pressed. It is the same shape the
/// existing full-screen sheet already has — local state until `_applySearch` —
/// only lifted out of one widget so three can share it.
///
/// ## Seeding
///
/// Built from the live [SearchFilters] via [SearchDraft.from] each time the bar
/// is opened, so a panel always shows what is actually running. Re-seed (rather
/// than mutate) whenever the committed filters change underneath — a ✕, a voice
/// search — or the draft would keep describing a search that no longer exists.
class SearchDraft extends ChangeNotifier {
  SearchDraft.from(SearchFilters filters)
      : locationText = filters.location ?? '',
        latitude = filters.latitude,
        longitude = filters.longitude,
        bounds = filters.bounds,
        dateMode = filters.dateMode,
        dateRange = (filters.checkIn != null && filters.checkOut != null)
            ? DateTimeRange(start: filters.checkIn!, end: filters.checkOut!)
            : null,
        singleDate = filters.singleDate,
        startTime = filters.startTime,
        endTime = filters.endTime,
        adults = filters.adults,
        children = filters.children,
        infants = filters.infants,
        propertyTypes = List<ListingType>.from(filters.propertyTypes),
        purpose =
            filters.purposeTags.isEmpty ? null : filters.purposeTags.first,
        landmark = filters.landmark;

  // ── Where ────────────────────────────────────────────────────────────────
  //
  // The text and the resolved point are separate on purpose: a guest can type
  // "Uttara" and never pick a prediction, in which case the commit geocodes the
  // text. `bounds` is a place's true extent and is independent of the point —
  // a city resolves to a box with no centre at all.
  String locationText;
  double? latitude;
  double? longitude;
  GeoBounds? bounds;

  // ── When ─────────────────────────────────────────────────────────────────
  SearchDateMode dateMode;
  DateTimeRange? dateRange;
  DateTime? singleDate;
  TimeOfDay? startTime;
  TimeOfDay? endTime;

  // ── Who ──────────────────────────────────────────────────────────────────
  int adults;
  int children;
  int infants;

  // ── Filters ──────────────────────────────────────────────────────────────
  List<ListingType> propertyTypes;

  /// One purpose, not a list. `SearchFilters.purposeTags` is a list because the
  /// RPC takes one, but the UI has only ever offered a single choice.
  ListingPurpose? purpose;
  Landmark? landmark;

  /// What [SearchFilters.guestCount] will become — the number the search
  /// actually runs with.
  int get guestCount => guestCountFor(adults: adults, children: children);

  /// True once the guest has narrowed anything. Drives whether the bar offers a
  /// way to clear, and mirrors `SearchFilters.hasActiveFilters` — note that a
  /// party of one is not a filter, and neither are infants on their own.
  bool get hasAnyInput =>
      locationText.trim().isNotEmpty ||
      dateRange != null ||
      singleDate != null ||
      guestCount > 1 ||
      propertyTypes.isNotEmpty ||
      purpose != null ||
      landmark != null;

  /// Applies [change] and notifies once. Every panel edits through this so no
  /// caller has to remember to notify — a silent edit would leave the bar's own
  /// summary showing the previous value.
  void edit(VoidCallback change) {
    change();
    notifyListeners();
  }

  /// Records a place the guest picked from the suggestion list, replacing any
  /// previously resolved one.
  ///
  /// Both coordinates and the box are set together, including to null: a new
  /// place with no viewport must drop the old box, or the previous search's
  /// extent silently keeps applying to a different place.
  void setResolvedPlace({
    required String text,
    double? latitude,
    double? longitude,
    GeoBounds? bounds,
  }) {
    edit(() {
      locationText = text;
      this.latitude = latitude;
      this.longitude = longitude;
      this.bounds = bounds;
    });
  }

  /// Typing invalidates whatever was resolved before.
  ///
  /// Without this, picking "Uttara, Dhaka" and then editing the text to
  /// "Mirpur" would search Mirpur's *name* at Uttara's coordinates — the point
  /// wins over the text everywhere downstream.
  void setLocationText(String text) {
    edit(() {
      locationText = text;
      latitude = null;
      longitude = null;
      bounds = null;
    });
  }
}
