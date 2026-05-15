import 'package:flutter/foundation.dart';

import '../data/mock_data.dart';
import '../models/booking.dart';
import '../models/booking_conflict_exception.dart';
import '../models/booking_duration.dart';
import '../models/booking_status.dart';
import '../models/listing.dart';
import '../models/owner_registration_draft.dart';
import '../models/review.dart';
import '../models/search_filters.dart';
import '../models/user.dart';
import 'musafir_repository.dart';

class InMemoryMusafirRepository extends ChangeNotifier
    implements MusafirRepository {
  InMemoryMusafirRepository() {
    _seed();
  }

  final List<Listing> _listings = [];
  final List<Booking> _bookings = [];
  final List<Review> _reviews = [];
  final Map<String, User> _users = {};

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

  // New marketplace methods

  @override
  User? getUserById(String id) {
    return _users[id];
  }

  @override
  User? getUserByEmail(String email) {
    return _users.values
        .where((u) => u.email?.toLowerCase() == email.toLowerCase())
        .firstOrNull;
  }

  @override
  void addUser(User user) {
    _users[user.id] = user;
    notifyListeners();
  }

  @override
  Listing? getListingById(String id) {
    return _listings.where((l) => l.id == id).firstOrNull;
  }

  @override
  List<Listing> searchListings(SearchFilters filters) {
    return _listings.where((listing) {
      if (!listing.available) return false;

      // Filter by property type
      if (filters.propertyTypes.isNotEmpty &&
          !filters.propertyTypes.contains(listing.type)) {
        return false;
      }

      // Filter by guest count
      if (listing.maxGuests < filters.guestCount) {
        return false;
      }

      // Filter by price range
      final price = listing.displayPrice;
      if (filters.minPrice != null && price < filters.minPrice!) {
        return false;
      }
      if (filters.maxPrice != null && price > filters.maxPrice!) {
        return false;
      }

      // Filter by amenities
      if (filters.amenities.isNotEmpty) {
        final listingAmenities = listing.amenityNames;
        for (final amenity in filters.amenities) {
          if (!listingAmenities.contains(amenity)) {
            return false;
          }
        }
      }

      // Filter by location (simple text match)
      if (filters.location != null && filters.location!.isNotEmpty) {
        final searchLower = filters.location!.toLowerCase();
        final matchesCity =
            listing.city?.toLowerCase().contains(searchLower) ?? false;
        final matchesAddress =
            listing.address.toLowerCase().contains(searchLower);
        final matchesTitle = listing.title.toLowerCase().contains(searchLower);
        if (!matchesCity && !matchesAddress && !matchesTitle) {
          return false;
        }
      }

      return true;
    }).toList()
      ..sort((a, b) {
        final ratingA = a.rating ?? 0;
        final ratingB = b.rating ?? 0;
        if (ratingA != ratingB) {
          return ratingB.compareTo(ratingA);
        }
        return b.reviewCount.compareTo(a.reviewCount);
      });
  }

  @override
  List<Listing> getFeaturedListings({int limit = 10}) {
    final available = _listings.where((l) => l.available).toList()
      ..sort((a, b) {
        // Sort by rating first, then by review count
        final ratingA = a.rating ?? 0;
        final ratingB = b.rating ?? 0;
        if (ratingA != ratingB) {
          return ratingB.compareTo(ratingA);
        }
        return b.reviewCount.compareTo(a.reviewCount);
      });
    return available.take(limit).toList();
  }

  @override
  List<Listing> getListingsByHost(String hostId) {
    return _listings.where((l) => l.hostId == hostId).toList();
  }

  @override
  void addListing(Listing listing) {
    _listings.add(listing);
    notifyListeners();
  }

  @override
  void updateListing(Listing listing) {
    final index = _listings.indexWhere((l) => l.id == listing.id);
    if (index != -1) {
      _listings[index] = listing;
      notifyListeners();
    }
  }

  @override
  void deleteListing(String listingId) {
    _listings.removeWhere((l) => l.id == listingId);
    notifyListeners();
  }

  @override
  List<Review> getReviewsForListing(String listingId) {
    return _reviews.where((r) => r.listingId == listingId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  void addReview(Review review) {
    _reviews.add(review);
    // Update listing rating
    final listing = getListingById(review.listingId);
    if (listing != null) {
      final reviews = getReviewsForListing(review.listingId);
      final avgRating =
          reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;
      final index = _listings.indexOf(listing);
      _listings[index] = listing.copyWith(
        rating: avgRating,
        reviewCount: reviews.length,
      );
    }
    notifyListeners();
  }

  @override
  double getAverageRating(String listingId) {
    final reviews = getReviewsForListing(listingId);
    if (reviews.isEmpty) return 0;
    return reviews.map((r) => r.rating).reduce((a, b) => a + b) /
        reviews.length;
  }

  @override
  List<Booking> getBookingsForUser(String userId) {
    return _bookings.where((b) => b.userId == userId).toList()
      ..sort((a, b) => b.effectiveCheckIn.compareTo(a.effectiveCheckIn));
  }

  @override
  List<Booking> getUpcomingBookings(String userId) {
    final now = DateTime.now();
    return _bookings
        .where((b) =>
            b.userId == userId &&
            b.status.isActive &&
            b.effectiveCheckIn.isAfter(now))
        .toList()
      ..sort((a, b) => a.effectiveCheckIn.compareTo(b.effectiveCheckIn));
  }

  @override
  List<Booking> getPastBookings(String userId) {
    final now = DateTime.now();
    return _bookings
        .where((b) =>
            b.userId == userId &&
            (b.status.isPast || b.effectiveCheckOut.isBefore(now)))
        .toList()
      ..sort((a, b) => b.effectiveCheckIn.compareTo(a.effectiveCheckIn));
  }

  @override
  Booking? getBookingById(String id) {
    return _bookings.where((b) => b.id == id).firstOrNull;
  }

  @override
  Booking createMarketplaceBooking({
    required String listingId,
    required String userId,
    required String userName,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guestCount,
    required double totalPrice,
    required String unitLabel,
  }) {
    final listing = getListingById(listingId);
    if (listing == null) {
      throw Exception('Listing not found');
    }

    // Check for listing conflicts (same seat/room can't be double-booked)
    final listingConflicts = getConflictingBookings(
      listingId: listingId,
      checkIn: checkIn,
      checkOut: checkOut,
    );
    if (listingConflicts.isNotEmpty) {
      throw BookingConflictException(
        'This time slot is already booked by another user',
        conflictType: ConflictType.listing,
        conflictingBookings: listingConflicts,
      );
    }

    // Check for user conflicts (same user can't book multiple places at same time)
    final userConflicts = getUserConflictingBookings(
      userId: userId,
      checkIn: checkIn,
      checkOut: checkOut,
    );
    if (userConflicts.isNotEmpty) {
      throw BookingConflictException(
        'You already have a booking during this time period',
        conflictType: ConflictType.user,
        conflictingBookings: userConflicts,
      );
    }

    final booking = Booking(
      id: 'booking_${_bookings.length + 1}',
      listingId: listingId,
      userId: userId,
      tenantName: userName,
      startAt: checkIn,
      endAt: checkOut,
      checkIn: checkIn,
      checkOut: checkOut,
      totalPrice: totalPrice,
      unitLabel: unitLabel,
      status: BookingStatus.confirmed,
      guestCount: guestCount,
      createdAt: DateTime.now(),
      listingTitle: listing.title,
      listingImageUrl: listing.primaryImage,
      listingCity: listing.city,
    );

    _bookings.add(booking);
    notifyListeners();
    return booking;
  }

  @override
  void cancelBooking(String bookingId) {
    final index = _bookings.indexWhere((b) => b.id == bookingId);
    if (index != -1) {
      _bookings[index] = _bookings[index].copyWith(
        status: BookingStatus.cancelled,
      );
      notifyListeners();
    }
  }

  // Availability & conflict checking methods

  @override
  List<Booking> getBookingsForListing(String listingId) {
    return _bookings.where((b) => b.listingId == listingId).toList()
      ..sort((a, b) => a.effectiveCheckIn.compareTo(b.effectiveCheckIn));
  }

  @override
  List<Booking> getActiveBookingsForListing(String listingId) {
    return _bookings
        .where((b) => b.listingId == listingId && b.status.isActive)
        .toList()
      ..sort((a, b) => a.effectiveCheckIn.compareTo(b.effectiveCheckIn));
  }

  @override
  bool isTimeSlotAvailable({
    required String listingId,
    required DateTime checkIn,
    required DateTime checkOut,
  }) {
    final conflicts = getConflictingBookings(
      listingId: listingId,
      checkIn: checkIn,
      checkOut: checkOut,
    );
    return conflicts.isEmpty;
  }

  @override
  List<Booking> getConflictingBookings({
    required String listingId,
    required DateTime checkIn,
    required DateTime checkOut,
  }) {
    final activeBookings = getActiveBookingsForListing(listingId);

    return activeBookings.where((booking) {
      final bookingStart = booking.effectiveCheckIn;
      final bookingEnd = booking.effectiveCheckOut;

      // Check for overlap:
      // Two ranges overlap if: start1 < end2 AND start2 < end1
      final hasOverlap = checkIn.isBefore(bookingEnd) &&
                         bookingStart.isBefore(checkOut);

      return hasOverlap;
    }).toList();
  }

  @override
  List<Booking> getUserConflictingBookings({
    required String userId,
    required DateTime checkIn,
    required DateTime checkOut,
    String? excludeListingId,
  }) {
    // Get all active bookings for this user
    final userBookings = _bookings.where((b) =>
      b.userId == userId &&
      b.status.isActive &&
      (excludeListingId == null || b.listingId != excludeListingId)
    ).toList();

    return userBookings.where((booking) {
      final bookingStart = booking.effectiveCheckIn;
      final bookingEnd = booking.effectiveCheckOut;

      // Check for overlap
      final hasOverlap = checkIn.isBefore(bookingEnd) &&
                         bookingStart.isBefore(checkOut);

      return hasOverlap;
    }).toList();
  }

  @override
  bool canUserBookDuring({
    required String userId,
    required DateTime checkIn,
    required DateTime checkOut,
  }) {
    final conflicts = getUserConflictingBookings(
      userId: userId,
      checkIn: checkIn,
      checkOut: checkOut,
    );
    return conflicts.isEmpty;
  }

  void _seed() {
    // Seed with rich mock data
    _listings.addAll(MockData.listings);
    _reviews.addAll(MockData.reviews);

    // Seed users
    for (final user in MockData.users) {
      _users[user.id] = user;
    }
  }
}
