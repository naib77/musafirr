import 'package:flutter/material.dart';

import '../core/currency/money.dart';

/// Display style for price
enum PriceDisplayStyle {
  /// Normal size, single line
  normal,

  /// Compact with abbreviated amounts
  compact,

  /// Large hero-style display
  large,

  /// Small badge-style
  badge,

  /// With strikethrough for discounts
  discounted,
}

/// Widget for displaying monetary amounts consistently
///
/// Supports:
/// - Per-unit pricing (e.g., "৳500/night")
/// - Discounted prices with strikethrough
/// - Compact notation for large amounts
/// - Multiple display styles
class PriceDisplay extends StatelessWidget {
  /// The amount to display
  final Money amount;

  /// Display style
  final PriceDisplayStyle style;

  /// Unit to show (e.g., "night", "hour", "month")
  final String? perUnit;

  /// Original price for showing discount
  final Money? originalPrice;

  /// Whether to show currency symbol
  final bool showCurrency;

  /// Whether to use compact notation
  final bool useCompact;

  /// Custom text style override
  final TextStyle? textStyle;

  /// Custom color override
  final Color? color;

  /// Alignment
  final CrossAxisAlignment alignment;

  const PriceDisplay({
    super.key,
    required this.amount,
    this.style = PriceDisplayStyle.normal,
    this.perUnit,
    this.originalPrice,
    this.showCurrency = true,
    this.useCompact = false,
    this.textStyle,
    this.color,
    this.alignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return switch (style) {
      PriceDisplayStyle.normal => _buildNormal(theme),
      PriceDisplayStyle.compact => _buildCompact(theme),
      PriceDisplayStyle.large => _buildLarge(theme),
      PriceDisplayStyle.badge => _buildBadge(theme),
      PriceDisplayStyle.discounted => _buildDiscounted(theme),
    };
  }

  Widget _buildNormal(ThemeData theme) {
    final effectiveStyle = textStyle ??
        theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: color ?? theme.colorScheme.onSurface,
        );

    return _buildPriceRow(
      priceText: amount.format(showSymbol: showCurrency, useCompact: useCompact),
      style: effectiveStyle!,
      theme: theme,
    );
  }

  Widget _buildCompact(ThemeData theme) {
    final effectiveStyle = textStyle ??
        theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: color ?? theme.colorScheme.onSurface,
        );

    return _buildPriceRow(
      priceText: amount.format(showSymbol: showCurrency, useCompact: true),
      style: effectiveStyle!,
      theme: theme,
    );
  }

  Widget _buildLarge(ThemeData theme) {
    final effectiveStyle = textStyle ??
        theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: color ?? theme.colorScheme.primary,
        );

    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          amount.format(showSymbol: showCurrency, useCompact: useCompact),
          style: effectiveStyle,
        ),
        if (perUnit != null)
          Text(
            'per $perUnit',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _buildBadge(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? theme.colorScheme.primary).withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        amount.format(showSymbol: showCurrency, useCompact: true),
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: color ?? theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildDiscounted(ThemeData theme) {
    final hasDiscount = originalPrice != null && originalPrice! > amount;

    if (!hasDiscount) {
      return _buildNormal(theme);
    }

    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Original price with strikethrough
            Text(
              originalPrice!.format(showSymbol: showCurrency),
              style: theme.textTheme.bodyMedium?.copyWith(
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            // Discounted price
            Text(
              amount.format(showSymbol: showCurrency),
              style: (textStyle ?? theme.textTheme.titleMedium)?.copyWith(
                fontWeight: FontWeight.bold,
                color: color ?? theme.colorScheme.error,
              ),
            ),
          ],
        ),
        if (perUnit != null)
          Text(
            '/$perUnit',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _buildPriceRow({
    required String priceText,
    required TextStyle style,
    required ThemeData theme,
  }) {
    if (perUnit == null) {
      return Text(priceText, style: style);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(priceText, style: style),
        Text(
          '/$perUnit',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Widget for displaying a price range
class PriceRangeDisplay extends StatelessWidget {
  final Money minPrice;
  final Money maxPrice;
  final TextStyle? textStyle;
  final bool useCompact;

  const PriceRangeDisplay({
    super.key,
    required this.minPrice,
    required this.maxPrice,
    this.textStyle,
    this.useCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = textStyle ??
        theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        );

    if (minPrice == maxPrice) {
      return Text(
        minPrice.format(useCompact: useCompact),
        style: style,
      );
    }

    return Text(
      '${minPrice.format(useCompact: useCompact)} - ${maxPrice.format(useCompact: useCompact)}',
      style: style,
    );
  }
}

/// Savings banner widget
class SavingsBanner extends StatelessWidget {
  final Money savedAmount;
  final Color? backgroundColor;
  final Color? textColor;

  const SavingsBanner({
    super.key,
    required this.savedAmount,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    if (savedAmount.isZero) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? Colors.green.shade50;
    final fgColor = textColor ?? Colors.green.shade700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.celebration, color: fgColor, size: 18),
          const SizedBox(width: 8),
          Text(
            'You save ${savedAmount.format()}!',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: fgColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
