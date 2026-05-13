import 'package:flutter/material.dart';

import '../../models/discount.dart';

/// Style variants for discount badge
enum DiscountBadgeStyle {
  /// Small chip-like badge
  chip,

  /// Standard badge with icon
  standard,

  /// Larger badge for listing cards
  card,

  /// Minimal text only
  text,

  /// Ribbon style for corners
  ribbon,
}

/// Discount badge widget for displaying discount info
class DiscountBadge extends StatelessWidget {
  const DiscountBadge({
    super.key,
    required this.discount,
    this.style = DiscountBadgeStyle.standard,
    this.showIcon = true,
    this.showDescription = false,
    this.customColor,
    this.onTap,
  }) : _percentage = null,
       _fixedAmount = null,
       _label = null;

  /// Create from discount value directly
  const DiscountBadge.percentage({
    super.key,
    required double percentage,
    this.style = DiscountBadgeStyle.standard,
    this.showIcon = true,
    this.showDescription = false,
    this.customColor,
    this.onTap,
  }) : discount = null,
       _percentage = percentage,
       _fixedAmount = null,
       _label = null;

  const DiscountBadge.fixed({
    super.key,
    required double amount,
    this.style = DiscountBadgeStyle.standard,
    this.showIcon = true,
    this.showDescription = false,
    this.customColor,
    this.onTap,
  }) : discount = null,
       _percentage = null,
       _fixedAmount = amount,
       _label = null;

  const DiscountBadge.custom({
    super.key,
    required String label,
    this.style = DiscountBadgeStyle.standard,
    this.showIcon = true,
    this.showDescription = false,
    this.customColor,
    this.onTap,
  }) : discount = null,
       _percentage = null,
       _fixedAmount = null,
       _label = label;

  final Discount? discount;
  final DiscountBadgeStyle style;
  final bool showIcon;
  final bool showDescription;
  final Color? customColor;
  final VoidCallback? onTap;

  final double? _percentage;
  final double? _fixedAmount;
  final String? _label;

  String get _displayText {
    if (_label != null) return _label!;
    if (_percentage != null) return '${_percentage!.toStringAsFixed(0)}% OFF';
    if (_fixedAmount != null) return '৳${_fixedAmount!.toStringAsFixed(0)} OFF';

    if (discount == null) return '';

    switch (discount!.type) {
      case DiscountType.percentage:
        return '${discount!.value.toStringAsFixed(0)}% OFF';
      case DiscountType.fixedAmount:
        return '৳${discount!.value.toStringAsFixed(0)} OFF';
      case DiscountType.freeNights:
        if (discount!.freeNightsConfig != null) {
          return 'Stay ${discount!.freeNightsConfig!.stayNights} Pay ${discount!.freeNightsConfig!.payNights}';
        }
        return 'FREE NIGHTS';
    }
  }

  Color _getBackgroundColor(ColorScheme colorScheme) {
    if (customColor != null) return customColor!;

    if (discount == null) return Colors.red;

    switch (discount!.category) {
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

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case DiscountBadgeStyle.chip:
        return _buildChipBadge(context);
      case DiscountBadgeStyle.standard:
        return _buildStandardBadge(context);
      case DiscountBadgeStyle.card:
        return _buildCardBadge(context);
      case DiscountBadgeStyle.text:
        return _buildTextBadge(context);
      case DiscountBadgeStyle.ribbon:
        return _buildRibbonBadge(context);
    }
  }

  Widget _buildChipBadge(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = _getBackgroundColor(colorScheme);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _displayText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildStandardBadge(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = _getBackgroundColor(colorScheme);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showIcon) ...[
              const Icon(
                Icons.local_offer,
                color: Colors.white,
                size: 14,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              _displayText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardBadge(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bgColor = _getBackgroundColor(colorScheme);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bgColor.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showIcon)
              Icon(
                Icons.local_offer,
                color: bgColor,
                size: 28,
              ),
            const SizedBox(height: 8),
            Text(
              _displayText,
              style: theme.textTheme.titleMedium?.copyWith(
                color: bgColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (showDescription && discount?.description != null) ...[
              const SizedBox(height: 4),
              Text(
                discount!.description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTextBadge(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = _getBackgroundColor(colorScheme);

    return GestureDetector(
      onTap: onTap,
      child: Text(
        _displayText,
        style: TextStyle(
          color: bgColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildRibbonBadge(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = _getBackgroundColor(colorScheme);

    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _RibbonPainter(color: bgColor),
        child: Padding(
          padding: const EdgeInsets.only(
            left: 8,
            right: 16,
            top: 4,
            bottom: 4,
          ),
          child: Text(
            _displayText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter for ribbon style
class _RibbonPainter extends CustomPainter {
  _RibbonPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width - 8, 0);
    path.lineTo(size.width, size.height / 2);
    path.lineTo(size.width - 8, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Stacked discount badges for multiple discounts
class StackedDiscountBadges extends StatelessWidget {
  const StackedDiscountBadges({
    super.key,
    required this.discounts,
    this.maxVisible = 2,
    this.style = DiscountBadgeStyle.chip,
  });

  final List<Discount> discounts;
  final int maxVisible;
  final DiscountBadgeStyle style;

  @override
  Widget build(BuildContext context) {
    if (discounts.isEmpty) return const SizedBox.shrink();

    final visible = discounts.take(maxVisible).toList();
    final remaining = discounts.length - maxVisible;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        ...visible.map((d) => DiscountBadge(
              discount: d,
              style: style,
            )),
        if (remaining > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '+$remaining more',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

/// Flash sale badge with countdown
class FlashSaleBadge extends StatelessWidget {
  const FlashSaleBadge({
    super.key,
    required this.discount,
    this.endsAt,
    this.showCountdown = true,
  });

  final Discount discount;
  final DateTime? endsAt;
  final bool showCountdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.pink.shade400, Colors.orange.shade400],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.pink.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.flash_on,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'FLASH SALE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                '${discount.value.toStringAsFixed(0)}% OFF',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (showCountdown && endsAt != null) ...[
            const SizedBox(width: 12),
            _CountdownTimer(endsAt: endsAt!),
          ],
        ],
      ),
    );
  }
}

class _CountdownTimer extends StatelessWidget {
  const _CountdownTimer({required this.endsAt});

  final DateTime endsAt;

  @override
  Widget build(BuildContext context) {
    final remaining = endsAt.difference(DateTime.now());
    if (remaining.isNegative) {
      return const Text(
        'ENDED',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m left',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
