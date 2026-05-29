import 'package:flutter/material.dart';

import '../../models/booking.dart';
import '../../models/booking_status.dart';
import '../../models/listing.dart';
import '../../models/review.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';
import '../../widgets/price_display.dart';
import '../review/host_review_screen.dart';

class HostReservationsScreen extends StatefulWidget {
  const HostReservationsScreen({
    super.key,
    required this.repository,
    required this.authState,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;

  @override
  State<HostReservationsScreen> createState() => _HostReservationsScreenState();
}

class _HostReservationsScreenState extends State<HostReservationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = widget.authState.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reservations'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Current'),
            Tab(text: 'Past'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.repository, widget.authState]),
        builder: (context, _) {
          // Get host's listings
          final hostListings = user != null
              ? widget.repository.listings
                  .where((l) => l.hostId == user.id || l.ownerName == user.name)
                  .toList()
              : <Listing>[];

          // Get bookings for host's listings
          final hostBookings = hostListings.isEmpty
              ? <Booking>[]
              : widget.repository.bookings
                  .where((b) => hostListings.any((l) => l.id == b.listingId))
                  .toList();

          final now = DateTime.now();

          final upcomingBookings = hostBookings
              .where(
                  (b) => b.status.isActive && b.effectiveCheckIn.isAfter(now))
              .toList()
            ..sort((a, b) => a.effectiveCheckIn.compareTo(b.effectiveCheckIn));

          final currentBookings = hostBookings
              .where((b) =>
                  b.status.isActive &&
                  b.effectiveCheckIn.isBefore(now) &&
                  b.effectiveCheckOut.isAfter(now))
              .toList();

          final pastBookings = hostBookings
              .where(
                  (b) => b.status.isPast || b.effectiveCheckOut.isBefore(now))
              .toList()
            ..sort((a, b) => b.effectiveCheckIn.compareTo(a.effectiveCheckIn));

          return TabBarView(
            controller: _tabController,
            children: [
              _buildBookingsList(
                context,
                theme,
                upcomingBookings,
                emptyMessage: 'No upcoming reservations',
                emptySubtitle: 'New bookings will appear here',
              ),
              _buildBookingsList(
                context,
                theme,
                currentBookings,
                emptyMessage: 'No current guests',
                emptySubtitle: 'Active stays will appear here',
              ),
              _buildBookingsList(
                context,
                theme,
                pastBookings,
                emptyMessage: 'No past reservations',
                emptySubtitle: 'Completed bookings will appear here',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBookingsList(
    BuildContext context,
    ThemeData theme,
    List<Booking> bookings, {
    required String emptyMessage,
    required String emptySubtitle,
  }) {
    if (bookings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_today,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                emptyMessage,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                emptySubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: bookings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final booking = bookings[index];
        return _ReservationCard(
          booking: booking,
          onTap: () => _showBookingDetails(context, booking),
        );
      },
    );
  }

  void _showBookingDetails(BuildContext context, Booking booking) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Guest info
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    child: Text(
                      booking.tenantName.isNotEmpty
                          ? booking.tenantName[0].toUpperCase()
                          : 'G',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking.tenantName,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Guest',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(booking.status)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      booking.status.title,
                      style: TextStyle(
                        color: _getStatusColor(booking.status),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),

              // Booking details
              _DetailRow(
                icon: Icons.home,
                label: 'Property',
                value: booking.listingTitle ?? 'N/A',
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.calendar_today,
                label: 'Check-in',
                value: _formatFullDate(booking.effectiveCheckIn),
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.calendar_today,
                label: 'Check-out',
                value: _formatFullDate(booking.effectiveCheckOut),
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.nights_stay,
                label: 'Nights',
                value: '${booking.numberOfNights}',
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.people,
                label: 'Guests',
                value: '${booking.guestCount}',
              ),
              const Divider(height: 32),

              // Earnings
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total earnings',
                    style: theme.textTheme.titleMedium,
                  ),
                  PriceDisplay(
                    amount: booking.totalPriceMoney,
                    style: PriceDisplayStyle.large,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Actions based on booking status
              _buildBookingActions(context, booking),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookingActions(BuildContext context, Booking booking) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final canCheckIn = booking.status == BookingStatus.confirmed &&
        !DateTime(now.year, now.month, now.day).isBefore(
            DateTime(booking.effectiveCheckIn.year,
                booking.effectiveCheckIn.month, booking.effectiveCheckIn.day));

    return switch (booking.status) {
      // Pending: Accept or Reject
      BookingStatus.pending => Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showRejectDialog(context, booking),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _showAcceptDialog(context, booking),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      // Confirmed: Check-in (if on/after start date) or Cancel
      BookingStatus.confirmed => Column(
          children: [
            if (canCheckIn)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _checkInGuest(context, booking),
                  icon: const Icon(Icons.login),
                  label: const Text('Guest Arrived'),
                ),
              ),
            if (canCheckIn) const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _cancelBooking(context, booking),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: const Text('Cancel Booking'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Messaging coming soon!')),
                      );
                    },
                    child: const Text('Message Guest'),
                  ),
                ),
              ],
            ),
          ],
        ),
      // Active: Service Complete
      BookingStatus.active => SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _completeService(context, booking),
            icon: const Icon(Icons.check_circle),
            label: const Text('Service Complete'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
            ),
          ),
        ),
      // Completed: Leave Review
      BookingStatus.completed => SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _navigateToReview(context, booking);
            },
            icon: const Icon(Icons.rate_review),
            label: const Text('Review Guest'),
          ),
        ),
      // Other past states: No actions
      _ => const SizedBox.shrink(),
    };
  }

  void _showAcceptDialog(BuildContext context, Booking booking) {
    final messageController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Accept Booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Accept booking from ${booking.tenantName}?'),
            const SizedBox(height: 16),
            TextField(
              controller: messageController,
              decoration: const InputDecoration(
                labelText: 'Welcome message (optional)',
                hintText: 'e.g., Looking forward to hosting you!',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final updated = booking.copyWith(
                status: BookingStatus.confirmed,
                confirmedAt: DateTime.now(),
                hostMessage: messageController.text.isNotEmpty
                    ? messageController.text
                    : null,
              );
              widget.repository.updateBooking(updated);
              Navigator.pop(dialogContext);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Booking accepted!')),
              );
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(BuildContext context, Booking booking) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Decline Booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Decline booking from ${booking.tenantName}?'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g., Dates not available',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final updated = booking.copyWith(
                status: BookingStatus.rejected,
                rejectionReason: reasonController.text.isNotEmpty
                    ? reasonController.text
                    : null,
              );
              widget.repository.updateBooking(updated);
              Navigator.pop(dialogContext);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Booking declined')),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
  }

  void _checkInGuest(BuildContext context, Booking booking) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm Check-in'),
        content: Text('Mark ${booking.tenantName} as arrived?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final updated = booking.copyWith(
                status: BookingStatus.active,
                actualCheckIn: DateTime.now(),
              );
              widget.repository.updateBooking(updated);
              Navigator.pop(dialogContext);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Guest checked in!')),
              );
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _completeService(BuildContext context, Booking booking) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Complete Service'),
        content: const Text(
          'Mark this booking as complete? This indicates the guest has left and service is finished.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final updated = booking.copyWith(
                status: BookingStatus.completed,
                completedAt: DateTime.now(),
              );
              widget.repository.updateBooking(updated);
              Navigator.pop(dialogContext);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Service completed! Don\'t forget to leave a review.'),
                ),
              );
            },
            child: const Text('Complete'),
          ),
        ],
      ),
    );
  }

  void _cancelBooking(BuildContext context, Booking booking) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: Text(
          'Are you sure you want to cancel the booking with ${booking.tenantName}? The guest will be notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep Booking'),
          ),
          FilledButton(
            onPressed: () {
              final user = widget.authState.currentUser;
              final updated = booking.copyWith(
                status: BookingStatus.cancelled,
                cancelledBy: user?.id,
                cancelledAt: DateTime.now(),
              );
              widget.repository.updateBooking(updated);
              Navigator.pop(dialogContext);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Booking cancelled')),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
  }

  void _navigateToReview(BuildContext context, Booking booking) {
    final user = widget.authState.currentUser;
    if (user == null) return;

    // Check if host already submitted a review for this booking
    final existingReviews = widget.repository.getReviewsForBooking(booking.id);
    final alreadyReviewed = existingReviews.any(
      (r) => r.reviewerId == user.id && r.reviewType == ReviewType.hostToGuest,
    );

    if (alreadyReviewed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have already submitted a review for this guest')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HostReviewScreen(
          booking: booking,
          onSubmit: (double rating, String? comment) {
            final review = Review.hostReview(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              bookingId: booking.id,
              reviewerId: user.id,
              reviewerName: user.name ?? 'Host',
              reviewerAvatarUrl: user.avatarUrl,
              guestId: booking.userId ?? '',
              rating: rating,
              comment: comment,
            );

            widget.repository.saveReview(review);

            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Thank you for your review! It will be visible once the guest also submits their review.'),
              ),
            );
          },
        ),
      ),
    );
  }

  Color _getStatusColor(BookingStatus status) {
    return switch (status) {
      BookingStatus.pending => Colors.orange,
      BookingStatus.confirmed => Colors.green,
      BookingStatus.rejected => Colors.red.shade700,
      BookingStatus.active => Colors.teal,
      BookingStatus.completed => Colors.blue,
      BookingStatus.cancelled => Colors.red,
    };
  }

  String _formatFullDate(DateTime date) {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }
}

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({
    required this.booking,
    required this.onTap,
  });

  final Booking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Guest avatar
              CircleAvatar(
                radius: 24,
                child: Text(
                  booking.tenantName.isNotEmpty
                      ? booking.tenantName[0].toUpperCase()
                      : 'G',
                ),
              ),
              const SizedBox(width: 16),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.tenantName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatDate(booking.effectiveCheckIn)} - ${_formatDate(booking.effectiveCheckOut)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      booking.listingTitle ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Price and status
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    booking.totalPriceMoney.format(showDecimal: false),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(booking.status)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      booking.status.title,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _getStatusColor(booking.status),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(BookingStatus status) {
    return switch (status) {
      BookingStatus.pending => Colors.orange,
      BookingStatus.confirmed => Colors.green,
      BookingStatus.rejected => Colors.red.shade700,
      BookingStatus.active => Colors.teal,
      BookingStatus.completed => Colors.blue,
      BookingStatus.cancelled => Colors.red,
    };
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
