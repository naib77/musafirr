import 'dart:ui';

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
    final isDark = theme.brightness == Brightness.dark;

    // Show success badge if present
    if (successLabel != null) {
      return _buildSuccessBadge(theme, isDark);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Dismissible(
        key: Key(notification.id),
        direction: onDismiss != null
            ? DismissDirection.endToStart
            : DismissDirection.none,
        onDismissed: (_) => onDismiss?.call(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: Colors.red.shade400,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: notification.isUnread
                      ? [
                          theme.colorScheme.primaryContainer.withValues(alpha: isDark ? 0.3 : 0.5),
                          theme.colorScheme.primaryContainer.withValues(alpha: isDark ? 0.15 : 0.25),
                        ]
                      : [
                          (isDark ? Colors.white : Colors.white).withValues(alpha: isDark ? 0.08 : 0.7),
                          (isDark ? Colors.white : Colors.white).withValues(alpha: isDark ? 0.04 : 0.5),
                        ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: notification.isUnread
                      ? theme.colorScheme.primary.withValues(alpha: 0.3)
                      : (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.1 : 0.08),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header row
                  _buildHeader(context, theme, isDark),
                  // Expanded content
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 200),
                    crossFadeState: isExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox.shrink(),
                    secondChild: _buildExpandedContent(context, theme, isDark),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessBadge(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF10B981).withValues(alpha: 0.15),
              const Color(0xFF34D399).withValues(alpha: 0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF34D399)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                successLabel!,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF059669),
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme, bool isDark) {
    return InkWell(
      onTap: () {
        if (notification.isUnread) {
          onMarkAsRead?.call();
        }
        onTap?.call();
      },
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Modern gradient icon
            NotificationIcon(notification: notification),
            const SizedBox(width: 14),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row with time
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: notification.isUnread
                                ? FontWeight.w700
                                : FontWeight.w500,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Time badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          notification.relativeTime,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Body
                  Text(
                    notification.body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: notification.isUnread
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.9)
                          : theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Priority badge
                  if (notification.priority == NotificationPriority.high ||
                      notification.priority == NotificationPriority.urgent) ...[
                    const SizedBox(height: 10),
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
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: AnimatedRotation(
                      duration: const Duration(milliseconds: 200),
                      turns: isExpanded ? 0.5 : 0,
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                // Unread indicator
                if (notification.isUnread)
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.primary.withValues(alpha: 0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(alpha: 0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedContent(BuildContext context, ThemeData theme, bool isDark) {
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Guest info
          _buildGuestInfo(
            theme,
            isDark,
            guestName: guestName,
            avatarUrl: guestAvatarUrl,
            rating: guestRating,
            reviewCount: guestReviewCount,
          ),
          const SizedBox(height: 12),
          // Booking details
          _buildBookingDetails(
            theme,
            isDark,
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
    ThemeData theme,
    bool isDark, {
    required String guestName,
    String? avatarUrl,
    double? rating,
    int? reviewCount,
  }) {
    return Row(
      children: [
        // Avatar with gradient border
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.primary.withValues(alpha: 0.6),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          child: CircleAvatar(
            radius: 22,
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
            child: avatarUrl == null
                ? Text(
                    guestName.isNotEmpty ? guestName[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(width: 14),
        // Name and rating
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                guestName,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              if (rating != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, size: 12, color: Colors.white),
                          const SizedBox(width: 2),
                          Text(
                            rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (reviewCount != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '$reviewCount reviews',
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
    ThemeData theme,
    bool isDark, {
    required String listingTitle,
    DateTime? checkIn,
    DateTime? checkOut,
    required int guestCount,
    num? totalAmount,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
        ),
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
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
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

    // Check if we need vertical layout based on screen width
    // 3 buttons need ~300px minimum to display properly horizontally
    final screenWidth = MediaQuery.of(context).size.width;
    final useVerticalLayout = screenWidth < 400;

    if (useVerticalLayout) {
      // Vertical layout for narrow screens - full width buttons
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Primary actions row (Accept + Decline)
          if (!isStale)
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onAccept,
                    child: const Text('Accept'),
                  ),
                ),
                const SizedBox(width: 8),
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
              ],
            ),
          if (!isStale) const SizedBox(height: 8),
          // View Details - full width
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onViewDetails,
              icon: const Icon(Icons.info_outline, size: 18),
              label: const Text('View Details'),
            ),
          ),
        ],
      );
    }

    // Horizontal layout for wider screens
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
