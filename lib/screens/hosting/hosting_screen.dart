import 'package:flutter/material.dart';

import '../../models/booking.dart';
import '../../models/booking_categorizer.dart';
import '../../models/booking_status.dart';
import '../../models/listing.dart';
import '../../repositories/musafir_repository.dart';
import '../../services/booking/booking_lifecycle_service.dart';
import '../../services/booking/booking_messaging_coordinator.dart';
import '../../state/auth_state.dart';
import '../../state/messaging_state.dart';
import '../../widgets/dialogs/booking_action_dialogs.dart';
import '../host/host_reservations_screen.dart';
import '../messaging/chat_screen.dart';

/// Modern hosting dashboard for hosts to manage their reservations.
///
/// Shows:
/// - Today's overview (check-ins/check-outs)
/// - Pending requests with inline Accept/Decline
/// - Active stays
/// - Upcoming reservations
class HostingScreen extends StatelessWidget {
  const HostingScreen({
    super.key,
    required this.repository,
    required this.authState,
    required this.bookingLifecycleService,
    this.bookingMessagingCoordinator,
    this.messagingState,
    this.notificationState,
    this.onOpenInbox,
    this.onOpenNotifications,
    this.showAppBar = true,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final BookingLifecycleService bookingLifecycleService;
  final BookingMessagingCoordinator? bookingMessagingCoordinator;
  final MessagingStateNotifier? messagingState;
  final dynamic notificationState;
  final VoidCallback? onOpenInbox;
  final VoidCallback? onOpenNotifications;
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([repository, authState]),
      builder: (context, _) {
        final user = authState.currentUser;
        if (user == null) {
          return const _NotHostView();
        }

        // Get host's listings
        final hostListings = repository.listings
            .where((l) => l.hostId == user.id || l.ownerName == user.name)
            .toList();

        if (hostListings.isEmpty) {
          return const _NotHostView();
        }

        // Get bookings for host's listings
        final hostBookings = repository.bookings
            .where((b) => hostListings.any((l) => l.id == b.listingId))
            .toList();

        return _HostingDashboard(
          // Stable key to preserve state across ListenableBuilder rebuilds
          key: const ValueKey('hosting_dashboard'),
          hostListings: hostListings,
          hostBookings: hostBookings,
          repository: repository,
          bookingLifecycleService: bookingLifecycleService,
          bookingMessagingCoordinator: bookingMessagingCoordinator,
          messagingState: messagingState,
          notificationState: notificationState,
          onOpenInbox: onOpenInbox,
          onOpenNotifications: onOpenNotifications,
          authState: authState,
          showAppBar: showAppBar,
        );
      },
    );
  }
}

class _NotHostView extends StatelessWidget {
  const _NotHostView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reservations'),
        centerTitle: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.home_work_outlined,
                size: 80,
                color: theme.colorScheme.primary.withOpacity(0.5),
              ),
              const SizedBox(height: 24),
              Text(
                'Start hosting on Musafir',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'List your space and start earning. Share your home with travelers from around the world.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () {
                  // TODO: Navigate to listing creation
                },
                icon: const Icon(Icons.add),
                label: const Text('Create a listing'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HostingDashboard extends StatefulWidget {
  const _HostingDashboard({
    super.key,
    required this.hostListings,
    required this.hostBookings,
    required this.repository,
    required this.bookingLifecycleService,
    this.bookingMessagingCoordinator,
    this.messagingState,
    this.notificationState,
    this.onOpenInbox,
    this.onOpenNotifications,
    required this.authState,
    required this.showAppBar,
  });

  final List<Listing> hostListings;
  final List<Booking> hostBookings;
  final MusafirRepository repository;
  final BookingLifecycleService bookingLifecycleService;
  final BookingMessagingCoordinator? bookingMessagingCoordinator;
  final MessagingStateNotifier? messagingState;
  final dynamic notificationState;
  final VoidCallback? onOpenInbox;
  final VoidCallback? onOpenNotifications;
  final AuthStateNotifier authState;
  final bool showAppBar;

  @override
  State<_HostingDashboard> createState() => _HostingDashboardState();
}

class _HostingDashboardState extends State<_HostingDashboard> {
  String? _processingBookingId;

  /// Navigate to chat with a guest
  void _openChat({required String conversationId, required String guestName}) {
    if (widget.messagingState == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          conversationId: conversationId,
          messagingState: widget.messagingState!,
          otherParticipantName: guestName,
        ),
      ),
    );
  }

  /// Show a modern success banner at the top
  void _showSuccessBanner(String message, {String? actionLabel, VoidCallback? onAction}) {
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
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leadingPadding: EdgeInsets.zero,
        actions: [
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: () {
                messenger.hideCurrentMaterialBanner();
                onAction();
              },
              child: Text(actionLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(seconds: 5), () {
      messenger.hideCurrentMaterialBanner();
    });
  }

  /// Show a modern info banner at the top
  void _showInfoBanner(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade700,
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
    Future.delayed(const Duration(seconds: 4), () {
      messenger.hideCurrentMaterialBanner();
    });
  }

  /// Show a modern error banner at the top
  void _showErrorBanner(String message) {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
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
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: theme.colorScheme.error,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    // Categorize via the shared seam so this screen, the dashboard, the guest
    // Trips screen and the Reservations sub-screen can never disagree. The
    // Upcoming bucket (pending + confirmed) is then split by status into the
    // two sections this screen shows ("Pending Requests" vs "Upcoming"), and
    // the Current bucket (checked-in) drives "Active Stays".
    final categorizer = BookingCategorizer(widget.hostBookings);

    final pendingBookings = categorizer.upcoming
        .where((b) => b.status == BookingStatus.pending)
        .toList()
      ..sort((a, b) => a.createdAt?.compareTo(b.createdAt ?? DateTime.now()) ?? 0);

    final activeBookings = categorizer.current;

    final confirmedBookings = categorizer.upcoming
        .where((b) => b.status == BookingStatus.confirmed)
        .toList()
      ..sort((a, b) => a.effectiveCheckIn.compareTo(b.effectiveCheckIn));

    // Today's events
    final todayCheckIns = confirmedBookings.where((b) {
      final checkIn = b.effectiveCheckIn;
      return checkIn.year == today.year &&
          checkIn.month == today.month &&
          checkIn.day == today.day;
    }).toList();

    final todayCheckOuts = activeBookings.where((b) {
      final checkOut = b.effectiveCheckOut;
      return checkOut.year == today.year &&
          checkOut.month == today.month &&
          checkOut.day == today.day;
    }).toList();

    final unreadCount = widget.messagingState?.totalUnreadCount ?? 0;

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Reservations'),
              centerTitle: false,
              actions: [
                // Messages icon
                if (widget.messagingState != null && widget.onOpenInbox != null)
                  IconButton(
                    icon: Badge(
                      isLabelVisible: unreadCount > 0,
                      label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                      child: const Icon(Icons.chat_bubble_outline),
                    ),
                    onPressed: widget.onOpenInbox,
                    tooltip: 'Messages',
                  ),
                // Notification bell
                if (widget.notificationState != null && widget.onOpenNotifications != null)
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: widget.onOpenNotifications,
                    tooltip: 'Notifications',
                  ),
              ],
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          // Trigger repository refresh
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Today's Overview Card
            _TodayCard(
              checkInsCount: todayCheckIns.length,
              checkOutsCount: todayCheckOuts.length,
              activeCount: activeBookings.length,
            ),
            const SizedBox(height: 24),

            // Pending Requests Section
            if (pendingBookings.isNotEmpty) ...[
              _SectionHeader(
                title: 'Pending Requests',
                count: pendingBookings.length,
                onSeeAll: () => _navigateToReservations(context),
              ),
              const SizedBox(height: 12),
              ...pendingBookings.take(3).map((booking) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PendingRequestCard(
                      booking: booking,
                      listing: widget.hostListings.firstWhere(
                        (l) => l.id == booking.listingId,
                        orElse: () => widget.hostListings.first,
                      ),
                      isProcessing: _processingBookingId == booking.id,
                      onAccept: () => _handleAccept(booking),
                      onDecline: () => _handleDecline(booking),
                    ),
                  )),
              if (pendingBookings.length > 3)
                TextButton(
                  onPressed: () => _navigateToReservations(context),
                  child: Text('View all ${pendingBookings.length} requests'),
                ),
              const SizedBox(height: 24),
            ],

            // Active Stays Section
            if (activeBookings.isNotEmpty) ...[
              _SectionHeader(
                title: 'Active Stays',
                count: activeBookings.length,
                onSeeAll: () => _navigateToReservations(context),
              ),
              const SizedBox(height: 12),
              ...activeBookings.map((booking) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ActiveStayCard(
                      booking: booking,
                      listing: widget.hostListings.firstWhere(
                        (l) => l.id == booking.listingId,
                        orElse: () => widget.hostListings.first,
                      ),
                      onComplete: () => _handleComplete(booking),
                    ),
                  )),
              const SizedBox(height: 24),
            ],

            // Upcoming Section
            if (confirmedBookings.isNotEmpty) ...[
              _SectionHeader(
                title: 'Upcoming',
                count: confirmedBookings.length,
                onSeeAll: () => _navigateToReservations(context),
              ),
              const SizedBox(height: 12),
              ...confirmedBookings.take(5).map((booking) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _UpcomingCard(
                      booking: booking,
                      listing: widget.hostListings.firstWhere(
                        (l) => l.id == booking.listingId,
                        orElse: () => widget.hostListings.first,
                      ),
                      onCheckIn: () => _handleCheckIn(booking),
                    ),
                  )),
              const SizedBox(height: 24),
            ],

            // Empty state
            if (pendingBookings.isEmpty &&
                activeBookings.isEmpty &&
                confirmedBookings.isEmpty)
              _EmptyState(
                listingsCount: widget.hostListings.length,
              ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _navigateToReservations(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HostReservationsScreen(
          repository: widget.repository,
          authState: widget.authState,
          messagingState: widget.messagingState,
        ),
      ),
    );
  }

  Future<void> _handleAccept(Booking booking) async {
    debugPrint('[DEBUG-accept] _handleAccept called for ${booking.id}, _processingBookingId=$_processingBookingId');

    // Prevent double-accept: check if already processing this booking
    if (_processingBookingId == booking.id) {
      debugPrint('[DEBUG-accept] Already processing ${booking.id}, ignoring');
      return;
    }

    // Double-check booking is still pending (may have changed)
    if (booking.status != BookingStatus.pending) {
      debugPrint('[DEBUG-accept] Booking ${booking.id} is no longer pending, status: ${booking.status}');
      return;
    }

    final result = await showAcceptBookingDialog(
      context,
      guestName: booking.tenantName,
    );
    if (result == null || !result.confirmed) return;

    // Check again after dialog (booking may have been accepted/rejected by now)
    final currentBooking = widget.repository.getBookingById(booking.id);
    if (currentBooking == null || currentBooking.status != BookingStatus.pending) {
      debugPrint('[DEBUG-accept] Booking ${booking.id} changed during dialog');
      if (mounted) {
        _showInfoBanner('This booking has already been processed');
      }
      return;
    }

    setState(() => _processingBookingId = booking.id);
    try {
      // Get the host ID from the listing or current user
      final listing = widget.hostListings.firstWhere(
        (l) => l.id == booking.listingId,
        orElse: () => widget.hostListings.first,
      );
      final hostId = listing.hostId ?? widget.authState.currentUser?.id ?? '';

      // Use coordinator if available (creates conversation automatically)
      if (widget.bookingMessagingCoordinator != null) {
        final coordResult = await widget.bookingMessagingCoordinator!.acceptBookingWithConversation(
          bookingId: booking.id,
          hostId: hostId,
          message: result.message,
        );
        if (mounted) {
          if (coordResult.hasConversation && widget.messagingState != null) {
            _showSuccessBanner(
              'Booking accepted!',
              actionLabel: 'Message Guest',
              onAction: () => _openChat(
                conversationId: coordResult.conversation!.id,
                guestName: booking.tenantName,
              ),
            );
          } else {
            _showSuccessBanner('Booking accepted!');
          }
        }
      } else {
        // Fallback to lifecycle service only
        await widget.bookingLifecycleService.acceptBooking(
          booking.id,
          message: result.message,
        );
        if (mounted) {
          _showSuccessBanner('Booking accepted!');
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorBanner('Failed to accept booking. Please try again.');
      }
    } finally {
      // Use addPostFrameCallback to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _processingBookingId = null);
        }
      });
    }
  }

  Future<void> _handleDecline(Booking booking) async {
    final result = await showDeclineBookingDialog(
      context,
      guestName: booking.tenantName,
    );
    if (result == null || !result.confirmed) return;

    setState(() => _processingBookingId = booking.id);
    try {
      widget.bookingLifecycleService.rejectBooking(
        booking.id,
        reason: result.message,
      );
      if (mounted) {
        _showSuccessBanner('Booking declined');
      }
    } catch (e) {
      if (mounted) {
        _showErrorBanner('Failed to decline booking. Please try again.');
      }
    } finally {
      // Use addPostFrameCallback to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _processingBookingId = null);
        }
      });
    }
  }

  Future<void> _handleCheckIn(Booking booking) async {
    try {
      widget.bookingLifecycleService.checkInGuest(booking.id);
      if (mounted) {
        _showSuccessBanner('Guest checked in!');
      }
    } catch (e) {
      if (mounted) {
        _showErrorBanner('Failed to check in guest. Please try again.');
      }
    }
  }

  Future<void> _handleComplete(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Stay'),
        content: Text(
          'Mark ${booking.tenantName}\'s stay as complete? '
          'This will allow both of you to leave reviews.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      widget.bookingLifecycleService.completeService(booking.id);
      if (mounted) {
        _showSuccessBanner('Stay marked as complete!');
      }
    } catch (e) {
      if (mounted) {
        _showErrorBanner('Failed to complete stay. Please try again.');
      }
    }
  }
}

// ============================================================
// COMPONENTS
// ============================================================

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.checkInsCount,
    required this.checkOutsCount,
    required this.activeCount,
  });

  final int checkInsCount;
  final int checkOutsCount;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.primaryContainer.withOpacity(0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.wb_sunny_outlined,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                'Today',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TodayStat(
                  icon: Icons.login,
                  label: 'Check-ins',
                  count: checkInsCount,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: theme.colorScheme.onPrimaryContainer.withOpacity(0.2),
              ),
              Expanded(
                child: _TodayStat(
                  icon: Icons.logout,
                  label: 'Check-outs',
                  count: checkOutsCount,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: theme.colorScheme.onPrimaryContainer.withOpacity(0.2),
              ),
              Expanded(
                child: _TodayStat(
                  icon: Icons.hotel,
                  label: 'Hosting',
                  count: activeCount,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodayStat extends StatelessWidget {
  const _TodayStat({
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          '$count',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onPrimaryContainer.withOpacity(0.8),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    this.onSeeAll,
  });

  final String title;
  final int count;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const Spacer(),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            child: const Text('See all'),
          ),
      ],
    );
  }
}

class _PendingRequestCard extends StatelessWidget {
  const _PendingRequestCard({
    required this.booking,
    required this.listing,
    required this.isProcessing,
    required this.onAccept,
    required this.onDecline,
  });

  final Booking booking;
  final Listing listing;
  final bool isProcessing;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Guest info row
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        booking.tenantName.isNotEmpty
                            ? booking.tenantName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            booking.tenantName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            listing.title,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Pending',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                // Expiration countdown banner
                if (booking.createdAt != null) ...[
                  const SizedBox(height: 12),
                  _ExpirationCountdown(createdAt: booking.createdAt!),
                ],
                const SizedBox(height: 12),
                // Booking details
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '${_formatDate(booking.effectiveCheckIn)} - ${_formatDate(booking.effectiveCheckOut)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.person, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '${booking.guestCount} guest${booking.guestCount > 1 ? 's' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '৳${booking.totalPrice.toStringAsFixed(0)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Action buttons
          Padding(
            padding: const EdgeInsets.all(12),
            child: isProcessing
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    children: [
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: onAccept,
                          child: const Text('Accept'),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}

/// Shows countdown until booking request expires (24 hours from creation)
class _ExpirationCountdown extends StatelessWidget {
  const _ExpirationCountdown({required this.createdAt});

  final DateTime createdAt;

  static const _expirationDuration = Duration(hours: 24);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expiresAt = createdAt.add(_expirationDuration);
    final now = DateTime.now();
    final remaining = expiresAt.difference(now);

    if (remaining.isNegative) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red),
            const SizedBox(width: 6),
            Text(
              'Expired',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    String timeText;
    Color color;
    if (remaining.inHours >= 1) {
      timeText = '${remaining.inHours}h ${remaining.inMinutes % 60}m left to respond';
      color = remaining.inHours < 6 ? Colors.orange : Colors.blue;
    } else if (remaining.inMinutes >= 1) {
      timeText = '${remaining.inMinutes}m left to respond';
      color = Colors.red;
    } else {
      timeText = 'Less than a minute left';
      color = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_top_rounded, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              timeText,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveStayCard extends StatelessWidget {
  const _ActiveStayCard({
    required this.booking,
    required this.listing,
    required this.onComplete,
  });

  final Booking booking;
  final Listing listing;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final checkOut = booking.effectiveCheckOut;
    final daysLeft = checkOut.difference(now).inDays;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Guest avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.green.withOpacity(0.2),
              child: const Icon(Icons.person, color: Colors.green),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.tenantName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    listing.title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      daysLeft <= 0
                          ? 'Checking out today'
                          : '$daysLeft day${daysLeft > 1 ? 's' : ''} left',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Complete button
            FilledButton.tonal(
              onPressed: onComplete,
              child: const Text('Complete'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({
    required this.booking,
    required this.listing,
    required this.onCheckIn,
  });

  final Booking booking;
  final Listing listing;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final checkIn = booking.effectiveCheckIn;
    final today = DateTime(now.year, now.month, now.day);
    final checkInDay = DateTime(checkIn.year, checkIn.month, checkIn.day);
    final isToday = checkInDay == today;
    final daysUntil = checkInDay.difference(today).inDays;
    // A confirmed booking whose check-in date has already passed is "overdue":
    // the host still needs to check the guest in (or the guest is a no-show).
    // Show the check-in action for today AND any past date, never a negative
    // "In -5 days" countdown.
    final isOverdue = checkInDay.isBefore(today);
    final canCheckInNow = isToday || isOverdue;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Date badge
            Container(
              width: 48,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isToday
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    _getMonthAbbr(checkIn.month),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isToday
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${checkIn.day}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isToday
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.tenantName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    listing.title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isOverdue
                        ? 'Overdue${daysUntil == -1 ? ' by 1 day' : ' by ${-daysUntil} days'}'
                        : isToday
                            ? 'Arriving today'
                            : 'In $daysUntil day${daysUntil > 1 ? 's' : ''}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isOverdue
                          ? Colors.orange.shade800
                          : isToday
                              ? theme.colorScheme.primary
                              : null,
                      fontWeight:
                          (isToday || isOverdue) ? FontWeight.bold : null,
                    ),
                  ),
                ],
              ),
            ),
            // Check-in button — available on the arrival day and any time after
            // (overdue), so a past-dated confirmed booking stays actionable.
            if (canCheckInNow)
              FilledButton(
                onPressed: onCheckIn,
                child: const Text('Check in'),
              ),
          ],
        ),
      ),
    );
  }

  String _getMonthAbbr(int month) {
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
    ];
    return months[month - 1];
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.listingsCount});

  final int listingsCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.event_available,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No active reservations',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You have $listingsCount listing${listingsCount > 1 ? 's' : ''} available. '
              'New booking requests will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
