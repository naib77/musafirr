import 'package:flutter/material.dart';

import '../../models/booking_status.dart';
import '../../models/notification.dart';
import '../../repositories/musafir_repository.dart';
import '../../repositories/supabase_musafir_repository.dart';
import '../../services/booking/booking_lifecycle_service.dart';
import '../../state/auth_state.dart';
import '../../state/messaging_state.dart';
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
    this.messagingState,
  });

  final NotificationStateNotifier notificationState;
  final MusafirRepository repository;
  final BookingLifecycleService bookingLifecycleService;
  final AuthStateNotifier authState;
  final MessagingStateNotifier? messagingState;

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  int _selectedTabIndex = 0;
  final ScrollController _scrollController = ScrollController();

  static const _tabs = ['All', 'Bookings', 'Payments', 'Messages', 'Other'];
  static const _tabIcons = [
    Icons.all_inbox_rounded,
    Icons.calendar_month_rounded,
    Icons.payments_rounded,
    Icons.chat_bubble_rounded,
    Icons.more_horiz_rounded,
  ];
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
    // Set up scroll listener for infinite scroll
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
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
    final isDark = theme.brightness == Brightness.dark;

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
                icon: const Icon(Icons.done_all_rounded),
                tooltip: 'Mark all as read',
                onPressed: () {
                  widget.notificationState.markAllAsRead();
                  _showSuccessBanner('All notifications marked as read');
                },
              );
            },
          ),
          // Settings
          IconButton(
            icon: const Icon(Icons.settings_rounded),
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

          return Column(
            children: [
              // Modern chip tabs
              _buildChipTabs(theme, isDark),
              // Content
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _buildNotificationList(
                    _getFilteredNotifications(_selectedTabIndex),
                    theme,
                    key: ValueKey(_selectedTabIndex),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChipTabs(ThemeData theme, bool isDark) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isSelected = index == _selectedTabIndex;
          final tabLabel = _tabs[index];
          final tabIcon = _tabIcons[index];

          return GestureDetector(
            onTap: () => setState(() => _selectedTabIndex = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.primary.withValues(alpha: 0.8),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isSelected
                    ? null
                    : isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    tabIcon,
                    size: 18,
                    color: isSelected
                        ? Colors.white
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tabLabel,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationList(
    List<AppNotification> notifications,
    ThemeData theme, {
    Key? key,
  }) {
    if (notifications.isEmpty) {
      return NotificationEmptyState(key: key);
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
      key: key,
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
      // Try to determine the appropriate tab based on the booking
      int initialTab = HostReservationTab.upcoming;
      String? highlightBookingId;

      final bookingId = notification.data?['booking_id'] as String?;
      if (bookingId != null) {
        final booking = widget.repository.getBookingById(bookingId);
        if (booking != null) {
          initialTab = HostReservationTab.forBooking(booking);
          highlightBookingId = bookingId;
        }
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HostReservationsScreen(
            repository: widget.repository,
            authState: widget.authState,
            messagingState: widget.messagingState,
            initialTabIndex: initialTab,
            highlightBookingId: highlightBookingId,
          ),
        ),
      );
      return;
    }

    // For unhandled routes, do nothing (deep linking not implemented yet)
    debugPrint('Unhandled action URL: $actionUrl');
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

    // Try local cache first, then fetch from Supabase if not found
    var booking = widget.repository.getBookingById(bookingId);
    if (booking == null && widget.repository is SupabaseMusafirRepository) {
      final supabaseRepo = widget.repository as SupabaseMusafirRepository;
      booking = await supabaseRepo.fetchBookingById(bookingId);
    }

    if (booking == null) {
      if (mounted) {
        _showErrorBanner('Booking not found. It may have been cancelled.');
      }
      return;
    }

    if (booking.status != BookingStatus.pending) {
      if (mounted) {
        _showErrorBanner(
          'This booking is no longer pending. Status: ${booking.status.title}',
        );
        setState(() {
          _bookingStatusCache[notification.id] = booking!.status;
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
      widget.bookingLifecycleService.acceptBooking(
        bookingId,
        message: result.message,
      );
      _showSuccessBadge(notification.id, 'Accepted');
      await widget.notificationState.markAsRead(notification.id);

      // Navigate to the appropriate tab in host reservations
      if (mounted) {
        // Re-fetch the updated booking to get the correct tab
        final updatedBooking = widget.repository.getBookingById(bookingId);
        final initialTab = updatedBooking != null
            ? HostReservationTab.forBooking(updatedBooking)
            : HostReservationTab.upcoming;

        // Delay navigation slightly to show the success badge
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => HostReservationsScreen(
                  repository: widget.repository,
                  authState: widget.authState,
                  messagingState: widget.messagingState,
                  initialTabIndex: initialTab,
                  highlightBookingId: bookingId,
                ),
              ),
            );
          }
        });
      }
    } on InvalidBookingStateException catch (e) {
      if (mounted) {
        _showErrorBanner(e.message);
      }
    } catch (e) {
      if (mounted) {
        _showErrorBanner('Failed to accept booking. Please try again.');
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

    // Try local cache first, then fetch from Supabase if not found
    var booking = widget.repository.getBookingById(bookingId);
    if (booking == null && widget.repository is SupabaseMusafirRepository) {
      final supabaseRepo = widget.repository as SupabaseMusafirRepository;
      booking = await supabaseRepo.fetchBookingById(bookingId);
    }

    if (booking == null) {
      if (mounted) {
        _showErrorBanner('Booking not found. It may have been cancelled.');
      }
      return;
    }

    if (booking.status != BookingStatus.pending) {
      if (mounted) {
        _showErrorBanner(
          'This booking is no longer pending. Status: ${booking.status.title}',
        );
        setState(() {
          _bookingStatusCache[notification.id] = booking!.status;
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
        _showErrorBanner(e.message);
      }
    } catch (e) {
      if (mounted) {
        _showErrorBanner('Failed to decline booking. Please try again.');
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
    setState(() => _successBadges[notificationId] = label);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _successBadges.remove(notificationId));
        widget.notificationState.delete(notificationId);
      }
    });
  }

  /// Show a modern error banner at the top
  void _showErrorBanner(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leadingPadding: EdgeInsets.zero,
        actions: [
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: const Text('Dismiss', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(seconds: 4), () {
      messenger.hideCurrentMaterialBanner();
    });
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
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
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
