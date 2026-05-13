import 'package:flutter/material.dart';

import '../../models/applied_discount.dart';
import '../../models/discount.dart';
import 'discount_badge.dart';

/// Price line item for breakdown
class PriceLineItem {
  const PriceLineItem({
    required this.label,
    required this.amount,
    this.subtitle,
    this.isDiscount = false,
    this.isFee = false,
    this.isTotal = false,
    this.icon,
    this.color,
    this.discount,
  });

  final String label;
  final double amount;
  final String? subtitle;
  final bool isDiscount;
  final bool isFee;
  final bool isTotal;
  final IconData? icon;
  final Color? color;
  final Discount? discount;

  /// Create from AppliedDiscount
  factory PriceLineItem.fromAppliedDiscount(AppliedDiscount applied) {
    return PriceLineItem(
      label: applied.discount?.name ?? 'Discount',
      amount: -applied.discountAmount,
      isDiscount: true,
      discount: applied.discount,
      color: Colors.green,
    );
  }
}

/// Price breakdown card with discount support
class PriceBreakdownCard extends StatelessWidget {
  const PriceBreakdownCard({
    super.key,
    required this.pricePerNight,
    required this.nights,
    this.serviceFee,
    this.cleaningFee,
    this.taxes,
    this.appliedDiscounts,
    this.additionalLineItems,
    this.showOriginalPrice = true,
    this.isExpanded = true,
    this.onExpandToggle,
    this.currencySymbol = '৳',
  });

  final double pricePerNight;
  final int nights;
  final double? serviceFee;
  final double? cleaningFee;
  final double? taxes;
  final List<AppliedDiscount>? appliedDiscounts;
  final List<PriceLineItem>? additionalLineItems;
  final bool showOriginalPrice;
  final bool isExpanded;
  final VoidCallback? onExpandToggle;
  final String currencySymbol;

  double get _subtotal => pricePerNight * nights;

  double get _totalDiscounts {
    if (appliedDiscounts == null || appliedDiscounts!.isEmpty) return 0;
    return appliedDiscounts!.fold(0.0, (sum, d) => sum + d.discountAmount);
  }

  double get _totalFees {
    return (serviceFee ?? 0) + (cleaningFee ?? 0) + (taxes ?? 0);
  }

  double get _total => _subtotal - _totalDiscounts + _totalFees;

  double get _originalTotal => _subtotal + _totalFees;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: onExpandToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Price Details',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (onExpandToggle != null)
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: colorScheme.onSurface.withOpacity(0.5),
                    ),
                ],
              ),
            ),
          ),

          if (isExpanded) ...[
            const Divider(height: 1),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Base price
                  _buildLineItem(
                    context,
                    '$currencySymbol${pricePerNight.toStringAsFixed(0)} × $nights night${nights > 1 ? 's' : ''}',
                    _subtotal,
                  ),

                  // Additional line items
                  if (additionalLineItems != null)
                    ...additionalLineItems!.map(
                      (item) => _buildCustomLineItem(context, item),
                    ),

                  // Fees
                  if (cleaningFee != null && cleaningFee! > 0)
                    _buildLineItem(
                      context,
                      'Cleaning fee',
                      cleaningFee!,
                      icon: Icons.cleaning_services_outlined,
                    ),

                  if (serviceFee != null && serviceFee! > 0)
                    _buildLineItem(
                      context,
                      'Service fee',
                      serviceFee!,
                      icon: Icons.receipt_outlined,
                    ),

                  if (taxes != null && taxes! > 0)
                    _buildLineItem(
                      context,
                      'Taxes',
                      taxes!,
                      icon: Icons.account_balance_outlined,
                    ),

                  // Discounts
                  if (appliedDiscounts != null && appliedDiscounts!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 8),
                    ...appliedDiscounts!.map(
                      (applied) => _buildDiscountLineItem(context, applied),
                    ),
                  ],

                  // Total
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  _buildTotalRow(context),
                ],
              ),
            ),
          ] else ...[
            // Collapsed view - just show total
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_totalDiscounts > 0 && showOriginalPrice)
                        Text(
                          '$currencySymbol${_originalTotal.toStringAsFixed(0)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            decoration: TextDecoration.lineThrough,
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      Text(
                        '$currencySymbol${_total.toStringAsFixed(0)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Savings banner
          if (_totalDiscounts > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.savings,
                    color: Colors.green,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'You\'re saving $currencySymbol${_totalDiscounts.toStringAsFixed(0)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLineItem(
    BuildContext context,
    String label,
    double amount, {
    IconData? icon,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 16,
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium,
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '$currencySymbol${amount.toStringAsFixed(0)}',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildCustomLineItem(BuildContext context, PriceLineItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final amountColor = item.isDiscount
        ? Colors.green
        : item.color ?? colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (item.icon != null) ...[
            Icon(
              item.icon,
              size: 16,
              color: item.color ?? colorScheme.onSurface.withOpacity(0.5),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: item.isTotal ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                    if (item.discount != null) ...[
                      const SizedBox(width: 8),
                      DiscountBadge(
                        discount: item.discount!,
                        style: DiscountBadgeStyle.chip,
                      ),
                    ],
                  ],
                ),
                if (item.subtitle != null)
                  Text(
                    item.subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '${item.amount < 0 ? '-' : ''}$currencySymbol${item.amount.abs().toStringAsFixed(0)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: amountColor,
              fontWeight: item.isTotal ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountLineItem(BuildContext context, AppliedDiscount applied) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(
              Icons.local_offer,
              size: 14,
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  applied.discount?.name ?? 'Discount',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.green.shade700,
                  ),
                ),
                if (applied.discount?.code != null)
                  Text(
                    applied.discount!.code!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '-$currencySymbol${applied.discountAmount.toStringAsFixed(0)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.green,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Total',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (_totalDiscounts > 0 && showOriginalPrice)
              Text(
                '$currencySymbol${_originalTotal.toStringAsFixed(0)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  decoration: TextDecoration.lineThrough,
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            Text(
              '$currencySymbol${_total.toStringAsFixed(0)}',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Compact price summary for listing cards
class CompactPriceSummary extends StatelessWidget {
  const CompactPriceSummary({
    super.key,
    required this.originalPrice,
    this.discountedPrice,
    this.discountPercentage,
    this.perNightLabel = true,
    this.currencySymbol = '৳',
  });

  final double originalPrice;
  final double? discountedPrice;
  final double? discountPercentage;
  final bool perNightLabel;
  final String currencySymbol;

  bool get _hasDiscount =>
      discountedPrice != null && discountedPrice! < originalPrice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_hasDiscount) ...[
          Text(
            '$currencySymbol${originalPrice.toStringAsFixed(0)}',
            style: theme.textTheme.bodySmall?.copyWith(
              decoration: TextDecoration.lineThrough,
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          '$currencySymbol${(_hasDiscount ? discountedPrice! : originalPrice).toStringAsFixed(0)}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        if (perNightLabel)
          Text(
            ' /night',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        if (discountPercentage != null && discountPercentage! > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '-${discountPercentage!.toStringAsFixed(0)}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
