import '../../models/geo_bounds.dart';
import '../../models/listing.dart';
import '../../models/listing_type.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';
import '../../services/places_service.dart';
import 'search_pill.dart' show ResolvedPlace;
import 'where_panel.dart';

/// The real service adapters behind the search bar.
///
/// The bar and its panels take their lookups as functions so they can be driven
/// in a test without a network. These are the production implementations, kept
/// out of `MainShell` so the shell does not grow a second job, and out of the
/// widgets so the widgets stay testable.

/// Places in the listing cache whose name contains [query], most stays first.
///
/// Local and synchronous — these are the searches most likely to return
/// something, so they appear the instant a letter is typed rather than after a
/// round trip. Capped at five: this list sits above the Google predictions and
/// must not push them off the panel.
///
/// An **empty** query is not "no results", it is the panel's opening state, and
/// it answers with the busiest places instead — Airbnb's "Suggested
/// destinations". A panel that greets you with an empty list reads as broken.
/// [types] is the search's own type filter, empty for "anything". Counting
/// past it is how a turf-scoped search came to offer "Dhaka — 9 stays": those
/// nine are rooms and seats, so tapping the row and pressing Search returned
/// nothing, and the list had promised otherwise. The count has to describe the
/// search that is about to run, not the catalogue.
List<CitySuggestion> citySuggestionsFrom(
  List<Listing> listings,
  String query, [
  List<ListingType> types = const [],
]) {
  final q = query.trim().toLowerCase();
  final scoped =
      types.isEmpty ? listings : listings.where((l) => types.contains(l.type));

  final counts = <String, int>{};
  for (final listing in scoped) {
    final city = listing.city;
    if (city == null || city.isEmpty) continue;
    counts[city] = (counts[city] ?? 0) + 1;
  }

  // Named for what is being counted, and only when the scope is a single type
  // — "3 rooms and turfs" is not a noun.
  final noun = types.length == 1 ? types.first.title.toLowerCase() : 'stay';

  final matches = counts.entries
      .where((e) => q.isEmpty || e.key.toLowerCase().contains(q))
      .map((e) => CitySuggestion(city: e.key, count: e.value, noun: noun))
      .toList()
    ..sort((a, b) => b.count.compareTo(a.count));

  return matches.take(5).toList();
}

/// Listings whose name or place contains [query], narrowed to [types].
///
/// The Where dropdown answered a typed query with *places* only — "Uttara",
/// "Uttara North Metro Rail Station", "Uttara University" — which is right
/// when the question is "which Uttara do you mean" and wrong when the guest
/// has already said Turf and is looking for grounds. A place row commits them
/// to another round trip before they see a single result.
///
/// Matched against title, address and city together, because a guest typing
/// "uttara" means the area and a guest typing "greenfield" means the ground,
/// and the field has no way to tell which they intended.
///
/// Capped at four: this sits above both the city rows and the Google
/// predictions, and all three have to fit the panel without pushing the
/// predictions out of reach.
List<Listing> listingSuggestionsFrom(
  List<Listing> listings,
  String query, [
  List<ListingType> types = const [],
]) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];

  return listings
      .where((l) => types.isEmpty || types.contains(l.type))
      .where((l) =>
          l.title.toLowerCase().contains(q) ||
          l.address.toLowerCase().contains(q) ||
          (l.city ?? '').toLowerCase().contains(q))
      .take(4)
      .toList();
}

/// Whether [query] names a city the app already has listings in.
bool isKnownCity(List<Listing> listings, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return false;
  return listings.any((l) => (l.city ?? '').trim().toLowerCase() == q);
}

/// Resolves typed text that no prediction was tapped for.
///
/// The priority is the sheet's, and it matters:
///
/// - **a box came back** → search and frame within it. Best case, and what
///   makes "Uttara" stay inside Uttara.
/// - **no box, and not a city we know** → centre an expanding proximity ring on
///   the point.
/// - **no box, but a known city** → no point at all, so the classic text search
///   runs and covers every stay in that city. A 1km ring on a city's geometric
///   centre would be worse than not resolving it in the first place.
Future<ResolvedPlace?> geocodeForSearch(
  String query, {
  required bool Function(String) knownCity,
}) async {
  final place = await GeocodingService().geocode(query);
  if (place == null) return null;
  final GeoBounds? bounds = place.bounds;
  if (bounds != null) return ResolvedPlace(bounds: bounds);
  if (knownCity(query)) return null;
  return ResolvedPlace(latitude: place.latitude, longitude: place.longitude);
}

/// "Nearby": the device's position, labelled where the platform can reverse
/// geocode it (mobile). The web has no reverse geocoder here, so it falls back
/// to a plain label rather than showing raw coordinates in the field.
///
/// Deliberately carries no bounds: near-me is a point-and-radius search, not an
/// area.
Future<PlaceLocation?> currentLocationPlace() async {
  final position = await LocationService().getCurrentLocation();
  if (position == null) return null;
  final label = await LocationService().getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      ) ??
      'Current location';
  return PlaceLocation(
    name: label,
    latitude: position.latitude,
    longitude: position.longitude,
  );
}
