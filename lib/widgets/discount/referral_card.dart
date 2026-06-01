import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/referral.dart';
import '../modern_banner.dart';

/// Referral card widget displaying user's referral info
class ReferralCard extends StatelessWidget {
  const ReferralCard({
    super.key,
    required this.referral,
    this.onShare,
    this.onCopyCode,
    this.showStats = true,
    this.compact = false,
  });

  final UserReferral referral;
  final VoidCallback? onShare;
  final VoidCallback? onCopyCode;
  final bool showStats;
  final bool compact;

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

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.card_giftcard,
                color: Colors.purple,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Invite friends & earn',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Give ৳${referral.refereeDiscountAmount.toStringAsFixed(0)}, get ৳${referral.referrerRewardAmount.toStringAsFixed(0)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: onShare,
              child: const Text('Share'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.purple.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.purple.shade400,
                  Colors.purple.shade600,
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
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.card_giftcard,
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
                        'Invite Friends',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Give ৳${referral.refereeDiscountAmount.toStringAsFixed(0)}, get ৳${referral.referrerRewardAmount.toStringAsFixed(0)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Referral code section
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your referral code',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.purple.withOpacity(0.2),
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          referral.referralCode,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                            color: Colors.purple.shade700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        color: Colors.purple,
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: referral.referralCode),
                          );
                          onCopyCode?.call();
                          ModernBanner.showSuccess(context, 'Code copied to clipboard');
                        },
                        tooltip: 'Copy code',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Share button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.share),
                    label: const Text('Share with friends'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.purple,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),

                // Stats
                if (showStats && referral.totalReferrals > 0) ...[
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatItem(
                          context,
                          'Referrals',
                          referral.totalReferrals.toString(),
                          Icons.people_outline,
                        ),
                      ),
                      Container(
                        height: 40,
                        width: 1,
                        color: colorScheme.outline.withOpacity(0.2),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          context,
                          'Completed',
                          referral.successfulReferrals.toString(),
                          Icons.check_circle_outline,
                        ),
                      ),
                      Container(
                        height: 40,
                        width: 1,
                        color: colorScheme.outline.withOpacity(0.2),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          context,
                          'Earned',
                          '৳${referral.totalRewardsEarned.toStringAsFixed(0)}',
                          Icons.savings_outlined,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Icon(
          icon,
          size: 20,
          color: Colors.purple.withOpacity(0.7),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ],
    );
  }
}

/// Referral completion card for showing individual referrals
class ReferralCompletionCard extends StatelessWidget {
  const ReferralCompletionCard({
    super.key,
    required this.completion,
    this.rewardAmount = 500,
  });

  final ReferralCompletion completion;
  final double rewardAmount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: _getStatusColor(completion.status).withOpacity(0.1),
              backgroundImage: completion.refereeAvatarUrl != null
                  ? NetworkImage(completion.refereeAvatarUrl!)
                  : null,
              child: completion.refereeAvatarUrl == null
                  ? Text(
                      _getInitials(completion.refereeName),
                      style: TextStyle(
                        color: _getStatusColor(completion.status),
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    completion.refereeName ?? 'Friend',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _getStatusText(completion.status),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  Text(
                    'Joined ${_formatDate(completion.signedUpAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),

            // Status badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(completion.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    completion.status.displayName,
                    style: TextStyle(
                      color: _getStatusColor(completion.status),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (completion.isComplete) ...[
                  const SizedBox(height: 4),
                  Text(
                    '+৳${rewardAmount.toStringAsFixed(0)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(ReferralStatus status) {
    switch (status) {
      case ReferralStatus.pending:
        return Colors.orange;
      case ReferralStatus.discountUsed:
        return Colors.blue;
      case ReferralStatus.completed:
        return Colors.green;
      case ReferralStatus.expired:
        return Colors.grey;
    }
  }

  String _getStatusText(ReferralStatus status) {
    switch (status) {
      case ReferralStatus.pending:
        return 'Waiting for first booking';
      case ReferralStatus.discountUsed:
        return 'Used their discount';
      case ReferralStatus.completed:
        return 'Completed first booking';
      case ReferralStatus.expired:
        return 'Referral expired';
    }
  }

  String _getInitials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'today';
    } else if (diff.inDays == 1) {
      return 'yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return '$weeks week${weeks > 1 ? 's' : ''} ago';
    } else {
      final months = (diff.inDays / 30).floor();
      return '$months month${months > 1 ? 's' : ''} ago';
    }
  }
}

/// How it works section for referrals
class ReferralHowItWorks extends StatelessWidget {
  const ReferralHowItWorks({
    super.key,
    this.refereeDiscount = 500,
    this.referrerReward = 500,
  });

  final double refereeDiscount;
  final double referrerReward;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How it works',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        _buildStep(
          context,
          1,
          'Share your code',
          'Share your unique referral code with friends',
          Icons.share,
        ),
        _buildStep(
          context,
          2,
          'Friend signs up',
          'They get ৳${refereeDiscount.toStringAsFixed(0)} off their first booking',
          Icons.person_add,
        ),
        _buildStep(
          context,
          3,
          'You earn rewards',
          'Get ৳${referrerReward.toStringAsFixed(0)} when they complete their first stay',
          Icons.card_giftcard,
          isLast: true,
        ),
      ],
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
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: Colors.purple,
                  size: 20,
                ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: Colors.purple.withOpacity(0.2),
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
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
