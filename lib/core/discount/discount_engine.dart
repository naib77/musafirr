import '../../models/applied_discount.dart';
import '../../models/discount.dart';
import '../../models/discount_eligibility.dart';
import 'stacking_rules.dart';

/// Result of calculating discount amounts
class DiscountCalculationResult {
  const DiscountCalculationResult({
    required this.discountAmount,
    required this.finalAmount,
    this.freeNightsApplied = 0,
    this.cappedAt,
  });

  /// Amount discounted
  final double discountAmount;

  /// Final amount after discount
  final double finalAmount;

  /// Number of free nights (for free_nights type)
  final int freeNightsApplied;

  /// If max cap was applied, the cap amount
  final double? cappedAt;

  /// Whether the discount was capped
  bool get wasCapped => cappedAt != null;
}

/// Result of applying multiple discounts
class MultiDiscountResult {
  const MultiDiscountResult({
    required this.appliedDiscounts,
    required this.originalAmount,
    required this.totalDiscountAmount,
    required this.finalAmount,
    required this.rejectedDiscounts,
  });

  /// Discounts that were successfully applied
  final List<DiscountEligibilityResult> appliedDiscounts;

  /// Discounts that were rejected (with reasons)
  final List<DiscountEligibilityResult> rejectedDiscounts;

  /// Original booking amount
  final double originalAmount;

  /// Total discount amount
  final double totalDiscountAmount;

  /// Final amount after all discounts
  final double finalAmount;

  /// Number of discounts applied
  int get appliedCount => appliedDiscounts.length;

  /// Whether any discounts were applied
  bool get hasDiscounts => appliedDiscounts.isNotEmpty;

  /// Get summary
  DiscountSummary toSummary() {
    final applied = appliedDiscounts.map((e) {
      return AppliedDiscount(
        id: 'temp_${e.discount.id}',
        discountId: e.discount.id,
        userId: '',
        originalAmount: originalAmount,
        discountAmount: e.calculatedAmount ?? 0,
        finalAmount: finalAmount,
        appliedAt: DateTime.now(),
        discount: e.discount,
      );
    }).toList();

    return DiscountSummary.fromAppliedDiscounts(applied, originalAmount);
  }
}

/// Core discount calculation engine
class DiscountEngine {
  DiscountEngine({
    StackingRulesEngine? stackingRules,
  }) : _stackingRules = stackingRules ?? StackingRulesEngine();

  final StackingRulesEngine _stackingRules;

  /// Calculate the discount amount for a single discount
  DiscountCalculationResult calculateDiscountAmount({
    required Discount discount,
    required double bookingAmount,
    required int nights,
  }) {
    double discountAmount;
    int freeNightsApplied = 0;
    double? cappedAt;

    switch (discount.type) {
      case DiscountType.percentage:
        discountAmount = bookingAmount * (discount.value / 100);
        // Apply max cap if set
        if (discount.maxDiscountAmount != null &&
            discountAmount > discount.maxDiscountAmount!) {
          cappedAt = discount.maxDiscountAmount;
          discountAmount = discount.maxDiscountAmount!;
        }
        break;

      case DiscountType.fixedAmount:
        discountAmount = discount.value;
        // Don't exceed booking amount
        if (discountAmount > bookingAmount) {
          discountAmount = bookingAmount;
        }
        break;

      case DiscountType.freeNights:
        if (discount.freeNightsConfig != null &&
            nights >= discount.freeNightsConfig!.stayNights) {
          freeNightsApplied = discount.freeNightsConfig!.freeNights;
          final perNightRate = bookingAmount / nights;
          discountAmount = freeNightsApplied * perNightRate;
        } else {
          discountAmount = 0;
        }
        break;
    }

    return DiscountCalculationResult(
      discountAmount: discountAmount,
      finalAmount: bookingAmount - discountAmount,
      freeNightsApplied: freeNightsApplied,
      cappedAt: cappedAt,
    );
  }

  /// Check eligibility and calculate amount for a single discount
  DiscountEligibilityResult evaluateDiscount({
    required Discount discount,
    required DiscountEligibilityContext context,
  }) {
    return DiscountEligibilityChecker.check(discount, context);
  }

  /// Apply multiple discounts with stacking rules
  MultiDiscountResult applyDiscounts({
    required List<Discount> discounts,
    required DiscountEligibilityContext context,
  }) {
    final eligibleResults = <DiscountEligibilityResult>[];
    final rejectedResults = <DiscountEligibilityResult>[];

    // First, check eligibility for all discounts
    for (final discount in discounts) {
      final result = evaluateDiscount(
        discount: discount,
        context: context,
      );

      if (result.isEligible) {
        eligibleResults.add(result);
      } else {
        rejectedResults.add(result);
      }
    }

    if (eligibleResults.isEmpty) {
      return MultiDiscountResult(
        appliedDiscounts: const [],
        rejectedDiscounts: rejectedResults,
        originalAmount: context.bookingAmount,
        totalDiscountAmount: 0,
        finalAmount: context.bookingAmount,
      );
    }

    // Apply stacking rules to find the best combination
    final stackingResult = _stackingRules.findBestCombination(
      eligibleResults.map((e) => e.discount).toList(),
      context.bookingAmount,
      context.nights,
    );

    // Split into applied and rejected based on stacking
    final appliedResults = <DiscountEligibilityResult>[];
    for (final result in eligibleResults) {
      if (stackingResult.appliedDiscounts.any((d) => d.id == result.discount.id)) {
        appliedResults.add(result);
      } else {
        rejectedResults.add(DiscountEligibilityResult.ineligible(
          discount: result.discount,
          reason: IneligibilityReason.cannotStack,
          details: 'A better discount combination was applied',
        ));
      }
    }

    return MultiDiscountResult(
      appliedDiscounts: appliedResults,
      rejectedDiscounts: rejectedResults,
      originalAmount: context.bookingAmount,
      totalDiscountAmount: stackingResult.totalDiscount,
      finalAmount: context.bookingAmount - stackingResult.totalDiscount,
    );
  }

  /// Find the best single discount from a list
  DiscountEligibilityResult? findBestDiscount({
    required List<Discount> discounts,
    required DiscountEligibilityContext context,
  }) {
    DiscountEligibilityResult? bestResult;
    double bestAmount = 0;

    for (final discount in discounts) {
      final result = evaluateDiscount(
        discount: discount,
        context: context,
      );

      if (result.isEligible && (result.calculatedAmount ?? 0) > bestAmount) {
        bestResult = result;
        bestAmount = result.calculatedAmount ?? 0;
      }
    }

    return bestResult;
  }

  /// Find all auto-applicable discounts for a booking
  List<DiscountEligibilityResult> findAutoApplicableDiscounts({
    required List<Discount> availableDiscounts,
    required DiscountEligibilityContext context,
  }) {
    final autoDiscounts = availableDiscounts.where((d) => d.code == null);
    final results = <DiscountEligibilityResult>[];

    for (final discount in autoDiscounts) {
      final result = evaluateDiscount(
        discount: discount,
        context: context,
      );

      if (result.isEligible) {
        results.add(result);
      }
    }

    // Sort by calculated amount (highest first)
    results.sort((a, b) =>
        (b.calculatedAmount ?? 0).compareTo(a.calculatedAmount ?? 0));

    return results;
  }

  /// Validate a promo code and return eligibility
  DiscountEligibilityResult validatePromoCode({
    required Discount? discount,
    required DiscountEligibilityContext context,
  }) {
    if (discount == null) {
      // Create a dummy discount for the error response
      return DiscountEligibilityResult.ineligible(
        discount: Discount(
          id: '',
          name: '',
          type: DiscountType.fixedAmount,
          category: DiscountCategory.platform,
          status: DiscountStatus.draft,
          value: 0,
          startsAt: DateTime.now(),
        ),
        reason: IneligibilityReason.invalidCode,
      );
    }

    return evaluateDiscount(discount: discount, context: context);
  }

  /// Calculate potential savings preview
  SavingsPreview calculateSavingsPreview({
    required List<Discount> applicableDiscounts,
    required DiscountEligibilityContext context,
  }) {
    final result = applyDiscounts(
      discounts: applicableDiscounts,
      context: context,
    );

    final bestSingle = findBestDiscount(
      discounts: applicableDiscounts,
      context: context,
    );

    return SavingsPreview(
      bestSingleDiscount: bestSingle?.discount,
      bestSingleAmount: bestSingle?.calculatedAmount ?? 0,
      stackedTotal: result.totalDiscountAmount,
      appliedDiscounts: result.appliedDiscounts.map((e) => e.discount).toList(),
      originalAmount: context.bookingAmount,
      finalAmount: result.finalAmount,
    );
  }
}

/// Preview of potential savings
class SavingsPreview {
  const SavingsPreview({
    required this.bestSingleDiscount,
    required this.bestSingleAmount,
    required this.stackedTotal,
    required this.appliedDiscounts,
    required this.originalAmount,
    required this.finalAmount,
  });

  /// Best single discount (if using only one)
  final Discount? bestSingleDiscount;

  /// Amount from best single discount
  final double bestSingleAmount;

  /// Total from stacked discounts
  final double stackedTotal;

  /// All applied discounts
  final List<Discount> appliedDiscounts;

  /// Original booking amount
  final double originalAmount;

  /// Final amount after discounts
  final double finalAmount;

  /// Whether stacking provides more savings
  bool get stackingIsBetter => stackedTotal > bestSingleAmount;

  /// Maximum possible savings
  double get maxSavings =>
      stackedTotal > bestSingleAmount ? stackedTotal : bestSingleAmount;

  /// Savings percentage
  double get savingsPercentage {
    if (originalAmount == 0) return 0;
    return (maxSavings / originalAmount) * 100;
  }
}
