import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/booking.dart';
import 'package:musafir/models/booking_status.dart';
import 'package:musafir/models/review.dart';
import 'package:musafir/services/review/review_service.dart';

/// In-memory review store for testing
class TestReviewStore implements ReviewStore {
  final Map<String, Review> _reviews = {};
  final Map<String, List<Review>> _byBooking = {};
  final Map<String, List<Review>> _byListing = {};
  final Map<String, List<Review>> _byReviewee = {};

  void clear() {
    _reviews.clear();
    _byBooking.clear();
    _byListing.clear();
    _byReviewee.clear();
  }

  @override
  void saveReview(Review review) {
    _reviews[review.id] = review;
    _byBooking.putIfAbsent(review.bookingId, () => []).add(review);
    if (review.listingId != null) {
      _byListing.putIfAbsent(review.listingId!, () => []).add(review);
    }
    _byReviewee.putIfAbsent(review.revieweeId, () => []).add(review);
  }

  @override
  List<Review> getReviewsForBooking(String bookingId) {
    return _byBooking[bookingId] ?? [];
  }

  @override
  List<Review> getRevealedReviewsForListing(String listingId) {
    return (_byListing[listingId] ?? [])
        .where((r) => r.isRevealed && r.reviewType == ReviewType.guestToHost)
        .toList();
  }

  @override
  List<Review> getRevealedReviewsForGuest(String guestId) {
    return (_byReviewee[guestId] ?? [])
        .where((r) => r.isRevealed && r.reviewType == ReviewType.hostToGuest)
        .toList();
  }

  @override
  void updateReview(Review review) {
    _reviews[review.id] = review;
    // Update in every index, not just _byBooking — reveal happens via
    // updateReview, so a stale copy here hides the review from the
    // revealed-only lookups.
    for (final list in [
      _byBooking[review.bookingId],
      if (review.listingId != null) _byListing[review.listingId!],
      _byReviewee[review.revieweeId],
    ]) {
      final idx = list?.indexWhere((r) => r.id == review.id) ?? -1;
      if (idx != -1) list![idx] = review;
    }
  }

  Review? get(String id) => _reviews[id];
}

/// In-memory booking store for testing
class TestBookingStore {
  final Map<String, Booking> _bookings = {};

  void add(Booking booking) {
    _bookings[booking.id] = booking;
  }

  Booking? get(String id) => _bookings[id];
}

void main() {
  late ReviewService service;
  late TestReviewStore reviewStore;
  late TestBookingStore bookingStore;

  setUp(() {
    reviewStore = TestReviewStore();
    bookingStore = TestBookingStore();
    service = ReviewService(
      reviewStore: reviewStore,
      getBooking: (id) => bookingStore.get(id),
      getCompletedAt: (booking) => booking.completedAt,
    );
  });

  Booking createCompletedBooking({
    String id = 'booking_1',
    String listingId = 'listing_1',
    String guestId = 'guest_1',
    String hostId = 'host_1',
    DateTime? completedAt,
  }) {
    final now = DateTime.now();
    return Booking(
      id: id,
      listingId: listingId,
      tenantName: 'Test Guest',
      startAt: now.subtract(const Duration(days: 2)),
      endAt: now.subtract(const Duration(days: 1)),
      totalPrice: 100.0,
      unitLabel: 'night',
      userId: guestId,
      status: BookingStatus.completed,
      createdAt: now.subtract(const Duration(days: 3)),
      completedAt: completedAt ?? now.subtract(const Duration(days: 1)),
    );
  }

  group('ReviewService.submitGuestReview', () {
    test('creates review with all 6 category ratings', () {
      final booking = createCompletedBooking();
      bookingStore.add(booking);

      final review = service.submitGuestReview(
        bookingId: booking.id,
        reviewerId: 'guest_1',
        reviewerName: 'Test Guest',
        ratings: GuestReviewRatings(
          overall: 4.5,
          cleanliness: 5.0,
          accuracy: 4.0,
          communication: 5.0,
          location: 4.0,
          value: 4.5,
        ),
        comment: 'Great place to stay!',
      );

      expect(review.reviewType, equals(ReviewType.guestToHost));
      expect(review.overallRating, equals(4.5));
      expect(review.categoryRatings?.cleanliness, equals(5.0));
      expect(review.categoryRatings?.accuracy, equals(4.0));
      expect(review.comment, equals('Great place to stay!'));
      expect(review.isRevealed, isFalse);
    });

    test('throws when comment is empty', () {
      final booking = createCompletedBooking();
      bookingStore.add(booking);

      expect(
        () => service.submitGuestReview(
          bookingId: booking.id,
          reviewerId: 'guest_1',
          reviewerName: 'Test Guest',
          ratings: GuestReviewRatings(
            overall: 4.5,
            cleanliness: 5.0,
            accuracy: 4.0,
            communication: 5.0,
            location: 4.0,
            value: 4.5,
          ),
          comment: '',
        ),
        throwsA(isA<ReviewValidationException>()),
      );
    });

    test('throws when booking not completed', () {
      final booking = Booking(
        id: 'booking_1',
        listingId: 'listing_1',
        tenantName: 'Test Guest',
        startAt: DateTime.now(),
        endAt: DateTime.now().add(const Duration(days: 1)),
        totalPrice: 100.0,
        unitLabel: 'night',
        userId: 'guest_1',
        status: BookingStatus.confirmed,
      );
      bookingStore.add(booking);

      expect(
        () => service.submitGuestReview(
          bookingId: booking.id,
          reviewerId: 'guest_1',
          reviewerName: 'Test Guest',
          ratings: GuestReviewRatings(
            overall: 4.5,
            cleanliness: 5.0,
            accuracy: 4.0,
            communication: 5.0,
            location: 4.0,
            value: 4.5,
          ),
          comment: 'Great!',
        ),
        throwsA(isA<ReviewValidationException>()),
      );
    });

    test('throws when review window expired (after 14 days)', () {
      final booking = createCompletedBooking(
        completedAt: DateTime.now().subtract(const Duration(days: 15)),
      );
      bookingStore.add(booking);

      expect(
        () => service.submitGuestReview(
          bookingId: booking.id,
          reviewerId: 'guest_1',
          reviewerName: 'Test Guest',
          ratings: GuestReviewRatings(
            overall: 4.5,
            cleanliness: 5.0,
            accuracy: 4.0,
            communication: 5.0,
            location: 4.0,
            value: 4.5,
          ),
          comment: 'Great!',
        ),
        throwsA(isA<ReviewValidationException>()),
      );
    });
  });

  group('ReviewService.submitHostReview', () {
    test('creates review with single overall rating', () {
      final booking = createCompletedBooking();
      bookingStore.add(booking);

      final review = service.submitHostReview(
        bookingId: booking.id,
        reviewerId: 'host_1',
        reviewerName: 'Test Host',
        rating: 4.0,
        comment: 'Great guest!',
      );

      expect(review.reviewType, equals(ReviewType.hostToGuest));
      expect(review.overallRating, equals(4.0));
      expect(review.categoryRatings, isNull);
      expect(review.isRevealed, isFalse);
    });

    test('allows empty comment for host review', () {
      final booking = createCompletedBooking();
      bookingStore.add(booking);

      final review = service.submitHostReview(
        bookingId: booking.id,
        reviewerId: 'host_1',
        reviewerName: 'Test Host',
        rating: 4.0,
      );

      expect(review.comment, isNull);
    });
  });

  group('Simultaneous reveal', () {
    test('reviews not revealed until both submit', () {
      final booking = createCompletedBooking();
      bookingStore.add(booking);

      final guestReview = service.submitGuestReview(
        bookingId: booking.id,
        reviewerId: 'guest_1',
        reviewerName: 'Test Guest',
        ratings: GuestReviewRatings(
          overall: 4.5,
          cleanliness: 5.0,
          accuracy: 4.0,
          communication: 5.0,
          location: 4.0,
          value: 4.5,
        ),
        comment: 'Great!',
      );

      expect(guestReview.isRevealed, isFalse);
      expect(service.areReviewsRevealed(booking.id), isFalse);
    });

    test('both reviews revealed when both submit', () {
      final booking = createCompletedBooking();
      bookingStore.add(booking);

      service.submitGuestReview(
        bookingId: booking.id,
        reviewerId: 'guest_1',
        reviewerName: 'Test Guest',
        ratings: GuestReviewRatings(
          overall: 4.5,
          cleanliness: 5.0,
          accuracy: 4.0,
          communication: 5.0,
          location: 4.0,
          value: 4.5,
        ),
        comment: 'Great!',
      );

      service.submitHostReview(
        bookingId: booking.id,
        reviewerId: 'host_1',
        reviewerName: 'Test Host',
        rating: 4.0,
      );

      expect(service.areReviewsRevealed(booking.id), isTrue);

      final reviews = reviewStore.getReviewsForBooking(booking.id);
      expect(reviews.every((r) => r.isRevealed), isTrue);
    });

    test('reviews revealed after 14 days even if only one submitted', () {
      final completedAt = DateTime.now().subtract(const Duration(days: 15));
      final booking = createCompletedBooking(completedAt: completedAt);
      bookingStore.add(booking);

      // Manually add an old review (simulating it was submitted earlier)
      final oldReview = Review(
        id: 'review_1',
        bookingId: booking.id,
        listingId: booking.listingId,
        reviewerId: 'guest_1',
        reviewerName: 'Test Guest',
        revieweeId: 'host_1',
        reviewType: ReviewType.guestToHost,
        overallRating: 4.5,
        comment: 'Great!',
        isRevealed: false,
        createdAt: completedAt.add(const Duration(days: 1)),
      );
      reviewStore.saveReview(oldReview);

      // Trigger reveal check
      service.revealExpiredReviews(booking.id, completedAt: completedAt);

      final revealed = reviewStore.get(oldReview.id);
      expect(revealed?.isRevealed, isTrue);
    });
  });

  group('ReviewService.getGuestAggregateRating', () {
    test('calculates average from revealed host reviews', () {
      final booking1 = createCompletedBooking(id: 'booking_1');
      final booking2 = createCompletedBooking(id: 'booking_2');
      bookingStore.add(booking1);
      bookingStore.add(booking2);

      // Submit reviews for both bookings (both sides to reveal)
      service.submitGuestReview(
        bookingId: 'booking_1',
        reviewerId: 'guest_1',
        reviewerName: 'Guest',
        ratings: GuestReviewRatings(
          overall: 4.0,
          cleanliness: 4.0,
          accuracy: 4.0,
          communication: 4.0,
          location: 4.0,
          value: 4.0,
        ),
        comment: 'Good!',
      );
      service.submitHostReview(
        bookingId: 'booking_1',
        reviewerId: 'host_1',
        reviewerName: 'Host',
        rating: 5.0,
      );

      service.submitGuestReview(
        bookingId: 'booking_2',
        reviewerId: 'guest_1',
        reviewerName: 'Guest',
        ratings: GuestReviewRatings(
          overall: 4.0,
          cleanliness: 4.0,
          accuracy: 4.0,
          communication: 4.0,
          location: 4.0,
          value: 4.0,
        ),
        comment: 'Nice!',
      );
      service.submitHostReview(
        bookingId: 'booking_2',
        reviewerId: 'host_1',
        reviewerName: 'Host',
        rating: 4.0,
      );

      final aggregate = service.getGuestAggregateRating('guest_1');

      expect(aggregate?.averageRating, equals(4.5)); // (5.0 + 4.0) / 2
      expect(aggregate?.reviewCount, equals(2));
    });

    test('returns null for guest with no reviews', () {
      final aggregate = service.getGuestAggregateRating('new_guest');
      expect(aggregate, isNull);
    });
  });

  group('ReviewService.getListingAggregateRating', () {
    test('calculates average from revealed guest reviews', () {
      final booking1 = createCompletedBooking(id: 'booking_1');
      final booking2 = createCompletedBooking(id: 'booking_2');
      bookingStore.add(booking1);
      bookingStore.add(booking2);

      // Submit reviews for both bookings
      service.submitGuestReview(
        bookingId: 'booking_1',
        reviewerId: 'guest_1',
        reviewerName: 'Guest 1',
        ratings: GuestReviewRatings(
          overall: 5.0,
          cleanliness: 5.0,
          accuracy: 5.0,
          communication: 5.0,
          location: 5.0,
          value: 5.0,
        ),
        comment: 'Perfect!',
      );
      service.submitHostReview(
        bookingId: 'booking_1',
        reviewerId: 'host_1',
        reviewerName: 'Host',
        rating: 4.0,
      );

      service.submitGuestReview(
        bookingId: 'booking_2',
        reviewerId: 'guest_2',
        reviewerName: 'Guest 2',
        ratings: GuestReviewRatings(
          overall: 4.0,
          cleanliness: 4.0,
          accuracy: 4.0,
          communication: 4.0,
          location: 4.0,
          value: 4.0,
        ),
        comment: 'Good!',
      );
      service.submitHostReview(
        bookingId: 'booking_2',
        reviewerId: 'host_1',
        reviewerName: 'Host',
        rating: 5.0,
      );

      final aggregate = service.getListingAggregateRating('listing_1');

      expect(aggregate?.averageRating, equals(4.5)); // (5.0 + 4.0) / 2
      expect(aggregate?.reviewCount, equals(2));
    });
  });
}
