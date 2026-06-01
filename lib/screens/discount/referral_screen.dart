import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/referral.dart';
import '../../state/referral_state.dart';
import '../../widgets/discount/referral_card.dart';
import '../../widgets/modern_banner.dart';

/// Screen for managing referrals
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _shareReferralCode(UserReferral referral) {
    Share.share(
      referral.shareMessage,
      subject: 'Join Musafir and save!',
    );
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ModernBanner.showSuccess(context, 'Referral code copied!');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Refer & Earn'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Invite Friends'),
            Tab(text: 'Referrals'),
          ],
        ),
      ),
      body: Consumer<ReferralStateNotifier>(
        builder: (context, state, child) {
          if (state.isLoading && state.userReferral == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.error != null && state.userReferral == null) {
            return _buildErrorView(state);
          }

          return TabBarView(
            controller: _tabController,
            children: [
              _buildInviteTab(state),
              _buildReferralsTab(state),
            ],
          );
        },
      ),
    );
  }

  Widget _buildErrorView(ReferralStateNotifier state) {
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

  Widget _buildInviteTab(ReferralStateNotifier state) {
    final referral = state.userReferral;

    if (referral == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () => state.refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Main referral card
            ReferralCard(
              referral: referral,
              onShare: () => _shareReferralCode(referral),
              onCopyCode: () => _copyCode(referral.referralCode),
            ),

            const SizedBox(height: 24),

            // How it works section
            ReferralHowItWorks(
              refereeDiscount: referral.refereeDiscountAmount,
              referrerReward: referral.referrerRewardAmount,
            ),

            const SizedBox(height: 24),

            // Share options
            _buildShareOptions(referral),

            const SizedBox(height: 24),

            // Terms
            _buildTerms(context),
          ],
        ),
      ),
    );
  }

  Widget _buildReferralsTab(ReferralStateNotifier state) {
    final completions = state.completions;
    final stats = state.stats;

    return RefreshIndicator(
      onRefresh: () => state.refresh(),
      child: completions.isEmpty
          ? _buildEmptyReferrals()
          : CustomScrollView(
              slivers: [
                // Stats header
                if (stats != null)
                  SliverToBoxAdapter(
                    child: _buildStatsHeader(stats),
                  ),

                // Referral list
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final completion = completions[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ReferralCompletionCard(
                            completion: completion,
                            rewardAmount:
                                state.userReferral?.referrerRewardAmount ?? 500,
                          ),
                        );
                      },
                      childCount: completions.length,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyReferrals() {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No referrals yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Share your code with friends to start earning rewards!',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _tabController.animateTo(0),
              icon: const Icon(Icons.share),
              label: const Text('Share Your Code'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsHeader(ReferralStats stats) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.purple.shade400,
            Colors.purple.shade600,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatColumn(
                  'Total Referrals',
                  stats.totalReferrals.toString(),
                  Icons.people,
                ),
              ),
              Container(
                height: 50,
                width: 1,
                color: Colors.white.withOpacity(0.3),
              ),
              Expanded(
                child: _buildStatColumn(
                  'Completed',
                  stats.completedReferrals.toString(),
                  Icons.check_circle,
                ),
              ),
              Container(
                height: 50,
                width: 1,
                color: Colors.white.withOpacity(0.3),
              ),
              Expanded(
                child: _buildStatColumn(
                  'Total Earned',
                  '৳${stats.totalEarnings.toStringAsFixed(0)}',
                  Icons.savings,
                ),
              ),
            ],
          ),
          if (stats.pendingReferrals > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.hourglass_empty, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '${stats.pendingReferrals} pending • ৳${stats.pendingEarnings.toStringAsFixed(0)} potential',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.8), size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildShareOptions(UserReferral referral) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Share via',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildShareButton(
              icon: Icons.message,
              label: 'Message',
              color: Colors.blue,
              onTap: () => _shareReferralCode(referral),
            ),
            _buildShareButton(
              icon: Icons.mail,
              label: 'Email',
              color: Colors.red,
              onTap: () => _shareReferralCode(referral),
            ),
            _buildShareButton(
              icon: Icons.copy,
              label: 'Copy Link',
              color: Colors.grey,
              onTap: () => _copyCode(referral.shareLink),
            ),
            _buildShareButton(
              icon: Icons.more_horiz,
              label: 'More',
              color: Colors.purple,
              onTap: () => _shareReferralCode(referral),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildShareButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerms(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
              const SizedBox(width: 8),
              Text(
                'Terms & Conditions',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '• Your friend must be a new Musafir user\n'
            '• They must complete their first booking\n'
            '• Rewards are credited after checkout\n'
            '• Credits can be used on future bookings\n'
            '• Musafir reserves the right to modify terms',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
