import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/data/facility_catalog.dart';
import 'package:musafir/models/facility.dart';
import 'package:musafir/models/listing.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/models/property.dart';
import 'package:musafir/repositories/musafir_repository.dart';
import 'package:musafir/screens/explore/hotel_screen.dart';
import 'package:musafir/screens/explore/listing_detail_screen.dart';
import 'package:musafir/screens/explore/listing_route.dart';
import 'package:musafir/state/auth_state.dart';
import 'package:musafir/state/favorites_state.dart';

/// Search returns a hotel once, as one of its room types (154). Whatever led
/// to that row -- a card, a pin, a saved place, an old link -- must open the
/// hotel with all its types, never the one room type on its own.
class _FakeRepo extends ChangeNotifier implements MusafirRepository {
  _FakeRepo(this._types);
  final List<Listing> _types;

  @override
  Future<Property?> fetchProperty(String propertyId) async => const Property(
        id: 'p1',
        ownerId: 'h1',
        name: 'Hotel Sea Crown',
        area: 'Kola Toli',
        city: "Cox's Bazar",
        facilities: [FacilityCatalog.gym, FacilityCatalog.restaurant],
      );

  @override
  Future<List<Listing>> propertyRoomTypes(String propertyId) async => _types;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeAuth extends ChangeNotifier implements AuthStateNotifier {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeFavorites extends ChangeNotifier implements FavoritesStateNotifier {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Listing _type(String id, String title,
        {String? propertyId = 'p1',
        bool hostAvailable = true,
        List<Facility> facilities = const []}) =>
    Listing(
      id: id,
      ownerName: 'Host',
      title: title,
      address: 'Kola Toli',
      type: ListingType.hotel,
      latitude: 21.4,
      longitude: 91.9,
      facilities: facilities,
      available: true,
      hostAvailable: hostAvailable,
      hostId: 'h1',
      dailyRate: 3000,
      propertyId: propertyId,
    );

Future<void> _pump(WidgetTester tester, Listing tapped, List<Listing> types) =>
    tester.pumpWidget(MaterialApp(
      home: ListingRoute(
        listingId: tapped.id,
        listing: tapped,
        repository: _FakeRepo(types),
        authState: _FakeAuth(),
        favoritesState: _FakeFavorites(),
      ),
    ));

void main() {
  testWidgets('a room type opens its hotel, with every bookable type',
      (tester) async {
    final types = [
      _type('t1', 'Deluxe'),
      _type('t2', 'Super Deluxe'),
      // Paused by the host: search would not offer it, so neither does this.
      _type('t3', 'Sea Front', hostAvailable: false),
    ];
    await _pump(tester, types[0], types);
    await tester.pumpAndSettle();

    expect(find.byType(HotelScreen), findsOneWidget);
    expect(find.byType(ListingDetailScreen), findsNothing);
    expect(find.text('Hotel Sea Crown'), findsWidgets);
    expect(find.text('Choose from 2 room types'), findsOneWidget);
    expect(find.text('Deluxe'), findsOneWidget);
    expect(find.text('Super Deluxe'), findsOneWidget);
    expect(find.text('Sea Front'), findsNothing);
  });

  testWidgets('hotel amenities show once; a room type shows only its own',
      (tester) async {
    // As 155 stores them: the hotel's gym and restaurant are copied onto
    // the room type, next to the kettle that is its own.
    final types = [
      _type('t1', 'Deluxe', facilities: const [
        FacilityCatalog.gym,
        FacilityCatalog.restaurant,
        FacilityCatalog.kettle,
        FacilityCatalog.wifi,
      ]),
    ];
    await _pump(tester, types[0], types);
    await tester.pumpAndSettle();

    expect(find.text('Hotel amenities'), findsOneWidget);
    expect(find.text('Gym'), findsOneWidget);
    expect(find.text('Restaurant'), findsOneWidget);
    expect(find.text('Wi-Fi · Kettle'), findsNothing);
    expect(find.text('Kettle · Wi-Fi'), findsOneWidget);
  });

  test('the room and hotel halves of the hotel catalog do not overlap', () {
    final room = {
      for (final g in FacilityCatalog.hotelRoomGroups)
        for (final f in g.facilities) f.name,
    };
    expect(room.intersection(FacilityCatalog.hotelPropertyNames), isEmpty);
    expect(FacilityCatalog.groupsFor(ListingType.hotel, inHotel: true),
        FacilityCatalog.hotelRoomGroups);
  });

  test('a search row is titled by its hotel, other listings by their own', () {
    final row = _type('t1', 'Deluxe')
        .copyWith(propertyName: 'Hotel Sea Crown', roomTypesMatching: 3);
    expect(row.cardTitle, 'Hotel Sea Crown');
    expect(row.isHotelRoomType, isTrue);
    final flat = _type('f1', 'Flat in Dhanmondi', propertyId: null);
    expect(flat.cardTitle, 'Flat in Dhanmondi');
    expect(flat.isHotelRoomType, isFalse);
  });
}
