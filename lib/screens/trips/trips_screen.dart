import 'package:flutter/material.dart';

import '../../data/mock_data.dart';
import '../../models/booking.dart';
import '../../models/booking_status.dart';
import '../../models/guest_review_ratings.dart';
import '../../models/review.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';
import '../../widgets/price_display.dart';
import '../review/guest_review_screen.dart';

class TripsScreen extends StatefulWidget {
  const TripsScreen({
    super.key,
    required this.repository,
    required this.authState,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen>
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trips'),
        centerTitle: false,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Past'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.repository, widget.authState]),
        builder: (context, _) {
          final user = widget.authState.currentUser;
          if (user == null) {
            return _buildLoginPrompt(context, theme);
          }

          // Get bookings from repository and mock data
          final repoBookings = widget.repository.getBookingsForUser(user.id);
          final mockBookings = MockData.getSampleBookings(user.id);
          final allBookings = [...repoBookings, ...mockBookings];

          final now = DateTime.now();
          final upcomingBookings = allBookings
              .where(
                  (b) => b.status.isActive && b.effectiveCheckIn.isAfter(now))
              .toList()
            ..sort((a, b) => a.effectiveCheckIn.compareTo(b.effectiveCheckIn));

          final pastBookings = allBookings
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
                isUpcoming: true,
              ),
              _buildBookingsList(
                context,
                theme,
                pastBookings,
                isUpcoming: false,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoginPrompt(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.luggage_outlined,
              size: 80,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              'Log in to see your trips',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Once you log in, your bookings will appear here.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingsList(
    BuildContext context,
    ThemeData theme,
    List<Booking> bookings, {
    required bool isUpcoming,
  }) {
    if (bookings.isEmpty) {
      return _buildEmptyState(context, theme, isUpcoming: isUpcoming);
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: bookings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        return _BookingCard(
          booking: bookings[index],
          onTap: () => _showBookingDetails(context, bookings[index]),
        );
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme, {
    required bool isUpcoming,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isUpcoming ? Icons.calendar_today : Icons.history,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              isUpcoming ? 'No upcoming trips' : 'No past trips',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isUpcoming
                  ? 'Time to dust off your bags and start planning your next adventure.'
                  : 'Once you complete a trip, it will appear here.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (isUpcoming) ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  // Navigate to explore
                },
                child: const Text('Start searching'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showBookingDetails(BuildContext context, Booking booking) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BookingDetailsSheet(
        booking: booking,
        repository: widget.repository,
        authState: widget.authState,
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            AspectRatio(
              aspectRatio: 2.5,
              child: booking.listingImageUrl != null
                  ? Image.network(
                      booking.listingImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildPlaceholder(theme),
                    )
                  : _buildPlaceholder(theme),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status chip
                  Chip(
                    label: Text(
                      booking.status.title,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _getStatusColor(booking.status),
                      ),
                    ),
                    backgroundColor:
                        _getStatusColor(booking.status).withValues(alpha: 0.1),
                    side: BorderSide.none,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(height: 8),
                  // Title
                  Text(
                    booking.listingTitle ?? 'Booking',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Location
                  if (booking.listingCity != null)
                    Text(
                      booking.listingCity!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 8),
                  // Dates
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_formatDate(booking.effectiveCheckIn)} - ${_formatDate(booking.effectiveCheckOut)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.home_outlined,
          size: 48,
          color: theme.colorScheme.onSurfaceVariant,
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

class _BookingDetailsSheet extends StatelessWidget {
  const _BookingDetailsSheet({
    required this.booking,
    required this.repository,
    required this.authState,
  });

  final Booking booking;
  final MusafirRepository repository;
  final AuthStateNotifier authState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
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

            // Title
            Text(
              booking.listingTitle ?? 'Booking Details',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (booking.listingCity != null)
              Text(
                booking.listingCity!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const Divider(height: 32),

            // Details
            _DetailRow(
              icon: Icons.calendar_today,
              label: 'Check-in',
              value: _formatFullDate(booking.effectiveCheckIn),
            ),
            const SizedBox(height: 16),
            _DetailRow(
              icon: Icons.calendar_today,
              label: 'Check-out',
              value: _formatFullDate(booking.effectiveCheckOut),
            ),
            const SizedBox(height: 16),
            _DetailRow(
              icon: Icons.people,
              label: 'Guests',
              value:
                  '${booking.guestCount} guest${booking.guestCount > 1 ? 's' : ''}',
            ),
            const SizedBox(height: 16),
            _DetailRow(
              icon: Icons.attach_money,
              label: 'Total',
              value: booking.totalPriceMoney.format(showDecimal: false),
            ),
            const SizedBox(height: 16),
            _DetailRow(
              icon: Icons.info_outline,
              label: 'Status',
              value: booking.status.title,
            ),
            const SizedBox(height: 32),

            // Status-specific info
            if (booking.status == BookingStatus.active) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.teal),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'You are checked in. Enjoy your stay!',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.teal.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (booking.status == BookingStatus.rejected) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cancel, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        booking.rejectionReason ?? 'Host declined this booking.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (booking.hostMessage != null &&
                booking.status == BookingStatus.confirmed) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Message from host:',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      booking.hostMessage!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Actions - only allow cancel for pending/confirmed (not active)
            if (booking.status == BookingStatus.pending ||
                booking.status == BookingStatus.confirmed) ...[
              OutlinedButton(
                onPressed: () {
                  _showCancelDialog(context, booking);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Cancel Booking'),
              ),
            ],

            // Completed booking - prompt for review
            if (booking.status == BookingStatus.completed) ...[
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _navigateToReview(context);
                },
                icon: const Icon(Icons.rate_review),
                label: const Text('Leave a Review'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  void _navigateToReview(BuildContext context) {
    final user = authState.currentUser;
    if (user == null) return;

    // Check if user already submitted a review for this booking
    final existingReviews = repository.getReviewsForBooking(booking.id);
    final alreadyReviewed = existingReviews.any(
      (r) => r.reviewerId == user.id && r.reviewType == ReviewType.guestToHost,
    );

    if (alreadyReviewed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have already submitted a review for this booking')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GuestReviewScreen(
          booking: booking,
          onSubmit: (GuestReviewRatings ratings, String comment) {
            // Get host info from listing
            final listing = repository.listings.firstWhere(
              (l) => l.id == booking.listingId,
              orElse: () => repository.listings.first,
            );

            final review = Review.guestReview(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              bookingId: booking.id,
              listingId: booking.listingId,
              reviewerId: user.id,
              reviewerName: user.name ?? 'Guest',
              reviewerAvatarUrl: user.avatarUrl,
              hostId: listing.hostId ?? '',
              ratings: ratings,
              comment: comment,
            );

            repository.saveReview(review);

            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Thank you for your review! It will be visible once the host also submits their review.'),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showCancelDialog(BuildContext context, Booking booking) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: const Text(
          'Are you sure you want to cancel this booking? The host will be notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep Booking'),
          ),
          FilledButton(
            onPressed: () {
              final updated = booking.copyWith(
                status: BookingStatus.cancelled,
                cancelledAt: DateTime.now(),
              );
              repository.updateBooking(updated);
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

  String _formatFullDate(DateTime date) {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
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
