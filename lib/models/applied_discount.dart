import 'package:flutter/foundation.dart';

import 'discount.dart';

/// Represents a discount that has been applied to a booking
@immutable
class AppliedDiscount {
  const AppliedDiscount({
    required this.id,
    required this.discountId,
    required this.userId,
    required this.originalAmount,
    required this.discountAmount,
    required this.finalAmount,
    required this.appliedAt,
    this.bookingId,
    this.listingId,
    this.stackedWith,
    this.isReversed = false,
    this.reversedAt,
    this.reversalReason,
    this.metadata,
    this.discount,
  });

  final String id;
  final String discountId;
  final String userId;
  final String? bookingId;
  final String? listingId;
  final double originalAmount;
  final double discountAmount;
  final double finalAmount;
  final DateTime appliedAt;
  final List<String>? stackedWith;
  final bool isReversed;
  final DateTime? reversedAt;
  final String? reversalReason;
  final Map<String, dynamic>? metadata;

  /// The discount that was applied (if loaded)
  final Discount? discount;

  /// Percentage saved
  double get savingsPercentage {
    if (originalAmount == 0) return 0;
    return (discountAmount / originalAmount) * 100;
  }

  /// Whether this was stacked with other discounts
  bool get wasStacked => stackedWith != null && stackedWith!.isNotEmpty;

  factory AppliedDiscount.fromJson(Map<String, dynamic> json) {
    return AppliedDiscount(
      id: json['id'] as String,
      discountId: json['discount_id'] as String,
      userId: json['user_id'] as String,
      bookingId: json['booking_id'] as String?,
      listingId: json['listing_id'] as String?,
      originalAmount: (json['original_amount'] as num).toDouble(),
      discountAmount: (json['discount_amount'] as num).toDouble(),
      finalAmount: (json['final_amount'] as num).toDouble(),
      appliedAt: DateTime.parse(json['applied_at'] as String),
      stackedWith: (json['stacked_with'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      isReversed: json['is_reversed'] as bool? ?? false,
      reversedAt: json['reversed_at'] != null
          ? DateTime.parse(json['reversed_at'] as String)
          : null,
      reversalReason: json['reversal_reason'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      discount: json['discount'] != null
          ? Discount.fromJson(json['discount'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'discount_id': discountId,
      'user_id': userId,
      'booking_id': bookingId,
      'listing_id': listingId,
      'original_amount': originalAmount,
      'discount_amount': discountAmount,
      'final_amount': finalAmount,
      'applied_at': appliedAt.toIso8601String(),
      'stacked_with': stackedWith,
      'is_reversed': isReversed,
      'reversed_at': reversedAt?.toIso8601String(),
      'reversal_reason': reversalReason,
      'metadata': metadata,
    };
  }

  AppliedDiscount copyWith({
    String? id,
    String? discountId,
    String? userId,
    String? bookingId,
    String? listingId,
    double? originalAmount,
    double? discountAmount,
    double? finalAmount,
    DateTime? appliedAt,
    List<String>? stackedWith,
    bool? isReversed,
    DateTime? reversedAt,
    String? reversalReason,
    Map<String, dynamic>? metadata,
    Discount? discount,
  }) {
    return AppliedDiscount(
      id: id ?? this.id,
      discountId: discountId ?? this.discountId,
      userId: userId ?? this.userId,
      bookingId: bookingId ?? this.bookingId,
      listingId: listingId ?? this.listingId,
      originalAmount: originalAmount ?? this.originalAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      finalAmount: finalAmount ?? this.finalAmount,
      appliedAt: appliedAt ?? this.appliedAt,
      stackedWith: stackedWith ?? this.stackedWith,
      isReversed: isReversed ?? this.isReversed,
      reversedAt: reversedAt ?? this.reversedAt,
      reversalReason: reversalReason ?? this.reversalReason,
      metadata: metadata ?? this.metadata,
      discount: discount ?? this.discount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppliedDiscount &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Summary of all applied discounts for a booking
@immutable
class DiscountSummary {
  const DiscountSummary({
    required this.appliedDiscounts,
    required this.originalAmount,
    required this.totalDiscountAmount,
    required this.finalAmount,
  });

  /// List of all applied discounts
  final List<AppliedDiscount> appliedDiscounts;

  /// Original amount before discounts
  final double originalAmount;

  /// Total discount amount
  final double totalDiscountAmount;

  /// Final amount after all discounts
  final double finalAmount;

  /// Number of discounts applied
  int get discountCount => appliedDiscounts.length;

  /// Whether any discounts were applied
  bool get hasDiscounts => appliedDiscounts.isNotEmpty;

  /// Total savings percentage
  double get savingsPercentage {
    if (originalAmount == 0) return 0;
    return (totalDiscountAmount / originalAmount) * 100;
  }

  /// Get savings message for display
  String get savingsMessage {
    if (!hasDiscounts) return '';
    return 'You saved ৳${totalDiscountAmount.toStringAsFixed(0)} (${savingsPercentage.toStringAsFixed(0)}%)';
  }

  factory DiscountSummary.empty(double originalAmount) {
    return DiscountSummary(
      appliedDiscounts: const [],
      originalAmount: originalAmount,
      totalDiscountAmount: 0,
      finalAmount: originalAmount,
    );
  }

  factory DiscountSummary.fromAppliedDiscounts(
    List<AppliedDiscount> discounts,
    double originalAmount,
  ) {
    if (discounts.isEmpty) {
      return DiscountSummary.empty(originalAmount);
    }

    final totalDiscount = discounts.fold<double>(
      0,
      (sum, d) => sum + d.discountAmount,
    );

    return DiscountSummary(
      appliedDiscounts: discounts,
      originalAmount: originalAmount,
      totalDiscountAmount: totalDiscount,
      finalAmount: originalAmount - totalDiscount,
    );
  }
}

/// Breakdown item for price display
@immutable
class DiscountBreakdownItem {
  const DiscountBreakdownItem({
    required this.name,
    required this.description,
    required this.amount,
    this.code,
    this.category,
    this.isHighlighted = false,
  });

  final String name;
  final String description;
  final double amount;
  final String? code;
  final DiscountCategory? category;
  final bool isHighlighted;

  /// Format amount for display (always negative for discounts)
  String get displayAmount => '-৳${amount.toStringAsFixed(0)}';

  factory DiscountBreakdownItem.fromAppliedDiscount(AppliedDiscount applied) {
    final discount = applied.discount;
    return DiscountBreakdownItem(
      name: discount?.name ?? 'Discount',
      description: discount?.shortDescription ?? '',
      amount: applied.discountAmount,
      code: discount?.code,
      category: discount?.category,
      isHighlighted: discount?.category == DiscountCategory.referral ||
          discount?.category == DiscountCategory.loyalty,
    );
  }
}
