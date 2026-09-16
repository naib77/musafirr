import '../../models/landmark.dart';
import '../../models/listing_purpose.dart';
import '../../models/listing_type.dart';

/// The coarse cut a guest makes before anything else: am I looking for a place
/// to stay, or for a ground to book?
///
/// It is deliberately *not* a fourth thing alongside type and purpose. It is a
/// one-tap way of writing a `ListingType`, because the two shapes this app
/// rents are different enough that asking which one you want is the first
/// question, not an overflow filter. [SearchScope.any] is the search that
/// names no type at all, which is what the explore feed runs.
enum SearchScope { any, turf }

/// What a search should hold after the guest picks [scope].
///
/// Pure, and a record rather than a mutation, so the rule below can be tested
/// without a widget or a draft.
///
/// **Turf and purpose are mutually exclusive, and that is the whole reason
/// this function exists.** `search_listings` ANDs its predicates, and
/// `purpose_tags` is a column on stays — a turf carries none — so "turf near a
/// hospital" is a search that can never match. It would not raise: it returns
/// zero rows, which `searchListingsFromDb` renders as a plain "no listings
/// found", and the guest has no way to see that the two pills they tapped
/// cancelled each other out. So picking Turf drops the purpose and its
/// landmark, and (see [scopeOfPurpose]) picking a purpose drops Turf.
({List<ListingType> types, ListingPurpose? purpose, Landmark? landmark})
    applyScope(
  SearchScope scope, {
  required List<ListingType> types,
  required ListingPurpose? purpose,
  required Landmark? landmark,
}) {
  switch (scope) {
    case SearchScope.turf:
      return (
        types: const [ListingType.turf],
        purpose: null,
        landmark: null,
      );
    case SearchScope.any:
      // Only turf is removed. The other types are the Filters panel's answers
      // and this control has no business clearing them — a guest who narrowed
      // to "Room" and then tapped Anything is saying "not just turf", not
      // "forget everything I picked".
      return (
        types: types.where((t) => t != ListingType.turf).toList(),
        purpose: purpose,
        landmark: landmark,
      );
  }
}

/// Which pill reads as selected for a set of types.
///
/// Turf has to be the *only* type for the Turf pill to light up: a search for
/// "rooms and turfs" is a real thing the Filters panel can express, and it is
/// neither of the two scopes this control offers.
SearchScope scopeOf(List<ListingType> types) =>
    types.length == 1 && types.first == ListingType.turf
        ? SearchScope.turf
        : SearchScope.any;

/// The types a search should hold once the guest picks [purpose] — the other
/// half of the exclusion above.
///
/// A purpose describes what a *stay* is for, so choosing one while the search
/// is scoped to turf has to drop the turf rather than produce the empty
/// search. Clearing the purpose (null) changes nothing: "any purpose" does not
/// conflict with anything.
List<ListingType> typesForPurpose(
  ListingPurpose? purpose,
  List<ListingType> types,
) {
  if (purpose == null) return types;
  return types.where((t) => t != ListingType.turf).toList();
}
