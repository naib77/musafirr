import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/listing.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/widgets/listing_price_map.dart';

/// The map itself needs a platform view, so these cover the two pure decisions
/// behind it: what a price pill says, and which listings may be plotted at all.
void main() {
  Listing listingOf({
    double lat = 23.8,
    double lng = 90.4,
    double? hourly,
    double? daily,
    double? monthly,
    String id = 'l1',
  }) {
    return Listing(
      id: id,
      ownerName: 'Host',
      title: 'A place',
      address: 'Road 1, Dhaka',
      type: ListingType.room,
      latitude: lat,
      longitude: lng,
      hourlyRate: hourly,
      dailyRate: daily,
      monthlyRate: monthly,
      facilities: const [],
      available: true,
    );
  }

  group('listingPriceLabel', () {
    test('shows the cheapest rate, compacted, with the taka sign', () {
      expect(listingPriceLabel(listingOf(hourly: 500, daily: 3000)), '৳500');
      expect(listingPriceLabel(listingOf(daily: 1500)), '৳1.5K');
      expect(listingPriceLabel(listingOf(monthly: 35000)), '৳35K');
    });

    test('never leaves the pill blank when a listing has no rate', () {
      expect(listingPriceLabel(listingOf()), '—');
    });
  });

  group('mappableListings', () {
    test('keeps listings with real coordinates', () {
      final list = [
        listingOf(id: 'a', lat: 23.8103, lng: 90.4125, hourly: 500),
        listingOf(id: 'b', lat: 22.3569, lng: 91.7832, daily: 1500),
      ];
      expect(mappableListings(list).map((l) => l.id), ['a', 'b']);
    });

    test('drops the (0,0) placeholder a host never pinned', () {
      // Left in, it plots in the Gulf of Guinea and stretches the camera
      // bounds across the planet.
      final list = [
        listingOf(id: 'pinned', lat: 23.8, lng: 90.4, hourly: 500),
        listingOf(id: 'unpinned', lat: 0, lng: 0, hourly: 500),
      ];
      expect(mappableListings(list).map((l) => l.id), ['pinned']);
    });

    test('drops out-of-range coordinates', () {
      final list = [
        listingOf(id: 'bad-lat', lat: 91.5, lng: 90.4),
        listingOf(id: 'bad-lng', lat: 23.8, lng: 181.2),
      ];
      expect(mappableListings(list), isEmpty);
    });
  });
}
