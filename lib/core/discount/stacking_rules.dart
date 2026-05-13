import '../../models/discount.dart';

/// Result of stacking calculation
class StackingResult {
  const StackingResult({
    required this.appliedDiscounts,
    required this.totalDiscount,
    required this.breakdown,
  });

  /// Discounts that were applied
  final List<Discount> appliedDiscounts;

  /// Total discount amount
  final double totalDiscount;

  /// Breakdown of each discount's contribution
  final List<StackingBreakdownItem> breakdown;

  /// Number of discounts applied
  int get count => appliedDiscounts.length;

  /// Whether multiple discounts were stacked
  bool get wasStacked => appliedDiscounts.length > 1;
}

/// Breakdown item showing each discount's contribution
class StackingBreakdownItem {
  const StackingBreakdownItem({
    required this.discount,
    required this.amount,
    required this.appliedToAmount,
  });

  /// The discount
  final Discount discount;

  /// Amount this discount contributed
  final double amount;

  /// The amount this discount was applied to
  final double appliedToAmount;
}

/// Engine for calculating discount stacking combinations
class StackingRulesEngine {
  /// Default stacking rules
  static const defaultRules = StackingRulesConfig();

  final StackingRulesConfig _config;

  StackingRulesEngine({StackingRulesConfig? config})
      : _config = config ?? defaultRules;

  /// Find the best combination of discounts
  StackingResult findBestCombination(
    List<Discount> eligibleDiscounts,
    double bookingAmount,
    int nights,
  ) {
    if (eligibleDiscounts.isEmpty) {
      return const StackingResult(
        appliedDiscounts: [],
        totalDiscount: 0,
        breakdown: [],
      );
    }

    // Sort by priority (lower = higher priority)
    final sorted = List<Discount>.from(eligibleDiscounts)
      ..sort((a, b) => a.priority.compareTo(b.priority));

    // Separate exclusive and stackable discounts
    final exclusiveDiscounts =
        sorted.where((d) => d.stackingBehavior == StackingBehavior.exclusive).toList();
    final stackableDiscounts =
        sorted.where((d) => d.stackingBehavior == StackingBehavior.stackable).toList();
    final bestOnlyDiscounts =
        sorted.where((d) => d.stackingBehavior == StackingBehavior.bestOnly).toList();

    // Calculate best exclusive discount
    StackingResult? bestExclusive;
    if (exclusiveDiscounts.isNotEmpty) {
      final best = _findBestSingle(exclusiveDiscounts, bookingAmount, nights);
      if (best != null) {
        bestExclusive = _createSingleResult(best, bookingAmount, nights);
      }
    }

    // Calculate best single best-only discount
    StackingResult? bestSingle;
    if (bestOnlyDiscounts.isNotEmpty) {
      final best = _findBestSingle(bestOnlyDiscounts, bookingAmount, nights);
      if (best != null) {
        bestSingle = _createSingleResult(best, bookingAmount, nights);
      }
    }

    // Calculate stacked discounts
    StackingResult? stackedResult;
    if (stackableDiscounts.isNotEmpty) {
      stackedResult = _calculateStackedDiscounts(
        stackableDiscounts,
        bookingAmount,
        nights,
      );
    }

    // Find the best overall result
    final candidates = <StackingResult>[
      if (bestExclusive != null) bestExclusive,
      if (bestSingle != null) bestSingle,
      if (stackedResult != null) stackedResult,
    ];

    if (candidates.isEmpty) {
      return const StackingResult(
        appliedDiscounts: [],
        totalDiscount: 0,
        breakdown: [],
      );
    }

    // Return the one with highest total discount
    return candidates.reduce((a, b) => a.totalDiscount >= b.totalDiscount ? a : b);
  }

  /// Find the best single discount from a list
  Discount? _findBestSingle(
    List<Discount> discounts,
    double bookingAmount,
    int nights,
  ) {
    Discount? best;
    double bestAmount = 0;

    for (final discount in discounts) {
      final amount = _calculateSingleDiscount(discount, bookingAmount, nights);
      if (amount > bestAmount) {
        best = discount;
        bestAmount = amount;
      }
    }

    return best;
  }

  /// Create result for a single discount
  StackingResult _createSingleResult(
    Discount discount,
    double bookingAmount,
    int nights,
  ) {
    final amount = _calculateSingleDiscount(discount, bookingAmount, nights);
    return StackingResult(
      appliedDiscounts: [discount],
      totalDiscount: amount,
      breakdown: [
        StackingBreakdownItem(
          discount: discount,
          amount: amount,
          appliedToAmount: bookingAmount,
        ),
      ],
    );
  }

  /// Calculate stacked discounts respecting category rules
  StackingResult _calculateStackedDiscounts(
    List<Discount> discounts,
    double bookingAmount,
    int nights,
  ) {
    final appliedDiscounts = <Discount>[];
    final breakdown = <StackingBreakdownItem>[];
    var remainingAmount = bookingAmount;
    var totalDiscount = 0.0;

    // Group by category for stacking rules
    final byCategory = <DiscountCategory, List<Discount>>{};
    for (final discount in discounts) {
      byCategory.putIfAbsent(discount.category, () => []).add(discount);
    }

    // Apply discounts in order based on config
    for (final category in _config.categoryOrder) {
      final categoryDiscounts = byCategory[category];
      if (categoryDiscounts == null || categoryDiscounts.isEmpty) continue;

      // Check if we've hit max discounts
      if (_config.maxStackedDiscounts != null &&
          appliedDiscounts.length >= _config.maxStackedDiscounts!) {
        break;
      }

      // Find best discount in this category
      final best = _findBestSingle(categoryDiscounts, remainingAmount, nights);
      if (best == null) continue;

      // Check if this category can stack with already applied categories
      final canStack = _canStackWithApplied(best, appliedDiscounts);
      if (!canStack) continue;

      // Calculate and apply
      final amount = _calculateSingleDiscount(best, remainingAmount, nights);
      if (amount <= 0) continue;

      appliedDiscounts.add(best);
      breakdown.add(StackingBreakdownItem(
        discount: best,
        amount: amount,
        appliedToAmount: remainingAmount,
      ));

      // Update for next iteration
      if (_config.applySequentially) {
        remainingAmount -= amount;
      }
      totalDiscount += amount;

      // Check max total discount
      if (_config.maxTotalDiscountPercentage != null) {
        final maxDiscount = bookingAmount * (_config.maxTotalDiscountPercentage! / 100);
        if (totalDiscount >= maxDiscount) {
          totalDiscount = maxDiscount;
          break;
        }
      }
    }

    return StackingResult(
      appliedDiscounts: appliedDiscounts,
      totalDiscount: totalDiscount,
      breakdown: breakdown,
    );
  }

  /// Check if a discount can stack with already applied discounts
  bool _canStackWithApplied(Discount discount, List<Discount> applied) {
    if (applied.isEmpty) return true;

    // Check if discount specifies stackable categories
    if (discount.stackableWithCategories != null) {
      for (final appliedDiscount in applied) {
        if (!discount.stackableWithCategories!.contains(appliedDiscount.category)) {
          return false;
        }
      }
    }

    // Check global rules
    for (final appliedDiscount in applied) {
      // Same category - check config
      if (appliedDiscount.category == discount.category) {
        if (!_config.allowSameCategoryStacking) {
          return false;
        }
      }

      // Check if applied discount restricts stacking
      if (appliedDiscount.stackableWithCategories != null &&
          !appliedDiscount.stackableWithCategories!.contains(discount.category)) {
        return false;
      }
    }

    return true;
  }

  /// Calculate discount amount for a single discount
  double _calculateSingleDiscount(
    Discount discount,
    double bookingAmount,
    int nights,
  ) {
    switch (discount.type) {
      case DiscountType.percentage:
        var amount = bookingAmount * (discount.value / 100);
        if (discount.maxDiscountAmount != null &&
            amount > discount.maxDiscountAmount!) {
          amount = discount.maxDiscountAmount!;
        }
        return amount;

      case DiscountType.fixedAmount:
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
}

/// Configuration for stacking rules
class StackingRulesConfig {
  const StackingRulesConfig({
    this.maxStackedDiscounts,
    this.maxTotalDiscountPercentage,
    this.applySequentially = true,
    this.allowSameCategoryStacking = false,
    this.categoryOrder = const [
      DiscountCategory.loyalty,
      DiscountCategory.referral,
      DiscountCategory.firstBooking,
      DiscountCategory.host,
      DiscountCategory.seasonal,
      DiscountCategory.platform,
      DiscountCategory.flashSale,
    ],
  });

  /// Maximum number of discounts that can be stacked
  final int? maxStackedDiscounts;

  /// Maximum total discount as percentage of booking
  final double? maxTotalDiscountPercentage;

  /// Whether to apply discounts sequentially (each on remaining amount)
  final bool applySequentially;

  /// Whether multiple discounts from same category can stack
  final bool allowSameCategoryStacking;

  /// Order in which categories are applied (first = highest priority)
  final List<DiscountCategory> categoryOrder;

  /// Strict rules: max 2 discounts, max 30% total
  static const strict = StackingRulesConfig(
    maxStackedDiscounts: 2,
    maxTotalDiscountPercentage: 30,
    allowSameCategoryStacking: false,
  );

  /// Moderate rules: max 3 discounts, max 50% total
  static const moderate = StackingRulesConfig(
    maxStackedDiscounts: 3,
    maxTotalDiscountPercentage: 50,
    allowSameCategoryStacking: false,
  );

  /// Generous rules: unlimited stacking, max 75% total
  static const generous = StackingRulesConfig(
    maxTotalDiscountPercentage: 75,
    allowSameCategoryStacking: true,
  );

  StackingRulesConfig copyWith({
    int? maxStackedDiscounts,
    double? maxTotalDiscountPercentage,
    bool? applySequentially,
    bool? allowSameCategoryStacking,
    List<DiscountCategory>? categoryOrder,
  }) {
    return StackingRulesConfig(
      maxStackedDiscounts: maxStackedDiscounts ?? this.maxStackedDiscounts,
      maxTotalDiscountPercentage:
          maxTotalDiscountPercentage ?? this.maxTotalDiscountPercentage,
      applySequentially: applySequentially ?? this.applySequentially,
      allowSameCategoryStacking:
          allowSameCategoryStacking ?? this.allowSameCategoryStacking,
      categoryOrder: categoryOrder ?? this.categoryOrder,
    );
  }
}
