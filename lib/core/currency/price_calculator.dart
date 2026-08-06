import 'currency_config.dart';
import 'money.dart';

/// Result of a price calculation
class PriceCalculation {
  /// Base price before any adjustments
  final Money basePrice;

  /// Number of units (nights, hours, etc.)
  final int units;

  /// Unit type (night, hour, month)
  final String unitType;

  /// Subtotal (basePrice * units)
  final Money subtotal;

  /// List of applied discounts
  final List<AppliedPriceAdjustment> discounts;

  /// Service fee
  final Money serviceFee;

  /// Total discount amount
  final Money totalDiscount;

  /// Final total after all adjustments
  final Money total;

  /// Total savings message
  String? get savingsMessage {
    if (totalDiscount.isZero) return null;
    return 'You save ${totalDiscount.format()}!';
  }

  const PriceCalculation({
    required this.basePrice,
    required this.units,
    required this.unitType,
    required this.subtotal,
    required this.discounts,
    required this.serviceFee,
    required this.totalDiscount,
    required this.total,
  });

  /// Get breakdown as list of line items
  List<PriceLineItem> get lineItems {
    final items = <PriceLineItem>[];

    // Base price line
    items.add(PriceLineItem(
      label: '${basePrice.format()} x $units $unitType${units > 1 ? 's' : ''}',
      amount: subtotal,
      isDiscount: false,
    ));

    // Discount lines
    for (final discount in discounts) {
      items.add(PriceLineItem(
        label: discount.label,
        amount: discount.amount,
        isDiscount: true,
        tooltip: discount.description,
      ));
    }

    // Service fee
    if (serviceFee.isPositive) {
      items.add(PriceLineItem(
        label: 'Service fee',
        amount: serviceFee,
        isDiscount: false,
        tooltip: 'This helps us run the platform',
      ));
    }

    return items;
  }
}

/// A line item in the price breakdown
class PriceLineItem {
  final String label;
  final Money amount;
  final bool isDiscount;
  final String? tooltip;

  const PriceLineItem({
    required this.label,
    required this.amount,
    required this.isDiscount,
    this.tooltip,
  });
}

/// An applied price adjustment (discount or fee)
class AppliedPriceAdjustment {
  final String id;
  final String label;
  final String? description;
  final Money amount;
  final AdjustmentType type;

  const AppliedPriceAdjustment({
    required this.id,
    required this.label,
    this.description,
    required this.amount,
    required this.type,
  });
}

enum AdjustmentType {
  percentageDiscount,
  fixedDiscount,
  freeNights,
  serviceFee,
  tax,
}

/// Calculator for booking prices
class PriceCalculator {
  PriceCalculator._();

  static PriceCalculator? _instance;

  /// Singleton instance
  static PriceCalculator get instance {
    _instance ??= PriceCalculator._();
    return _instance!;
  }

  /// Calculate total price for a booking
  ///
  /// [pricePerUnit] - Price per night/hour/month
  /// [units] - Number of nights/hours/months
  /// [unitType] - Type of unit (night, hour, month)
  /// [discounts] - List of discounts to apply
  /// [includeServiceFee] - Whether to include service fee
  PriceCalculation calculate({
    required Money pricePerUnit,
    required int units,
    required String unitType,
    List<DiscountInput> discounts = const [],
    bool includeServiceFee = true,
  }) {
    // Calculate subtotal
    final subtotal = pricePerUnit.multiply(units.toDouble());

    // Apply discounts
    var discountedAmount = subtotal;
    final appliedDiscounts = <AppliedPriceAdjustment>[];
    var totalDiscountAmount = Money.zeroBdt;

    for (final discount in discounts) {
      final discountAmount = _calculateDiscount(discountedAmount, discount);

      if (discountAmount.isPositive) {
        appliedDiscounts.add(AppliedPriceAdjustment(
          id: discount.id,
          label: discount.label,
          description: discount.description,
          amount: discountAmount,
          type: discount.type == DiscountType.percentage
              ? AdjustmentType.percentageDiscount
              : AdjustmentType.fixedDiscount,
        ));

        discountedAmount = discountedAmount.subtract(discountAmount);
        totalDiscountAmount = totalDiscountAmount.add(discountAmount);
      }
    }

    // Enforce max discount
    final maxDiscount = subtotal.percentage(CurrencyConfig.maxDiscountPercent);
    if (totalDiscountAmount > maxDiscount) {
      // Recalculate with capped discount
      totalDiscountAmount = maxDiscount;
      discountedAmount = subtotal.subtract(maxDiscount);
    }

    // Calculate service fee on discounted amount
    Money serviceFee = Money.zeroBdt;
    if (includeServiceFee) {
      serviceFee =
          discountedAmount.percentage(CurrencyConfig.serviceFeePercent);
    }

    // Calculate final total
    final total = discountedAmount.add(serviceFee);

    return PriceCalculation(
      basePrice: pricePerUnit,
      units: units,
      unitType: unitType,
      subtotal: subtotal,
      discounts: appliedDiscounts,
      serviceFee: serviceFee,
      totalDiscount: totalDiscountAmount,
      total: total,
    );
  }

  /// Calculate discount amount based on type
  Money _calculateDiscount(Money amount, DiscountInput discount) {
    switch (discount.type) {
      case DiscountType.percentage:
        return amount.percentage(discount.value);
      case DiscountType.fixed:
        final fixedAmount = Money.bdt(discount.value);
        // Don't exceed the amount
        return fixedAmount > amount ? amount : fixedAmount;
      case DiscountType.freeNights:
        // Handle separately in booking calculation
        return Money.zeroBdt;
    }
  }

  /// Calculate estimated price range for a listing
  ///
  /// Returns (min, max) based on different booking durations
  (Money min, Money max) calculatePriceRange({
    Money? hourlyRate,
    Money? dailyRate,
    Money? monthlyRate,
  }) {
    final prices = <Money>[];

    if (hourlyRate != null && hourlyRate.isPositive) {
      prices.add(hourlyRate);
    }
    if (dailyRate != null && dailyRate.isPositive) {
      prices.add(dailyRate);
    }
    if (monthlyRate != null && monthlyRate.isPositive) {
      prices.add(monthlyRate);
    }

    if (prices.isEmpty) {
      return (Money.zeroBdt, Money.zeroBdt);
    }

    prices.sort();
    return (prices.first, prices.last);
  }

  /// Calculate long-stay discount
  ///
  /// Standard discounts:
  /// - 7+ nights: 5% off
  /// - 14+ nights: 10% off
  /// - 28+ nights (monthly): 15% off
  DiscountInput? calculateLongStayDiscount(int nights) {
    if (nights >= 28) {
      return DiscountInput(
        id: 'long_stay_monthly',
        label: 'Monthly stay discount',
        description: '15% off for stays of 28+ nights',
        type: DiscountType.percentage,
        value: 15,
      );
    } else if (nights >= 14) {
      return DiscountInput(
        id: 'long_stay_biweekly',
        label: 'Bi-weekly discount',
        description: '10% off for stays of 14+ nights',
        type: DiscountType.percentage,
        value: 10,
      );
    } else if (nights >= 7) {
      return DiscountInput(
        id: 'long_stay_weekly',
        label: 'Weekly stay discount',
        description: '5% off for stays of 7+ nights',
        type: DiscountType.percentage,
        value: 5,
      );
    }
    return null;
  }

  /// Reset singleton (for testing)
  static void reset() {
    _instance = null;
  }
}

/// Input for a discount to be applied
class DiscountInput {
  final String id;
  final String label;
  final String? description;
  final DiscountType type;
  final double value; // Percentage (0-100) or fixed amount

  const DiscountInput({
    required this.id,
    required this.label,
    this.description,
    required this.type,
    required this.value,
  });
}

enum DiscountType {
  percentage,
  fixed,
  freeNights,
}
