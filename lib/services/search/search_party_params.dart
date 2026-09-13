import '../../models/search_filters.dart';

/// The `search_listings` arguments describing the party, or nothing at all.
///
/// ## Why "or nothing at all" is the whole point
///
/// PostgREST picks a function overload by the **keys present in the request**,
/// not by their values. Migration 118 added `p_adults` / `p_children` /
/// `p_infants` / `p_pets` with defaults, so a caller that omits them resolves
/// to the same function and behaves exactly as it did before — but a caller
/// that sends them as zeros against a database where 118 has not yet been
/// applied demands a function that does not exist. That resolves to nothing,
/// `searchListingsFromDb` catches it, and **every search on the site becomes
/// "no results"**.
///
/// `build/web` is a committed artifact and the deployed bundle always lags a
/// migration, so that window is real, not theoretical. Returning an empty map
/// for an unnarrowed search means the default explore feed and the overwhelming
/// majority of searches never depend on the migration at all — the same trick
/// 112 used for `p_check_in`/`p_check_out`, and for the same reason.
///
/// ## What counts as narrowing
///
/// Adults and children only once one of them is past its default (1 adult, no
/// children): below that they say nothing `p_guest_count` does not already say,
/// so sending them would buy four keys and a migration dependency for no filter.
/// Infants and pets have no such proxy — neither is folded into `guestCount` —
/// so any non-zero value is a genuine filter and must be sent.
///
/// All four go together once any one of them does. They are one predicate group
/// in the SQL, and a partial send would let a stale value from a previous
/// argument list decide the search.
Map<String, dynamic> searchPartyParams(SearchFilters filters) {
  final narrowed = filters.adults > 1 ||
      filters.children > 0 ||
      filters.infants > 0 ||
      filters.pets > 0;
  if (!narrowed) return const {};
  return {
    'p_adults': filters.adults,
    'p_children': filters.children,
    'p_infants': filters.infants,
    'p_pets': filters.pets,
  };
}
