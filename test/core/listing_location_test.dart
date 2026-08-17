import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/core/privacy/listing_location.dart';
import 'package:musafir/models/listing.dart';
import 'package:musafir/models/listing_exact_address.dart';
import 'package:musafir/models/listing_type.dart';

/// A host's exact address names their front door, so `public.listings` no longer
/// carries one: migration 093 moved the house/flat/road parts and the precise
/// coordinates into `public.listing_addresses` behind RLS, and a trigger keeps
/// the listing itself area-level.
///
/// **The entitlement rule (who gets the address) is enforced in SQL and tested
/// there** — see `supabase/tests/093_listing_address_privacy_test.sql`. What is
/// tested here is the client's half: that it renders whatever the server allowed
/// without inventing precision, and that it fails closed when the server says
/// nothing.
void main() {
  Listing listingOf({
    String? area = 'Uttara',
    String? city = 'Dhaka',
    String address = 'Uttara, Dhaka',
    double latitude = 23.87361,
    double longitude = 90.40194,
  }) {
    return Listing(
      id: 'l-1',
      ownerName: 'Host',
      hostId: 'host-1',
      title: 'A place',
      // What the server actually sends now: the area-level line.
      address: address,
      type: ListingType.room,
      latitude: latitude,
      longitude: longitude,
      hourlyRate: 150,
      facilities: const [],
      available: true,
      area: area,
      city: city,
    );
  }

  const disclosed = ListingExactAddress(
    listingId: 'l-1',
    houseNo: 'house 14',
    flatFloor: 'E-6',
    street: 'Road 12B',
    address: 'house 14, E-6, Road 12B, Uttara, Dhaka',
    latitude: 23.873612,
    longitude: 90.401937,
  );

  group('what the area-level address reduces to', () {
    test('the house, flat and road are dropped; area and city remain', () {
      expect(listingOf().approximateAddress, 'Uttara, Dhaka');
    });

    test('no area saved falls back to the city, not the full line', () {
      final listing = listingOf(area: null, address: 'Dhaka');
      expect(listing.approximateAddress, 'Dhaka');
    });

    test('no structured parts at all never leaks the composed line', () {
      // Rows written before the structured columns existed: we can't tell which
      // segment is the house number, so nothing specific may be shown. The
      // server's trigger leaves `address` null for these; the client must not
      // fall back to it either.
      final listing = Listing(
        id: 'l-2',
        ownerName: 'Host',
        title: 'A place',
        address: 'house 9, Road 4, Banani, Dhaka',
        type: ListingType.room,
        latitude: 23.79,
        longitude: 90.40,
        hourlyRate: 150,
        facilities: const [],
        available: true,
      );

      expect(listing.approximateAddress, 'Approximate location');
      expect(listing.approximateAddress, isNot(contains('Road 4')));
    });
  });

  group('the client fails closed', () {
    test('no answer from the server means the area', () {
      // Covers both "request still in flight" and "RLS declined" — they are
      // deliberately the same value, so there is no state in which the UI
      // promises precision it does not have.
      final location = ListingLocation.forListing(listingOf(), null);

      expect(location.isExact, isFalse);
      expect(location.label, 'Uttara, Dhaka');
      expect(location.disclosure, isNotNull);
      expect(location.radiusMeters, ListingLocation.approximateRadiusMeters);
    });

    test('a disclosure row with nothing in it is still the area', () {
      // A listing whose host never entered an address yields a row that carries
      // no more than the listing already shows. Treating it as "exact" would
      // swap the circle for a pin and enable directions on nothing.
      const hollow = ListingExactAddress(listingId: 'l-1');
      final location = ListingLocation.forListing(listingOf(), hollow);

      expect(location.isExact, isFalse);
      expect(location.radiusMeters, ListingLocation.approximateRadiusMeters);
    });

    test('a real disclosure is shown in full', () {
      final location = ListingLocation.forListing(listingOf(), disclosed);

      expect(location.isExact, isTrue);
      expect(location.label, 'house 14, E-6, Road 12B, Uttara, Dhaka');
      expect(location.disclosure, isNull);
      expect(location.radiusMeters, isNull);
      // The server's precise point, NOT the listing's snapped one.
      expect(location.latitude, 23.873612);
      expect(location.longitude, 90.401937);
    });

    test("a disclosure with no coordinates falls back to the listing's point",
        () {
      // A host who typed an address but never dropped a pin. The listing's own
      // coordinates are what's left, and from the server those are already
      // snapped — so this is a slightly coarse pin, never a wrong one.
      const noCoords = ListingExactAddress(
        listingId: 'l-1',
        street: 'Road 12B',
        address: 'Road 12B, Uttara, Dhaka',
      );
      final listing = listingOf(latitude: 23.874, longitude: 90.402);
      final location = ListingLocation.forListing(listing, noCoords);

      expect(location.isExact, isTrue);
      expect(location.latitude, listing.latitude);
      expect(location.longitude, listing.longitude);
    });

    test('a disclosure with only parts composes a line from the listing', () {
      const partsOnly = ListingExactAddress(
        listingId: 'l-1',
        houseNo: 'house 14',
        street: 'Road 12B',
      );
      final location = ListingLocation.forListing(listingOf(), partsOnly);

      expect(location.label, 'house 14, Road 12B, Uttara, Dhaka');
    });
  });

  group('the coordinates handed to the map', () {
    test('the grid matches the one migration 093 snaps to', () {
      // If these drift apart the app draws its circle centred somewhere the
      // server never intended. snap_coordinate() in 093 divides by this value.
      expect(ListingLocation.gridDegrees, 0.001);
    });

    test('the true point stays well inside the circle', () {
      // Worst case is half a cell on each axis. At Dhaka's latitude that is
      // ~78m diagonally, against a 300m radius.
      final listing = listingOf(latitude: 23.8735, longitude: 90.4019);
      final location = ListingLocation.approximate(listing);

      expect((location.latitude - listing.latitude).abs(),
          lessThanOrEqualTo(ListingLocation.gridDegrees / 2 + 1e-9));
      expect((location.longitude - listing.longitude).abs(),
          lessThanOrEqualTo(ListingLocation.gridDegrees / 2 + 1e-9));
    });

    test('snapping an already-snapped point changes nothing', () {
      // The server sends snapped coordinates, and the maps snap again on the way
      // to a marker. That second pass must be a no-op or pins would creep.
      final once = ListingLocation.snapCoordinate(23.87361);
      expect(ListingLocation.snapCoordinate(once), once);
    });

    test('the centre is stable across repeated reads', () {
      // Not random jitter: a fresh offset per read could be averaged over many
      // samples to recover the true point. A fixed grid gives the same answer
      // every time and reveals nothing beyond which cell the listing is in.
      final listing = listingOf();
      expect(ListingLocation.approximate(listing).latitude,
          ListingLocation.approximate(listing).latitude);
    });

    test('neighbours on the same block share a centre', () {
      // Which of them is which stays unknowable — that is the point.
      final a = ListingLocation.approximate(listingOf());
      final b = ListingLocation.approximate(
        listingOf(latitude: 23.87363, longitude: 90.40196),
      );

      expect(a.latitude, b.latitude);
      expect(a.longitude, b.longitude);
    });
  });
}
