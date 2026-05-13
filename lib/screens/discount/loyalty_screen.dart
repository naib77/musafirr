import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/loyalty_tier.dart';
import '../../state/loyalty_state.dart';
import '../../widgets/discount/tier_progress.dart';

/// Screen for loyalty program details
class LoyaltyScreen extends StatelessWidget {
  const LoyaltyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loyalty Program'),
      ),
      body: Consumer<LoyaltyStateNotifier>(
        builder: (context, state, child) {
          if (state.isLoading && state.userLoyalty == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.error != null && state.userLoyalty == null) {
            return _buildErrorView(context, state);
          }

          return _buildContent(context, state);
        },
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, LoyaltyStateNotifier state) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            state.error ?? 'Something went wrong',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => state.refresh(),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, LoyaltyStateNotifier state) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () => state.refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Upgrade notification
            if (state.recentUpgrade != null)
              _buildUpgradeNotification(context, state),

            // Tier progress card
            if (state.progress != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: TierProgressCard(
                  progress: state.progress!,
                  onViewBenefits: () =>
                      _showBenefitsSheet(context, state.currentTier!),
                ),
              ),

            // Stats section
            _buildStatsSection(context, state),

            // All tiers overview
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Loyalty Tiers',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (state.tiers.isNotEmpty)
                    TiersOverview(
                      tiers: state.tiers,
                      currentTierLevel: state.tierLevel.level,
                      onTierTap: (tier) => _showTierDetails(context, tier),
                    ),
                ],
              ),
            ),

            const Divider(height: 32),

            // Benefits section
            if (state.currentTier != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: TierBenefitsList(tier: state.currentTier!),
              ),

            const Divider(height: 32),

            // How it works
            _buildHowItWorks(context),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildUpgradeNotification(
    BuildContext context,
    LoyaltyStateNotifier state,
  ) {
    final theme = Theme.of(context);
    final upgrade = state.recentUpgrade!;
    final newTier = upgrade.newTier;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            newTier.color.withOpacity(0.8),
            newTier.color,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: newTier.color.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.celebration,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Congratulations!',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      upgrade.message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => state.clearUpgradeNotification(),
              ),
            ],
          ),
          if (upgrade.newBenefits.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'New Benefits:',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.white.withOpacity(0.9),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...upgrade.newBenefits.map((benefit) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.check, color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                benefit,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsSection(BuildContext context, LoyaltyStateNotifier state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Stats',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  'Bookings',
                  state.totalBookings.toString(),
                  Icons.calendar_month,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  context,
                  'Nights',
                  state.totalNightsStayed.toString(),
                  Icons.nightlight,
                  Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  'Total Spent',
                  '৳${state.totalAmountSpent.toStringAsFixed(0)}',
                  Icons.payments,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  context,
                  'Points',
                  state.loyaltyPoints.toString(),
                  Icons.stars,
                  Colors.amber,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorks(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to Level Up',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          _buildStep(
            context,
            1,
            'Book stays',
            'Every booking brings you closer to the next tier',
            Icons.calendar_today,
          ),
          _buildStep(
            context,
            2,
            'Stay more nights',
            'Longer stays contribute to your progress',
            Icons.nightlight,
          ),
          _buildStep(
            context,
            3,
            'Unlock rewards',
            'Higher tiers mean better discounts and perks',
            Icons.card_giftcard,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStep(
    BuildContext context,
    int number,
    String title,
    String description,
    IconData icon, {
    bool isLast = false,
  }) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  number.toString(),
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: theme.colorScheme.primary.withOpacity(0.2),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showBenefitsSheet(BuildContext context, LoyaltyTier tier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Tier header
                Row(
                  children: [
                    TierBadge(tier: tier, size: TierBadgeSize.large),
                    const Spacer(),
                    if (tier.discountPercentage > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: tier.color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${tier.discountPercentage.toStringAsFixed(0)}% OFF',
                          style: TextStyle(
                            color: tier.color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),

                // Benefits
                TierBenefitsList(tier: tier),

                const SizedBox(height: 24),

                // Requirements
                Text(
                  'Requirements',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                _buildRequirementRow(
                  context,
                  'Bookings',
                  '${tier.minBookings}+',
                  Icons.calendar_month,
                ),
                _buildRequirementRow(
                  context,
                  'Nights stayed',
                  '${tier.minNightsStayed}+',
                  Icons.nightlight,
                ),
                _buildRequirementRow(
                  context,
                  'Total spent',
                  '৳${tier.minTotalSpent.toStringAsFixed(0)}+',
                  Icons.payments,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRequirementRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text(label, style: theme.textTheme.bodyMedium),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showTierDetails(BuildContext context, LoyaltyTier tier) {
    _showBenefitsSheet(context, tier);
  }
}
