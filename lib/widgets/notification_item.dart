import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/notification.dart';

/// A list item for displaying a notification with glassmorphism design
class NotificationItem extends StatelessWidget {
  const NotificationItem({
    super.key,
    required this.notification,
    this.onTap,
    this.onDismiss,
    this.onMarkAsRead,
    this.showDivider = true,
  });

  final AppNotification notification;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;
  final VoidCallback? onMarkAsRead;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
          child:
              const Icon(Icons.delete_outline, color: Colors.white, size: 28),
        ),
        child: GestureDetector(
          onTap: () {
            if (notification.isUnread) {
              onMarkAsRead?.call();
            }
            onTap?.call();
          },
          child: _GlassCard(
            isUnread: notification.isUnread,
            isDark: isDark,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Modern gradient icon
                  _ModernNotificationIcon(notification: notification),
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
                                ? theme.colorScheme.onSurface
                                    .withValues(alpha: 0.9)
                                : theme.colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Priority badge for high/urgent
                        if (notification.priority ==
                                NotificationPriority.high ||
                            notification.priority ==
                                NotificationPriority.urgent) ...[
                          const SizedBox(height: 10),
                          NotificationPriorityBadge(
                              priority: notification.priority),
                        ],
                      ],
                    ),
                  ),
                  // Unread indicator
                  if (notification.isUnread) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 10,
                      height: 10,
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
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glassmorphism card widget
class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    required this.isUnread,
    required this.isDark,
  });

  final Widget child;
  final bool isUnread;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isUnread
                  ? [
                      theme.colorScheme.primaryContainer
                          .withValues(alpha: isDark ? 0.3 : 0.5),
                      theme.colorScheme.primaryContainer
                          .withValues(alpha: isDark ? 0.15 : 0.25),
                    ]
                  : [
                      (isDark ? Colors.white : Colors.white)
                          .withValues(alpha: isDark ? 0.08 : 0.7),
                      (isDark ? Colors.white : Colors.white)
                          .withValues(alpha: isDark ? 0.04 : 0.5),
                    ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isUnread
                  ? theme.colorScheme.primary.withValues(alpha: 0.3)
                  : (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: isDark ? 0.1 : 0.08),
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
          child: child,
        ),
      ),
    );
  }
}

/// Modern notification icon with gradient background
class _ModernNotificationIcon extends StatelessWidget {
  const _ModernNotificationIcon({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final colors = _getGradientColors(notification.type);

    // If notification has an image, show it
    if (notification.imageUrl != null) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: colors[0].withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            notification.imageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildGradientIcon(colors),
          ),
        ),
      );
    }

    return _buildGradientIcon(colors);
  }

  Widget _buildGradientIcon(List<Color> colors) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: colors[0].withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        _getIcon(),
        color: Colors.white,
        size: 24,
      ),
    );
  }

  IconData _getIcon() {
    switch (notification.type) {
      case NotificationType.bookingRequest:
        return Icons.calendar_month_rounded;
      case NotificationType.bookingConfirmed:
        return Icons.check_circle_rounded;
      case NotificationType.bookingCancelled:
        return Icons.cancel_rounded;
      case NotificationType.bookingReminder:
        return Icons.alarm_rounded;
      case NotificationType.checkInReminder:
        return Icons.login_rounded;
      case NotificationType.checkOutReminder:
        return Icons.logout_rounded;
      case NotificationType.paymentReceived:
        return Icons.payments_rounded;
      case NotificationType.paymentFailed:
        return Icons.error_rounded;
      case NotificationType.refundProcessed:
        return Icons.money_off_rounded;
      case NotificationType.reviewReceived:
        return Icons.star_rounded;
      case NotificationType.reviewReminder:
        return Icons.rate_review_rounded;
      case NotificationType.promotionAvailable:
        return Icons.local_offer_rounded;
      case NotificationType.discountExpiring:
        return Icons.timer_rounded;
      case NotificationType.referralReward:
        return Icons.card_giftcard_rounded;
      case NotificationType.newMessage:
        return Icons.chat_bubble_rounded;
      case NotificationType.messageRead:
        return Icons.done_all_rounded;
      case NotificationType.systemAlert:
        return Icons.info_rounded;
      case NotificationType.accountUpdate:
        return Icons.person_rounded;
      case NotificationType.securityAlert:
        return Icons.security_rounded;
    }
  }

  List<Color> _getGradientColors(NotificationType type) {
    switch (type) {
      case NotificationType.bookingRequest:
      case NotificationType.bookingReminder:
        return [const Color(0xFF6366F1), const Color(0xFF8B5CF6)];
      case NotificationType.bookingConfirmed:
        return [const Color(0xFF10B981), const Color(0xFF34D399)];
      case NotificationType.bookingCancelled:
        return [const Color(0xFFEF4444), const Color(0xFFF87171)];
      case NotificationType.checkInReminder:
      case NotificationType.checkOutReminder:
        return [const Color(0xFFF59E0B), const Color(0xFFFBBF24)];
      case NotificationType.paymentReceived:
      case NotificationType.refundProcessed:
        return [const Color(0xFF059669), const Color(0xFF10B981)];
      case NotificationType.paymentFailed:
        return [const Color(0xFFDC2626), const Color(0xFFEF4444)];
      case NotificationType.reviewReceived:
      case NotificationType.reviewReminder:
        return [const Color(0xFFF59E0B), const Color(0xFFD97706)];
      case NotificationType.promotionAvailable:
      case NotificationType.discountExpiring:
        return [const Color(0xFF8B5CF6), const Color(0xFFA855F7)];
      case NotificationType.referralReward:
        return [const Color(0xFF14B8A6), const Color(0xFF2DD4BF)];
      case NotificationType.newMessage:
      case NotificationType.messageRead:
        return [const Color(0xFF3B82F6), const Color(0xFF60A5FA)];
      case NotificationType.systemAlert:
      case NotificationType.accountUpdate:
        return [const Color(0xFF6B7280), const Color(0xFF9CA3AF)];
      case NotificationType.securityAlert:
        return [const Color(0xFFDC2626), const Color(0xFFB91C1C)];
    }
  }
}

/// Icon for notification based on type - uses gradient style
class NotificationIcon extends StatelessWidget {
  const NotificationIcon({super.key, required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    return _ModernNotificationIcon(notification: notification);
  }
}

Color _getLegacyColor(NotificationType type, ThemeData theme) {
  switch (type) {
    case NotificationType.bookingRequest:
    case NotificationType.bookingReminder:
      return Colors.blue;
    case NotificationType.bookingConfirmed:
      return Colors.green;
    case NotificationType.bookingCancelled:
      return Colors.red;
    case NotificationType.checkInReminder:
    case NotificationType.checkOutReminder:
      return Colors.orange;
    case NotificationType.paymentReceived:
    case NotificationType.refundProcessed:
      return Colors.green;
    case NotificationType.paymentFailed:
      return Colors.red;
    case NotificationType.reviewReceived:
    case NotificationType.reviewReminder:
      return Colors.amber;
    case NotificationType.promotionAvailable:
    case NotificationType.discountExpiring:
      return Colors.purple;
    case NotificationType.referralReward:
      return Colors.teal;
    case NotificationType.newMessage:
    case NotificationType.messageRead:
      return theme.colorScheme.primary;
    case NotificationType.systemAlert:
    case NotificationType.accountUpdate:
      return Colors.grey;
    case NotificationType.securityAlert:
      return Colors.red;
  }
}

/// Badge for high priority notifications with modern glassmorphism style
class NotificationPriorityBadge extends StatelessWidget {
  const NotificationPriorityBadge({super.key, required this.priority});

  final NotificationPriority priority;

  @override
  Widget build(BuildContext context) {
    final isUrgent = priority == NotificationPriority.urgent;
    final colors = isUrgent
        ? [const Color(0xFFEF4444), const Color(0xFFF87171)]
        : [const Color(0xFFF59E0B), const Color(0xFFFBBF24)];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors[0].withValues(alpha: 0.15),
            colors[1].withValues(alpha: 0.1)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors[0].withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isUrgent
                  ? Icons.priority_high_rounded
                  : Icons.trending_up_rounded,
              size: 10,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isUrgent ? 'Urgent' : 'Important',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors[0],
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact notification item for smaller displays
class NotificationItemCompact extends StatelessWidget {
  const NotificationItemCompact({
    super.key,
    required this.notification,
    this.onTap,
  });

  final AppNotification notification;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      leading: NotificationIcon(notification: notification),
      title: Text(
        notification.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight:
              notification.isUnread ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        notification.body,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: notification.isUnread
          ? Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            )
          : Text(
              notification.relativeTime,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }
}

/// Grouped notification header with modern design
class NotificationGroupHeader extends StatelessWidget {
  const NotificationGroupHeader({
    super.key,
    required this.title,
    this.unreadCount = 0,
    this.onMarkAllAsRead,
  });

  final String title;
  final int unreadCount;
  final VoidCallback? onMarkAllAsRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
          ),
          if (unreadCount > 0) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '$unreadCount new',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (unreadCount > 0 && onMarkAllAsRead != null)
            TextButton(
              onPressed: onMarkAllAsRead,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Mark all read',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Empty state for no notifications with modern glassmorphism design
class NotificationEmptyState extends StatelessWidget {
  const NotificationEmptyState({
    super.key,
    this.title = 'No notifications',
    this.subtitle = 'You\'re all caught up!',
    this.icon = Icons.notifications_none_rounded,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Modern gradient icon container
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.15),
                    theme.colorScheme.primary.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  width: 2,
                ),
              ),
              child: Icon(
                icon,
                size: 48,
                color: theme.colorScheme.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
