import 'package:flutter/material.dart';

import '../../models/booking.dart';
import '../../models/booking_status.dart';
import '../../models/listing.dart';
import '../../models/review.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';
import '../../state/messaging_state.dart';
import '../../widgets/price_display.dart';
import '../messaging/chat_screen.dart';
import '../review/host_review_screen.dart';

class HostReservationsScreen extends StatefulWidget {
  const HostReservationsScreen({
    super.key,
    required this.repository,
    required this.authState,
    this.messagingState,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final MessagingStateNotifier? messagingState;

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

  /// Show a modern success banner at the top
  void _showSuccessBanner(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leadingPadding: EdgeInsets.zero,
        actions: [
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(seconds: 3), () {
      messenger.hideCurrentMaterialBanner();
    });
  }

  /// Show a modern info/warning banner at the top
  void _showInfoBanner(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade700,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leadingPadding: EdgeInsets.zero,
        actions: [
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(seconds: 4), () {
      messenger.hideCurrentMaterialBanner();
    });
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
            Tab(text: 'Active Stays'),
            Tab(text: 'Completed'),
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

              // Booking type badge
              _BookingTypeBadge(unitLabel: booking.unitLabel),
              const SizedBox(height: 16),

              // Booking details
              _DetailRow(
                icon: Icons.home,
                label: 'Property',
                value: booking.listingTitle ?? 'N/A',
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.login,
                label: 'Check-in',
                value: _formatDateTimeForBooking(booking.effectiveCheckIn, booking.unitLabel),
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.logout,
                label: 'Check-out',
                value: _formatDateTimeForBooking(booking.effectiveCheckOut, booking.unitLabel),
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: _getDurationIcon(booking.unitLabel),
                label: _getDurationLabel(booking.unitLabel),
                value: _getDurationValue(booking),
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
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _openChatForBooking(booking);
                    },
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Message Guest'),
                  ),
                ),
              ],
            ),
          ],
        ),
      // Active: Service Complete + Message Guest
      BookingStatus.active => Column(
          children: [
            SizedBox(
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
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _openChatForBooking(booking);
                },
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Message Guest'),
              ),
            ),
          ],
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
              _showSuccessBanner('Booking accepted!');
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
              _showSuccessBanner('Booking declined');
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
              _showSuccessBanner('Guest checked in!');
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
              _showSuccessBanner('Service completed! Don\'t forget to leave a review.');
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
              _showSuccessBanner('Booking cancelled');
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
      _showInfoBanner('You have already submitted a review for this guest');
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
            _showSuccessBanner('Thank you for your review!');
          },
        ),
      ),
    );
  }

  Future<void> _openChatForBooking(Booking booking) async {
    if (widget.messagingState == null) {
      _showInfoBanner('Messaging is not available');
      return;
    }

    // Find the conversation for this booking
    final conversations = widget.messagingState!.conversations;
    var conversation = conversations.where((c) => c.bookingId == booking.id).firstOrNull;

    // If no conversation exists, create one
    if (conversation == null) {
      final guestId = booking.userId;
      if (guestId == null) {
        _showInfoBanner('Cannot message: guest information not available');
        return;
      }

      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Starting conversation...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // Create the conversation
      conversation = await widget.messagingState!.startConversation(
        otherUserId: guestId,
        bookingId: booking.id,
        listingId: booking.listingId,
      );

      if (conversation == null) {
        if (mounted) {
          _showInfoBanner('Failed to start conversation. Please try again.');
        }
        return;
      }
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            conversationId: conversation!.id,
            messagingState: widget.messagingState!,
            otherParticipantName: booking.tenantName,
            otherParticipantAvatarUrl: null,
          ),
        ),
      );
    }
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

  String _formatDateTimeForBooking(DateTime date, String unitLabel) {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final dateStr = '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';

    // For hourly bookings, always show time
    // For daily bookings, show time if it's not midnight
    // For monthly bookings, just show date
    if (unitLabel == 'hour') {
      return '$dateStr at ${_formatTime(date)}';
    } else if (unitLabel == 'night') {
      // Show time if not default check-in/out times
      if (date.hour != 0 || date.minute != 0) {
        return '$dateStr at ${_formatTime(date)}';
      }
      return dateStr;
    }
    return dateStr;
  }

  String _formatTime(DateTime date) {
    final hour = date.hour;
    final minute = date.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    if (minute == 0) {
      return '$displayHour $period';
    }
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  IconData _getDurationIcon(String unitLabel) {
    return switch (unitLabel) {
      'hour' => Icons.schedule,
      'month' => Icons.calendar_month,
      _ => Icons.nights_stay,
    };
  }

  String _getDurationLabel(String unitLabel) {
    return switch (unitLabel) {
      'hour' => 'Duration',
      'month' => 'Months',
      _ => 'Nights',
    };
  }

  String _getDurationValue(Booking booking) {
    final duration = booking.effectiveCheckOut.difference(booking.effectiveCheckIn);

    return switch (booking.unitLabel) {
      'hour' => '${duration.inHours} hour${duration.inHours != 1 ? 's' : ''}',
      'month' => '${(duration.inDays / 30).round()} month${(duration.inDays / 30).round() != 1 ? 's' : ''}',
      _ => '${duration.inDays} night${duration.inDays != 1 ? 's' : ''}',
    };
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            booking.tenantName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _BookingTypeChip(unitLabel: booking.unitLabel),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDateRange(),
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

              const SizedBox(width: 12),

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

  String _formatDateRange() {
    final checkIn = booking.effectiveCheckIn;
    final checkOut = booking.effectiveCheckOut;

    if (booking.unitLabel == 'hour') {
      // For hourly: "May 31, 2:00 PM - 5:00 PM"
      if (checkIn.year == checkOut.year &&
          checkIn.month == checkOut.month &&
          checkIn.day == checkOut.day) {
        return '${_formatDate(checkIn)}, ${_formatTime(checkIn)} - ${_formatTime(checkOut)}';
      }
      return '${_formatDate(checkIn)} ${_formatTime(checkIn)} - ${_formatDate(checkOut)} ${_formatTime(checkOut)}';
    }

    // For daily/monthly: "May 31 - Jun 2"
    return '${_formatDate(checkIn)} - ${_formatDate(checkOut)}';
  }

  String _formatTime(DateTime date) {
    final hour = date.hour;
    final minute = date.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    if (minute == 0) {
      return '$displayHour $period';
    }
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
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

class _BookingTypeChip extends StatelessWidget {
  const _BookingTypeChip({required this.unitLabel});

  final String unitLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (label, color) = switch (unitLabel) {
      'hour' => ('Hourly', Colors.purple),
      'month' => ('Monthly', Colors.indigo),
      _ => ('Daily', Colors.teal),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
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

class _BookingTypeBadge extends StatelessWidget {
  const _BookingTypeBadge({required this.unitLabel});

  final String unitLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (label, icon, color) = switch (unitLabel) {
      'hour' => ('Hourly Booking', Icons.schedule, Colors.purple),
      'month' => ('Monthly Booking', Icons.calendar_month, Colors.indigo),
      _ => ('Daily Booking', Icons.nights_stay, Colors.teal),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
