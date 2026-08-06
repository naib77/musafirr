import 'package:flutter/material.dart';

import '../core/currency/money.dart';
import '../core/currency/price_calculator.dart';

/// Widget displaying a detailed price breakdown
class PriceBreakdownCard extends StatelessWidget {
  /// The price calculation result
  final PriceCalculation calculation;

  /// Whether to show expanded details
  final bool expanded;

  /// Callback when promo code section is tapped
  final VoidCallback? onPromoCodeTap;

  /// Callback when a discount is removed
  final void Function(String discountId)? onRemoveDiscount;

  const PriceBreakdownCard({
    super.key,
    required this.calculation,
    this.expanded = true,
    this.onPromoCodeTap,
    this.onRemoveDiscount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Price details',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(height: 1),

          // Line items
          if (expanded) ...[
            ...calculation.lineItems.map((item) => _buildLineItem(
                  context,
                  item,
                )),
          ] else ...[
            // Collapsed view - just subtotal
            _buildSimpleRow(
              context,
              label:
                  '${calculation.basePrice.format()} x ${calculation.units} ${calculation.unitType}${calculation.units > 1 ? 's' : ''}',
              amount: calculation.subtotal,
            ),
          ],

          // Promo code section
          if (onPromoCodeTap != null) ...[
            const Divider(height: 1),
            _buildPromoCodeSection(context),
          ],

          // Total
          const Divider(height: 1),
          _buildTotalRow(context),

          // Savings banner
          if (calculation.totalDiscount.isPositive) ...[
            const Divider(height: 1),
            _buildSavingsBanner(context),
          ],
        ],
      ),
    );
  }

  Widget _buildLineItem(BuildContext context, PriceLineItem item) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    item.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: item.isDiscount
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (item.tooltip != null) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: item.tooltip!,
                    child: Icon(
                      Icons.info_outline,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            item.isDiscount ? '-${item.amount.format()}' : item.amount.format(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: item.isDiscount
                  ? Colors.green.shade700
                  : theme.colorScheme.onSurface,
              fontWeight: item.isDiscount ? FontWeight.w500 : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleRow(
    BuildContext context, {
    required String label,
    required Money amount,
    bool isDiscount = false,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            isDiscount ? '-${amount.format()}' : amount.format(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDiscount ? Colors.green.shade700 : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoCodeSection(BuildContext context) {
    final theme = Theme.of(context);
    final hasPromoApplied = calculation.discounts.any(
      (d) =>
          d.type == AdjustmentType.percentageDiscount ||
          d.type == AdjustmentType.fixedDiscount,
    );

    return InkWell(
      onTap: onPromoCodeTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              hasPromoApplied ? Icons.check_circle : Icons.confirmation_number,
              color: hasPromoApplied
                  ? Colors.green
                  : theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasPromoApplied ? 'Promo code applied' : 'Add promo code',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: hasPromoApplied
                      ? Colors.green.shade700
                      : theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Total',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            calculation.total.format(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavingsBanner(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.celebration, color: Colors.green.shade700, size: 18),
          const SizedBox(width: 8),
          Text(
            'You\'re saving ${calculation.totalDiscount.format()}!',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.green.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Simplified price summary row
class PriceSummaryRow extends StatelessWidget {
  final Money basePrice;
  final int units;
  final String unitType;
  final Money total;
  final Money? discount;

  const PriceSummaryRow({
    super.key,
    required this.basePrice,
    required this.units,
    required this.unitType,
    required this.total,
    this.discount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${basePrice.format()} x $units $unitType${units > 1 ? 's' : ''}',
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              total.format(),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (discount != null && discount!.isPositive) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Save ${discount!.format()}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
