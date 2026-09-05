import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/geo_bounds.dart';
import 'package:musafir/models/landmark.dart';
import 'package:musafir/models/listing_purpose.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/models/search_filters.dart';
import 'package:musafir/widgets/search/search_commit.dart';
import 'package:musafir/widgets/search/search_draft.dart';

/// A draft seeded from nothing, then edited — the shape every panel produces.
SearchDraft draftOf(void Function(SearchDraft d) edit) {
  final draft = SearchDraft.from(const SearchFilters());
  edit(draft);
  return draft;
}

const _landmark = Landmark(
  id: 'l1',
  name: 'Dhaka Medical College',
  type: 'hospital',
  latitude: 23.72,
  longitude: 90.39,
);

void main() {
  group('guestCountFor', () {
    test('adults and children add up', () {
      expect(guestCountFor(adults: 2, children: 1), 3);
    });

    // Every travel site's convention, and the reason this is a function rather
    // than a sum written out at each call site.
    test('infants are not part of it at all', () {
      final draft = draftOf((d) {
        d.adults = 2;
        d.infants = 3;
      });
      expect(draft.guestCount, 2);
    });

    test('never drops below one', () {
      expect(guestCountFor(adults: 0, children: 0), 1);
    });

    // guestCount is compared against a listing's max_guests, so a party larger
    // than any listing could hold is not a search, it is an empty page.
    test('clamps at the search maximum', () {
      expect(guestCountFor(adults: 40, children: 40), maxSearchGuests);
    });
  });

  group('filtersFromDraft — dates', () {
    test('a range commits as check-in and check-out', () {
      final filters = filtersFromDraft(
        draftOf((d) => d.dateRange = DateTimeRange(
              start: DateTime(2026, 9, 12),
              end: DateTime(2026, 9, 15),
            )),
        const SearchFilters(),
      );
      expect(filters.dateMode, SearchDateMode.dateRange);
      expect(filters.checkIn, DateTime(2026, 9, 12));
      expect(filters.checkOut, DateTime(2026, 9, 15));
    });

    test('an hourly window commits as a date plus times', () {
      final filters = filtersFromDraft(
        draftOf((d) {
          d.dateMode = SearchDateMode.singleDateWithTime;
          d.singleDate = DateTime(2026, 9, 12);
          d.startTime = const TimeOfDay(hour: 14, minute: 0);
          d.endTime = const TimeOfDay(hour: 17, minute: 0);
        }),
        const SearchFilters(),
      );
      expect(filters.dateMode, SearchDateMode.singleDateWithTime);
      expect(filters.singleDate, DateTime(2026, 9, 12));
      expect(filters.startTime, const TimeOfDay(hour: 14, minute: 0));
      expect(filters.endTime, const TimeOfDay(hour: 17, minute: 0));
    });

    // This is the bug the wipe-then-set shape exists to prevent. Passing null
    // for the inactive mode's fields does NOT clear them — copyWith reads null
    // as "unchanged" — so a range picked after an hourly window used to leave
    // the stale singleDate behind, keeping hasActiveFilters true for a
    // selection no longer on screen.
    test('a range wipes a previously committed hourly window', () {
      final base = SearchFilters(
        dateMode: SearchDateMode.singleDateWithTime,
        singleDate: DateTime(2026, 8, 1),
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 11, minute: 0),
      );
      final filters = filtersFromDraft(
        draftOf((d) => d.dateRange = DateTimeRange(
              start: DateTime(2026, 9, 12),
              end: DateTime(2026, 9, 15),
            )),
        base,
      );
      expect(filters.singleDate, isNull);
      expect(filters.startTime, isNull);
      expect(filters.endTime, isNull);
    });

    test('an hourly window wipes a previously committed range', () {
      final base = SearchFilters(
        checkIn: DateTime(2026, 8, 1),
        checkOut: DateTime(2026, 8, 4),
      );
      final filters = filtersFromDraft(
        draftOf((d) {
          d.dateMode = SearchDateMode.singleDateWithTime;
          d.singleDate = DateTime(2026, 9, 12);
          d.startTime = const TimeOfDay(hour: 14, minute: 0);
          d.endTime = const TimeOfDay(hour: 17, minute: 0);
        }),
        base,
      );
      expect(filters.checkIn, isNull);
      expect(filters.checkOut, isNull);
    });

    test('choosing no dates clears the ones that were running', () {
      final base = SearchFilters(
        checkIn: DateTime(2026, 8, 1),
        checkOut: DateTime(2026, 8, 4),
      );
      final filters = filtersFromDraft(draftOf((_) {}), base);
      expect(filters.checkIn, isNull);
      expect(filters.checkOut, isNull);
      expect(filters.hasDateSelection, isFalse);
    });

    // Half a range is not a window — searchDateWindowFor drops it, and the RPC
    // would refuse it — so it must not commit as one.
    test('half a range does not become a date selection', () {
      final filters = filtersFromDraft(
        draftOf((d) => d.singleDate = DateTime(2026, 9, 12)),
        const SearchFilters(),
      );
      expect(filters.hasDateSelection, isFalse);
    });
  });

  group('filtersFromDraft — where', () {
    test('a typed place with no resolved point commits as text', () {
      final filters = filtersFromDraft(
        draftOf((d) => d.locationText = 'Uttara'),
        const SearchFilters(),
      );
      expect(filters.location, 'Uttara');
      expect(filters.latitude, isNull);
      expect(filters.longitude, isNull);
    });

    test('whitespace is trimmed off the committed text', () {
      final filters = filtersFromDraft(
        draftOf((d) => d.locationText = '  Uttara  '),
        const SearchFilters(),
      );
      expect(filters.location, 'Uttara');
    });

    test('a resolved point commits with its coordinates', () {
      final filters = filtersFromDraft(
        draftOf((d) => d.setResolvedPlace(
              text: 'Uttara, Dhaka',
              latitude: 23.87,
              longitude: 90.39,
            )),
        const SearchFilters(),
      );
      expect(filters.latitude, 23.87);
      expect(filters.longitude, 90.39);
    });

    // A place's box is independent of its centre — a city resolves to a box
    // with no point at all — so clearing coordinates must not take it with it.
    test('a box survives a resolve that produced no point', () {
      const box = GeoBounds(swLat: 23.7, swLng: 90.3, neLat: 23.9, neLng: 90.5);
      final filters = filtersFromDraft(
        draftOf((d) => d.setResolvedPlace(text: 'Dhaka', bounds: box)),
        const SearchFilters(),
      );
      expect(filters.bounds, box);
      expect(filters.latitude, isNull);
    });

    test('a stale box does not survive a place that has none', () {
      const box = GeoBounds(swLat: 23.7, swLng: 90.3, neLat: 23.9, neLng: 90.5);
      const base = SearchFilters(location: 'Dhaka', bounds: box);
      final filters = filtersFromDraft(
        draftOf((d) => d.setResolvedPlace(
              text: 'Some Lane',
              latitude: 23.8,
              longitude: 90.4,
            )),
        base,
      );
      expect(filters.bounds, isNull);
    });

    test('a landmark search drops the place box', () {
      const box = GeoBounds(swLat: 23.7, swLng: 90.3, neLat: 23.9, neLng: 90.5);
      final filters = filtersFromDraft(
        draftOf((d) {
          d.setResolvedPlace(text: 'Dhaka', bounds: box);
          d.landmark = _landmark;
        }),
        const SearchFilters(),
      );
      expect(filters.bounds, isNull);
      expect(filters.landmark, _landmark);
    });

    test('emptying the field clears text, point and box together', () {
      const base = SearchFilters(
        location: 'Dhaka',
        latitude: 23.8,
        longitude: 90.4,
        bounds: GeoBounds(swLat: 23.7, swLng: 90.3, neLat: 23.9, neLng: 90.5),
      );
      final filters = filtersFromDraft(draftOf((_) {}), base);
      expect(filters.location, isNull);
      expect(filters.latitude, isNull);
      expect(filters.longitude, isNull);
      expect(filters.bounds, isNull);
    });

    // Typing over a picked prediction must invalidate its coordinates, or the
    // search runs the new name at the old place — the point wins downstream.
    test('editing the text after picking a place drops the point', () {
      final filters = filtersFromDraft(
        draftOf((d) {
          d.setResolvedPlace(text: 'Uttara', latitude: 23.87, longitude: 90.39);
          d.setLocationText('Mirpur');
        }),
        const SearchFilters(),
      );
      expect(filters.location, 'Mirpur');
      expect(filters.latitude, isNull);
      expect(filters.longitude, isNull);
    });
  });

  group('filtersFromDraft — who, type and purpose', () {
    test('the breakdown and the derived count both commit', () {
      final filters = filtersFromDraft(
        draftOf((d) {
          d.adults = 2;
          d.children = 1;
          d.infants = 1;
        }),
        const SearchFilters(),
      );
      expect(filters.adults, 2);
      expect(filters.children, 1);
      expect(filters.infants, 1);
      expect(filters.guestCount, 3); // infants excluded
    });

    test('a purpose commits as the single-element list the RPC takes', () {
      final filters = filtersFromDraft(
        draftOf((d) => d.purpose = ListingPurpose.medical),
        const SearchFilters(),
      );
      expect(filters.purposeTags, [ListingPurpose.medical]);
    });

    test('dropping the purpose empties the list', () {
      const base = SearchFilters(purposeTags: [ListingPurpose.medical]);
      final filters = filtersFromDraft(draftOf((_) {}), base);
      expect(filters.purposeTags, isEmpty);
    });

    test('dropping the landmark clears it', () {
      final base = const SearchFilters().copyWith(landmark: _landmark);
      final filters = filtersFromDraft(draftOf((_) {}), base);
      expect(filters.landmark, isNull);
    });

    test('property types commit', () {
      final filters = filtersFromDraft(
        draftOf((d) => d.propertyTypes = [ListingType.room]),
        const SearchFilters(),
      );
      expect(filters.propertyTypes, [ListingType.room]);
    });
  });

  // The whole reason this layers over `base` with copyWith: fields no panel
  // edits must not be dropped the first time someone builds a UI for them.
  group('filtersFromDraft — fields no panel owns', () {
    test('price and amenities survive a commit', () {
      const base = SearchFilters(
        minPrice: 500,
        maxPrice: 2500,
        amenities: ['wifi'],
      );
      final filters = filtersFromDraft(
        draftOf((d) => d.locationText = 'Uttara'),
        base,
      );
      expect(filters.minPrice, 500);
      expect(filters.maxPrice, 2500);
      expect(filters.amenities, ['wifi']);
    });
  });

  group('a draft seeded from live filters', () {
    test('round-trips an untouched search unchanged', () {
      final base = SearchFilters(
        location: 'Uttara, Dhaka',
        latitude: 23.87,
        longitude: 90.39,
        checkIn: DateTime(2026, 9, 12),
        checkOut: DateTime(2026, 9, 15),
        guestCount: 3,
        adults: 2,
        children: 1,
        infants: 1,
        propertyTypes: const [ListingType.room],
        purposeTags: const [ListingPurpose.medical],
      );
      final filters = filtersFromDraft(SearchDraft.from(base), base);

      expect(filters.location, base.location);
      expect(filters.latitude, base.latitude);
      expect(filters.checkIn, base.checkIn);
      expect(filters.checkOut, base.checkOut);
      expect(filters.guestCount, 3);
      expect(filters.adults, 2);
      expect(filters.children, 1);
      expect(filters.infants, 1);
      expect(filters.propertyTypes, base.propertyTypes);
      expect(filters.purposeTags, base.purposeTags);
    });

    test('an untouched empty search stays inactive', () {
      final filters = filtersFromDraft(
          SearchDraft.from(const SearchFilters()), const SearchFilters());
      expect(filters.hasActiveFilters, isFalse);
    });

    test('hasAnyInput agrees with hasActiveFilters about a party of one', () {
      final draft = draftOf((d) => d.adults = 1);
      expect(draft.hasAnyInput, isFalse);
      expect(
        filtersFromDraft(draft, const SearchFilters()).hasActiveFilters,
        isFalse,
      );
    });

    // Infants alone do not narrow anything, so they must not make a search
    // look active — the bar would offer a ✕ that clears nothing visible.
    test('infants alone are not an active search', () {
      final draft = draftOf((d) => d.infants = 2);
      expect(draft.hasAnyInput, isFalse);
      expect(
        filtersFromDraft(draft, const SearchFilters()).hasActiveFilters,
        isFalse,
      );
    });
  });
}
