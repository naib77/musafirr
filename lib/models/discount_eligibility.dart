import 'package:flutter/foundation.dart';

import 'discount.dart';

/// Reason why a discount is not eligible
enum IneligibilityReason {
  /// Discount not found
  notFound,

  /// Discount is not active
  inactive,

  /// Discount hasn't started yet
  notStarted,

  /// Discount has expired
  expired,

  /// Total usage limit reached
  usageLimitReached,

  /// User has already used this discount
  alreadyUsed,

  /// Booking amount too low
  belowMinimumAmount,

  /// Stay duration too short
  belowMinimumNights,

  /// Stay duration too long
  aboveMaximumNights,

  /// User not eligible
  userNotEligible,

  /// Listing not eligible
  listingNotEligible,

  /// Host not eligible
  hostNotEligible,

  /// Check-in date not in valid range
  checkInDateInvalid,

  /// Check-in day of week not allowed
  checkInDayNotAllowed,

  /// Only for new users
  newUsersOnly,

  /// Only for first booking
  firstBookingOnly,

  /// Cannot stack with other discounts
  cannotStack,

  /// Invalid promo code
  invalidCode,

  /// Unknown error
  unknown,
}

extension IneligibilityReasonExtension on IneligibilityReason {
  String get message {
    switch (this) {
      case IneligibilityReason.notFound:
        return 'Discount not found';
      case IneligibilityReason.inactive:
        return 'This discount is not active';
      case IneligibilityReason.notStarted:
        return 'This discount has not started yet';
      case IneligibilityReason.expired:
        return 'This discount has expired';
      case IneligibilityReason.usageLimitReached:
        return 'This discount has reached its usage limit';
      case IneligibilityReason.alreadyUsed:
        return 'You have already used this discount';
      case IneligibilityReason.belowMinimumAmount:
        return 'Booking amount is below the minimum required';
      case IneligibilityReason.belowMinimumNights:
        return 'Stay duration is below the minimum required';
      case IneligibilityReason.aboveMaximumNights:
        return 'Stay duration exceeds the maximum allowed';
      case IneligibilityReason.userNotEligible:
        return 'You are not eligible for this discount';
      case IneligibilityReason.listingNotEligible:
        return 'This discount is not valid for this listing';
      case IneligibilityReason.hostNotEligible:
        return 'This discount is not valid for this host';
      case IneligibilityReason.checkInDateInvalid:
        return 'Check-in date is outside the valid range';
      case IneligibilityReason.checkInDayNotAllowed:
        return 'This discount is not valid for this check-in day';
      case IneligibilityReason.newUsersOnly:
        return 'This discount is only for new users';
      case IneligibilityReason.firstBookingOnly:
        return 'This discount is only for your first booking';
      case IneligibilityReason.cannotStack:
        return 'This discount cannot be combined with others';
      case IneligibilityReason.invalidCode:
        return 'Invalid promo code';
      case IneligibilityReason.unknown:
        return 'Unable to apply this discount';
    }
  }

  String messageWithDetails(String? details) {
    if (details == null) return message;
    return '$message: $details';
  }
}

/// Context for checking discount eligibility
@immutable
class DiscountEligibilityContext {
  const DiscountEligibilityContext({
    required this.userId,
    required this.bookingAmount,
    required this.nights,
    required this.checkInDate,
    this.listingId,
    this.hostId,
    this.isNewUser = false,
    this.isFirstBooking = false,
    this.userDiscountUsageCount = 0,
    this.existingDiscounts = const [],
  });

  /// User making the booking
  final String userId;

  /// Total booking amount before discounts (in BDT)
  final double bookingAmount;

  /// Number of nights in the booking
  final int nights;

  /// Check-in date
  final DateTime checkInDate;

  /// Listing being booked
  final String? listingId;

  /// Host of the listing
  final String? hostId;

  /// Whether user is new (first time on platform)
  final bool isNewUser;

  /// Whether this is user's first booking
  final bool isFirstBooking;

  /// Number of times user has used this discount
  final int userDiscountUsageCount;

  /// Other discounts already applied (for stacking checks)
  final List<Discount> existingDiscounts;

  /// Check-out date (computed)
  DateTime get checkOutDate => checkInDate.add(Duration(days: nights));

  /// Day of week for check-in (0 = Sunday, 6 = Saturday)
  int get checkInDayOfWeek => checkInDate.weekday % 7;

  DiscountEligibilityContext copyWith({
    String? userId,
    double? bookingAmount,
    int? nights,
    DateTime? checkInDate,
    String? listingId,
    String? hostId,
    bool? isNewUser,
    bool? isFirstBooking,
    int? userDiscountUsageCount,
    List<Discount>? existingDiscounts,
  }) {
    return DiscountEligibilityContext(
      userId: userId ?? this.userId,
      bookingAmount: bookingAmount ?? this.bookingAmount,
      nights: nights ?? this.nights,
      checkInDate: checkInDate ?? this.checkInDate,
      listingId: listingId ?? this.listingId,
      hostId: hostId ?? this.hostId,
      isNewUser: isNewUser ?? this.isNewUser,
      isFirstBooking: isFirstBooking ?? this.isFirstBooking,
      userDiscountUsageCount:
          userDiscountUsageCount ?? this.userDiscountUsageCount,
      existingDiscounts: existingDiscounts ?? this.existingDiscounts,
    );
  }
}

/// Result of checking discount eligibility
@immutable
class DiscountEligibilityResult {
  const DiscountEligibilityResult._({
    required this.isEligible,
    required this.discount,
    this.reason,
    this.details,
    this.calculatedAmount,
  });

  /// Create an eligible result
  factory DiscountEligibilityResult.eligible({
    required Discount discount,
    required double calculatedAmount,
  }) {
    return DiscountEligibilityResult._(
      isEligible: true,
      discount: discount,
      calculatedAmount: calculatedAmount,
    );
  }

  /// Create an ineligible result
  factory DiscountEligibilityResult.ineligible({
    required Discount discount,
    required IneligibilityReason reason,
    String? details,
  }) {
    return DiscountEligibilityResult._(
      isEligible: false,
      discount: discount,
      reason: reason,
      details: details,
    );
  }

  /// Whether the discount is eligible
  final bool isEligible;

  /// The discount being checked
  final Discount discount;

  /// Reason for ineligibility (if not eligible)
  final IneligibilityReason? reason;

  /// Additional details about ineligibility
  final String? details;

  /// Calculated discount amount (if eligible)
  final double? calculatedAmount;

  /// Get user-friendly error message
  String? get errorMessage {
    if (isEligible) return null;
    return reason?.messageWithDetails(details);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscountEligibilityResult &&
          runtimeType == other.runtimeType &&
          isEligible == other.isEligible &&
          discount.id == other.discount.id &&
          reason == other.reason;

  @override
  int get hashCode =>
      isEligible.hashCode ^ discount.id.hashCode ^ reason.hashCode;
}

/// Checker class for discount eligibility
class DiscountEligibilityChecker {
  /// Check if a discount is eligible for the given context
  static DiscountEligibilityResult check(
    Discount discount,
    DiscountEligibilityContext context,
  ) {
    // Check status
    if (discount.status != DiscountStatus.active) {
      return DiscountEligibilityResult.ineligible(
        discount: discount,
        reason: IneligibilityReason.inactive,
      );
    }

    // Check dates
    final now = DateTime.now();
    if (discount.startsAt.isAfter(now)) {
      return DiscountEligibilityResult.ineligible(
        discount: discount,
        reason: IneligibilityReason.notStarted,
      );
    }

    if (discount.endsAt != null && discount.endsAt!.isBefore(now)) {
      return DiscountEligibilityResult.ineligible(
        discount: discount,
        reason: IneligibilityReason.expired,
      );
    }

    // Check total usage limit
    if (discount.isUsageLimitReached) {
      return DiscountEligibilityResult.ineligible(
        discount: discount,
        reason: IneligibilityReason.usageLimitReached,
      );
    }

    // Check per-user limit
    if (discount.perUserLimit != null &&
        context.userDiscountUsageCount >= discount.perUserLimit!) {
      return DiscountEligibilityResult.ineligible(
        discount: discount,
        reason: IneligibilityReason.alreadyUsed,
      );
    }

    // Check minimum booking amount
    if (context.bookingAmount < discount.minBookingAmount) {
      return DiscountEligibilityResult.ineligible(
        discount: discount,
        reason: IneligibilityReason.belowMinimumAmount,
        details: 'Minimum ৳${discount.minBookingAmount.toStringAsFixed(0)}',
      );
    }

    // Check minimum nights
    if (context.nights < discount.minNights) {
      return DiscountEligibilityResult.ineligible(
        discount: discount,
        reason: IneligibilityReason.belowMinimumNights,
        details: 'Minimum ${discount.minNights} nights',
      );
    }

    // Check maximum nights
    if (discount.maxNights != null && context.nights > discount.maxNights!) {
      return DiscountEligibilityResult.ineligible(
        discount: discount,
        reason: IneligibilityReason.aboveMaximumNights,
        details: 'Maximum ${discount.maxNights} nights',
      );
    }

    // Check eligible users
    if (discount.eligibleUserIds != null &&
        !discount.eligibleUserIds!.contains(context.userId)) {
      return DiscountEligibilityResult.ineligible(
        discount: discount,
        reason: IneligibilityReason.userNotEligible,
      );
    }

    // Check eligible listings
    if (discount.eligibleListingIds != null &&
        context.listingId != null &&
        !discount.eligibleListingIds!.contains(context.listingId)) {
      return DiscountEligibilityResult.ineligible(
        discount: discount,
        reason: IneligibilityReason.listingNotEligible,
      );
    }

    // Check eligible hosts
    if (discount.eligibleHostIds != null &&
        context.hostId != null &&
        !discount.eligibleHostIds!.contains(context.hostId)) {
      return DiscountEligibilityResult.ineligible(
        discount: discount,
        reason: IneligibilityReason.hostNotEligible,
      );
    }

    // Check new users only
    if (discount.newUsersOnly && !context.isNewUser) {
      return DiscountEligibilityResult.ineligible(
        discount: discount,
        reason: IneligibilityReason.newUsersOnly,
      );
    }

    // Check first booking only
    if (discount.firstBookingOnly && !context.isFirstBooking) {
      return DiscountEligibilityResult.ineligible(
        discount: discount,
        reason: IneligibilityReason.firstBookingOnly,
      );
    }

    // Check check-in date range
    if (discount.checkInStartDate != null &&
        context.checkInDate.isBefore(discount.checkInStartDate!)) {
      return DiscountEligibilityResult.ineligible(
        discount: discount,
        reason: IneligibilityReason.checkInDateInvalid,
        details:
            'Check-in must be after ${_formatDate(discount.checkInStartDate!)}',
      );
    }

    if (discount.checkInEndDate != null &&
        context.checkInDate.isAfter(discount.checkInEndDate!)) {
      return DiscountEligibilityResult.ineligible(
        discount: discount,
        reason: IneligibilityReason.checkInDateInvalid,
        details:
            'Check-in must be before ${_formatDate(discount.checkInEndDate!)}',
      );
    }

    // Check day of week restrictions
    if (discount.allowedCheckInDays != null &&
        !discount.allowedCheckInDays!.contains(context.checkInDayOfWeek)) {
      return DiscountEligibilityResult.ineligible(
        discount: discount,
        reason: IneligibilityReason.checkInDayNotAllowed,
        details: _getAllowedDaysMessage(discount.allowedCheckInDays!),
      );
    }

    // Check stacking rules
    if (context.existingDiscounts.isNotEmpty) {
      final stackingResult =
          _checkStacking(discount, context.existingDiscounts);
      if (!stackingResult.canStack) {
        return DiscountEligibilityResult.ineligible(
          discount: discount,
          reason: IneligibilityReason.cannotStack,
          details: stackingResult.reason,
        );
      }
    }

    // All checks passed - calculate discount amount
    final calculatedAmount = _calculateDiscountAmount(
      discount,
      context.bookingAmount,
      context.nights,
    );

    return DiscountEligibilityResult.eligible(
      discount: discount,
      calculatedAmount: calculatedAmount,
    );
  }

  static ({bool canStack, String? reason}) _checkStacking(
    Discount discount,
    List<Discount> existingDiscounts,
  ) {
    // If this discount is exclusive, it can't stack
    if (discount.stackingBehavior == StackingBehavior.exclusive) {
      return (
        canStack: existingDiscounts.isEmpty,
        reason: 'This discount cannot be combined with others',
      );
    }

    // Check if any existing discount is exclusive
    for (final existing in existingDiscounts) {
      if (existing.stackingBehavior == StackingBehavior.exclusive) {
        return (
          canStack: false,
          reason: '${existing.name} cannot be combined with other discounts',
        );
      }
    }

    // Check stackable categories
    if (discount.stackableWithCategories != null) {
      for (final existing in existingDiscounts) {
        if (!discount.stackableWithCategories!.contains(existing.category)) {
          return (
            canStack: false,
            reason:
                'Cannot combine with ${existing.category.displayName} discounts',
          );
        }
      }
    }

    return (canStack: true, reason: null);
  }

  static double _calculateDiscountAmount(
    Discount discount,
    double bookingAmount,
    int nights,
  ) {
    switch (discount.type) {
      case DiscountType.percentage:
        var amount = bookingAmount * (discount.value / 100);
        // Apply max cap if set
        if (discount.maxDiscountAmount != null &&
            amount > discount.maxDiscountAmount!) {
          amount = discount.maxDiscountAmount!;
        }
        return amount;

      case DiscountType.fixedAmount:
        // Don't exceed booking amount
        return discount.value > bookingAmount ? bookingAmount : discount.value;

      case DiscountType.freeNights:
        if (discount.freeNightsConfig != null &&
            nights >= discount.freeNightsConfig!.stayNights) {
          final freeNights = discount.freeNightsConfig!.freeNights;
          final perNightRate = bookingAmount / nights;
          return freeNights * perNightRate;
        }
        return 0;
    }
  }

  static String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  static String _getAllowedDaysMessage(List<int> days) {
    const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final allowedDays = days.map((d) => dayNames[d]).join(', ');
    return 'Only valid for $allowedDays check-ins';
  }
}
