import 'package:flutter/material.dart';

import '../models/notification.dart';

/// A list item for displaying a notification
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
          InkWell(
            onTap: () {
              if (notification.isUnread) {
                onMarkAsRead?.call();
              }
              onTap?.call();
            },
            child: Container(
              color: notification.isUnread
                  ? theme.colorScheme.primaryContainer.withOpacity(0.3)
                  : null,
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
                        // Priority badge for high/urgent
                        if (notification.priority == NotificationPriority.high ||
                            notification.priority == NotificationPriority.urgent) ...[
                          const SizedBox(height: 6),
                          NotificationPriorityBadge(priority: notification.priority),
                        ],
                      ],
                    ),
                  ),
                  // Unread indicator
                  if (notification.isUnread) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
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
}

/// Icon for notification based on type
class NotificationIcon extends StatelessWidget {
  const NotificationIcon({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _getColor(theme);

    // If notification has an image, show it
    if (notification.imageUrl != null) {
      return CircleAvatar(
        radius: 20,
        backgroundImage: NetworkImage(notification.imageUrl!),
        onBackgroundImageError: (_, __) {},
        child: notification.imageUrl == null
            ? Icon(_getIcon(), color: color, size: 20)
            : null,
      );
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        _getIcon(),
        color: color,
        size: 20,
      ),
    );
  }

  IconData _getIcon() {
    switch (notification.type) {
      case NotificationType.bookingRequest:
        return Icons.calendar_month;
      case NotificationType.bookingConfirmed:
        return Icons.check_circle;
      case NotificationType.bookingCancelled:
        return Icons.cancel;
      case NotificationType.bookingReminder:
        return Icons.alarm;
      case NotificationType.checkInReminder:
        return Icons.login;
      case NotificationType.checkOutReminder:
        return Icons.logout;
      case NotificationType.paymentReceived:
        return Icons.paid;
      case NotificationType.paymentFailed:
        return Icons.error;
      case NotificationType.refundProcessed:
        return Icons.money_off;
      case NotificationType.reviewReceived:
        return Icons.star;
      case NotificationType.reviewReminder:
        return Icons.rate_review;
      case NotificationType.promotionAvailable:
        return Icons.local_offer;
      case NotificationType.discountExpiring:
        return Icons.timer;
      case NotificationType.referralReward:
        return Icons.card_giftcard;
      case NotificationType.newMessage:
        return Icons.chat_bubble;
      case NotificationType.messageRead:
        return Icons.done_all;
      case NotificationType.systemAlert:
        return Icons.info;
      case NotificationType.accountUpdate:
        return Icons.person;
      case NotificationType.securityAlert:
        return Icons.security;
    }
  }

  Color _getColor(ThemeData theme) {
    switch (notification.type) {
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
}

/// Badge for high priority notifications
class NotificationPriorityBadge extends StatelessWidget {
  const NotificationPriorityBadge({required this.priority});

  final NotificationPriority priority;

  @override
  Widget build(BuildContext context) {
    final isUrgent = priority == NotificationPriority.urgent;
    final color = isUrgent ? Colors.red : Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUrgent ? Icons.priority_high : Icons.arrow_upward,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isUrgent ? 'Urgent' : 'Important',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
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
          fontWeight: notification.isUnread ? FontWeight.w600 : FontWeight.normal,
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

/// Grouped notification header
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (unreadCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (unreadCount > 0 && onMarkAllAsRead != null)
            TextButton(
              onPressed: onMarkAllAsRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
    );
  }
}

/// Empty state for no notifications
class NotificationEmptyState extends StatelessWidget {
  const NotificationEmptyState({
    super.key,
    this.title = 'No notifications',
    this.subtitle = 'You\'re all caught up!',
    this.icon = Icons.notifications_none,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
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
}
