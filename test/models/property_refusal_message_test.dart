import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/property.dart';

/// 156's delete refusals are told apart by hint, never by message text
/// (database-booking-and-search.md). A hint that falls through to the
/// generic "Could not save" would tell a host nothing about why a delete
/// was refused, so each one is pinned here.
void main() {
  const generic = 'Could not save. Please try again.';

  test('every 156 delete hint has its own wording', () {
    for (final hint in [
      'listing_has_bookings',
      'property_has_bookings',
      'listing_has_history',
      'property_has_history',
      'property_not_found',
      'not_a_room_type',
    ]) {
      expect(propertyRefusalMessage(hint), isNot(generic), reason: hint);
    }
  });

  test('paid history points the host at hiding instead', () {
    expect(propertyRefusalMessage('property_has_history'), contains('Hide'));
    expect(propertyRefusalMessage('listing_has_history'), contains('Hide'));
  });

  test('an unknown or missing hint is the generic message', () {
    expect(propertyRefusalMessage(null), generic);
    expect(propertyRefusalMessage('something_new'), generic);
  });
}
