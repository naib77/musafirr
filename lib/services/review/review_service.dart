import 'package:uuid/uuid.dart';

import '../../models/booking.dart';
import '../../models/booking_status.dart';
import '../../models/guest_review_ratings.dart';
import '../../models/review.dart';
import '../booking/booking_rules.dart';

/// Exception thrown when review validation fails.
class ReviewValidationException implements Exception {
  ReviewValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Exception thrown when a review already exists.
class DuplicateReviewException implements Exception {
  DuplicateReviewException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Abstract interface for review storage operations.
abstract class ReviewStore {
  void saveReview(Review review);
  List<Review> getReviewsForBooking(String bookingId);
  List<Review> getRevealedReviewsForListing(String listingId);
  List<Review> getRevealedReviewsForGuest(String guestId);
  void updateReview(Review review);
}

/// Service for managing bidirectional reviews with simultaneous reveal.
class ReviewService {
  ReviewService({
    required this.reviewStore,
    required this.getBooking,
    required this.getCompletedAt,
  });

  final ReviewStore reviewStore;
  final Booking? Function(String bookingId) getBooking;
  final DateTime? Function(Booking booking) getCompletedAt;

  static const _uuid = Uuid();

  /// Submit a guest review for a listing/host.
  ///
  /// Requires all 6 category ratings and a non-empty comment.
  /// Review will not be revealed until host also submits or 14 days pass.
  Review submitGuestReview({
    required String bookingId,
    required String reviewerId,
    required String reviewerName,
    String? reviewerAvatarUrl,
    required GuestReviewRatings ratings,
    required String comment,
  }) {
    final booking = _validateBookingForReview(bookingId);

    // Guest review requires comment
    if (comment.trim().isEmpty) {
      throw ReviewValidationException(
        'Guest reviews require a comment',
      );
    }

    // Check for duplicate
    final existingReviews = reviewStore.getReviewsForBooking(bookingId);
    if (existingReviews.any((r) => r.reviewType == ReviewType.guestToHost)) {
      throw DuplicateReviewException(
        'A guest review already exists for this booking',
      );
    }

    final review = Review.guestReview(
      id: _uuid.v4(),
      bookingId: bookingId,
      listingId: booking.listingId,
      reviewerId: reviewerId,
      reviewerName: reviewerName,
      reviewerAvatarUrl: reviewerAvatarUrl,
      hostId: _getHostId(booking),
      ratings: ratings,
      comment: comment,
    );

    reviewStore.saveReview(review);

    // Check if both reviews now exist and reveal them
    _tryRevealReviews(bookingId);

    return review;
  }

  /// Submit a host review for a guest.
  ///
  /// Requires only overall rating. Comment is optional.
  /// Review will not be revealed until guest also submits or 14 days pass.
  Review submitHostReview({
    required String bookingId,
    required String reviewerId,
    required String reviewerName,
    String? reviewerAvatarUrl,
    required double rating,
    String? comment,
  }) {
    final booking = _validateBookingForReview(bookingId);

    // Check for duplicate
    final existingReviews = reviewStore.getReviewsForBooking(bookingId);
    if (existingReviews.any((r) => r.reviewType == ReviewType.hostToGuest)) {
      throw DuplicateReviewException(
        'A host review already exists for this booking',
      );
    }

    final review = Review.hostReview(
      id: _uuid.v4(),
      bookingId: bookingId,
      reviewerId: reviewerId,
      reviewerName: reviewerName,
      reviewerAvatarUrl: reviewerAvatarUrl,
      guestId: booking.userId ?? '',
      rating: rating,
      comment: comment?.isNotEmpty == true ? comment : null,
    );

    reviewStore.saveReview(review);

    // Check if both reviews now exist and reveal them
    _tryRevealReviews(bookingId);

    return review;
  }

  /// Check if reviews for this booking have been revealed.
  bool areReviewsRevealed(String bookingId) {
    final reviews = reviewStore.getReviewsForBooking(bookingId);
    if (reviews.isEmpty) return false;
    return reviews.every((r) => r.isRevealed);
  }

  /// Get revealed guest reviews for a listing.
  List<Review> getRevealedReviewsForListing(String listingId) {
    return reviewStore.getRevealedReviewsForListing(listingId);
  }

  /// Get revealed host reviews for a guest.
  List<Review> getRevealedReviewsForGuest(String guestId) {
    return reviewStore.getRevealedReviewsForGuest(guestId);
  }

  /// Calculate aggregate rating for a listing from revealed guest reviews.
  AggregateRating? getListingAggregateRating(String listingId) {
    final reviews = getRevealedReviewsForListing(listingId);
    if (reviews.isEmpty) return null;

    final total = reviews.fold<double>(
      0,
      (sum, r) => sum + r.overallRating,
    );

    return AggregateRating(
      averageRating: total / reviews.length,
      reviewCount: reviews.length,
    );
  }

  /// Calculate aggregate rating for a guest from revealed host reviews.
  AggregateRating? getGuestAggregateRating(String guestId) {
    final reviews = getRevealedReviewsForGuest(guestId);
    if (reviews.isEmpty) return null;

    final total = reviews.fold<double>(
      0,
      (sum, r) => sum + r.overallRating,
    );

    return AggregateRating(
      averageRating: total / reviews.length,
      reviewCount: reviews.length,
    );
  }

  /// Reveal reviews that have passed the 14-day window.
  ///
  /// Call this periodically or when checking review status.
  void revealExpiredReviews(String bookingId, {DateTime? completedAt}) {
    final reviews = reviewStore.getReviewsForBooking(bookingId);
    if (reviews.isEmpty) return;
    if (reviews.every((r) => r.isRevealed)) return;

    final now = DateTime.now();
    final deadline = completedAt?.add(BookingRules.reviewRevealDuration) ??
        now.subtract(const Duration(days: 1));

    if (now.isAfter(deadline)) {
      _revealAllReviews(reviews);
    }
  }

  /// Check if a user can submit a review for a booking.
  bool canSubmitReview(String bookingId, String userId, ReviewType type) {
    final booking = getBooking(bookingId);
    if (booking == null) return false;
    if (booking.status != BookingStatus.completed) return false;

    final completedAt = getCompletedAt(booking);
    if (completedAt == null) return false;

    // Check if within review window
    final now = DateTime.now();
    final deadline = completedAt.add(BookingRules.reviewWindowDuration);
    if (now.isAfter(deadline)) return false;

    // Check if review already exists
    final existingReviews = reviewStore.getReviewsForBooking(bookingId);
    return !existingReviews.any((r) => r.reviewType == type);
  }

  Booking _validateBookingForReview(String bookingId) {
    final booking = getBooking(bookingId);
    if (booking == null) {
      throw ReviewValidationException('Booking not found');
    }

    if (booking.status != BookingStatus.completed) {
      throw ReviewValidationException(
        'Can only review completed bookings',
      );
    }

    final completedAt = getCompletedAt(booking);
    if (completedAt == null) {
      throw ReviewValidationException('Booking completion date not found');
    }

    // Check review window
    final now = DateTime.now();
    final deadline = completedAt.add(BookingRules.reviewWindowDuration);
    if (now.isAfter(deadline)) {
      throw ReviewValidationException(
        'Review window has expired (14 days after service completion)',
      );
    }

    return booking;
  }

  void _tryRevealReviews(String bookingId) {
    final reviews = reviewStore.getReviewsForBooking(bookingId);

    // Check if both guest and host have submitted
    final hasGuestReview =
        reviews.any((r) => r.reviewType == ReviewType.guestToHost);
    final hasHostReview =
        reviews.any((r) => r.reviewType == ReviewType.hostToGuest);

    if (hasGuestReview && hasHostReview) {
      _revealAllReviews(reviews);
    }
  }

  void _revealAllReviews(List<Review> reviews) {
    final now = DateTime.now();
    for (final review in reviews) {
      if (!review.isRevealed) {
        final revealed = review.copyWith(
          isRevealed: true,
          revealedAt: now,
        );
        reviewStore.updateReview(revealed);
      }
    }
  }

  String _getHostId(Booking booking) {
    // In a real implementation, this would lookup the listing's host
    // For now, we'll use a placeholder
    return booking.listing?.hostId ?? 'unknown_host';
  }
}
