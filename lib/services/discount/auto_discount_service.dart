import '../../models/discount.dart';
import '../../models/loyalty_tier.dart';
import 'loyalty_service.dart';
import 'referral_service.dart';

/// Auto-detected discount types
enum AutoDiscountType {
  firstBooking,
  earlyBird,
  longStay,
  lastMinute,
  loyalty,
  referral,
  weekdayStay,
  repeatGuest,
}

extension AutoDiscountTypeExtension on AutoDiscountType {
  String get displayName {
    switch (this) {
      case AutoDiscountType.firstBooking:
        return 'First Booking';
      case AutoDiscountType.earlyBird:
        return 'Early Bird';
      case AutoDiscountType.longStay:
        return 'Long Stay';
      case AutoDiscountType.lastMinute:
        return 'Last Minute';
      case AutoDiscountType.loyalty:
        return 'Loyalty';
      case AutoDiscountType.referral:
        return 'Referral';
      case AutoDiscountType.weekdayStay:
        return 'Weekday';
      case AutoDiscountType.repeatGuest:
        return 'Repeat Guest';
    }
  }

  String get description {
    switch (this) {
      case AutoDiscountType.firstBooking:
        return 'Special discount for your first booking';
      case AutoDiscountType.earlyBird:
        return 'Book early and save more';
      case AutoDiscountType.longStay:
        return 'Extended stay savings';
      case AutoDiscountType.lastMinute:
        return 'Last minute deal';
      case AutoDiscountType.loyalty:
        return 'Thank you for being a loyal customer';
      case AutoDiscountType.referral:
        return 'Referral reward';
      case AutoDiscountType.weekdayStay:
        return 'Weekday special rate';
      case AutoDiscountType.repeatGuest:
        return 'Welcome back discount';
    }
  }

  DiscountCategory get category {
    switch (this) {
      case AutoDiscountType.firstBooking:
        return DiscountCategory.firstBooking;
      case AutoDiscountType.earlyBird:
      case AutoDiscountType.longStay:
      case AutoDiscountType.lastMinute:
      case AutoDiscountType.weekdayStay:
        return DiscountCategory.platform;
      case AutoDiscountType.loyalty:
        return DiscountCategory.loyalty;
      case AutoDiscountType.referral:
        return DiscountCategory.referral;
      case AutoDiscountType.repeatGuest:
        return DiscountCategory.platform;
    }
  }

  int get priority {
    switch (this) {
      case AutoDiscountType.loyalty:
        return 10;
      case AutoDiscountType.referral:
        return 9;
      case AutoDiscountType.firstBooking:
        return 8;
      case AutoDiscountType.repeatGuest:
        return 7;
      case AutoDiscountType.earlyBird:
        return 6;
      case AutoDiscountType.longStay:
        return 5;
      case AutoDiscountType.lastMinute:
        return 4;
      case AutoDiscountType.weekdayStay:
        return 3;
    }
  }
}

/// Configuration for auto-discount detection
class AutoDiscountConfig {
  const AutoDiscountConfig({
    this.earlyBirdDaysAhead = 30,
    this.earlyBirdDiscountPercent = 10,
    this.longStayMinNights = 7,
    this.longStayDiscountPercent = 15,
    this.lastMinuteDaysAhead = 3,
    this.lastMinuteDiscountPercent = 20,
    this.firstBookingDiscountPercent = 10,
    this.weekdayDiscountPercent = 5,
    this.repeatGuestDiscountPercent = 5,
    this.repeatGuestMinBookings = 2,
  });

  /// Days ahead for early bird discount
  final int earlyBirdDaysAhead;
  final double earlyBirdDiscountPercent;

  /// Minimum nights for long stay discount
  final int longStayMinNights;
  final double longStayDiscountPercent;

  /// Days ahead for last minute discount
  final int lastMinuteDaysAhead;
  final double lastMinuteDiscountPercent;

  /// First booking discount
  final double firstBookingDiscountPercent;

  /// Weekday discount
  final double weekdayDiscountPercent;

  /// Repeat guest requirements
  final double repeatGuestDiscountPercent;
  final int repeatGuestMinBookings;

  static const standard = AutoDiscountConfig();

  static const generous = AutoDiscountConfig(
    earlyBirdDaysAhead: 21,
    earlyBirdDiscountPercent: 15,
    longStayMinNights: 5,
    longStayDiscountPercent: 20,
    lastMinuteDaysAhead: 5,
    lastMinuteDiscountPercent: 25,
    firstBookingDiscountPercent: 15,
    weekdayDiscountPercent: 8,
    repeatGuestDiscountPercent: 8,
    repeatGuestMinBookings: 1,
  );
}

/// Detected discount with metadata
class DetectedDiscount {
  const DetectedDiscount({
    required this.type,
    required this.discount,
    required this.reason,
    this.expiresAt,
    this.metadata,
  });

  final AutoDiscountType type;
  final Discount discount;
  final String reason;
  final DateTime? expiresAt;
  final Map<String, dynamic>? metadata;

  /// Whether this discount is about to expire
  bool get isExpiringSoon {
    if (expiresAt == null) return false;
    return expiresAt!.difference(DateTime.now()).inHours < 24;
  }

  /// Display message for the user
  String get displayMessage {
    final value = discount.type == DiscountType.percentage
        ? '${discount.value.toStringAsFixed(0)}%'
        : '৳${discount.value.toStringAsFixed(0)}';
    return '$value off - ${type.description}';
  }
}

/// Result of auto-discount detection
class AutoDiscountResult {
  const AutoDiscountResult({
    required this.detectedDiscounts,
    required this.totalPotentialSavings,
    this.bestCombination,
  });

  final List<DetectedDiscount> detectedDiscounts;
  final double totalPotentialSavings;
  final List<DetectedDiscount>? bestCombination;

  bool get hasDiscounts => detectedDiscounts.isNotEmpty;
  int get discountCount => detectedDiscounts.length;

  /// Get highest value discount
  DetectedDiscount? get bestDiscount {
    if (detectedDiscounts.isEmpty) return null;
    return detectedDiscounts.reduce((a, b) =>
        a.discount.value > b.discount.value ? a : b);
  }

  /// Get discounts by type
  List<DetectedDiscount> byType(AutoDiscountType type) {
    return detectedDiscounts.where((d) => d.type == type).toList();
  }

  /// Get summary message
  String get summaryMessage {
    if (!hasDiscounts) return 'No discounts available';
    if (discountCount == 1) {
      return detectedDiscounts.first.displayMessage;
    }
    return '$discountCount discounts available - Save up to ৳${totalPotentialSavings.toStringAsFixed(0)}';
  }
}

/// Context for auto-discount detection
class AutoDiscountContext {
  const AutoDiscountContext({
    required this.userId,
    required this.bookingAmount,
    required this.nights,
    required this.checkInDate,
    required this.checkOutDate,
    this.listingId,
    this.hostId,
    this.isFirstBooking = false,
    this.previousBookingsCount = 0,
    this.userLoyalty,
    this.hasReferralDiscount = false,
    this.referralDiscountAmount,
  });

  final String userId;
  final double bookingAmount;
  final int nights;
  final DateTime checkInDate;
  final DateTime checkOutDate;
  final String? listingId;
  final String? hostId;
  final bool isFirstBooking;
  final int previousBookingsCount;
  final UserLoyalty? userLoyalty;
  final bool hasReferralDiscount;
  final double? referralDiscountAmount;

  /// Days until check-in
  int get daysUntilCheckIn {
    return checkInDate.difference(DateTime.now()).inDays;
  }

  /// Whether check-in is on a weekday
  bool get isWeekdayCheckIn {
    final day = checkInDate.weekday;
    return day >= 1 && day <= 4; // Mon-Thu
  }

  /// Whether entire stay is on weekdays
  bool get isFullWeekdayStay {
    var current = checkInDate;
    while (current.isBefore(checkOutDate)) {
      if (current.weekday >= 5) return false; // Fri, Sat, Sun
      current = current.add(const Duration(days: 1));
    }
    return true;
  }
}

/// Auto-discount detection service
abstract class AutoDiscountService {
  /// Detect all applicable auto-discounts
  Future<AutoDiscountResult> detectDiscounts(AutoDiscountContext context);

  /// Get specific discount by type
  Future<DetectedDiscount?> getDiscount(
    AutoDiscountType type,
    AutoDiscountContext context,
  );

  /// Check if user qualifies for early bird discount
  Future<bool> qualifiesForEarlyBird(AutoDiscountContext context);

  /// Check if user qualifies for long stay discount
  Future<bool> qualifiesForLongStay(AutoDiscountContext context);

  /// Check if user qualifies for last minute discount
  Future<bool> qualifiesForLastMinute(AutoDiscountContext context);
}

/// In-memory implementation
class InMemoryAutoDiscountService implements AutoDiscountService {
  InMemoryAutoDiscountService({
    LoyaltyService? loyaltyService,
    ReferralService? referralService,
    AutoDiscountConfig config = AutoDiscountConfig.standard,
  })  : _loyaltyService = loyaltyService ?? InMemoryLoyaltyService(),
        _referralService = referralService ?? InMemoryReferralService(),
        _config = config;

  final LoyaltyService _loyaltyService;
  final ReferralService _referralService;
  final AutoDiscountConfig _config;

  @override
  Future<AutoDiscountResult> detectDiscounts(AutoDiscountContext context) async {
    final detected = <DetectedDiscount>[];
    double totalSavings = 0;

    // Check first booking discount
    if (context.isFirstBooking) {
      final discount = _createFirstBookingDiscount(context);
      detected.add(discount);
      totalSavings += _calculateSavings(discount.discount, context.bookingAmount, context.nights);
    }

    // Check early bird discount
    if (await qualifiesForEarlyBird(context)) {
      final discount = _createEarlyBirdDiscount(context);
      detected.add(discount);
      totalSavings += _calculateSavings(discount.discount, context.bookingAmount, context.nights);
    }

    // Check long stay discount
    if (await qualifiesForLongStay(context)) {
      final discount = _createLongStayDiscount(context);
      detected.add(discount);
      totalSavings += _calculateSavings(discount.discount, context.bookingAmount, context.nights);
    }

    // Check last minute discount
    if (await qualifiesForLastMinute(context)) {
      final discount = _createLastMinuteDiscount(context);
      detected.add(discount);
      totalSavings += _calculateSavings(discount.discount, context.bookingAmount, context.nights);
    }

    // Check weekday discount
    if (context.isFullWeekdayStay) {
      final discount = _createWeekdayDiscount(context);
      detected.add(discount);
      totalSavings += _calculateSavings(discount.discount, context.bookingAmount, context.nights);
    }

    // Check repeat guest discount
    if (context.previousBookingsCount >= _config.repeatGuestMinBookings) {
      final discount = _createRepeatGuestDiscount(context);
      detected.add(discount);
      totalSavings += _calculateSavings(discount.discount, context.bookingAmount, context.nights);
    }

    // Check loyalty discount
    final loyaltyDiscount = await _checkLoyaltyDiscount(context);
    if (loyaltyDiscount != null) {
      detected.add(loyaltyDiscount);
      totalSavings += _calculateSavings(loyaltyDiscount.discount, context.bookingAmount, context.nights);
    }

    // Check referral discount
    if (context.hasReferralDiscount && context.referralDiscountAmount != null) {
      final discount = _createReferralDiscount(context);
      detected.add(discount);
      totalSavings += context.referralDiscountAmount!;
    }

    // Sort by priority
    detected.sort((a, b) => b.type.priority.compareTo(a.type.priority));

    // Find best combination (non-exclusive stackable discounts)
    final bestCombination = _findBestCombination(detected, context);

    print('╔══════════════════════════════════════════════════════════════╗');
    print('║              AUTO-DISCOUNTS DETECTED                         ║');
    print('╠══════════════════════════════════════════════════════════════╣');
    print('║ User: ${context.userId}');
    print('║ Booking Amount: ৳${context.bookingAmount.toStringAsFixed(0)}');
    print('║ Nights: ${context.nights}');
    print('║ Discounts Found: ${detected.length}');
    for (final d in detected) {
      print('║   - ${d.type.displayName}: ${d.discount.value}%');
    }
    print('║ Total Potential Savings: ৳${totalSavings.toStringAsFixed(0)}');
    print('╚══════════════════════════════════════════════════════════════╝');

    return AutoDiscountResult(
      detectedDiscounts: detected,
      totalPotentialSavings: totalSavings,
      bestCombination: bestCombination,
    );
  }

  @override
  Future<DetectedDiscount?> getDiscount(
    AutoDiscountType type,
    AutoDiscountContext context,
  ) async {
    switch (type) {
      case AutoDiscountType.firstBooking:
        if (context.isFirstBooking) {
          return _createFirstBookingDiscount(context);
        }
        break;
      case AutoDiscountType.earlyBird:
        if (await qualifiesForEarlyBird(context)) {
          return _createEarlyBirdDiscount(context);
        }
        break;
      case AutoDiscountType.longStay:
        if (await qualifiesForLongStay(context)) {
          return _createLongStayDiscount(context);
        }
        break;
      case AutoDiscountType.lastMinute:
        if (await qualifiesForLastMinute(context)) {
          return _createLastMinuteDiscount(context);
        }
        break;
      case AutoDiscountType.loyalty:
        return _checkLoyaltyDiscount(context);
      case AutoDiscountType.referral:
        if (context.hasReferralDiscount) {
          return _createReferralDiscount(context);
        }
        break;
      case AutoDiscountType.weekdayStay:
        if (context.isFullWeekdayStay) {
          return _createWeekdayDiscount(context);
        }
        break;
      case AutoDiscountType.repeatGuest:
        if (context.previousBookingsCount >= _config.repeatGuestMinBookings) {
          return _createRepeatGuestDiscount(context);
        }
        break;
    }
    return null;
  }

  @override
  Future<bool> qualifiesForEarlyBird(AutoDiscountContext context) async {
    return context.daysUntilCheckIn >= _config.earlyBirdDaysAhead;
  }

  @override
  Future<bool> qualifiesForLongStay(AutoDiscountContext context) async {
    return context.nights >= _config.longStayMinNights;
  }

  @override
  Future<bool> qualifiesForLastMinute(AutoDiscountContext context) async {
    return context.daysUntilCheckIn <= _config.lastMinuteDaysAhead &&
        context.daysUntilCheckIn >= 0;
  }

  // Private helper methods

  DetectedDiscount _createFirstBookingDiscount(AutoDiscountContext context) {
    return DetectedDiscount(
      type: AutoDiscountType.firstBooking,
      discount: Discount(
        id: 'auto_first_booking',
        name: 'First Booking Discount',
        description: 'Welcome! Enjoy ${_config.firstBookingDiscountPercent.toStringAsFixed(0)}% off your first booking',
        type: DiscountType.percentage,
        category: DiscountCategory.firstBooking,
        status: DiscountStatus.active,
        value: _config.firstBookingDiscountPercent,
        startsAt: DateTime.now().subtract(const Duration(days: 365)),
        stackingBehavior: StackingBehavior.stackable,
        stackableWithCategories: [
          DiscountCategory.loyalty,
          DiscountCategory.platform,
        ],
        priority: AutoDiscountType.firstBooking.priority,
      ),
      reason: 'This is your first booking with us!',
    );
  }

  DetectedDiscount _createEarlyBirdDiscount(AutoDiscountContext context) {
    return DetectedDiscount(
      type: AutoDiscountType.earlyBird,
      discount: Discount(
        id: 'auto_early_bird',
        name: 'Early Bird Discount',
        description: 'Book ${_config.earlyBirdDaysAhead}+ days ahead and save ${_config.earlyBirdDiscountPercent.toStringAsFixed(0)}%',
        type: DiscountType.percentage,
        category: DiscountCategory.platform,
        status: DiscountStatus.active,
        value: _config.earlyBirdDiscountPercent,
        startsAt: DateTime.now().subtract(const Duration(days: 365)),
        stackingBehavior: StackingBehavior.stackable,
        stackableWithCategories: [
          DiscountCategory.loyalty,
          DiscountCategory.firstBooking,
        ],
        priority: AutoDiscountType.earlyBird.priority,
      ),
      reason: 'Booking ${context.daysUntilCheckIn} days in advance',
      metadata: {'daysAhead': context.daysUntilCheckIn},
    );
  }

  DetectedDiscount _createLongStayDiscount(AutoDiscountContext context) {
    return DetectedDiscount(
      type: AutoDiscountType.longStay,
      discount: Discount(
        id: 'auto_long_stay',
        name: 'Long Stay Discount',
        description: 'Stay ${_config.longStayMinNights}+ nights and save ${_config.longStayDiscountPercent.toStringAsFixed(0)}%',
        type: DiscountType.percentage,
        category: DiscountCategory.platform,
        status: DiscountStatus.active,
        value: _config.longStayDiscountPercent,
        startsAt: DateTime.now().subtract(const Duration(days: 365)),
        stackingBehavior: StackingBehavior.stackable,
        stackableWithCategories: [
          DiscountCategory.loyalty,
          DiscountCategory.firstBooking,
        ],
        priority: AutoDiscountType.longStay.priority,
      ),
      reason: 'Staying for ${context.nights} nights',
      metadata: {'nights': context.nights},
    );
  }

  DetectedDiscount _createLastMinuteDiscount(AutoDiscountContext context) {
    return DetectedDiscount(
      type: AutoDiscountType.lastMinute,
      discount: Discount(
        id: 'auto_last_minute',
        name: 'Last Minute Deal',
        description: 'Book within ${_config.lastMinuteDaysAhead} days and save ${_config.lastMinuteDiscountPercent.toStringAsFixed(0)}%',
        type: DiscountType.percentage,
        category: DiscountCategory.platform,
        status: DiscountStatus.active,
        value: _config.lastMinuteDiscountPercent,
        startsAt: DateTime.now().subtract(const Duration(days: 365)),
        stackingBehavior: StackingBehavior.exclusive, // Doesn't stack with early bird
        priority: AutoDiscountType.lastMinute.priority,
      ),
      reason: 'Booking ${context.daysUntilCheckIn} days before check-in',
      expiresAt: context.checkInDate,
      metadata: {'daysUntilCheckIn': context.daysUntilCheckIn},
    );
  }

  DetectedDiscount _createWeekdayDiscount(AutoDiscountContext context) {
    return DetectedDiscount(
      type: AutoDiscountType.weekdayStay,
      discount: Discount(
        id: 'auto_weekday',
        name: 'Weekday Special',
        description: 'Save ${_config.weekdayDiscountPercent.toStringAsFixed(0)}% on weekday stays',
        type: DiscountType.percentage,
        category: DiscountCategory.platform,
        status: DiscountStatus.active,
        value: _config.weekdayDiscountPercent,
        startsAt: DateTime.now().subtract(const Duration(days: 365)),
        stackingBehavior: StackingBehavior.stackable,
        stackableWithCategories: [
          DiscountCategory.loyalty,
          DiscountCategory.firstBooking,
          DiscountCategory.platform,
        ],
        priority: AutoDiscountType.weekdayStay.priority,
      ),
      reason: 'Full weekday stay (Mon-Thu)',
    );
  }

  DetectedDiscount _createRepeatGuestDiscount(AutoDiscountContext context) {
    return DetectedDiscount(
      type: AutoDiscountType.repeatGuest,
      discount: Discount(
        id: 'auto_repeat_guest',
        name: 'Repeat Guest Discount',
        description: 'Thank you for coming back! Save ${_config.repeatGuestDiscountPercent.toStringAsFixed(0)}%',
        type: DiscountType.percentage,
        category: DiscountCategory.platform,
        status: DiscountStatus.active,
        value: _config.repeatGuestDiscountPercent,
        startsAt: DateTime.now().subtract(const Duration(days: 365)),
        stackingBehavior: StackingBehavior.stackable,
        stackableWithCategories: [
          DiscountCategory.loyalty,
          DiscountCategory.platform,
        ],
        priority: AutoDiscountType.repeatGuest.priority,
      ),
      reason: '${context.previousBookingsCount} previous bookings',
      metadata: {'previousBookings': context.previousBookingsCount},
    );
  }

  DetectedDiscount _createReferralDiscount(AutoDiscountContext context) {
    return DetectedDiscount(
      type: AutoDiscountType.referral,
      discount: Discount(
        id: 'auto_referral',
        name: 'Referral Discount',
        description: 'Referral reward: ৳${context.referralDiscountAmount?.toStringAsFixed(0) ?? '0'} off',
        type: DiscountType.fixedAmount,
        category: DiscountCategory.referral,
        status: DiscountStatus.active,
        value: context.referralDiscountAmount ?? 0,
        startsAt: DateTime.now().subtract(const Duration(days: 365)),
        stackingBehavior: StackingBehavior.stackable,
        stackableWithCategories: [
          DiscountCategory.loyalty,
          DiscountCategory.platform,
          DiscountCategory.firstBooking,
        ],
        priority: AutoDiscountType.referral.priority,
      ),
      reason: 'Applied referral code',
    );
  }

  Future<DetectedDiscount?> _checkLoyaltyDiscount(
      AutoDiscountContext context) async {
    // Check if user has loyalty data
    if (context.userLoyalty == null) {
      final result = await _loyaltyService.getUserLoyalty(context.userId);
      if (result.isFailure || result.data == null) return null;

      final loyalty = result.data!;
      if (loyalty.currentTier == null || loyalty.discountPercentage <= 0) {
        return null;
      }

      return DetectedDiscount(
        type: AutoDiscountType.loyalty,
        discount: Discount(
          id: 'auto_loyalty_${loyalty.currentTierId}',
          name: '${loyalty.tierName} Member Discount',
          description: '${loyalty.discountPercentage.toStringAsFixed(0)}% off for ${loyalty.tierName} members',
          type: DiscountType.percentage,
          category: DiscountCategory.loyalty,
          status: DiscountStatus.active,
          value: loyalty.discountPercentage,
          startsAt: DateTime.now().subtract(const Duration(days: 365)),
          stackingBehavior: StackingBehavior.stackable,
          stackableWithCategories: [
            DiscountCategory.platform,
            DiscountCategory.host,
            DiscountCategory.referral,
          ],
          priority: AutoDiscountType.loyalty.priority,
        ),
        reason: '${loyalty.tierName} tier member',
        metadata: {
          'tier': loyalty.tierName,
          'level': loyalty.tierLevel.level,
        },
      );
    }

    final loyalty = context.userLoyalty!;
    if (loyalty.discountPercentage <= 0) return null;

    return DetectedDiscount(
      type: AutoDiscountType.loyalty,
      discount: Discount(
        id: 'auto_loyalty_${loyalty.currentTierId}',
        name: '${loyalty.tierName} Member Discount',
        description: '${loyalty.discountPercentage.toStringAsFixed(0)}% off for ${loyalty.tierName} members',
        type: DiscountType.percentage,
        category: DiscountCategory.loyalty,
        status: DiscountStatus.active,
        value: loyalty.discountPercentage,
        startsAt: DateTime.now().subtract(const Duration(days: 365)),
        stackingBehavior: StackingBehavior.stackable,
        stackableWithCategories: [
          DiscountCategory.platform,
          DiscountCategory.host,
          DiscountCategory.referral,
        ],
        priority: AutoDiscountType.loyalty.priority,
      ),
      reason: '${loyalty.tierName} tier member',
      metadata: {
        'tier': loyalty.tierName,
        'level': loyalty.tierLevel.level,
      },
    );
  }

  List<DetectedDiscount> _findBestCombination(
    List<DetectedDiscount> discounts,
    AutoDiscountContext context,
  ) {
    if (discounts.isEmpty) return [];

    // Filter out exclusive discounts if there are stackable ones
    final stackable = discounts
        .where((d) => d.discount.stackingBehavior != StackingBehavior.exclusive)
        .toList();

    final exclusive = discounts
        .where((d) => d.discount.stackingBehavior == StackingBehavior.exclusive)
        .toList();

    // Calculate stackable total
    double stackableTotal = 0;
    for (final d in stackable) {
      stackableTotal += _calculateSavings(d.discount, context.bookingAmount, context.nights);
    }

    // Find best exclusive
    double bestExclusiveValue = 0;
    DetectedDiscount? bestExclusive;
    for (final d in exclusive) {
      final value = _calculateSavings(d.discount, context.bookingAmount, context.nights);
      if (value > bestExclusiveValue) {
        bestExclusiveValue = value;
        bestExclusive = d;
      }
    }

    // Return whichever combination is better
    if (bestExclusiveValue > stackableTotal && bestExclusive != null) {
      return [bestExclusive];
    }

    return stackable;
  }

  double _calculateSavings(Discount discount, double amount, int nights) {
    switch (discount.type) {
      case DiscountType.percentage:
        var savings = amount * (discount.value / 100);
        if (discount.maxDiscountAmount != null &&
            savings > discount.maxDiscountAmount!) {
          savings = discount.maxDiscountAmount!;
        }
        return savings;
      case DiscountType.fixedAmount:
        return discount.value.clamp(0, amount);
      case DiscountType.freeNights:
        if (discount.freeNightsConfig != null &&
            nights >= discount.freeNightsConfig!.stayNights) {
          final freeNights = discount.freeNightsConfig!.freeNights;
          final perNight = amount / nights;
          return freeNights * perNight;
        }
        return 0;
    }
  }
}
