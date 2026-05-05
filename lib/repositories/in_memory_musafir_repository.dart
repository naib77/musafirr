import 'package:flutter/foundation.dart';

import '../data/facility_catalog.dart';
import '../models/booking.dart';
import '../models/booking_duration.dart';
import '../models/listing.dart';
import '../models/listing_type.dart';
import '../models/owner_registration_draft.dart';
import 'musafir_repository.dart';

class InMemoryMusafirRepository extends ChangeNotifier
    implements MusafirRepository {
  InMemoryMusafirRepository() {
    _seed();
  }

  final List<Listing> _listings = [];
  final List<Booking> _bookings = [];

  @override
  List<Listing> get listings => List.unmodifiable(_listings);

  @override
  List<Booking> get bookings => List.unmodifiable(_bookings);

  @override
  int get availableCount => _listings.where((item) => item.available).length;

  @override
  int get ownerCount => _listings.map((item) => item.ownerName).toSet().length;

  @override
  List<Listing> searchByArea({
    required double centerLat,
    required double centerLng,
    required double delta,
  }) {
    return _listings.where((listing) {
      final insideLat = (listing.latitude - centerLat).abs() <= delta;
      final insideLng = (listing.longitude - centerLng).abs() <= delta;
      return listing.available && insideLat && insideLng;
    }).toList();
  }

  @override
  void registerOwnerListing(OwnerRegistrationDraft draft) {
    _listings.add(
      Listing(
        id: 'listing_${_listings.length + 1}',
        ownerName: draft.mobile,
        title: draft.title,
        address: draft.address,
        type: draft.type,
        latitude: draft.latitude,
        longitude: draft.longitude,
        hourlyRate: draft.hourlyRate,
        dailyRate: draft.dailyRate,
        monthlyRate: draft.monthlyRate,
        facilities: draft.facilities,
        available: true,
      ),
    );
    notifyListeners();
  }

  @override
  Booking createBooking({
    required Listing listing,
    required String tenantName,
    required BookingDuration duration,
  }) {
    final now = DateTime.now();
    final endAt = switch (duration.unitLabel) {
      'hour' => now.add(Duration(hours: duration.multiplier)),
      'day' => now.add(Duration(days: duration.multiplier)),
      _ => DateTime(
          now.year,
          now.month + duration.multiplier,
          now.day,
          now.hour,
          now.minute,
        ),
    };
    final unitRate = switch (duration.unitLabel) {
      'hour' => listing.hourlyRate,
      'day' => listing.dailyRate,
      _ => listing.monthlyRate,
    };
    final booking = Booking(
      id: 'booking_${_bookings.length + 1}',
      listingId: listing.id,
      tenantName: tenantName,
      startAt: now,
      endAt: endAt,
      totalPrice: unitRate * duration.multiplier,
      unitLabel: duration.unitLabel,
    );
    _bookings.add(booking);
    listing.available = false;
    notifyListeners();
    return booking;
  }

  void _seed() {
    _listings.addAll([
      Listing(
        id: 'listing_1',
        ownerName: 'Owner 01710000001',
        title: 'Family Room in Dhanmondi',
        address: 'Dhanmondi, Dhaka',
        type: ListingType.room,
        latitude: 23.7465,
        longitude: 90.3760,
        hourlyRate: 150,
        dailyRate: 1200,
        monthlyRate: 22000,
        facilities: const [
          FacilityCatalog.wifi,
          FacilityCatalog.ac,
          FacilityCatalog.bath,
        ],
        available: true,
      ),
      Listing(
        id: 'listing_2',
        ownerName: 'Owner 01710000002',
        title: 'Budget Seat near Uttara',
        address: 'Uttara, Dhaka',
        type: ListingType.seat,
        latitude: 23.8759,
        longitude: 90.3795,
        hourlyRate: 60,
        dailyRate: 450,
        monthlyRate: 9000,
        facilities: const [
          FacilityCatalog.wifi,
          FacilityCatalog.bath,
        ],
        available: true,
      ),
      Listing(
        id: 'listing_3',
        ownerName: 'Owner 01710000003',
        title: 'Full House for Small Team',
        address: 'Mirpur DOHS, Dhaka',
        type: ListingType.fullHouse,
        latitude: 23.8223,
        longitude: 90.3654,
        hourlyRate: 350,
        dailyRate: 3000,
        monthlyRate: 52000,
        facilities: const [
          FacilityCatalog.wifi,
          FacilityCatalog.ac,
          FacilityCatalog.bath,
          FacilityCatalog.kitchen,
          FacilityCatalog.parking,
        ],
        available: true,
      ),
    ]);
  }
}
