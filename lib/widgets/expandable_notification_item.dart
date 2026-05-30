import 'package:flutter/material.dart';

import '../models/booking_status.dart';
import '../models/notification.dart';
import 'notification_item.dart';

/// An expandable notification item for booking requests.
///
/// Shows a chevron icon that toggles expansion. When expanded,
/// displays guest info, booking details, and action buttons.
class ExpandableNotificationItem extends StatelessWidget {
  const ExpandableNotificationItem({
    super.key,
    required this.notification,
    required this.isExpanded,
    required this.onExpand,
    required this.onCollapse,
    this.onTap,
    this.onDismiss,
    this.onMarkAsRead,
    required this.onAccept,
    required this.onDecline,
    required this.onViewDetails,
    this.bookingStatus,
    this.isProcessing = false,
    this.successLabel,
    this.showDivider = true,
  });

  final AppNotification notification;
  final bool isExpanded;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;
  final VoidCallback? onMarkAsRead;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onViewDetails;
  final BookingStatus? bookingStatus;
  final bool isProcessing;
  final String? successLabel;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Show success badge if present
    if (successLabel != null) {
      return _buildSuccessBadge(theme);
    }

    return Dismissible(
      key: Key(notification.id),
      direction: onDismiss != null
          ? DismissDirection.endToStart
          : DismissDirection.none,
      onDismissed: (_) => onDismiss?.call(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Column(
        children: [
          Container(
            color: notification.isUnread
                ? theme.colorScheme.primaryContainer.withOpacity(0.3)
                : null,
            child: Column(
              children: [
                // Header row
                _buildHeader(context, theme),
                // Expanded content
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox.shrink(),
                  secondChild: _buildExpandedContent(context, theme),
                ),
              ],
            ),
          ),
          if (showDivider)
            Divider(
              height: 1,
              indent: 68,
              color: theme.colorScheme.outlineVariant,
            ),
        ],
      ),
    );
  }

  Widget _buildSuccessBadge(ThemeData theme) {
    return Container(
      color: Colors.green.withOpacity(0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              successLabel!,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return InkWell(
      onTap: () {
        if (notification.isUnread) {
          onMarkAsRead?.call();
        }
        onTap?.call();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            NotificationIcon(notification: notification),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row with time
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: notification.isUnread
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        notification.relativeTime,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Body
                  Text(
                    notification.body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: notification.isUnread
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Priority badge
                  if (notification.priority == NotificationPriority.high ||
                      notification.priority == NotificationPriority.urgent) ...[
                    const SizedBox(height: 6),
                    NotificationPriorityBadge(priority: notification.priority),
                  ],
                ],
              ),
            ),
            // Chevron and unread indicator
            const SizedBox(width: 8),
            Column(
              children: [
                // Chevron button
                GestureDetector(
                  onTap: () {
                    if (isExpanded) {
                      onCollapse();
                    } else {
                      onExpand();
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: AnimatedRotation(
                      duration: const Duration(milliseconds: 200),
                      turns: isExpanded ? 0.5 : 0,
                      child: Icon(
                        Icons.expand_more,
                        size: 24,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                // Unread indicator
                if (notification.isUnread)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedContent(BuildContext context, ThemeData theme) {
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

    final isStale =
        bookingStatus != null && bookingStatus != BookingStatus.pending;

    return Padding(
      padding: const EdgeInsets.fromLTRB(68, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Guest info
          _buildGuestInfo(
            theme,
            guestName: guestName,
            avatarUrl: guestAvatarUrl,
            rating: guestRating,
            reviewCount: guestReviewCount,
          ),
          const SizedBox(height: 12),
          // Booking details
          _buildBookingDetails(
            theme,
            listingTitle: listingTitle,
            checkIn: checkIn,
            checkOut: checkOut,
            guestCount: guestCount,
            totalAmount: totalAmount,
          ),
          // Stale warning
          if (isStale) ...[
            const SizedBox(height: 12),
            _buildStaleWarning(theme),
          ],
          const SizedBox(height: 12),
          // Action buttons
          _buildActionButtons(context, theme, isStale: isStale),
        ],
      ),
    );
  }

  Widget _buildGuestInfo(
    ThemeData theme, {
    required String guestName,
    String? avatarUrl,
    double? rating,
    int? reviewCount,
  }) {
    return Row(
      children: [
        // Avatar
        CircleAvatar(
          radius: 20,
          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
          child: avatarUrl == null
              ? Text(
                  guestName.isNotEmpty ? guestName[0].toUpperCase() : '?',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )
              : null,
        ),
        const SizedBox(width: 12),
        // Name and rating
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                guestName,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (rating != null) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.star, size: 14, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      rating.toStringAsFixed(1),
                      style: theme.textTheme.bodySmall,
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
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBookingDetails(
    ThemeData theme, {
    required String listingTitle,
    DateTime? checkIn,
    DateTime? checkOut,
    required int guestCount,
    num? totalAmount,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Listing title
          Text(
            listingTitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          // Dates
          if (checkIn != null && checkOut != null) ...[
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 14),
                const SizedBox(width: 8),
                Text(
                  '${_formatDate(checkIn)} - ${_formatDate(checkOut)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          // Guests
          Row(
            children: [
              const Icon(Icons.person, size: 14),
              const SizedBox(width: 8),
              Text(
                '$guestCount ${guestCount == 1 ? 'guest' : 'guests'}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          // Amount
          if (totalAmount != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.payments, size: 14),
                const SizedBox(width: 8),
                Text(
                  '৳${totalAmount.toStringAsFixed(0)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStaleWarning(ThemeData theme) {
    final statusText = bookingStatus?.title ?? 'Changed';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This booking is no longer pending. Status: $statusText',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.orange.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    ThemeData theme, {
    required bool isStale,
  }) {
    if (isProcessing) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Row(
      children: [
        // View Details
        Expanded(
          child: OutlinedButton(
            onPressed: onViewDetails,
            child: const Text('View Details'),
          ),
        ),
        const SizedBox(width: 8),
        // Decline
        if (!isStale)
          Expanded(
            child: OutlinedButton(
              onPressed: onDecline,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
              child: const Text('Decline'),
            ),
          ),
        if (!isStale) const SizedBox(width: 8),
        // Accept
        if (!isStale)
          Expanded(
            child: FilledButton(
              onPressed: onAccept,
              child: const Text('Accept'),
            ),
          ),
      ],
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
