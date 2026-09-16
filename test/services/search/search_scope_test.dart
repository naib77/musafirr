import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/landmark.dart';
import 'package:musafir/models/listing_purpose.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/services/search/search_scope.dart';

/// Turf arrived as a `ListingType`, purpose is a separate dimension, and the
/// one-tap Turf pill is the place the two meet. `search_listings` ANDs its
/// predicates and `purpose_tags` is a column on stays — a turf carries none —
/// so "turf near a hospital" returns zero rows without raising, and the guest
/// cannot tell that apart from "there are no turfs here".
void main() {
  final hospital = Landmark(
    id: 'lm1',
    name: 'Uttara Adhunik Hospital',
    type: 'hospital',
    latitude: 23.87,
    longitude: 90.38,
  );

  group('picking a scope', () {
    test('turf becomes the only type', () {
      final next = applyScope(
        SearchScope.turf,
        types: [ListingType.room, ListingType.seat],
        purpose: null,
        landmark: null,
      );

      expect(next.types, [ListingType.turf]);
    });

    test('turf drops a purpose and its landmark', () {
      final next = applyScope(
        SearchScope.turf,
        types: const [],
        purpose: ListingPurpose.medical,
        landmark: hospital,
      );

      expect(next.purpose, isNull);
      expect(next.landmark, isNull);
    });

    test('Anything removes turf and nothing else', () {
      final next = applyScope(
        SearchScope.any,
        types: [ListingType.turf, ListingType.room],
        purpose: ListingPurpose.exam,
        landmark: null,
      );

      // A guest who narrowed to Room and then tapped Anything is saying "not
      // just turf", not "forget what I picked".
      expect(next.types, [ListingType.room]);
      expect(next.purpose, ListingPurpose.exam);
    });

    test('Anything on an already-empty search stays empty', () {
      final next = applyScope(
        SearchScope.any,
        types: const [],
        purpose: null,
        landmark: null,
      );

      expect(next.types, isEmpty);
    });
  });

  group('which pill reads as selected', () {
    test('turf alone is the turf scope', () {
      expect(scopeOf([ListingType.turf]), SearchScope.turf);
    });

    test('turf beside another type is not', () {
      // "Rooms and turfs" is a real search the Filters panel can express, and
      // it is neither of the two scopes this control offers. Lighting up Turf
      // for it would make the next tap silently drop the room.
      expect(scopeOf([ListingType.turf, ListingType.room]), SearchScope.any);
    });

    test('no type at all is Anything', () {
      expect(scopeOf(const []), SearchScope.any);
    });

    test('stays only are Anything', () {
      expect(scopeOf([ListingType.room]), SearchScope.any);
    });
  });

  group('picking a purpose, the other direction', () {
    test('drops turf', () {
      expect(
        typesForPurpose(ListingPurpose.medical, [ListingType.turf]),
        isEmpty,
      );
    });

    test('leaves stay types alone', () {
      expect(
        typesForPurpose(
          ListingPurpose.medical,
          [ListingType.room, ListingType.turf],
        ),
        [ListingType.room],
      );
    });

    test('clearing the purpose conflicts with nothing', () {
      // "Any purpose" is not a purpose, so it must not quietly widen a search
      // the guest deliberately narrowed to turf.
      expect(typesForPurpose(null, [ListingType.turf]), [ListingType.turf]);
    });
  });

  group('the pair cannot produce the unmatchable search', () {
    test('no ordering of the two leaves turf and a purpose together', () {
      // Turf then Medical.
      var types = applyScope(
        SearchScope.turf,
        types: const [],
        purpose: null,
        landmark: null,
      ).types;
      types = typesForPurpose(ListingPurpose.medical, types);
      expect(types.contains(ListingType.turf), isFalse);

      // Medical then Turf.
      final next = applyScope(
        SearchScope.turf,
        types: const [],
        purpose: ListingPurpose.medical,
        landmark: hospital,
      );
      expect(next.types, [ListingType.turf]);
      expect(next.purpose, isNull);
    });
  });
}
