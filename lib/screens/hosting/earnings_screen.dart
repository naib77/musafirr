import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/booking.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';

/// Screen showing host's earnings summary.
///
/// Earnings semantics (single source of truth for this screen):
///   - **Realized**  — money from bookings the host has marked `completed`.
///   - **Pending**   — money committed but not yet realized: `confirmed`
///                     (guest is booked) + `active` (guest currently staying).
/// The two are reported separately so the screen never looks "empty" just
/// because no booking has been marked complete yet.
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

        // Host's own listings — match strictly by owner id. Matching on
        // display name would fold in a different host who shares the same name.
        final hostListings =
            repository.listings.where((l) => l.hostId == user.id).toList();

        if (hostListings.isEmpty) {
          return _RefreshWrap(
            repository: repository,
            child: const _NoListingsView(),
          );
        }

        final hostListingIds = hostListings.map((l) => l.id).toSet();
        final hostBookings = repository.bookings
            .where((b) => hostListingIds.contains(b.listingId))
            .toList();

        // Realized = paid OR completed (see Booking.isEarnedRevenue); pending =
        // accepted stays still awaiting payment. Payment-driven so a paid,
        // not-yet-completed booking is realized immediately instead of sitting
        // in "pending" forever.
        final completed = hostBookings.where((b) => b.isEarnedRevenue).toList()
          ..sort((a, b) => (b.paidAt ?? b.completedAt ?? b.effectiveCheckOut)
              .compareTo(a.paidAt ?? a.completedAt ?? a.effectiveCheckOut));

        final pending = hostBookings.where((b) => b.isPendingPayout).toList();

        final now = DateTime.now();
        final thisMonthStart = DateTime(now.year, now.month, 1);

        final totalEarnings =
            completed.fold<double>(0, (sum, b) => sum + b.totalPrice);
        // Attribute earned money to the month it was actually collected
        // (paid_at). Fall back to completion/checkout for legacy completed
        // bookings that predate the payment flow (no paid_at).
        final thisMonthEarnings = completed
            .where((b) => (b.paidAt ?? b.completedAt ?? b.effectiveCheckOut)
                .isAfter(thisMonthStart))
            .fold<double>(0, (sum, b) => sum + b.totalPrice);
        final pendingPayouts =
            pending.fold<double>(0, (sum, b) => sum + b.totalPrice);
        final avgPerBooking =
            completed.isEmpty ? 0.0 : totalEarnings / completed.length;

        return _RefreshWrap(
          repository: repository,
          child: _EarningsDashboard(
            totalEarnings: totalEarnings,
            thisMonthEarnings: thisMonthEarnings,
            pendingPayouts: pendingPayouts,
            completedCount: completed.length,
            pendingCount: pending.length,
            avgPerBooking: avgPerBooking,
            recentBookings: completed.take(12).toList(),
            repository: repository,
          ),
        );
      },
    );
  }
}

/// Wraps any body in a working pull-to-refresh that reloads the repository.
/// (The previous version had an empty `onRefresh` so it never reloaded.)
class _RefreshWrap extends StatelessWidget {
  const _RefreshWrap({required this.repository, required this.child});

  final MusafirRepository repository;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: repository.refresh,
      child: child,
    );
  }
}

class _NotLoggedInView extends StatelessWidget {
  const _NotLoggedInView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        Icon(
          Icons.lock_outline_rounded,
          size: 64,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),
        Text(
          'Log in to view earnings',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _NoListingsView extends StatelessWidget {
  const _NoListingsView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.12),
        Center(
          child: Container(
            width: 104,
            height: 104,
            decoration: const BoxDecoration(
              gradient: AppColors.brandGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              size: 48,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'No earnings yet',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Create a listing to start earning. Income from completed bookings '
          'will appear here.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _EarningsDashboard extends StatelessWidget {
  const _EarningsDashboard({
    required this.totalEarnings,
    required this.thisMonthEarnings,
    required this.pendingPayouts,
    required this.completedCount,
    required this.pendingCount,
    required this.avgPerBooking,
    required this.recentBookings,
    required this.repository,
  });

  final double totalEarnings;
  final double thisMonthEarnings;
  final double pendingPayouts;
  final int completedCount;
  final int pendingCount;
  final double avgPerBooking;
  final List<Booking> recentBookings;
  final MusafirRepository repository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _HeroEarningsCard(
          totalEarnings: totalEarnings,
          thisMonthEarnings: thisMonthEarnings,
          pendingPayouts: pendingPayouts,
        ),
        const SizedBox(height: 16),

        // Secondary metrics
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                icon: Icons.check_circle_rounded,
                color: AppColors.success,
                value: '$completedCount',
                label: 'Completed',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                icon: Icons.schedule_rounded,
                color: AppColors.warning,
                value: '$pendingCount',
                label: 'In progress',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                icon: Icons.trending_up_rounded,
                color: AppColors.blue,
                value: '৳${_compact(avgPerBooking)}',
                label: 'Avg / booking',
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent earnings',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (recentBookings.isNotEmpty)
              Text(
                '$completedCount total',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        if (recentBookings.isEmpty)
          _EmptyRecentEarnings(pendingCount: pendingCount)
        else
          ...recentBookings.map((booking) {
            final listing = repository.listings
                .where((l) => l.id == booking.listingId)
                .firstOrNull;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _EarningItem(
                booking: booking,
                listingTitle:
                    listing?.title ?? booking.listingTitle ?? 'Listing',
              ),
            );
          }),
      ],
    );
  }
}

class _HeroEarningsCard extends StatelessWidget {
  const _HeroEarningsCard({
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
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.savings_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'Total earned',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '৳${_formatFull(totalEarnings)}',
              style: theme.textTheme.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: 'This month',
                  amount: thisMonthEarnings,
                  icon: Icons.calendar_today_rounded,
                ),
              ),
              Container(
                width: 1,
                height: 42,
                color: Colors.white.withValues(alpha: 0.25),
              ),
              Expanded(
                child: _HeroStat(
                  label: 'Pending payout',
                  amount: pendingPayouts,
                  icon: Icons.pending_actions_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.85)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '৳${_formatFull(amount)}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRecentEarnings extends StatelessWidget {
  const _EmptyRecentEarnings({required this.pendingCount});

  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // When bookings are in flight but none are completed, explain *why* the
    // realized total is still zero instead of looking broken.
    final hasPending = pendingCount > 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            hasPending
                ? Icons.hourglass_top_rounded
                : Icons.receipt_long_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            hasPending
                ? 'Earnings are on the way'
                : 'No completed bookings yet',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasPending
                ? 'You have $pendingCount booking${pendingCount == 1 ? '' : 's'} '
                    'in progress. Mark a stay complete to realize its earnings.'
                : 'Income shows here once you mark a booking complete.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
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
    final initial =
        booking.tenantName.trim().isEmpty ? '?' : booking.tenantName.trim()[0];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Guest avatar initial
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              initial.toUpperCase(),
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.brand,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.tenantName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  listingTitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${booking.durationLabel} · ${_formatDate(completedDate)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '+৳${booking.totalPrice.toStringAsFixed(0)}',
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ============== Formatting helpers ==============

/// Full amount with thousands separators, e.g. 1234567 -> "12,34,567" style is
/// overkill here — use plain grouped thousands for clarity.
String _formatFull(double amount) {
  final whole = amount.round();
  final s = whole.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Compact form for tight tiles: 1.2K / 3.4M.
String _compact(double amount) {
  if (amount >= 1000000) return '${(amount / 1000000).toStringAsFixed(1)}M';
  if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
  return amount.toStringAsFixed(0);
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
