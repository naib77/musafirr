import 'package:flutter/material.dart';

import '../../core/currency/currency.dart';
import '../../core/currency/money.dart';
import '../../models/listing.dart';
import '../../models/booking.dart';
import '../../models/booking_categorizer.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';
import '../../state/messaging_state.dart';
import 'create_listing_screen.dart';
import 'host_listings_screen.dart';
import 'host_reservations_screen.dart';

class HostDashboardScreen extends StatelessWidget {
  const HostDashboardScreen({
    super.key,
    required this.repository,
    required this.authState,
    this.messagingState,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final MessagingStateNotifier? messagingState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = authState.currentUser;

    return ListenableBuilder(
        listenable: Listenable.merge([repository, authState]),
        builder: (context, _) {
          final hostListings = user != null
              ? repository.listings
                  .where((l) => l.hostId == user.id || l.ownerName == user.name)
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

          final totalEarnings = hostBookings.fold<Money>(
            Money.zero(Currency.BDT),
            (sum, b) => sum.add(b.totalPriceMoney),
          );

          return SingleChildScrollView(
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
                  onTap: () => _navigateToReservations(context),
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

  void _navigateToReservations(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HostReservationsScreen(
          repository: repository,
          authState: authState,
          messagingState: messagingState,
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
