import 'package:flutter/material.dart';

import '../models/booking_status.dart';
import '../models/notification.dart';

/// Bottom sheet that displays full booking details from a notification.
///
/// Shows guest info, booking details, and Accept/Decline buttons.
class BookingDetailsSheet extends StatelessWidget {
  const BookingDetailsSheet({
    super.key,
    required this.notification,
    required this.onAccept,
    required this.onDecline,
    this.bookingStatus,
    this.isProcessing = false,
  });

  final AppNotification notification;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final BookingStatus? bookingStatus;
  final bool isProcessing;

  static Future<void> show(
    BuildContext context, {
    required AppNotification notification,
    required VoidCallback onAccept,
    required VoidCallback onDecline,
    BookingStatus? bookingStatus,
    bool isProcessing = false,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BookingDetailsSheet(
        notification: notification,
        onAccept: onAccept,
        onDecline: onDecline,
        bookingStatus: bookingStatus,
        isProcessing: isProcessing,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = notification.data ?? {};
    final guestName = data['guest_name'] as String? ?? 'Guest';
    final guestAvatarUrl = data['guest_avatar_url'] as String?;
    final guestRating = (data['guest_rating'] as num?)?.toDouble();
    final guestReviewCount = data['guest_review_count'] as int?;
    final guestCount = data['guest_count'] as int? ?? 1;
    final listingTitle = data['listing_title'] as String? ?? '';
    final totalAmount = data['total_amount'] as num?;
    final checkInStr = data['check_in'] as String?;
    final checkOutStr = data['check_out'] as String?;

    DateTime? checkIn;
    DateTime? checkOut;
    if (checkInStr != null) {
      checkIn = DateTime.tryParse(checkInStr);
    }
    if (checkOutStr != null) {
      checkOut = DateTime.tryParse(checkOutStr);
    }

    int? numberOfNights;
    if (checkIn != null && checkOut != null) {
      numberOfNights = checkOut.difference(checkIn).inDays;
    }

    final isStale =
        bookingStatus != null && bookingStatus != BookingStatus.pending;
    // Accept/Decline require a PROVEN pending status; unknown (null) means
    // the lookup missed and the request may already be handled elsewhere.
    final canAct = bookingStatus == BookingStatus.pending;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Booking Request',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Guest info section
                      _buildSectionHeader(theme, 'Guest'),
                      const SizedBox(height: 12),
                      _buildGuestCard(
                        theme,
                        guestName: guestName,
                        avatarUrl: guestAvatarUrl,
                        rating: guestRating,
                        reviewCount: guestReviewCount,
                      ),
                      const SizedBox(height: 24),
                      // Booking details section
                      _buildSectionHeader(theme, 'Booking Details'),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        theme,
                        icon: Icons.home,
                        label: 'Property',
                        value: listingTitle,
                      ),
                      if (checkIn != null && checkOut != null) ...[
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          theme,
                          icon: Icons.calendar_today,
                          label: 'Check-in',
                          value: _formatFullDate(checkIn),
                        ),
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          theme,
                          icon: Icons.calendar_today,
                          label: 'Check-out',
                          value: _formatFullDate(checkOut),
                        ),
                      ],
                      if (numberOfNights != null) ...[
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          theme,
                          icon: Icons.nightlight_round,
                          label: 'Duration',
                          value:
                              '$numberOfNights ${numberOfNights == 1 ? 'night' : 'nights'}',
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        theme,
                        icon: Icons.group,
                        label: 'Guests',
                        value: '$guestCount ${guestCount == 1 ? 'guest' : 'guests'}',
                      ),
                      if (totalAmount != null) ...[
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          theme,
                          icon: Icons.payments,
                          label: 'Total',
                          value: '৳${totalAmount.toStringAsFixed(0)}',
                          valueStyle: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                            fontSize: 16,
                          ),
                        ),
                      ],
                      // Stale warning
                      if (isStale) ...[
                        const SizedBox(height: 24),
                        _buildStaleWarning(theme),
                      ],
                      // Bottom padding for action buttons
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
              // Action buttons (fixed at bottom)
              _buildActionBar(context, theme, canAct: canAct),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildGuestCard(
    ThemeData theme, {
    required String guestName,
    String? avatarUrl,
    double? rating,
    int? reviewCount,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 30,
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(
                    guestName.isNotEmpty ? guestName[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  guestName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (rating != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 16, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(
                        rating.toStringAsFixed(1),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (reviewCount != null) ...[
                        Text(
                          ' ($reviewCount reviews)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ] else
                  Text(
                    'New guest',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
    TextStyle? valueStyle,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: valueStyle ??
              theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }

  Widget _buildStaleWarning(ThemeData theme) {
    final statusText = bookingStatus?.title ?? 'Changed';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.orange, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Booking Status Changed',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This booking is no longer pending. Current status: $statusText',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(
    BuildContext context,
    ThemeData theme, {
    required bool canAct,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: isProcessing
            ? const Center(child: CircularProgressIndicator())
            : !canAct
                ? FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            onDecline();
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Decline'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.pop(context);
                            onAccept();
                          },
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Accept'),
                        ),
                      ),
                    ],
                  ),
      ),
    );
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
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
