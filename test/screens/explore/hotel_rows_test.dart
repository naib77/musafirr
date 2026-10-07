import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/listing.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/screens/explore/hotel_rows.dart';

Listing _l(String id,
        {String? propertyId,
        double rate = 3000,
        double? rating,
        DateTime? createdAt}) =>
    Listing(
      id: id,
      ownerName: 'Host',
      title: id,
      address: 'Kola Toli',
      type: propertyId == null ? ListingType.fullHouse : ListingType.hotel,
      latitude: 21.4,
      longitude: 91.9,
      facilities: const [],
      available: true,
      dailyRate: rate,
      rating: rating,
      createdAt: createdAt,
      propertyId: propertyId,
    );

List<String> _ids(CuratedRow row) => row.items.map((l) => l.id).toList();

void main() {
  test('no hotels, no hotel rows', () {
    expect(hotelRows([_l('flat'), _l('room')]), isEmpty);
  });

  test('only hotels, each row in its own order', () {
    final rows = hotelRows([
      _l('flat', rate: 100, rating: 5, createdAt: DateTime(2026, 10, 6)),
      _l('a', propertyId: 'p1', rate: 5000, createdAt: DateTime(2026, 9, 1)),
      _l('b',
          propertyId: 'p2',
          rate: 2000,
          rating: 4.2,
          createdAt: DateTime(2026, 10, 1)),
      _l('c', propertyId: 'p3', rate: 3500, rating: 4.8),
    ]);

    expect(rows.map((r) => r.title), [
      'Newly available hotels',
      'Budget-friendly hotels',
      'Top rated hotels',
    ]);
    expect(_ids(rows[0]), ['b', 'a']); // c has no created_at
    expect(_ids(rows[1]), ['b', 'c', 'a']);
    expect(_ids(rows[2]), ['c', 'b']); // a is unrated
  });

  test('an empty row is dropped, not shown as a bare heading', () {
    final rows = hotelRows([
      _l('a', propertyId: 'p1', createdAt: DateTime(2026, 9, 1)),
    ]);
    expect(rows.map((r) => r.title),
        ['Newly available hotels', 'Budget-friendly hotels']);
  });
}
