import '../../core/discount/discount_engine.dart';
import '../../core/discount/stacking_rules.dart';
import '../../models/applied_discount.dart';
import '../../models/discount.dart';
import '../../models/discount_eligibility.dart';

/// Result wrapper for discount operations
class DiscountResult<T> {
  const DiscountResult.success(this.data)
      : error = null,
        errorCode = null;
  const DiscountResult.failure(this.error, [this.errorCode]) : data = null;

  final T? data;
  final String? error;
  final String? errorCode;

  bool get isSuccess => error == null;
  bool get isFailure => error != null;
}

/// Request for applying discounts to a booking
class ApplyDiscountsRequest {
  const ApplyDiscountsRequest({
    required this.userId,
    required this.bookingAmount,
    required this.nights,
    required this.checkInDate,
    this.bookingId,
    this.listingId,
    this.hostId,
    this.promoCode,
    this.autoApply = true,
  });

  final String userId;
  final double bookingAmount;
  final int nights;
  final DateTime checkInDate;
  final String? bookingId;
  final String? listingId;
  final String? hostId;
  final String? promoCode;
  final bool autoApply;
}

/// Abstract interface for discount service
abstract class DiscountService {
  /// Get all active discounts
  Future<DiscountResult<List<Discount>>> getActiveDiscounts();

  /// Get discounts for a specific listing/host
  Future<DiscountResult<List<Discount>>> getDiscountsForListing(String listingId);

  /// Get a discount by code
  Future<DiscountResult<Discount>> getDiscountByCode(String code);

  /// Get a discount by ID
  Future<DiscountResult<Discount>> getDiscountById(String id);

  /// Get user's discount usage count for a specific discount
  Future<DiscountResult<int>> getUserDiscountUsageCount(
      String userId, String discountId);

  /// Get user's applied discounts history
  Future<DiscountResult<List<AppliedDiscount>>> getUserAppliedDiscounts(
      String userId);

  /// Apply discounts to a booking
  Future<DiscountResult<DiscountSummary>> applyDiscounts(
      ApplyDiscountsRequest request);

  /// Validate a promo code
  Future<DiscountResult<DiscountEligibilityResult>> validatePromoCode({
    required String code,
    required DiscountEligibilityContext context,
  });

  /// Reverse a discount application
  Future<DiscountResult<void>> reverseDiscount(
      String usageId, String reason);

  /// Create a host discount
  Future<DiscountResult<Discount>> createHostDiscount({
    required String hostId,
    required String name,
    required DiscountType type,
    required double value,
    String? description,
    List<String>? listingIds,
    int? minNights,
    DateTime? startsAt,
    DateTime? endsAt,
  });

  /// Check if user is eligible for first booking discount
  Future<DiscountResult<bool>> isEligibleForFirstBookingDiscount(String userId);

  /// Get user's loyalty tier discount
  Future<DiscountResult<Discount?>> getLoyaltyDiscount(String userId);
}

/// In-memory implementation for development
class InMemoryDiscountService implements DiscountService {
  InMemoryDiscountService() {
    _initializeSampleData();
  }

  final DiscountEngine _engine = DiscountEngine(
    stackingRules: StackingRulesEngine(
      config: StackingRulesConfig.moderate,
    ),
  );

  final List<Discount> _discounts = [];
  final List<AppliedDiscount> _appliedDiscounts = [];
  final Map<String, int> _userBookingCounts = {};
  final Map<String, Map<String, int>> _userDiscountUsage = {};

  void _initializeSampleData() {
    final now = DateTime.now();

    _discounts.addAll([
      // Welcome discount
      Discount(
        id: 'disc_welcome',
        code: 'WELCOME500',
        name: 'Welcome Discount',
        description: 'Get ৳500 off your first booking!',
        type: DiscountType.fixedAmount,
        category: DiscountCategory.firstBooking,
        status: DiscountStatus.active,
        value: 500,
        minBookingAmount: 2000,
        startsAt: now.subtract(const Duration(days: 365)),
        perUserLimit: 1,
        firstBookingOnly: true,
        stackingBehavior: StackingBehavior.stackable,
      ),

      // Early bird discount
      Discount(
        id: 'disc_earlybird',
        code: 'EARLYBIRD10',
        name: 'Early Bird Discount',
        description: '10% off when you book 30+ days in advance',
        type: DiscountType.percentage,
        category: DiscountCategory.platform,
        status: DiscountStatus.active,
        value: 10,
        minBookingAmount: 5000,
        minNights: 2,
        startsAt: now.subtract(const Duration(days: 30)),
        stackingBehavior: StackingBehavior.bestOnly,
        maxDiscountAmount: 3000,
      ),

      // Long stay discount
      Discount(
        id: 'disc_longstay',
        code: 'LONGSTAY15',
        name: 'Long Stay Discount',
        description: '15% off for stays of 7+ nights',
        type: DiscountType.percentage,
        category: DiscountCategory.platform,
        status: DiscountStatus.active,
        value: 15,
        minBookingAmount: 10000,
        minNights: 7,
        startsAt: now.subtract(const Duration(days: 60)),
        stackingBehavior: StackingBehavior.stackable,
        stackableWithCategories: [
          DiscountCategory.loyalty,
          DiscountCategory.referral,
        ],
      ),

      // Weekend special
      Discount(
        id: 'disc_weekend',
        code: 'WEEKEND20',
        name: 'Weekend Special',
        description: '20% off weekend stays (max ৳2000)',
        type: DiscountType.percentage,
        category: DiscountCategory.seasonal,
        status: DiscountStatus.active,
        value: 20,
        minBookingAmount: 3000,
        minNights: 2,
        startsAt: now.subtract(const Duration(days: 14)),
        perUserLimit: 2,
        maxDiscountAmount: 2000,
        allowedCheckInDays: [5, 6, 0], // Fri, Sat, Sun
        stackingBehavior: StackingBehavior.exclusive,
      ),

      // Free nights deal
      Discount(
        id: 'disc_freenights',
        name: 'Stay 7, Pay 5',
        description: 'Book 7 nights and get 2 nights free!',
        type: DiscountType.freeNights,
        category: DiscountCategory.platform,
        status: DiscountStatus.active,
        value: 0,
        minNights: 7,
        startsAt: now.subtract(const Duration(days: 90)),
        freeNightsConfig: const FreeNightsConfig(stayNights: 7, payNights: 5),
        stackingBehavior: StackingBehavior.exclusive,
      ),

      // Auto-applied loyalty discount (no code)
      Discount(
        id: 'disc_loyalty_silver',
        name: 'Silver Member Discount',
        description: '3% off for Silver tier members',
        type: DiscountType.percentage,
        category: DiscountCategory.loyalty,
        status: DiscountStatus.active,
        value: 3,
        startsAt: now.subtract(const Duration(days: 365)),
        stackingBehavior: StackingBehavior.stackable,
        priority: 10,
      ),
    ]);
  }

  @override
  Future<DiscountResult<List<Discount>>> getActiveDiscounts() async {
    await Future.delayed(const Duration(milliseconds: 200));

    final active = _discounts
        .where((d) =>
            d.status == DiscountStatus.active &&
            d.startsAt.isBefore(DateTime.now()) &&
            (d.endsAt == null || d.endsAt!.isAfter(DateTime.now())))
        .toList();

    return DiscountResult.success(active);
  }

  @override
  Future<DiscountResult<List<Discount>>> getDiscountsForListing(
      String listingId) async {
    await Future.delayed(const Duration(milliseconds: 200));

    final discounts = _discounts.where((d) {
      if (!d.isCurrentlyValid) return false;
      if (d.eligibleListingIds == null) return true;
      return d.eligibleListingIds!.contains(listingId);
    }).toList();

    return DiscountResult.success(discounts);
  }

  @override
  Future<DiscountResult<Discount>> getDiscountByCode(String code) async {
    await Future.delayed(const Duration(milliseconds: 150));

    final discount = _discounts.cast<Discount?>().firstWhere(
          (d) => d?.code?.toUpperCase() == code.toUpperCase(),
          orElse: () => null,
        );

    if (discount == null) {
      return const DiscountResult.failure('Promo code not found', 'NOT_FOUND');
    }

    return DiscountResult.success(discount);
  }

  @override
  Future<DiscountResult<Discount>> getDiscountById(String id) async {
    await Future.delayed(const Duration(milliseconds: 100));

    final discount = _discounts.cast<Discount?>().firstWhere(
          (d) => d?.id == id,
          orElse: () => null,
        );

    if (discount == null) {
      return const DiscountResult.failure('Discount not found', 'NOT_FOUND');
    }

    return DiscountResult.success(discount);
  }

  @override
  Future<DiscountResult<int>> getUserDiscountUsageCount(
      String userId, String discountId) async {
    await Future.delayed(const Duration(milliseconds: 100));

    final userUsage = _userDiscountUsage[userId];
    if (userUsage == null) {
      return const DiscountResult.success(0);
    }

    return DiscountResult.success(userUsage[discountId] ?? 0);
  }

  @override
  Future<DiscountResult<List<AppliedDiscount>>> getUserAppliedDiscounts(
      String userId) async {
    await Future.delayed(const Duration(milliseconds: 200));

    final userDiscounts = _appliedDiscounts
        .where((d) => d.userId == userId && !d.isReversed)
        .toList();

    return DiscountResult.success(userDiscounts);
  }

  @override
  Future<DiscountResult<DiscountSummary>> applyDiscounts(
      ApplyDiscountsRequest request) async {
    await Future.delayed(const Duration(milliseconds: 300));

    // Build eligibility context
    final isFirstBooking =
        (_userBookingCounts[request.userId] ?? 0) == 0;

    final discountsToCheck = <Discount>[];

    // Add promo code discount if provided
    if (request.promoCode != null) {
      final codeResult = await getDiscountByCode(request.promoCode!);
      if (codeResult.isSuccess && codeResult.data != null) {
        discountsToCheck.add(codeResult.data!);
      } else {
        return DiscountResult.failure(
          'Invalid promo code: ${request.promoCode}',
          'INVALID_CODE',
        );
      }
    }

    // Add auto-applicable discounts if enabled
    if (request.autoApply) {
      final activeResult = await getActiveDiscounts();
      if (activeResult.isSuccess && activeResult.data != null) {
        final autoDiscounts = activeResult.data!.where((d) => d.code == null);
        discountsToCheck.addAll(autoDiscounts);
      }
    }

    // Build context with usage counts
    var context = DiscountEligibilityContext(
      userId: request.userId,
      bookingAmount: request.bookingAmount,
      nights: request.nights,
      checkInDate: request.checkInDate,
      listingId: request.listingId,
      hostId: request.hostId,
      isFirstBooking: isFirstBooking,
      isNewUser: isFirstBooking,
    );

    // Update context with usage counts for each discount
    for (final discount in discountsToCheck) {
      final usageResult =
          await getUserDiscountUsageCount(request.userId, discount.id);
      if (usageResult.isSuccess) {
        context = context.copyWith(
          userDiscountUsageCount: usageResult.data ?? 0,
        );
      }
    }

    // Apply discounts using engine
    final result = _engine.applyDiscounts(
      discounts: discountsToCheck,
      context: context,
    );

    // Record usage for applied discounts
    if (result.hasDiscounts) {
      for (final applied in result.appliedDiscounts) {
        final appliedDiscount = AppliedDiscount(
          id: 'usage_${DateTime.now().millisecondsSinceEpoch}_${applied.discount.id}',
          discountId: applied.discount.id,
          userId: request.userId,
          bookingId: request.bookingId,
          listingId: request.listingId,
          originalAmount: request.bookingAmount,
          discountAmount: applied.calculatedAmount ?? 0,
          finalAmount: result.finalAmount,
          appliedAt: DateTime.now(),
          stackedWith: result.appliedDiscounts
              .where((d) => d.discount.id != applied.discount.id)
              .map((d) => d.discount.id)
              .toList(),
          discount: applied.discount,
        );
        _appliedDiscounts.add(appliedDiscount);

        // Update usage count
        _userDiscountUsage.putIfAbsent(request.userId, () => {});
        _userDiscountUsage[request.userId]![applied.discount.id] =
            (_userDiscountUsage[request.userId]![applied.discount.id] ?? 0) + 1;
      }
    }

    return DiscountResult.success(result.toSummary());
  }

  @override
  Future<DiscountResult<DiscountEligibilityResult>> validatePromoCode({
    required String code,
    required DiscountEligibilityContext context,
  }) async {
    final discountResult = await getDiscountByCode(code);

    if (discountResult.isFailure) {
      return DiscountResult.failure(
        discountResult.error ?? 'Invalid promo code',
        'INVALID_CODE',
      );
    }

    final discount = discountResult.data!;

    // Get user's usage count for this discount
    final usageResult =
        await getUserDiscountUsageCount(context.userId, discount.id);
    final usageCount = usageResult.data ?? 0;

    // Update context with usage count
    final updatedContext = context.copyWith(userDiscountUsageCount: usageCount);

    // Validate using engine
    final result = _engine.validatePromoCode(
      discount: discount,
      context: updatedContext,
    );

    return DiscountResult.success(result);
  }

  @override
  Future<DiscountResult<void>> reverseDiscount(
      String usageId, String reason) async {
    await Future.delayed(const Duration(milliseconds: 200));

    final index = _appliedDiscounts.indexWhere((d) => d.id == usageId);
    if (index == -1) {
      return const DiscountResult.failure('Usage not found', 'NOT_FOUND');
    }

    final applied = _appliedDiscounts[index];
    _appliedDiscounts[index] = applied.copyWith(
      isReversed: true,
      reversedAt: DateTime.now(),
      reversalReason: reason,
    );

    // Decrease usage count
    if (_userDiscountUsage.containsKey(applied.userId)) {
      final currentCount =
          _userDiscountUsage[applied.userId]![applied.discountId] ?? 0;
      if (currentCount > 0) {
        _userDiscountUsage[applied.userId]![applied.discountId] =
            currentCount - 1;
      }
    }

    return const DiscountResult.success(null);
  }

  @override
  Future<DiscountResult<Discount>> createHostDiscount({
    required String hostId,
    required String name,
    required DiscountType type,
    required double value,
    String? description,
    List<String>? listingIds,
    int? minNights,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

    final discount = Discount(
      id: 'disc_host_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      description: description,
      type: type,
      category: DiscountCategory.host,
      status: DiscountStatus.active,
      value: value,
      startsAt: startsAt ?? DateTime.now(),
      endsAt: endsAt,
      minNights: minNights ?? 1,
      eligibleListingIds: listingIds,
      hostId: hostId,
      stackingBehavior: StackingBehavior.stackable,
      stackableWithCategories: [
        DiscountCategory.platform,
        DiscountCategory.referral,
        DiscountCategory.loyalty,
      ],
    );

    _discounts.add(discount);
    return DiscountResult.success(discount);
  }

  @override
  Future<DiscountResult<bool>> isEligibleForFirstBookingDiscount(
      String userId) async {
    await Future.delayed(const Duration(milliseconds: 100));
    final bookingCount = _userBookingCounts[userId] ?? 0;
    return DiscountResult.success(bookingCount == 0);
  }

  @override
  Future<DiscountResult<Discount?>> getLoyaltyDiscount(String userId) async {
    await Future.delayed(const Duration(milliseconds: 150));

    // For demo, return silver tier discount
    final loyaltyDiscount = _discounts.cast<Discount?>().firstWhere(
          (d) => d?.category == DiscountCategory.loyalty && d?.code == null,
          orElse: () => null,
        );

    return DiscountResult.success(loyaltyDiscount);
  }

  /// For testing: set user's booking count
  void setUserBookingCount(String userId, int count) {
    _userBookingCounts[userId] = count;
  }

  /// For testing: add a discount
  void addDiscount(Discount discount) {
    _discounts.add(discount);
  }
}
