import 'package:flutter/material.dart';

import '../../models/applied_discount.dart';
import '../../models/discount.dart';

/// Style variants for savings banner
enum SavingsBannerStyle {
  /// Compact inline style
  compact,

  /// Standard banner with details
  standard,

  /// Expanded with breakdown
  expanded,

  /// Celebratory style for large savings
  celebration,
}

/// Savings banner widget to show discount savings
class SavingsBanner extends StatelessWidget {
  const SavingsBanner({
    super.key,
    required this.totalSavings,
    this.appliedDiscounts,
    this.style = SavingsBannerStyle.standard,
    this.onTap,
    this.showBreakdown = false,
    this.originalAmount,
    this.finalAmount,
  });

  /// Create from DiscountSummary
  factory SavingsBanner.fromSummary({
    Key? key,
    required DiscountSummary summary,
    SavingsBannerStyle style = SavingsBannerStyle.standard,
    VoidCallback? onTap,
    bool showBreakdown = false,
  }) {
    return SavingsBanner(
      key: key,
      totalSavings: summary.totalDiscountAmount,
      appliedDiscounts: summary.appliedDiscounts,
      style: style,
      onTap: onTap,
      showBreakdown: showBreakdown,
      originalAmount: summary.originalAmount,
      finalAmount: summary.finalAmount,
    );
  }

  final double totalSavings;
  final List<AppliedDiscount>? appliedDiscounts;
  final SavingsBannerStyle style;
  final VoidCallback? onTap;
  final bool showBreakdown;
  final double? originalAmount;
  final double? finalAmount;

  @override
  Widget build(BuildContext context) {
    if (totalSavings <= 0) return const SizedBox.shrink();

    switch (style) {
      case SavingsBannerStyle.compact:
        return _buildCompactBanner(context);
      case SavingsBannerStyle.standard:
        return _buildStandardBanner(context);
      case SavingsBannerStyle.expanded:
        return _buildExpandedBanner(context);
      case SavingsBannerStyle.celebration:
        return _buildCelebrationBanner(context);
    }
  }

  Widget _buildCompactBanner(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.savings,
              color: Colors.green,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              'You\'re saving ৳${totalSavings.toStringAsFixed(0)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: Colors.green.shade700,
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStandardBanner(BuildContext context) {
    final theme = Theme.of(context);
    final discountCount = appliedDiscounts?.length ?? 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.green.shade400,
              Colors.green.shade600,
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.savings,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You\'re saving',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  Text(
                    '৳${totalSavings.toStringAsFixed(0)}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (discountCount > 0)
                    Text(
                      '$discountCount discount${discountCount > 1 ? 's' : ''} applied',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.chevron_right,
                color: Colors.white,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedBanner(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.green.shade400,
                  Colors.green.shade600,
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.celebration,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Savings',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      Text(
                        '৳${totalSavings.toStringAsFixed(0)}',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Breakdown
          if (showBreakdown && appliedDiscounts != null && appliedDiscounts!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Discount Breakdown',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...appliedDiscounts!.map((applied) => _buildDiscountRow(
                        context,
                        applied.discount?.name ?? 'Discount',
                        applied.discountAmount,
                        _getCategoryIcon(applied.discount?.category),
                        _getCategoryColor(applied.discount?.category),
                      )),
                  const Divider(height: 24),
                  if (originalAmount != null && finalAmount != null) ...[
                    _buildPriceRow(
                      context,
                      'Original Price',
                      originalAmount!,
                      isOriginal: true,
                    ),
                    const SizedBox(height: 4),
                    _buildPriceRow(
                      context,
                      'Final Price',
                      finalAmount!,
                      isFinal: true,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCelebrationBanner(BuildContext context) {
    final theme = Theme.of(context);
    final percentage = originalAmount != null && originalAmount! > 0
        ? ((totalSavings / originalAmount!) * 100).toStringAsFixed(0)
        : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.green.shade400,
            Colors.teal.shade500,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.celebration,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(width: 8),
              Text(
                'Awesome Deal!',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.celebration,
                color: Colors.white,
                size: 32,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'You\'re saving ',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
                Text(
                  '৳${totalSavings.toStringAsFixed(0)}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (percentage != null)
                  Text(
                    ' ($percentage%)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
              ],
            ),
          ),
          if (appliedDiscounts != null && appliedDiscounts!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: appliedDiscounts!.map((applied) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    applied.discount?.name ?? 'Discount',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDiscountRow(
    BuildContext context,
    String name,
    double amount,
    IconData icon,
    Color color,
  ) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            '-৳${amount.toStringAsFixed(0)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.green,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(
    BuildContext context,
    String label,
    double amount, {
    bool isOriginal = false,
    bool isFinal = false,
  }) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: isFinal ? FontWeight.w600 : null,
          ),
        ),
        Text(
          '৳${amount.toStringAsFixed(0)}',
          style: theme.textTheme.bodyMedium?.copyWith(
            decoration: isOriginal ? TextDecoration.lineThrough : null,
            color: isOriginal
                ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                : isFinal
                    ? theme.colorScheme.primary
                    : null,
            fontWeight: isFinal ? FontWeight.bold : null,
            fontSize: isFinal ? 18 : null,
          ),
        ),
      ],
    );
  }

  IconData _getCategoryIcon(DiscountCategory? category) {
    switch (category) {
      case null:
        return Icons.local_offer;
      case DiscountCategory.platform:
        return Icons.local_offer;
      case DiscountCategory.host:
        return Icons.home;
      case DiscountCategory.referral:
        return Icons.people;
      case DiscountCategory.loyalty:
        return Icons.star;
      case DiscountCategory.firstBooking:
        return Icons.celebration;
      case DiscountCategory.seasonal:
        return Icons.event;
      case DiscountCategory.flashSale:
        return Icons.flash_on;
    }
  }

  Color _getCategoryColor(DiscountCategory? category) {
    switch (category) {
      case null:
        return Colors.grey;
      case DiscountCategory.platform:
        return Colors.red;
      case DiscountCategory.host:
        return Colors.orange;
      case DiscountCategory.referral:
        return Colors.purple;
      case DiscountCategory.loyalty:
        return Colors.amber.shade700;
      case DiscountCategory.firstBooking:
        return Colors.green;
      case DiscountCategory.seasonal:
        return Colors.blue;
      case DiscountCategory.flashSale:
        return Colors.pink;
    }
  }
}

/// Animated savings counter
class AnimatedSavingsCounter extends StatefulWidget {
  const AnimatedSavingsCounter({
    super.key,
    required this.amount,
    this.duration = const Duration(milliseconds: 1000),
    this.style,
    this.prefix = '৳',
  });

  final double amount;
  final Duration duration;
  final TextStyle? style;
  final String prefix;

  @override
  State<AnimatedSavingsCounter> createState() => _AnimatedSavingsCounterState();
}

class _AnimatedSavingsCounterState extends State<AnimatedSavingsCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: widget.amount).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedSavingsCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.amount != widget.amount) {
      _animation = Tween<double>(
        begin: _animation.value,
        end: widget.amount,
      ).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      );
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Text(
          '${widget.prefix}${_animation.value.toStringAsFixed(0)}',
          style: widget.style,
        );
      },
    );
  }
}
