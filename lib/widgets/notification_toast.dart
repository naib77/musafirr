import 'dart:async';

import 'package:flutter/material.dart';

import '../models/notification.dart';

/// An in-app toast notification that appears at the top of the screen
class NotificationToast extends StatefulWidget {
  const NotificationToast({
    super.key,
    required this.notification,
    this.onTap,
    this.onDismiss,
    this.duration = const Duration(seconds: 4),
    this.showCloseButton = true,
  });

  /// The notification to display
  final AppNotification notification;

  /// Callback when toast is tapped
  final VoidCallback? onTap;

  /// Callback when toast is dismissed
  final VoidCallback? onDismiss;

  /// How long to show the toast
  final Duration duration;

  /// Whether to show the close button
  final bool showCloseButton;

  @override
  State<NotificationToast> createState() => _NotificationToastState();
}

class _NotificationToastState extends State<NotificationToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();

    // Auto-dismiss after duration
    _dismissTimer = Timer(widget.duration, _dismiss);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    _controller.reverse().then((_) {
      widget.onDismiss?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surface,
              child: InkWell(
                onTap: () {
                  _dismiss();
                  widget.onTap?.call();
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getBorderColor(theme),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Icon
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _getIconBackgroundColor(theme),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _getIcon(),
                          color: _getIconColor(theme),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Content
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.notification.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.notification.body,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // Close button
                      if (widget.showCloseButton) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _dismiss,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getIcon() {
    switch (widget.notification.type) {
      case NotificationType.bookingRequest:
      case NotificationType.bookingConfirmed:
      case NotificationType.bookingCancelled:
      case NotificationType.bookingReminder:
        return Icons.calendar_today;
      case NotificationType.checkInReminder:
        return Icons.login;
      case NotificationType.checkOutReminder:
        return Icons.logout;
      case NotificationType.paymentReceived:
        return Icons.payment;
      case NotificationType.paymentFailed:
        return Icons.error_outline;
      case NotificationType.refundProcessed:
        return Icons.money_off;
      case NotificationType.reviewReceived:
      case NotificationType.reviewReminder:
        return Icons.star;
      case NotificationType.promotionAvailable:
      case NotificationType.discountExpiring:
        return Icons.local_offer;
      case NotificationType.referralReward:
        return Icons.card_giftcard;
      case NotificationType.newMessage:
      case NotificationType.messageRead:
        return Icons.message;
      case NotificationType.systemAlert:
        return Icons.info;
      case NotificationType.accountUpdate:
        return Icons.person;
      case NotificationType.securityAlert:
        return Icons.security;
    }
  }

  Color _getIconColor(ThemeData theme) {
    switch (widget.notification.type.category) {
      case 'booking':
        return Colors.blue;
      case 'payment':
        return widget.notification.type == NotificationType.paymentFailed
            ? Colors.red
            : Colors.green;
      case 'review':
        return Colors.amber;
      case 'promotion':
        return Colors.purple;
      case 'message':
        return theme.colorScheme.primary;
      case 'system':
        return widget.notification.type == NotificationType.securityAlert
            ? Colors.red
            : Colors.grey;
      default:
        return theme.colorScheme.primary;
    }
  }

  Color _getIconBackgroundColor(ThemeData theme) {
    return _getIconColor(theme).withValues(alpha: 0.1);
  }

  Color _getBorderColor(ThemeData theme) {
    if (widget.notification.priority == NotificationPriority.urgent) {
      return Colors.red.withValues(alpha: 0.5);
    }
    if (widget.notification.priority == NotificationPriority.high) {
      return theme.colorScheme.primary.withValues(alpha: 0.3);
    }
    return theme.colorScheme.outlineVariant;
  }
}

/// Overlay entry for showing notification toasts
class NotificationToastOverlay {
  NotificationToastOverlay._();

  static OverlayEntry? _currentEntry;

  /// Show a notification toast
  static void show(
    BuildContext context, {
    required AppNotification notification,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 4),
  }) {
    // Dismiss any existing toast
    dismiss();

    _currentEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: NotificationToast(
          notification: notification,
          onTap: () {
            dismiss();
            onTap?.call();
          },
          onDismiss: dismiss,
          duration: duration,
        ),
      ),
    );

    Overlay.of(context).insert(_currentEntry!);
  }

  /// Dismiss the current toast
  static void dismiss() {
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

/// A simpler banner-style notification
class NotificationBanner extends StatelessWidget {
  const NotificationBanner({
    super.key,
    required this.notification,
    this.onTap,
    this.onDismiss,
  });

  final AppNotification notification;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: _getBackgroundColor(theme),
      child: InkWell(
        onTap: onTap,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  _getIcon(),
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        notification.body,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: onDismiss,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getIcon() {
    switch (notification.type.category) {
      case 'booking':
        return Icons.calendar_today;
      case 'payment':
        return Icons.payment;
      case 'review':
        return Icons.star;
      case 'promotion':
        return Icons.local_offer;
      case 'message':
        return Icons.message;
      case 'system':
        return Icons.info;
      default:
        return Icons.notifications;
    }
  }

  Color _getBackgroundColor(ThemeData theme) {
    switch (notification.priority) {
      case NotificationPriority.urgent:
        return Colors.red;
      case NotificationPriority.high:
        return theme.colorScheme.primary;
      case NotificationPriority.normal:
        return theme.colorScheme.secondary;
      case NotificationPriority.low:
        return Colors.grey.shade600;
    }
  }
}
