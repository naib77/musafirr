import 'package:flutter/material.dart';

import '../../models/booking_status.dart';
import '../../models/notification.dart';
import '../../repositories/musafir_repository.dart';
import '../../services/booking/booking_lifecycle_service.dart';
import '../../state/auth_state.dart';
import '../../state/notification_state.dart';
import '../../widgets/booking_details_sheet.dart';
import '../../widgets/dialogs/booking_action_dialogs.dart';
import '../../widgets/expandable_notification_item.dart';
import '../../widgets/notification_item.dart';
import '../host/host_reservations_screen.dart';
import 'notification_settings_screen.dart';

/// Main notification center screen displaying all user notifications
class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({
    super.key,
    required this.notificationState,
    required this.repository,
    required this.bookingLifecycleService,
    required this.authState,
  });

  final NotificationStateNotifier notificationState;
  final MusafirRepository repository;
  final BookingLifecycleService bookingLifecycleService;
  final AuthStateNotifier authState;

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

  // Expansion state management
  String? _expandedNotificationId;
  final Set<String> _manuallyCollapsed = {};
  String? _processingNotificationId;
  final Map<String, String> _successBadges = {};
  final Map<String, BookingStatus?> _bookingStatusCache = {};

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

          // Use expandable item for booking requests
          if (notification.type == NotificationType.bookingRequest) {
            return ExpandableNotificationItem(
              notification: notification,
              isExpanded: _isExpanded(notification),
              onExpand: () => _handleExpand(notification.id),
              onCollapse: () => _handleCollapse(notification.id),
              showDivider: index < notifications.length - 1,
              onTap: () => _handleNotificationTap(notification),
              onMarkAsRead: () =>
                  widget.notificationState.markAsRead(notification.id),
              onDismiss: () =>
                  widget.notificationState.delete(notification.id),
              onAccept: () => _handleAcceptBooking(notification),
              onDecline: () => _handleDeclineBooking(notification),
              onViewDetails: () => _showBookingDetailsSheet(notification),
              bookingStatus: _bookingStatusCache[notification.id],
              isProcessing: _processingNotificationId == notification.id,
              successLabel: _successBadges[notification.id],
            );
          }

          // Use standard item for other notifications
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
    // Parse the action URL and navigate accordingly
    if (actionUrl.startsWith('/host/reservations')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HostReservationsScreen(
            repository: widget.repository,
            authState: widget.authState,
          ),
        ),
      );
      return;
    }

    // For unhandled routes, show a snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Navigate to: $actionUrl'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // ============================================================
  // EXPANSION STATE MANAGEMENT
  // ============================================================

  /// Check if a notification should auto-expand.
  /// Auto-expand unread booking requests that haven't been manually collapsed.
  bool _shouldAutoExpand(AppNotification notification) {
    return notification.type == NotificationType.bookingRequest &&
        notification.isUnread &&
        !_manuallyCollapsed.contains(notification.id);
  }

  /// Check if a notification is currently expanded.
  bool _isExpanded(AppNotification notification) {
    // If explicitly expanded, show as expanded
    if (_expandedNotificationId == notification.id) {
      return true;
    }
    // If something else is explicitly expanded, don't auto-expand this one
    if (_expandedNotificationId != null) {
      return false;
    }
    // Auto-expand logic
    return _shouldAutoExpand(notification);
  }

  /// Handle expanding a notification (accordion behavior).
  void _handleExpand(String notificationId) {
    // Check if notification still exists (it may have been deleted)
    final notification = widget.notificationState.notifications
        .where((n) => n.id == notificationId)
        .firstOrNull;

    if (notification == null) {
      debugPrint('[DEBUG-expand] Notification $notificationId not found, ignoring expand');
      return;
    }

    setState(() {
      _expandedNotificationId = notificationId;
    });
    // Check booking status when expanding
    final bookingId = notification.data?['booking_id'] as String?;
    if (bookingId != null) {
      _checkBookingStatus(notificationId, bookingId);
    }
  }

  /// Handle collapsing a notification.
  void _handleCollapse(String notificationId) {
    setState(() {
      _expandedNotificationId = null;
      _manuallyCollapsed.add(notificationId);
    });
  }

  /// Check and cache the current booking status.
  void _checkBookingStatus(String notificationId, String bookingId) {
    final booking = widget.repository.getBookingById(bookingId);
    if (mounted) {
      setState(() {
        _bookingStatusCache[notificationId] = booking?.status;
      });
    }
  }

  // ============================================================
  // BOOKING ACTION HANDLERS
  // ============================================================

  Future<void> _handleAcceptBooking(AppNotification notification) async {
    final bookingId = notification.data?['booking_id'] as String?;
    final guestName = notification.data?['guest_name'] as String? ?? 'Guest';

    if (bookingId == null) return;

    // Stale check
    final booking = widget.repository.getBookingById(bookingId);
    if (booking == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking not found')),
        );
      }
      return;
    }

    if (booking.status != BookingStatus.pending) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'This booking is no longer pending. Status: ${booking.status.title}',
            ),
          ),
        );
        setState(() {
          _bookingStatusCache[notification.id] = booking.status;
        });
      }
      return;
    }

    // Show dialog
    final result = await showAcceptBookingDialog(context, guestName: guestName);
    if (result == null || !result.confirmed) return;

    // Process
    setState(() => _processingNotificationId = notification.id);
    try {
      debugPrint('[DEBUG-accept] Accepting booking $bookingId with message: ${result.message}');
      final updatedBooking = widget.bookingLifecycleService.acceptBooking(
        bookingId,
        message: result.message,
      );
      debugPrint('[DEBUG-accept] Booking accepted, new status: ${updatedBooking.status}');
      _showSuccessBadge(notification.id, 'Accepted');
      debugPrint('[DEBUG-accept] Success badge shown for notification ${notification.id}');
      await widget.notificationState.markAsRead(notification.id);
      debugPrint('[DEBUG-accept] Notification marked as read');
    } on InvalidBookingStateException catch (e) {
      debugPrint('[DEBUG-accept] InvalidBookingStateException: ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _handleAcceptBooking(notification),
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('[DEBUG-accept] Unexpected error: $e');
      debugPrint('[DEBUG-accept] Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingNotificationId = null);
      }
    }
  }

  Future<void> _handleDeclineBooking(AppNotification notification) async {
    final bookingId = notification.data?['booking_id'] as String?;
    final guestName = notification.data?['guest_name'] as String? ?? 'Guest';

    if (bookingId == null) return;

    // Stale check
    final booking = widget.repository.getBookingById(bookingId);
    if (booking == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking not found')),
        );
      }
      return;
    }

    if (booking.status != BookingStatus.pending) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'This booking is no longer pending. Status: ${booking.status.title}',
            ),
          ),
        );
        setState(() {
          _bookingStatusCache[notification.id] = booking.status;
        });
      }
      return;
    }

    // Show dialog
    final result =
        await showDeclineBookingDialog(context, guestName: guestName);
    if (result == null || !result.confirmed) return;

    // Process
    setState(() => _processingNotificationId = notification.id);
    try {
      widget.bookingLifecycleService.rejectBooking(
        bookingId,
        reason: result.message,
      );
      _showSuccessBadge(notification.id, 'Declined');
      await widget.notificationState.markAsRead(notification.id);
    } on InvalidBookingStateException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _handleDeclineBooking(notification),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingNotificationId = null);
      }
    }
  }

  void _showBookingDetailsSheet(AppNotification notification) {
    final bookingId = notification.data?['booking_id'] as String?;
    BookingStatus? bookingStatus;
    if (bookingId != null) {
      final booking = widget.repository.getBookingById(bookingId);
      bookingStatus = booking?.status;
    }

    BookingDetailsSheet.show(
      context,
      notification: notification,
      bookingStatus: bookingStatus,
      isProcessing: _processingNotificationId == notification.id,
      onAccept: () => _handleAcceptBooking(notification),
      onDecline: () => _handleDeclineBooking(notification),
    );
  }

  void _showSuccessBadge(String notificationId, String label) {
    debugPrint('[DEBUG-badge] Setting success badge "$label" for notification $notificationId');
    debugPrint('[DEBUG-badge] Current successBadges before: $_successBadges');
    setState(() => _successBadges[notificationId] = label);
    debugPrint('[DEBUG-badge] Current successBadges after: $_successBadges');
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        debugPrint('[DEBUG-badge] Removing badge and deleting notification $notificationId');
        setState(() => _successBadges.remove(notificationId));
        widget.notificationState.delete(notificationId);
      }
    });
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
