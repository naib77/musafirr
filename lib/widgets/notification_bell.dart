import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../state/notification_state.dart';

/// A notification bell icon with an unread count badge
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    required this.notificationState,
    required this.onTap,
    this.iconSize = 24.0,
    this.badgeColor,
    this.iconColor,
    this.showBadgeWhenZero = false,
    this.maxCount = 99,
  });

  /// Notification state to listen to
  final NotificationStateNotifier notificationState;

  /// Callback when bell is tapped
  final VoidCallback onTap;

  /// Size of the bell icon
  final double iconSize;

  /// Color of the badge (defaults to red)
  final Color? badgeColor;

  /// Color of the icon
  final Color? iconColor;

  /// Whether to show badge when count is 0
  final bool showBadgeWhenZero;

  /// Maximum count to display (shows "99+" if exceeded)
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: notificationState,
      builder: (context, _) {
        final unreadCount = notificationState.unreadCount;

        return IconButton(
          onPressed: onTap,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                unreadCount > 0 ? Icons.notifications : Icons.notifications_outlined,
                size: iconSize,
                color: iconColor ?? theme.colorScheme.onSurface,
              ),
              if (unreadCount > 0 || showBadgeWhenZero)
                Positioned(
                  right: -4,
                  top: -4,
                  child: _Badge(
                    count: unreadCount,
                    maxCount: maxCount,
                    color: badgeColor ?? Colors.red,
                  ),
                ),
            ],
          ),
          tooltip: unreadCount > 0
              ? '$unreadCount unread notification${unreadCount > 1 ? 's' : ''}'
              : 'Notifications',
        );
      },
    );
  }
}

/// Badge showing the notification count
class _Badge extends StatelessWidget {
  const _Badge({
    required this.count,
    required this.maxCount,
    required this.color,
  });

  final int count;
  final int maxCount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      // Show a small dot when count is 0 but badge is visible
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      );
    }

    final displayText = count > maxCount ? '$maxCount+' : '$count';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        displayText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Animated notification bell that shakes when new notifications arrive
class AnimatedNotificationBell extends StatefulWidget {
  const AnimatedNotificationBell({
    super.key,
    required this.notificationState,
    required this.onTap,
    this.iconSize = 24.0,
    this.badgeColor,
    this.iconColor,
    this.decorated = false,
  });

  final NotificationStateNotifier notificationState;
  final VoidCallback onTap;
  final double iconSize;
  final Color? badgeColor;
  final Color? iconColor;

  /// When true, renders inside a soft circular chip so it matches
  /// [HeaderActionButton] in [AppPageHeader]. Default (false) keeps the bare
  /// [IconButton] used elsewhere (e.g. the Explore search row).
  final bool decorated;

  @override
  State<AnimatedNotificationBell> createState() => _AnimatedNotificationBellState();
}

class _AnimatedNotificationBellState extends State<AnimatedNotificationBell>
    with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  int _previousCount = 0;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut),
    );

    _previousCount = widget.notificationState.unreadCount;
    widget.notificationState.addListener(_onNotificationChange);
  }

  @override
  void dispose() {
    widget.notificationState.removeListener(_onNotificationChange);
    _shakeController.dispose();
    super.dispose();
  }

  void _onNotificationChange() {
    final newCount = widget.notificationState.unreadCount;
    if (newCount > _previousCount) {
      // New notification arrived, shake the bell
      _shakeController.forward(from: 0);
    }
    _previousCount = newCount;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: widget.notificationState,
      builder: (context, _) {
        final unreadCount = widget.notificationState.unreadCount;
        final tooltip = unreadCount > 0
            ? '$unreadCount unread notification${unreadCount > 1 ? 's' : ''}'
            : 'Notifications';

        final iconStack = AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) {
            return Transform.rotate(
              angle: _shakeAnimation.value * 0.1 *
                  ((_shakeAnimation.value * 10).toInt().isEven ? 1 : -1),
              child: child,
            );
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                unreadCount > 0 ? Icons.notifications : Icons.notifications_outlined,
                size: widget.iconSize,
                color: widget.iconColor ??
                    (widget.decorated
                        ? AppColors.ink
                        : theme.colorScheme.onSurface),
              ),
              if (unreadCount > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: _Badge(
                    count: unreadCount,
                    maxCount: 99,
                    color: widget.badgeColor ?? Colors.red,
                  ),
                ),
            ],
          ),
        );

        if (widget.decorated) {
          // Soft circular chip matching HeaderActionButton.
          return Tooltip(
            message: tooltip,
            child: Material(
              color: AppColors.surfaceMuted,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: iconStack,
                ),
              ),
            ),
          );
        }

        return IconButton(
          onPressed: widget.onTap,
          icon: iconStack,
          tooltip: tooltip,
        );
      },
    );
  }
}

/// Compact notification indicator for navigation bars
class NotificationIndicator extends StatelessWidget {
  const NotificationIndicator({
    super.key,
    required this.notificationState,
    this.size = 8.0,
    this.color,
  });

  final NotificationStateNotifier notificationState;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notificationState,
      builder: (context, _) {
        if (notificationState.unreadCount == 0) {
          return const SizedBox.shrink();
        }

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color ?? Colors.red,
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
