import 'package:flutter/material.dart';

import '../../models/loyalty_tier.dart';

/// Tier progress card showing progress towards next tier
class TierProgressCard extends StatelessWidget {
  const TierProgressCard({
    super.key,
    required this.progress,
    this.showAllMetrics = true,
    this.compact = false,
    this.onViewBenefits,
  });

  final TierProgress progress;
  final bool showAllMetrics;
  final bool compact;
  final VoidCallback? onViewBenefits;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompactCard(context);
    }
    return _buildFullCard(context);
  }

  Widget _buildCompactCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tierColor = progress.currentTier.color;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: tierColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tierColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                progress.currentTier.icon,
                color: tierColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${progress.currentTier.name} Member',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (progress.hasNextTier) ...[
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: progress.overallProgress / 100,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(tierColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${progress.overallProgress.toStringAsFixed(0)}% to ${progress.nextTier!.name}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Highest tier achieved!',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onViewBenefits != null)
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: onViewBenefits,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tierColor = progress.currentTier.color;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tierColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with current tier
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  tierColor.withValues(alpha: 0.8),
                  tierColor,
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    progress.currentTier.icon,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        progress.currentTier.name,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Member',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                if (progress.currentTier.discountPercentage > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${progress.currentTier.discountPercentage.toStringAsFixed(0)}% OFF',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Progress section
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (progress.hasNextTier) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progress to ${progress.nextTier!.name}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${progress.overallProgress.toStringAsFixed(0)}%',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: tierColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Overall progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress.overallProgress / 100,
                      minHeight: 8,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(tierColor),
                    ),
                  ),

                  if (showAllMetrics) ...[
                    const SizedBox(height: 20),
                    _buildMetricRow(
                      context,
                      'Bookings',
                      progress.bookingsProgress,
                      progress.bookingsRequired,
                      progress.bookingsProgressPercent,
                      Icons.calendar_month_outlined,
                      tierColor,
                    ),
                    const SizedBox(height: 12),
                    _buildMetricRow(
                      context,
                      'Nights Stayed',
                      progress.nightsProgress,
                      progress.nightsRequired,
                      progress.nightsProgressPercent,
                      Icons.nightlight_outlined,
                      tierColor,
                    ),
                    const SizedBox(height: 12),
                    _buildMetricRow(
                      context,
                      'Total Spent',
                      progress.spentProgress.toInt(),
                      progress.spentRequired.toInt(),
                      progress.spentProgressPercent,
                      Icons.payments_outlined,
                      tierColor,
                      isCurrency: true,
                    ),
                  ],
                ] else ...[
                  Center(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.emoji_events,
                          color: Colors.amber,
                          size: 48,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You\'ve reached the highest tier!',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Enjoy all the exclusive benefits',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // View benefits button
                if (onViewBenefits != null) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onViewBenefits,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: tierColor,
                        side: BorderSide(color: tierColor),
                      ),
                      child: const Text('View Benefits'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(
    BuildContext context,
    String label,
    int current,
    int required,
    double percentage,
    IconData icon,
    Color color, {
    bool isCurrency = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final currentText = isCurrency ? '৳$current' : current.toString();
    final requiredText = isCurrency ? '৳$required' : required.toString();
    final remaining = required - current;
    final remainingText = isCurrency ? '৳$remaining' : remaining.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon,
                size: 16, color: colorScheme.onSurface.withValues(alpha: 0.6)),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.bodyMedium,
            ),
            const Spacer(),
            Text(
              '$currentText / $requiredText',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percentage / 100,
                  minHeight: 6,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(
                    percentage >= 100 ? Colors.green : color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 50,
              child: Text(
                remaining > 0 ? '$remainingText left' : '✓',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: remaining > 0
                      ? colorScheme.onSurface.withValues(alpha: 0.6)
                      : Colors.green,
                  fontWeight: remaining > 0 ? null : FontWeight.bold,
                ),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Tier badge widget
class TierBadge extends StatelessWidget {
  const TierBadge({
    super.key,
    required this.tier,
    this.size = TierBadgeSize.medium,
    this.showLabel = true,
  });

  final LoyaltyTier tier;
  final TierBadgeSize size;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    double iconSize;
    double padding;
    double fontSize;

    switch (size) {
      case TierBadgeSize.small:
        iconSize = 16;
        padding = 6;
        fontSize = 10;
        break;
      case TierBadgeSize.medium:
        iconSize = 24;
        padding = 10;
        fontSize = 12;
        break;
      case TierBadgeSize.large:
        iconSize = 32;
        padding = 14;
        fontSize = 14;
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: tier.color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: tier.color.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: Icon(
            tier.icon,
            color: tier.color,
            size: iconSize,
          ),
        ),
        if (showLabel) ...[
          const SizedBox(width: 8),
          Text(
            tier.name,
            style: TextStyle(
              color: tier.color,
              fontWeight: FontWeight.w600,
              fontSize: fontSize,
            ),
          ),
        ],
      ],
    );
  }
}

enum TierBadgeSize { small, medium, large }

/// Tier benefits list widget
class TierBenefitsList extends StatelessWidget {
  const TierBenefitsList({
    super.key,
    required this.tier,
    this.highlightNew = false,
    this.previousTier,
  });

  final LoyaltyTier tier;
  final bool highlightNew;
  final LoyaltyTier? previousTier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final benefits = tier.benefitsList;

    final previousBenefits = previousTier?.benefitsList.toSet() ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${tier.name} Benefits',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ...benefits.map((benefit) {
          final isNew = highlightNew && !previousBenefits.contains(benefit);

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: isNew ? Colors.green : tier.color,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    benefit,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isNew ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                if (isNew)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'NEW',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// All tiers overview widget
class TiersOverview extends StatelessWidget {
  const TiersOverview({
    super.key,
    required this.tiers,
    required this.currentTierLevel,
    this.onTierTap,
  });

  final List<LoyaltyTier> tiers;
  final int currentTierLevel;
  final void Function(LoyaltyTier)? onTierTap;

  @override
  Widget build(BuildContext context) {
    final sortedTiers = List<LoyaltyTier>.from(tiers)
      ..sort((a, b) => a.level.compareTo(b.level));

    return Column(
      children: [
        // Tier progress line
        Row(
          children: sortedTiers.asMap().entries.expand((entry) {
            final index = entry.key;
            final tier = entry.value;
            final isCurrentOrPast = tier.level <= currentTierLevel;
            final isLast = index == sortedTiers.length - 1;

            return [
              GestureDetector(
                onTap: () => onTierTap?.call(tier),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isCurrentOrPast
                            ? tier.color
                            : tier.color.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: tier.color,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        tier.icon,
                        color: isCurrentOrPast ? Colors.white : tier.color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tier.name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: tier.level == currentTierLevel
                            ? FontWeight.bold
                            : null,
                        color:
                            tier.level == currentTierLevel ? tier.color : null,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: tier.level < currentTierLevel
                          ? tier.color
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ];
          }).toList(),
        ),
      ],
    );
  }
}
