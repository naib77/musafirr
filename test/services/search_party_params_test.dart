import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/search_filters.dart';
import 'package:musafir/services/search/search_party_params.dart';

void main() {
  group('searchPartyParams', () {
    // THE load-bearing case. The default explore feed is
    // searchListingsFromDb(const SearchFilters()), so if this sends keys, every
    // visitor's first screen depends on migration 118 having been applied — and
    // build/web always lags a migration. Absent keys resolve to the same
    // function and filter nothing; present keys against a pre-118 database
    // resolve to no function at all and the catch renders it as "no results".
    test('an untouched search sends no keys', () {
      expect(searchPartyParams(const SearchFilters()), isEmpty);
    });

    test('one adult and nothing else is still untouched', () {
      expect(
        searchPartyParams(const SearchFilters(adults: 1, guestCount: 1)),
        isEmpty,
      );
    });

    // p_guest_count already carries adults + children, so below the defaults
    // these four add a migration dependency and no filter.
    test('a party the guest count already describes sends no keys', () {
      expect(
        searchPartyParams(const SearchFilters(guestCount: 4)),
        isEmpty,
        reason: 'guestCount alone was set by some other surface',
      );
    });

    test('more than one adult narrows', () {
      expect(
        searchPartyParams(const SearchFilters(adults: 2, guestCount: 2)),
        {'p_adults': 2, 'p_children': 0, 'p_infants': 0, 'p_pets': 0},
      );
    });

    test('a child narrows', () {
      final params =
          searchPartyParams(const SearchFilters(adults: 1, children: 1));
      expect(params['p_children'], 1);
    });

    // Infants and pets are excluded from guestCount, so nothing else in the
    // request says they were asked for. Since 118 both genuinely filter —
    // infants against max_infants, pets against pets_allowed — so a non-zero
    // value has to travel or the search silently ignores what the guest chose.
    test('an infant narrows even though it is not a guest', () {
      final params = searchPartyParams(const SearchFilters(infants: 1));
      expect(params['p_infants'], 1);
      expect(params['p_adults'], 1, reason: 'the group travels together');
    });

    test('a pet narrows even though it is not a guest', () {
      final params = searchPartyParams(const SearchFilters(pets: 1));
      expect(params['p_pets'], 1);
    });

    // One predicate group in the SQL. A partial send would leave a stale value
    // from a previous argument list deciding part of the search.
    test('the four keys are all-or-nothing', () {
      final params = searchPartyParams(const SearchFilters(pets: 1));
      expect(
        params.keys.toSet(),
        {'p_adults', 'p_children', 'p_infants', 'p_pets'},
      );
    });
  });
}
