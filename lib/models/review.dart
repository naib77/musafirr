import 'guest_review_ratings.dart';

/// Type of review indicating direction
enum ReviewType {
  /// Guest reviewing the host/listing
  guestToHost,

  /// Host reviewing the guest
  hostToGuest,
}

/// Bidirectional review model supporting both guest and host reviews.
///
/// Guest reviews include 6-category ratings and required text.
/// Host reviews have single overall rating and optional text.
class Review {
  const Review({
    required this.id,
    required this.bookingId,
    this.listingId,
    required this.reviewerId,
    required this.reviewerName,
    this.reviewerAvatarUrl,
    required this.revieweeId,
    required this.reviewType,
    required this.overallRating,
    this.categoryRatings,
    this.comment,
    required this.isRevealed,
    required this.createdAt,
    this.revealedAt,
  });

  final String id;

  /// The booking this review is associated with
  final String bookingId;

  /// The listing being reviewed (for guest-to-host reviews)
  final String? listingId;

  /// Who wrote the review
  final String reviewerId;
  final String reviewerName;
  final String? reviewerAvatarUrl;

  /// Who is being reviewed
  final String revieweeId;

  /// Direction of the review
  final ReviewType reviewType;

  /// Overall rating (1-5)
  final double overallRating;

  /// Category ratings (only for guest-to-host reviews)
  final GuestReviewRatings? categoryRatings;

  /// Review text (required for guest reviews, optional for host reviews)
  final String? comment;

  /// Whether this review has been revealed (simultaneous reveal)
  final bool isRevealed;

  /// When the review was created
  final DateTime createdAt;

  /// When the review was revealed (if applicable)
  final DateTime? revealedAt;

  // Legacy compatibility getters
  String get listingIdLegacy => listingId ?? '';
  String get userId => reviewerId;
  String get userName => reviewerName;
  String? get userAvatarUrl => reviewerAvatarUrl;
  double get rating => overallRating;

  Review copyWith({
    String? id,
    String? bookingId,
    String? listingId,
    String? reviewerId,
    String? reviewerName,
    String? reviewerAvatarUrl,
    String? revieweeId,
    ReviewType? reviewType,
    double? overallRating,
    GuestReviewRatings? categoryRatings,
    String? comment,
    bool? isRevealed,
    DateTime? createdAt,
    DateTime? revealedAt,
  }) {
    return Review(
      id: id ?? this.id,
      bookingId: bookingId ?? this.bookingId,
      listingId: listingId ?? this.listingId,
      reviewerId: reviewerId ?? this.reviewerId,
      reviewerName: reviewerName ?? this.reviewerName,
      reviewerAvatarUrl: reviewerAvatarUrl ?? this.reviewerAvatarUrl,
      revieweeId: revieweeId ?? this.revieweeId,
      reviewType: reviewType ?? this.reviewType,
      overallRating: overallRating ?? this.overallRating,
      categoryRatings: categoryRatings ?? this.categoryRatings,
      comment: comment ?? this.comment,
      isRevealed: isRevealed ?? this.isRevealed,
      createdAt: createdAt ?? this.createdAt,
      revealedAt: revealedAt ?? this.revealedAt,
    );
  }

  /// Create a guest-to-host review with category ratings
  factory Review.guestReview({
    required String id,
    required String bookingId,
    required String listingId,
    required String reviewerId,
    required String reviewerName,
    String? reviewerAvatarUrl,
    required String hostId,
    required GuestReviewRatings ratings,
    required String comment,
    DateTime? createdAt,
  }) {
    return Review(
      id: id,
      bookingId: bookingId,
      listingId: listingId,
      reviewerId: reviewerId,
      reviewerName: reviewerName,
      reviewerAvatarUrl: reviewerAvatarUrl,
      revieweeId: hostId,
      reviewType: ReviewType.guestToHost,
      overallRating: ratings.overall,
      categoryRatings: ratings,
      comment: comment,
      isRevealed: false,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  /// Create a host-to-guest review with single rating
  factory Review.hostReview({
    required String id,
    required String bookingId,
    required String reviewerId,
    required String reviewerName,
    String? reviewerAvatarUrl,
    required String guestId,
    required double rating,
    String? comment,
    DateTime? createdAt,
  }) {
    return Review(
      id: id,
      bookingId: bookingId,
      listingId: null,
      reviewerId: reviewerId,
      reviewerName: reviewerName,
      reviewerAvatarUrl: reviewerAvatarUrl,
      revieweeId: guestId,
      reviewType: ReviewType.hostToGuest,
      overallRating: rating,
      categoryRatings: null,
      comment: comment,
      isRevealed: false,
      createdAt: createdAt ?? DateTime.now(),
    );
  }
}

/// Aggregate rating information
class AggregateRating {
  const AggregateRating({
    required this.averageRating,
    required this.reviewCount,
  });

  final double averageRating;
  final int reviewCount;

  bool get hasReviews => reviewCount > 0;
}
