import 'package:flutter/material.dart';

import '../../models/booking.dart';
import '../../models/booking_status.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';

/// Screen showing host's earnings summary
class EarningsScreen extends StatelessWidget {
  const EarningsScreen({
    super.key,
    required this.repository,
    required this.authState,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([repository, authState]),
      builder: (context, _) {
        final user = authState.currentUser;
        if (user == null) {
          return const _NotLoggedInView();
        }

        // Get host's listings
        final hostListings = repository.listings
            .where((l) => l.hostId == user.id || l.ownerName == user.name)
            .toList();

        if (hostListings.isEmpty) {
          return const _NoListingsView();
        }

        // Get completed bookings for earnings calculation
        final hostBookings = repository.bookings
            .where((b) => hostListings.any((l) => l.id == b.listingId))
            .toList();

        final completedBookings = hostBookings
            .where((b) => b.status == BookingStatus.completed)
            .toList()
          ..sort((a, b) => (b.completedAt ?? b.effectiveCheckOut)
              .compareTo(a.completedAt ?? a.effectiveCheckOut));

        // Calculate earnings
        final now = DateTime.now();
        final thisMonthStart = DateTime(now.year, now.month, 1);

        final totalEarnings = completedBookings.fold<double>(
          0,
          (sum, b) => sum + b.totalPrice,
        );

        final thisMonthEarnings = completedBookings
            .where((b) =>
                (b.completedAt ?? b.effectiveCheckOut).isAfter(thisMonthStart))
            .fold<double>(0, (sum, b) => sum + b.totalPrice);

        // Pending payouts (confirmed but not yet completed)
        final pendingPayouts = hostBookings
            .where((b) =>
                b.status == BookingStatus.confirmed ||
                b.status == BookingStatus.active)
            .fold<double>(0, (sum, b) => sum + b.totalPrice);

        return _EarningsDashboard(
          totalEarnings: totalEarnings,
          thisMonthEarnings: thisMonthEarnings,
          pendingPayouts: pendingPayouts,
          recentBookings: completedBookings.take(10).toList(),
          repository: repository,
        );
      },
    );
  }
}

class _NotLoggedInView extends StatelessWidget {
  const _NotLoggedInView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.login,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Login to view earnings',
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoListingsView extends StatelessWidget {
  const _NoListingsView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.account_balance_wallet,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No earnings yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Create a listing to start earning. Your earnings from completed bookings will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EarningsDashboard extends StatelessWidget {
  const _EarningsDashboard({
    required this.totalEarnings,
    required this.thisMonthEarnings,
    required this.pendingPayouts,
    required this.recentBookings,
    required this.repository,
  });

  final double totalEarnings;
  final double thisMonthEarnings;
  final double pendingPayouts;
  final List<Booking> recentBookings;
  final MusafirRepository repository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async {
        // Trigger repository refresh if available
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Earnings summary cards
          _EarningsSummaryCard(
            totalEarnings: totalEarnings,
            thisMonthEarnings: thisMonthEarnings,
            pendingPayouts: pendingPayouts,
          ),
          const SizedBox(height: 24),

          // Recent completed bookings
          Text(
            'Recent Earnings',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          if (recentBookings.isEmpty)
            _EmptyRecentEarnings()
          else
            ...recentBookings.map((booking) {
              final listing = repository.listings.firstWhere(
                (l) => l.id == booking.listingId,
                orElse: () => repository.listings.first,
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _EarningItem(
                  booking: booking,
                  listingTitle: listing.title,
                ),
              );
            }),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _EarningsSummaryCard extends StatelessWidget {
  const _EarningsSummaryCard({
    required this.totalEarnings,
    required this.thisMonthEarnings,
    required this.pendingPayouts,
  });

  final double totalEarnings;
  final double thisMonthEarnings;
  final double pendingPayouts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total Earnings',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '৳${_formatAmount(totalEarnings)}',
            style: theme.textTheme.headlineLarge?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _SummaryItem(
                  label: 'This Month',
                  amount: thisMonthEarnings,
                  icon: Icons.calendar_today,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.3),
              ),
              Expanded(
                child: _SummaryItem(
                  label: 'Pending',
                  amount: pendingPayouts,
                  icon: Icons.pending_actions,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toStringAsFixed(0);
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.amount,
    required this.icon,
  });

  final String label;
  final double amount;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '৳${amount.toStringAsFixed(0)}',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _EmptyRecentEarnings extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'No completed bookings yet',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Completed bookings will appear here',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _EarningItem extends StatelessWidget {
  const _EarningItem({
    required this.booking,
    required this.listingTitle,
  });

  final Booking booking;
  final String listingTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completedDate = booking.completedAt ?? booking.effectiveCheckOut;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Green check icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.tenantName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  listingTitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatDate(completedDate),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Amount
          Text(
            '+৳${booking.totalPrice.toStringAsFixed(0)}',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
