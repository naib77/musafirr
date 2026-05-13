import 'package:flutter/material.dart';

import '../../models/notification.dart';
import '../../state/notification_state.dart';
import '../../widgets/notification_item.dart';
import 'notification_settings_screen.dart';

/// Main notification center screen displaying all user notifications
class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({
    super.key,
    required this.notificationState,
  });

  final NotificationStateNotifier notificationState;

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  static const _tabs = ['All', 'Bookings', 'Payments', 'Messages', 'Other'];
  static const _tabCategories = [
    null, // All
    'booking',
    'payment',
    'message',
    null, // Other (review, promotion, system)
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);

    // Set up scroll listener for infinite scroll
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      // Load more when near the end
      widget.notificationState.loadMore();
    }
  }

  List<AppNotification> _getFilteredNotifications(int tabIndex) {
    final notifications = widget.notificationState.notifications;

    if (tabIndex == 0) {
      // All notifications
      return notifications;
    }

    if (tabIndex == 4) {
      // Other: review, promotion, system
      return notifications.where((n) {
        final category = n.type.category;
        return category == 'review' ||
            category == 'promotion' ||
            category == 'system';
      }).toList();
    }

    // Filter by specific category
    final category = _tabCategories[tabIndex];
    return notifications.where((n) => n.type.category == category).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          // Mark all as read
          ListenableBuilder(
            listenable: widget.notificationState,
            builder: (context, _) {
              if (widget.notificationState.unreadCount == 0) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.done_all),
                tooltip: 'Mark all as read',
                onPressed: () {
                  widget.notificationState.markAllAsRead();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('All notifications marked as read'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              );
            },
          ),
          // Settings
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Notification settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => NotificationSettingsScreen(
                    notificationState: widget.notificationState,
                  ),
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.notificationState,
        builder: (context, _) {
          if (widget.notificationState.isLoading &&
              widget.notificationState.notifications.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (widget.notificationState.error != null &&
              widget.notificationState.notifications.isEmpty) {
            return _buildErrorState(theme);
          }

          return TabBarView(
            controller: _tabController,
            children: List.generate(_tabs.length, (index) {
              return _buildNotificationList(
                _getFilteredNotifications(index),
                theme,
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildNotificationList(
    List<AppNotification> notifications,
    ThemeData theme,
  ) {
    if (notifications.isEmpty) {
      return const NotificationEmptyState();
    }

    // Group notifications by date
    final today = DateTime.now();
    final todayNotifications = <AppNotification>[];
    final yesterdayNotifications = <AppNotification>[];
    final earlierNotifications = <AppNotification>[];

    for (final notification in notifications) {
      final date = notification.createdAt;
      if (_isSameDay(date, today)) {
        todayNotifications.add(notification);
      } else if (_isSameDay(date, today.subtract(const Duration(days: 1)))) {
        yesterdayNotifications.add(notification);
      } else {
        earlierNotifications.add(notification);
      }
    }

    return RefreshIndicator(
      onRefresh: widget.notificationState.refresh,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Today
          if (todayNotifications.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: NotificationGroupHeader(
                title: 'Today',
                unreadCount: todayNotifications.where((n) => n.isUnread).length,
              ),
            ),
            _buildNotificationSliver(todayNotifications),
          ],

          // Yesterday
          if (yesterdayNotifications.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: NotificationGroupHeader(
                title: 'Yesterday',
                unreadCount:
                    yesterdayNotifications.where((n) => n.isUnread).length,
              ),
            ),
            _buildNotificationSliver(yesterdayNotifications),
          ],

          // Earlier
          if (earlierNotifications.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: NotificationGroupHeader(
                title: 'Earlier',
                unreadCount:
                    earlierNotifications.where((n) => n.isUnread).length,
              ),
            ),
            _buildNotificationSliver(earlierNotifications),
          ],

          // Loading indicator at bottom
          if (widget.notificationState.isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),

          // Bottom padding
          const SliverToBoxAdapter(
            child: SizedBox(height: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationSliver(List<AppNotification> notifications) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final notification = notifications[index];
          return NotificationItem(
            notification: notification,
            showDivider: index < notifications.length - 1,
            onTap: () => _handleNotificationTap(notification),
            onMarkAsRead: () =>
                widget.notificationState.markAsRead(notification.id),
            onDismiss: () => widget.notificationState.delete(notification.id),
          );
        },
        childCount: notifications.length,
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load notifications',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              widget.notificationState.error ?? 'Unknown error',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: widget.notificationState.refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _handleNotificationTap(AppNotification notification) {
    // Mark as read
    if (notification.isUnread) {
      widget.notificationState.markAsRead(notification.id);
    }

    // Handle navigation based on notification type
    final actionUrl = notification.actionUrl;
    if (actionUrl != null) {
      _navigateToAction(actionUrl, notification);
    }
  }

  void _navigateToAction(String actionUrl, AppNotification notification) {
    // For now, just show what would happen
    // In a real app, this would use Navigator or GoRouter
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Navigate to: $actionUrl'),
        duration: const Duration(seconds: 2),
      ),
    );

    // TODO: Implement actual navigation
    // final deepLink = NotificationDeepLinkHandler.parseActionUrl(actionUrl);
    // if (deepLink != null) {
    //   Navigator.pushNamed(context, deepLink.route, arguments: deepLink.arguments);
    // }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

/// Bottom sheet for quick notification actions
class NotificationActionsSheet extends StatelessWidget {
  const NotificationActionsSheet({
    super.key,
    required this.notification,
    required this.onMarkAsRead,
    required this.onDelete,
    required this.onMute,
  });

  final AppNotification notification;
  final VoidCallback onMarkAsRead;
  final VoidCallback onDelete;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          const SizedBox(height: 16),
          // Notification preview
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    notification.title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          // Actions
          if (notification.isUnread)
            ListTile(
              leading: const Icon(Icons.mark_email_read),
              title: const Text('Mark as read'),
              onTap: () {
                Navigator.pop(context);
                onMarkAsRead();
              },
            ),
          ListTile(
            leading: const Icon(Icons.notifications_off),
            title: Text('Mute ${notification.type.category} notifications'),
            onTap: () {
              Navigator.pop(context);
              onMute();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Delete', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              onDelete();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
