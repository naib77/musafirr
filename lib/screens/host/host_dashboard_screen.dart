import 'package:flutter/material.dart';

import '../../core/utils/responsive.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money.dart';
import '../../core/theme/app_colors.dart';
import '../../models/listing.dart';
import '../../models/booking.dart';
import '../../models/booking_categorizer.dart';
import '../../models/booking_status.dart';
import '../../models/leaderboard_entry.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';
import '../../state/messaging_state.dart';
import '../../widgets/modern_banner.dart';
import '../leaderboard/host_leaderboard_screen.dart';
import 'create_listing_screen.dart';
import 'host_listings_screen.dart';
import 'host_reservations_screen.dart';
import 'scheduled_messages_screen.dart';

class HostDashboardScreen extends StatelessWidget {
  const HostDashboardScreen({
    super.key,
    required this.repository,
    required this.authState,
    this.messagingState,
    this.onOpenReservations,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final MessagingStateNotifier? messagingState;

  /// Switches the shell to the Reservations tab. Preferred over pushing a new
  /// route so the user sees the full tabbed UI (Guest/Host switcher + bottom
  /// nav), exactly as if they tapped the Reservations tab directly.
  final VoidCallback? onOpenReservations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = authState.currentUser;

    return ListenableBuilder(
        listenable: Listenable.merge([repository, authState]),
        builder: (context, _) {
          final hostListings = user != null
              ? repository.listings
                  .where((l) => l.hostId == user.id)
                  .toList()
              : <Listing>[];

          final hostBookings = hostListings.isEmpty
              ? <Booking>[]
              : repository.bookings
                  .where((b) => hostListings.any((l) => l.id == b.listingId))
                  .toList();

          // Same shared categorizer as the Reservations "Upcoming" tab, so the
          // dashboard count and list always agree with that tab. The dashboard
          // re-sorts by most-recently-requested for an "activity feed" feel.
          final upcomingBookings = BookingCategorizer(hostBookings).upcoming
            ..sort((a, b) => (b.createdAt ?? b.effectiveCheckIn)
                .compareTo(a.createdAt ?? a.effectiveCheckIn));

          // Today's overview (migrated from the retired HostingScreen): how many
          // guests arrive / leave today, and how many are currently in-house.
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          bool isSameDay(DateTime d) =>
              d.year == today.year && d.month == today.month && d.day == today.day;

          final activeBookings =
              hostBookings.where((b) => b.status == BookingStatus.active).toList();
          final todayCheckIns = hostBookings
              .where((b) =>
                  b.status == BookingStatus.confirmed &&
                  isSameDay(b.effectiveCheckIn))
              .length;
          final todayCheckOuts =
              activeBookings.where((b) => isSameDay(b.effectiveCheckOut)).length;

          // Realized earnings — paid OR completed bookings (see
          // Booking.isEarnedRevenue), matching the Earnings tab. Payment-driven
          // so a paid-but-not-yet-completed booking shows up immediately;
          // pending/cancelled/rejected money is still excluded.
          final totalEarnings = hostBookings
              .where((b) => b.isEarnedRevenue)
              .fold<Money>(
                Money.zero(Currency.BDT),
                (sum, b) => sum.add(b.totalPriceMoney),
              );

          return ResponsiveCenter(
            maxWidth: 960,
            child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Welcome message
                Text(
                  'Welcome back, ${user?.name.split(' ').first ?? 'Host'}!',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage your listings and reservations',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),

                // Host-wide availability toggle
                _AvailabilityCard(
                  available: user?.hostAvailable ?? true,
                  onChanged: (value) {
                    if (user == null) return;
                    authState.updateUser(user.copyWith(hostAvailable: value));
                    ModernBanner.showInfo(
                      context,
                      value
                          ? "You're now available — guests can book you."
                          : "You're now away — you won't receive new bookings.",
                    );
                  },
                ),
                const SizedBox(height: 12),

                // Leaderboard rank card
                if (user != null)
                  _RankCard(repository: repository, hostId: user.id),
                const SizedBox(height: 24),

                // Stats cards
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.home,
                        value: '${hostListings.length}',
                        label: 'Listings',
                        color: theme.colorScheme.primary,
                        theme: theme,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.calendar_today,
                        value: '${upcomingBookings.length}',
                        label: 'Upcoming',
                        color: Colors.orange,
                        theme: theme,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.attach_money,
                        value: totalEarnings.format(showDecimal: false),
                        label: 'Earnings',
                        color: Colors.green,
                        theme: theme,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Today's overview
                _TodayCard(
                  checkInsCount: todayCheckIns,
                  checkOutsCount: todayCheckOuts,
                  activeCount: activeBookings.length,
                  theme: theme,
                ),
                const SizedBox(height: 24),

                // Quick actions
                Text(
                  'Quick Actions',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _ActionCard(
                  icon: Icons.add_home,
                  title: 'Create New Listing',
                  description: 'Add a new property to your portfolio',
                  onTap: () => _navigateToCreateListing(context),
                  theme: theme,
                ),
                const SizedBox(height: 8),
                _ActionCard(
                  icon: Icons.home_work,
                  title: 'Manage Listings',
                  description: 'View and edit your properties',
                  onTap: () => _navigateToListings(context),
                  trailing: hostListings.isNotEmpty
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${hostListings.length}',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : null,
                  theme: theme,
                ),
                const SizedBox(height: 8),
                _ActionCard(
                  icon: Icons.book_online,
                  title: 'Reservations',
                  description: 'View upcoming and past bookings',
                  onTap: onOpenReservations ??
                      () => _navigateToReservations(context),
                  trailing: upcomingBookings.isNotEmpty
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${upcomingBookings.length}',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : null,
                  theme: theme,
                ),
                const SizedBox(height: 8),
                _ActionCard(
                  icon: Icons.schedule_send,
                  title: 'Scheduled messages',
                  description: 'Automatic guest messages for each stay',
                  onTap: () => _navigateToScheduledMessages(context),
                  theme: theme,
                ),
                const SizedBox(height: 24),

                // Recent activity
                if (upcomingBookings.isNotEmpty) ...[
                  Text(
                    'Upcoming Reservations',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...upcomingBookings.take(3).map((booking) => Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          onTap: () => _navigateToBooking(context, booking),
                          leading: CircleAvatar(
                            child: Text(
                              booking.tenantName.isNotEmpty
                                  ? booking.tenantName[0].toUpperCase()
                                  : 'G',
                            ),
                          ),
                          title: Text(booking.tenantName),
                          subtitle: Text(
                            '${_formatDate(booking.effectiveCheckIn)} - ${_formatDate(booking.effectiveCheckOut)}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                booking.totalPriceMoney
                                    .format(showDecimal: false),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      )),
                ] else ...[
                  // Empty state
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 48,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No upcoming reservations',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hostListings.isEmpty
                                ? 'Create a listing to start receiving bookings'
                                : 'Your upcoming bookings will appear here',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            ),
          );
        },
      );
  }

  void _navigateToCreateListing(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateListingScreen(
          repository: repository,
          authState: authState,
        ),
      ),
    );
  }

  void _navigateToListings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HostListingsScreen(
          repository: repository,
          authState: authState,
        ),
      ),
    );
  }

  void _navigateToScheduledMessages(BuildContext context) {
    final hostId = authState.currentUser?.id;
    if (hostId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScheduledMessagesScreen(hostId: hostId),
      ),
    );
  }

  void _navigateToReservations(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HostReservationsScreen(
          repository: repository,
          authState: authState,
          messagingState: messagingState,
          showBackButton: true,
        ),
      ),
    );
  }

  /// Open the reservations screen on the tab matching this booking, with the
  /// booking highlighted.
  void _navigateToBooking(BuildContext context, Booking booking) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HostReservationsScreen(
          repository: repository,
          authState: authState,
          messagingState: messagingState,
          initialTabIndex: HostReservationTab.forBooking(booking),
          highlightBookingId: booking.id,
          showBackButton: true,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
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
    return '${months[date.month - 1]} ${date.day}';
  }
}

/// Modern host-wide availability toggle. Green when available, amber "Away"
/// when not, with a switch.
class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({required this.available, required this.onChanged});

  final bool available;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = available ? AppColors.success : AppColors.warning;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              available
                  ? Icons.check_circle_rounded
                  : Icons.do_not_disturb_on_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  available ? 'Available' : 'Away',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  available
                      ? "You're accepting new bookings"
                      : "You're not accepting new bookings",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Wrap in a transparent Material so the Switch always has a Material
          // ancestor, no matter how this card is embedded (e.g. pushed as a
          // standalone route without a Scaffold). Prevents the
          // "No Material widget found" crash.
          Material(
            color: Colors.transparent,
            child: Switch(
              value: available,
              activeTrackColor: AppColors.success,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// "You're #X this month" card linking to the public leaderboard. Fetches the
/// host's rank once; shows a softer prompt if they aren't ranked yet.
class _RankCard extends StatefulWidget {
  const _RankCard({required this.repository, required this.hostId});

  final MusafirRepository repository;
  final String hostId;

  @override
  State<_RankCard> createState() => _RankCardState();
}

class _RankCardState extends State<_RankCard> {
  late Future<LeaderboardEntry?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.getMyHostRank(
      hostId: widget.hostId,
      period: LeaderboardPeriod.monthly,
    );
  }

  void _openLeaderboard() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HostLeaderboardScreen(
          repository: widget.repository,
          currentUserId: widget.hostId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<LeaderboardEntry?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final entry = snapshot.data;
        final ranked = entry != null;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openLeaderboard,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brand.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.emoji_events_rounded,
                        color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ranked
                              ? "You're #${entry.rank} this month"
                              : 'Host leaderboard',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ranked
                              ? 'Host Score ${entry.score.toStringAsFixed(0)} • tap to view Top Hosts'
                              : 'Complete bookings to climb the rankings',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.theme,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Glanceable "Today" summary for the host — migrated from the retired
/// HostingScreen so the dashboard keeps that overview in one place.
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.checkInsCount,
    required this.checkOutsCount,
    required this.activeCount,
    required this.theme,
  });

  final int checkInsCount;
  final int checkOutsCount;
  final int activeCount;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.wb_sunny_outlined,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                'Today',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TodayStat(
                  label: 'Check-ins',
                  count: checkInsCount,
                  theme: theme,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.2),
              ),
              Expanded(
                child: _TodayStat(
                  label: 'Check-outs',
                  count: checkOutsCount,
                  theme: theme,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.2),
              ),
              Expanded(
                child: _TodayStat(
                  label: 'Hosting',
                  count: activeCount,
                  theme: theme,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodayStat extends StatelessWidget {
  const _TodayStat({
    required this.label,
    required this.count,
    required this.theme,
  });

  final String label;
  final int count;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$count',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    required this.theme,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final ThemeData theme;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: theme.colorScheme.primary,
          ),
        ),
        title: Text(title),
        subtitle: Text(
          description,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: trailing ?? const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
