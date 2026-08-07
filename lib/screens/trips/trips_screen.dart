import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../models/booking.dart';
import '../../models/booking_categorizer.dart';
import '../../models/booking_status.dart';
import '../../models/review.dart';
import '../../repositories/musafir_repository.dart';
import '../../services/app_settings_service.dart';
import '../../services/booking/booking_lifecycle_service.dart'
    show InvalidBookingStateException;
import '../../services/booking/booking_messaging_coordinator.dart';
import '../../services/booking/booking_rules.dart';
import '../../services/payment/sslcommerz_service.dart';
import '../../state/auth_state.dart';
import '../../state/messaging_state.dart';
import '../../state/notification_state.dart';
import '../../widgets/app_page_header.dart';
import '../../widgets/booking_contact_card.dart';
import '../../widgets/booking_filter_bar.dart';
import '../../widgets/modern_banner.dart';
import '../../widgets/notification_bell.dart';
import '../messaging/chat_screen.dart';
import '../payment/payment_webview_screen.dart';
import '../review/guest_review_screen.dart';

class TripsScreen extends StatefulWidget {
  const TripsScreen({
    super.key,
    required this.repository,
    required this.authState,
    this.messagingState,
    this.notificationState,
    this.bookingMessagingCoordinator,
    this.onOpenNotifications,
    this.onNavigateToExplore,
    this.onTabTapped,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final MessagingStateNotifier? messagingState;
  final NotificationStateNotifier? notificationState;

  /// When provided, guest cancellations go through the coordinator so the
  /// host receives the cancellation message in the conversation.
  final BookingMessagingCoordinator? bookingMessagingCoordinator;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onNavigateToExplore;

  /// Called when the bottom navigation tab is tapped while already on this screen
  final VoidCallback? onTabTapped;

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  int _selectedIndex = 0;
  final _bookingRules = BookingRules();

  // List controls (shared across tabs): date sort direction + status filter.
  bool _sortDescending = false;
  BookingStatus? _statusFilter;

  // Scroll controllers for each tab (for pagination)
  late final ScrollController _upcomingScrollController;
  late final ScrollController _currentScrollController;
  late final ScrollController _pastScrollController;

  @override
  void initState() {
    super.initState();
    _upcomingScrollController = ScrollController()
      ..addListener(_onUpcomingScroll);
    _currentScrollController = ScrollController()
      ..addListener(_onCurrentScroll);
    _pastScrollController = ScrollController()..addListener(_onPastScroll);

    // Safe to call directly from initState: the repository uses SafeNotifier,
    // which defers any build-phase notification to post-frame.
    _initialLoad();
  }

  @override
  void dispose() {
    _upcomingScrollController.dispose();
    _currentScrollController.dispose();
    _pastScrollController.dispose();
    super.dispose();
  }

  void _initialLoad() {
    final user = widget.authState.currentUser;
    if (user != null) {
      // Fetch total counts first (for accurate badge display)
      widget.repository.getBookingCounts(user.id);
      // Reset pagination for this user
      widget.repository.resetBookingsPagination(user.id);
    }
  }

  void _onUpcomingScroll() => _onScroll(_upcomingScrollController);
  void _onCurrentScroll() => _onScroll(_currentScrollController);
  void _onPastScroll() => _onScroll(_pastScrollController);

  void _onScroll(ScrollController controller) {
    // Load more when 80% scrolled
    if (controller.position.pixels >=
        controller.position.maxScrollExtent * 0.8) {
      _loadMore();
    }
  }

  void _loadMore() {
    final user = widget.authState.currentUser;
    if (user == null) return;

    if (!widget.repository.isLoadingBookings &&
        widget.repository.hasMoreBookings) {
      widget.repository.fetchNextBookingsPage(user.id);
    }
  }

  Future<void> _onRefresh() async {
    final user = widget.authState.currentUser;
    if (user == null) return;

    // Refresh both counts and bookings
    await Future.wait([
      widget.repository.getBookingCounts(user.id),
      widget.repository.resetBookingsPagination(user.id),
    ]);
  }

  /// Called when user taps the Trips tab while already on it
  void refreshFromTabTap() {
    final user = widget.authState.currentUser;
    if (user == null) return;

    // Scroll to top and refresh
    final controller = switch (_selectedIndex) {
      0 => _upcomingScrollController,
      1 => _currentScrollController,
      2 => _pastScrollController,
      _ => _upcomingScrollController,
    };

    if (controller.hasClients) {
      controller.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    _onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Column(
        children: [
          AppPageHeader(
            title: 'My Trips',
            subtitle: 'Upcoming and past stays',
            actions: [
              if (widget.notificationState != null &&
                  widget.onOpenNotifications != null)
                AnimatedNotificationBell(
                  notificationState: widget.notificationState!,
                  onTap: widget.onOpenNotifications!,
                  iconSize: 22,
                  decorated: true,
                ),
            ],
          ),
          Expanded(
            child: ListenableBuilder(
              listenable:
                  Listenable.merge([widget.repository, widget.authState]),
              builder: (context, _) {
                final user = widget.authState.currentUser;
                if (user == null) {
                  return _buildLoginPrompt(context, theme);
                }

                final allBookings =
                    widget.repository.getBookingsForUser(user.id);
                final categorizer = BookingCategorizer(allBookings);

                // Use cached total counts for badges (not loaded count)
                final counts = widget.repository.cachedBookingCounts;
                final tabs = [
                  _TabData('Upcoming',
                      counts?['upcoming'] ?? categorizer.upcoming.length),
                  _TabData('Current',
                      counts?['current'] ?? categorizer.current.length),
                  _TabData('Past', counts?['past'] ?? categorizer.past.length),
                ];

                // The current tab's raw bucket, then derive filter options and
                // apply the user's status filter + date sort.
                final rawList = switch (_selectedIndex) {
                  0 => categorizer.upcoming,
                  1 => categorizer.current,
                  _ => categorizer.past,
                };
                final available = distinctStatuses(rawList);
                // If the active filter isn't valid for this tab, ignore it.
                final effectiveStatus =
                    (_statusFilter != null && available.contains(_statusFilter))
                        ? _statusFilter
                        : null;
                final processed = applyBookingFilterSort(
                  rawList,
                  statusFilter: effectiveStatus,
                  sortDescending: _sortDescending,
                );
                final tabType = switch (_selectedIndex) {
                  0 => _TabType.upcoming,
                  1 => _TabType.current,
                  _ => _TabType.past,
                };

                return Column(
                  children: [
                    // Modern 3-tab segmented control with badges
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: _SegmentedControlWithBadges(
                        selectedIndex: _selectedIndex,
                        tabs: tabs,
                        onChanged: (index) =>
                            setState(() => _selectedIndex = index),
                      ),
                    ),
                    // Sort + status filter controls
                    BookingFilterBar(
                      sortDescending: _sortDescending,
                      statusFilter: effectiveStatus,
                      availableStatuses: available,
                      onSortChanged: (desc) =>
                          setState(() => _sortDescending = desc),
                      onStatusChanged: (status) =>
                          setState(() => _statusFilter = status),
                    ),
                    // Content
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _buildBookingsList(
                          context,
                          theme,
                          processed,
                          tabType: tabType,
                          userId: user.id,
                          key: ValueKey('tab-$_selectedIndex'),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginPrompt(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.luggage_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Log in to see your trips',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Once you log in, your bookings will appear here.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingsList(
    BuildContext context,
    ThemeData theme,
    List<Booking> bookings, {
    required _TabType tabType,
    required String userId,
    Key? key,
  }) {
    // Get the appropriate scroll controller for this tab
    final scrollController = switch (tabType) {
      _TabType.upcoming => _upcomingScrollController,
      _TabType.current => _currentScrollController,
      _TabType.past => _pastScrollController,
    };

    if (bookings.isEmpty && !widget.repository.isLoadingBookings) {
      return RefreshIndicator(
        onRefresh: _onRefresh,
        child: CustomScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              child:
                  _buildEmptyState(context, theme, tabType: tabType, key: key),
            ),
          ],
        ),
      );
    }

    // For past bookings, find ones that need review
    final needsReviewBookings = <Booking>[];
    if (tabType == _TabType.past) {
      for (final booking in bookings) {
        if (booking.status == BookingStatus.completed) {
          final existingReviews =
              widget.repository.getReviewsForBooking(booking.id);
          final hasReviewed = existingReviews.any(
            (r) =>
                r.reviewerId == userId &&
                r.reviewType == ReviewType.guestToHost,
          );
          if (!hasReviewed) {
            needsReviewBookings.add(booking);
          }
        }
      }
    }

    final hasReviewBanner =
        tabType == _TabType.past && needsReviewBookings.isNotEmpty;
    final isLoading = widget.repository.isLoadingBookings;
    final hasMore = widget.repository.hasMoreBookings;

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: CustomScrollView(
        key: key,
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Review prompt banner at top (for past bookings)
          if (hasReviewBanner)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _ReviewPromptBanner(
                  bookingsCount: needsReviewBookings.length,
                  firstBooking: needsReviewBookings.first,
                  onTap: () =>
                      _showBookingDetails(context, needsReviewBookings.first),
                ),
              ),
            ),

          // Booking cards
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final booking = bookings[index];
                  // Messaging is always available — even after the stay ends.
                  final showMessageButton = widget.messagingState != null;

                  return Padding(
                    padding: EdgeInsets.only(top: index > 0 ? 10 : 0),
                    child: _EnhancedBookingCard(
                      booking: booking,
                      onTap: () => _showBookingDetails(context, booking),
                      showReviewBadge: needsReviewBookings.contains(booking),
                      tabType: tabType,
                      bookingRules: _bookingRules,
                      needsReviewBookings: needsReviewBookings,
                      onMessageHost: showMessageButton
                          ? () => _openChatForBooking(booking)
                          : null,
                      onPay: () => _payForBooking(booking),
                    ),
                  );
                },
                childCount: bookings.length,
              ),
            ),
          ),

          // Loading indicator at bottom
          if (isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),

          // "Load more" hint when there are more items
          if (!isLoading && hasMore && bookings.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'Scroll for more',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
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

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme, {
    required _TabType tabType,
    Key? key,
  }) {
    final (icon, title, subtitle) = switch (tabType) {
      _TabType.upcoming => (
          Icons.calendar_today_rounded,
          'No upcoming trips',
          'Time to dust off your bags and start planning your next adventure.',
        ),
      _TabType.current => (
          Icons.hotel_rounded,
          'No active stays',
          'When you check in to a property, your current stay will appear here.',
        ),
      _TabType.past => (
          Icons.history_rounded,
          'No past trips',
          'Once you complete a trip, it will appear here.',
        ),
    };

    return Center(
      key: key,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
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
            if (tabType == _TabType.upcoming) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: widget.onNavigateToExplore,
                icon: const Icon(Icons.search),
                label: const Text('Start searching'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showBookingDetails(BuildContext context, Booking booking) {
    // Messaging is always available — even after the stay ends.
    final showMessageButton = widget.messagingState != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EnhancedBookingDetailsSheet(
        booking: booking,
        repository: widget.repository,
        authState: widget.authState,
        bookingRules: _bookingRules,
        bookingMessagingCoordinator: widget.bookingMessagingCoordinator,
        onNavigateToExplore: widget.onNavigateToExplore,
        onMessageHost:
            showMessageButton ? () => _openChatForBooking(booking) : null,
      ),
    );
  }

  Future<void> _openChatForBooking(Booking booking) async {
    if (widget.messagingState == null) return;

    final user = widget.authState.currentUser;
    if (user == null) return;

    // Find the conversation for this booking
    final conversations = widget.messagingState!.conversations;
    var conversation =
        conversations.where((c) => c.bookingId == booking.id).firstOrNull;

    // If no conversation exists, create one
    if (conversation == null) {
      // Get the host ID from the listing
      final listing = widget.repository.listings
          .where((l) => l.id == booking.listingId)
          .firstOrNull;

      final hostId = listing?.hostId;
      if (hostId == null) {
        if (mounted) {
          ModernBanner.showInfo(
              context, 'Cannot message: host information not available');
        }
        return;
      }

      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Starting conversation...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // Create the conversation
      conversation = await widget.messagingState!.startConversation(
        otherUserId: hostId,
        bookingId: booking.id,
        listingId: booking.listingId,
      );

      if (conversation == null) {
        if (mounted) {
          ModernBanner.showError(
              context, 'Failed to start conversation. Please try again.');
        }
        return;
      }
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            conversationId: conversation!.id,
            messagingState: widget.messagingState!,
            otherParticipantName: conversation.displayName,
            otherParticipantAvatarUrl: conversation.avatarUrl,
          ),
        ),
      );
    }
  }

  /// Entry point for the "Pay" button. If the admin has enabled hand cash, the
  /// guest first chooses online vs cash; otherwise it goes straight to the
  /// online gateway (unchanged behaviour).
  Future<void> _payForBooking(Booking booking) async {
    if (!AppSettingsService.instance.cashPaymentEnabled) {
      await _payOnline(booking);
      return;
    }

    final method = await _choosePaymentMethod(booking);
    if (!mounted || method == null) return; // dismissed
    switch (method) {
      case _PayMethod.online:
        await _payOnline(booking);
      case _PayMethod.cash:
        await _chooseCashPayment(booking);
    }
  }

  /// Bottom sheet letting the guest pick how to pay. Returns null if dismissed.
  Future<_PayMethod?> _choosePaymentMethod(Booking booking) {
    final amount = '৳${booking.totalPrice.toStringAsFixed(0)}';
    return showModalBottomSheet<_PayMethod>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('How would you like to pay?',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline, color: AppColors.brand),
              title: const Text('Pay online'),
              subtitle: Text('Card, bKash, or bank — pay $amount now'),
              onTap: () => Navigator.pop(ctx, _PayMethod.online),
            ),
            ListTile(
              leading:
                  const Icon(Icons.payments_outlined, color: AppColors.brand),
              title: const Text('Hand cash'),
              subtitle:
                  const Text('Pay the host directly; they confirm receipt'),
              onTap: () => Navigator.pop(ctx, _PayMethod.cash),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Guest chose hand cash: record the choice (server re-checks the toggle and
  /// that the guest owns the booking). This does NOT mark the booking paid —
  /// the host confirms once they physically receive the cash.
  Future<void> _chooseCashPayment(Booking booking) async {
    final ok = await SslcommerzService.instance.chooseCashPayment(booking.id);
    if (!mounted) return;
    if (!ok) {
      ModernBanner.showError(
          context, 'Could not select cash payment. Please try again.');
      return;
    }
    final user = widget.authState.currentUser;
    if (user != null) {
      await widget.repository.resetBookingsPagination(user.id);
    }
    if (!mounted) return;
    ModernBanner.showSuccess(
      context,
      'Pay the host in cash — they\'ll confirm it and your booking updates.',
    );
  }

  /// Online payment flow: start an SSLCommerz session, open the hosted gateway
  /// in a WebView, then confirm settlement (the server validates the payment)
  /// and refresh the booking list.
  Future<void> _payOnline(Booking booking) async {
    final init = await SslcommerzService.instance.initiate(booking.id);
    if (!mounted) return;
    if (!init.success || init.gatewayUrl == null) {
      ModernBanner.showError(context, init.error ?? 'Could not start payment');
      return;
    }

    // Web has no in-app WebView (webview_flutter is Android/iOS only): open the
    // hosted gateway in a new browser tab, then confirm settlement by polling.
    // The tab is opened from the button's own onPressed so the browser treats
    // it as a user gesture (avoids popup blocking after the async init call).
    if (kIsWeb) {
      final gatewayUrl = init.gatewayUrl!;
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Secure payment'),
          content: const Text(
            'Tap "Open payment page" to pay in a new tab. Once you finish there, '
            'come back and tap "I\'ve paid".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(gatewayUrl),
                webOnlyWindowName: '_blank',
              ),
              child: const Text('Open payment page'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'paid'),
              child: const Text("I've paid"),
            ),
          ],
        ),
      );
      if (result == 'paid') await _settlePayment(booking, init.tranId);
      return;
    }

    // Mobile: in-app WebView that detects the redirect outcome.
    final outcome = await Navigator.push<PaymentOutcome>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PaymentWebViewScreen(gatewayUrl: init.gatewayUrl!),
      ),
    );
    if (!mounted) return;

    switch (outcome) {
      case PaymentOutcome.success:
        await _settlePayment(booking, init.tranId);
      case PaymentOutcome.failed:
        ModernBanner.showError(context, 'Payment failed. Please try again.');
      case PaymentOutcome.cancelled:
      case null:
        break;
    }
  }

  /// Confirms settlement (the server validates the payment via the Validation
  /// API) and refreshes the booking list. Shared by the mobile WebView and the
  /// web new-tab flows. Resolves the precise outcome by polling the payment
  /// attempt so failures are surfaced, not silently swallowed.
  Future<void> _settlePayment(Booking booking, String? tranId) async {
    if (!mounted) return;
    ModernBanner.showInfo(context, 'Confirming your payment…');
    final settlement = tranId == null
        ? PaymentSettlement.pending
        : await SslcommerzService.instance.awaitSettlement(tranId);
    final user = widget.authState.currentUser;
    if (user != null) {
      await widget.repository.resetBookingsPagination(user.id);
    }
    if (!mounted) return;
    switch (settlement) {
      case PaymentSettlement.paid:
        ModernBanner.showSuccess(context, 'Payment successful! 🎉');
      case PaymentSettlement.failed:
        ModernBanner.showError(context,
            'Payment failed or could not be verified. Please try again.');
      case PaymentSettlement.pending:
        ModernBanner.showInfo(
            context, 'Payment received — your booking will update shortly.');
    }
  }
}

enum _TabType { upcoming, current, past }

/// How the guest chose to pay at the pay step.
enum _PayMethod { online, cash }

class _TabData {
  final String label;
  final int count;
  const _TabData(this.label, this.count);
}

// =============================================================================
// ENHANCED BOOKING CARD - Deep module with contextual state banners
// =============================================================================

class _EnhancedBookingCard extends StatelessWidget {
  const _EnhancedBookingCard({
    required this.booking,
    required this.onTap,
    required this.tabType,
    required this.bookingRules,
    this.showReviewBadge = false,
    this.needsReviewBookings = const [],
    this.onMessageHost,
    this.onPay,
  });

  final Booking booking;
  final VoidCallback onTap;
  final _TabType tabType;
  final BookingRules bookingRules;
  final bool showReviewBadge;
  final List<Booking> needsReviewBookings;
  final VoidCallback? onMessageHost;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final hint = _hint();
    final showMessage = onMessageHost != null &&
        (booking.status == BookingStatus.confirmed ||
            booking.status == BookingStatus.active);
    // Guest can pay any time after the host accepts and before the stay is
    // completed — i.e. 'confirmed' or 'active' (checked in) — while unpaid.
    final showPay = onPay != null &&
        (booking.status == BookingStatus.confirmed ||
            booking.status == BookingStatus.active) &&
        !booking.isPaid;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumbnail(theme),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            booking.listingTitle ?? 'Booking',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusChip(status: booking.status),
                        if (booking.isPaid &&
                            booking.status != BookingStatus.pending &&
                            booking.status != BookingStatus.cancelled) ...[
                          const SizedBox(width: 6),
                          const _PaidBadge(),
                        ],
                      ],
                    ),
                    if (booking.listingCity != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              booking.listingCity!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            size: 13,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '${_formatDate(booking.effectiveCheckIn)} → '
                            '${_formatDate(booking.effectiveCheckOut)}  ·  '
                            '${booking.durationLabel}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (hint != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(hint.icon, size: 13, color: hint.color),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              hint.text,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: hint.color,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (showPay && booking.isCashChosen) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.payments_outlined,
                              size: 15, color: AppColors.brand),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Cash selected — pay the host; they\'ll confirm it',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.brand,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: onPay,
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: const Text('Change'),
                          ),
                        ],
                      ),
                    ] else if (showPay) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onPay,
                          icon: const Icon(Icons.lock_outline, size: 16),
                          label: Text(
                              'Pay ৳${booking.totalPrice.toStringAsFixed(0)}'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ] else if (booking.isPaid &&
                        booking.status != BookingStatus.completed) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.verified_rounded,
                              size: 14, color: Colors.green.shade600),
                          const SizedBox(width: 4),
                          Text(
                            'Paid',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (showMessage) ...[
                      const SizedBox(height: 8),
                      _CompactMessageButton(onTap: onMessageHost!),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbnail(ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 84,
        height: 84,
        child: booking.listingImageUrl != null
            ? Image.network(
                booking.listingImageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(theme),
              )
            : _placeholder(theme),
      ),
    );
  }

  Widget _placeholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.home_outlined,
        size: 28,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  /// Single-line contextual hint derived from booking state — the compact
  /// replacement for the old full-width banner. Null when the status chip
  /// already says everything (e.g. a completed + reviewed stay).
  ({IconData icon, String text, Color color})? _hint() {
    final now = DateTime.now();
    switch (booking.status) {
      case BookingStatus.pending:
        final createdAt = booking.createdAt;
        if (createdAt == null) {
          return (
            icon: Icons.schedule_rounded,
            text: 'Awaiting host response',
            color: Colors.orange.shade800,
          );
        }
        final remaining =
            createdAt.add(BookingRules.expirationDuration).difference(now);
        final String t;
        if (remaining.isNegative) {
          t = 'expired';
        } else if (remaining.inHours >= 1) {
          t = '${remaining.inHours}h ${remaining.inMinutes % 60}m left';
        } else if (remaining.inMinutes >= 1) {
          t = '${remaining.inMinutes}m left';
        } else {
          t = 'expiring soon';
        }
        return (
          icon: Icons.hourglass_top_rounded,
          text: 'Awaiting host · $t',
          color: remaining.inHours < 6
              ? Colors.red.shade700
              : Colors.orange.shade800,
        );
      case BookingStatus.confirmed:
        final canCheckIn = bookingRules.canCheckIn(booking, now: now);
        final days = booking.effectiveCheckIn.difference(now).inDays;
        if (canCheckIn) {
          return (
            icon: Icons.login_rounded,
            text: 'Ready to check in today',
            color: Colors.green.shade700,
          );
        }
        // Confirmed but checkout already passed without a check-in — awaiting
        // auto-completion, not an upcoming arrival.
        if (now.isAfter(booking.effectiveCheckOut)) {
          return (
            icon: Icons.hourglass_bottom_rounded,
            text: 'Stay ended · finalizing',
            color: Colors.blueGrey.shade600,
          );
        }
        if (days <= 3) {
          return (
            icon: Icons.event_available_rounded,
            text: 'Check-in in $days day${days == 1 ? '' : 's'}',
            color: Colors.blue.shade700,
          );
        }
        return (
          icon: Icons.check_circle_outline_rounded,
          text: 'Confirmed for ${_formatDate(booking.effectiveCheckIn)}',
          color: Colors.green.shade700,
        );
      case BookingStatus.active:
        final total = booking.numberOfNights;
        final left = booking.effectiveCheckOut.difference(now).inDays;
        final checkoutHint = left > 0
            ? '$left day${left == 1 ? '' : 's'} left'
            : 'checkout today';
        // Hourly / sub-day stays have no "nights" — a "Day X of N" counter is
        // meaningless (it would read "Day 1 of 0").
        if (total < 1) {
          return (
            icon: Icons.hotel_rounded,
            text: 'Checked in · $checkoutHint',
            color: Colors.teal.shade700,
          );
        }
        // Clamp so an active stay lingering past checkout (within the
        // auto-complete grace) never reads "Day 4 of 3".
        final stayed = (now.difference(booking.effectiveCheckIn).inDays + 1)
            .clamp(1, total);
        return (
          icon: Icons.hotel_rounded,
          text: 'Day $stayed of $total · $checkoutHint',
          color: Colors.teal.shade700,
        );
      case BookingStatus.completed:
        if (showReviewBadge) {
          final completedAt = booking.completedAt ?? booking.effectiveCheckOut;
          final daysLeft = completedAt
              .add(BookingRules.reviewWindowDuration)
              .difference(now)
              .inDays;
          return daysLeft > 0
              ? (
                  icon: Icons.rate_review_rounded,
                  text:
                      '$daysLeft day${daysLeft == 1 ? '' : 's'} left to review',
                  color: Colors.amber.shade800,
                )
              : (
                  icon: Icons.rate_review_rounded,
                  text: 'Last day to leave a review',
                  color: Colors.red.shade700,
                );
        }
        return null;
      case BookingStatus.rejected:
        return (
          icon: Icons.search_rounded,
          text: 'Declined · tap to find similar',
          color: Colors.red.shade700,
        );
      case BookingStatus.cancelled:
        final byGuest = booking.cancelledBy == booking.userId;
        return (
          icon: Icons.cancel_outlined,
          text: byGuest ? 'You cancelled this booking' : 'Cancelled by host',
          color: Colors.grey.shade600,
        );
    }
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

// =============================================================================
// COMPACT STATUS CHIP + MESSAGE BUTTON
// =============================================================================

/// Small green pill shown next to the status chip once a booking is paid
/// (online settlement or a host-confirmed cash payment).
class _PaidBadge extends StatelessWidget {
  const _PaidBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 12, color: AppColors.success),
          SizedBox(width: 3),
          Text(
            'Paid',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      BookingStatus.pending => Colors.orange.shade700,
      BookingStatus.confirmed => Colors.green.shade600,
      BookingStatus.rejected => Colors.red.shade700,
      BookingStatus.active => Colors.teal.shade600,
      BookingStatus.completed => Colors.blue.shade600,
      BookingStatus.cancelled => Colors.grey.shade600,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            status.title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactMessageButton extends StatelessWidget {
  const _CompactMessageButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline,
                  size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'Message host',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// REVIEW PROMPT BANNER
// =============================================================================

class _ReviewPromptBanner extends StatelessWidget {
  const _ReviewPromptBanner({
    required this.bookingsCount,
    required this.firstBooking,
    required this.onTap,
  });

  final int bookingsCount;
  final Booking firstBooking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.rate_review_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bookingsCount == 1
                            ? 'Share your experience!'
                            : '$bookingsCount stays to review',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        bookingsCount == 1
                            ? 'Leave a review for ${firstBooking.listingTitle ?? "your stay"}'
                            : 'Your reviews help other travelers',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// ENHANCED BOOKING DETAILS SHEET
// =============================================================================

/// Opens the guest-facing booking detail sheet for [booking].
///
/// Public so other entry points — e.g. tapping a booking notification — can
/// deep-link straight to a specific trip, reusing the exact same detail view
/// (host message, lifecycle timestamps, cancel/review actions) the Trips tab
/// shows.
Future<void> showGuestBookingDetails(
  BuildContext context, {
  required Booking booking,
  required MusafirRepository repository,
  required AuthStateNotifier authState,
  VoidCallback? onNavigateToExplore,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _EnhancedBookingDetailsSheet(
      booking: booking,
      repository: repository,
      authState: authState,
      bookingRules: BookingRules(),
      onNavigateToExplore: onNavigateToExplore,
    ),
  );
}

class _EnhancedBookingDetailsSheet extends StatelessWidget {
  const _EnhancedBookingDetailsSheet({
    required this.booking,
    required this.repository,
    required this.authState,
    required this.bookingRules,
    this.bookingMessagingCoordinator,
    this.onNavigateToExplore,
    this.onMessageHost,
  });

  final Booking booking;
  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final BookingRules bookingRules;

  /// When provided, cancelling routes through the coordinator so the host
  /// receives the cancellation message in the conversation.
  final BookingMessagingCoordinator? bookingMessagingCoordinator;
  final VoidCallback? onNavigateToExplore;
  final VoidCallback? onMessageHost;

  /// The host's welcome/accept message, if any (null when blank).
  String? get _hostMessage {
    final msg = booking.hostMessage?.trim();
    return (msg == null || msg.isEmpty) ? null : msg;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Status-specific banner at top
            _buildStatusBanner(context, theme),
            const SizedBox(height: 20),

            // Host's welcome / message — shown here so the guest always sees it
            // even if the chat thread fails to load. Sourced from the booking
            // row (booking.hostMessage), independent of the messaging system.
            if (_hostMessage != null) ...[
              _HostMessageCard(message: _hostMessage!),
              const SizedBox(height: 20),
            ],

            // Title
            Text(
              booking.listingTitle ?? 'Booking Details',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (booking.listingCity != null)
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    booking.listingCity!,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),

            // Host phone (shared once the booking is confirmed). Renders
            // nothing while pending/declined.
            BookingContactCard(
              repository: repository,
              bookingId: booking.id,
              viewerIsHost: false,
            ),
            const Divider(height: 32),

            // Details grid
            _buildDetailsGrid(theme),
            const SizedBox(height: 24),

            // Actions
            _buildActions(context, theme),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(BuildContext context, ThemeData theme) {
    final now = DateTime.now();

    // PENDING
    if (booking.status == BookingStatus.pending) {
      final createdAt = booking.createdAt;
      final expiresAt = createdAt?.add(BookingRules.expirationDuration);
      final remaining =
          expiresAt != null ? expiresAt.difference(now) : Duration.zero;

      return _DetailsBanner(
        icon: Icons.hourglass_top_rounded,
        title: 'Awaiting Host Response',
        subtitle: remaining.isNegative
            ? 'This request has expired'
            : 'Host has ${remaining.inHours}h ${remaining.inMinutes % 60}m to respond',
        color: Colors.orange,
      );
    }

    // CONFIRMED
    if (booking.status == BookingStatus.confirmed) {
      final canCheckIn = bookingRules.canCheckIn(booking, now: now);
      // Confirmed but the whole stay window has already elapsed without a
      // check-in — it is awaiting auto-completion, not an upcoming arrival.
      if (!canCheckIn && now.isAfter(booking.effectiveCheckOut)) {
        return _DetailsBanner(
          icon: Icons.hourglass_bottom_rounded,
          title: 'Stay Window Ended',
          subtitle:
              'Being finalized — this will move to your past trips shortly',
          color: Colors.blueGrey,
        );
      }
      return _DetailsBanner(
        icon: canCheckIn ? Icons.login_rounded : Icons.check_circle_rounded,
        title: canCheckIn ? 'Ready to Check In!' : 'Booking Confirmed',
        subtitle: canCheckIn
            ? 'Contact your host when you arrive'
            : 'Check-in on ${_formatFullDate(booking.effectiveCheckIn)}',
        color: Colors.green,
      );
    }

    // ACTIVE
    if (booking.status == BookingStatus.active) {
      final daysLeft = booking.effectiveCheckOut.difference(now).inDays;
      return _DetailsBanner(
        icon: Icons.hotel_rounded,
        title: 'Currently Staying',
        subtitle: daysLeft > 0
            ? 'Checkout in $daysLeft day${daysLeft == 1 ? '' : 's'}'
            : 'Checkout is today!',
        color: Colors.teal,
      );
    }

    // COMPLETED
    if (booking.status == BookingStatus.completed) {
      return _DetailsBanner(
        icon: Icons.task_alt_rounded,
        title: 'Stay Completed',
        subtitle: 'We hope you had a great time!',
        color: Colors.blue,
      );
    }

    // REJECTED
    if (booking.status == BookingStatus.rejected) {
      return _DetailsBanner(
        icon: Icons.cancel_rounded,
        title: 'Request Declined',
        subtitle: booking.rejectionReason ??
            'The host couldn\'t accommodate your request',
        color: Colors.red.shade700,
      );
    }

    // CANCELLED
    if (booking.status == BookingStatus.cancelled) {
      return _DetailsBanner(
        icon: Icons.cancel_outlined,
        title: 'Booking Cancelled',
        subtitle: booking.cancelledBy == booking.userId
            ? 'You cancelled this booking'
            : 'This booking was cancelled by the host',
        color: Colors.grey,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildDetailsGrid(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _DetailRow(
            icon: Icons.login_rounded,
            label: 'Check-in',
            value: _formatDateTime(booking.effectiveCheckIn),
          ),
          const SizedBox(height: 16),
          _DetailRow(
            icon: Icons.logout_rounded,
            label: 'Check-out',
            value: _formatDateTime(booking.effectiveCheckOut),
          ),
          const SizedBox(height: 16),
          _DetailRow(
            icon: Icons.nights_stay_rounded,
            label: 'Duration',
            value: booking.durationLabel,
          ),
          const SizedBox(height: 16),
          _DetailRow(
            icon: Icons.people_rounded,
            label: 'Guests',
            value:
                '${booking.guestCount} guest${booking.guestCount > 1 ? 's' : ''}',
          ),
          const SizedBox(height: 16),
          _DetailRow(
            icon: Icons.payments_rounded,
            label: 'Total',
            value: booking.totalPriceMoney.format(showDecimal: false),
            valueStyle: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),

          // Lifecycle timestamps — only those that have happened, so the guest
          // can see the actual progress of their stay.
          if (booking.confirmedAt != null) ...[
            const Divider(height: 32),
            _DetailRow(
              icon: Icons.event_available_rounded,
              label: 'Accepted',
              value: _formatDateTime(booking.confirmedAt!),
            ),
          ],
          if (booking.actualCheckIn != null) ...[
            const SizedBox(height: 16),
            _DetailRow(
              icon: Icons.meeting_room_rounded,
              label: 'Checked in',
              value: _formatDateTime(booking.actualCheckIn!),
            ),
          ],
          if (booking.completedAt != null) ...[
            const SizedBox(height: 16),
            _DetailRow(
              icon: Icons.task_alt_rounded,
              label: 'Completed',
              value: _formatDateTime(booking.completedAt!),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, ThemeData theme) {
    final user = authState.currentUser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Message Host button for confirmed/active
        if (onMessageHost != null &&
            (booking.status == BookingStatus.confirmed ||
                booking.status == BookingStatus.active)) ...[
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onMessageHost!();
            },
            icon: const Icon(Icons.chat_bubble_outline),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            label: const Text('Message Host'),
          ),
          const SizedBox(height: 12),
        ],

        // Cancel button for pending/confirmed
        if (booking.status == BookingStatus.pending ||
            booking.status == BookingStatus.confirmed) ...[
          OutlinedButton.icon(
            onPressed: () => _showCancelDialog(context),
            icon: const Icon(Icons.cancel_outlined),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              minimumSize: const Size.fromHeight(52),
            ),
            label: const Text('Cancel Booking'),
          ),
          const SizedBox(height: 12),
        ],

        // Review button for completed
        if (booking.status == BookingStatus.completed && user != null) ...[
          _buildReviewButton(context, theme, user.id),
          const SizedBox(height: 12),
        ],

        // REBOOK/FIND SIMILAR for rejected bookings - THE RECOVERY PATH
        if (booking.status == BookingStatus.rejected) ...[
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onNavigateToExplore?.call();
            },
            icon: const Icon(Icons.search_rounded),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            label: const Text('Find Similar Stays'),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildReviewButton(
      BuildContext context, ThemeData theme, String userId) {
    final existingReviews = repository.getReviewsForBooking(booking.id);
    final alreadyReviewed = existingReviews.any(
      (r) => r.reviewerId == userId && r.reviewType == ReviewType.guestToHost,
    );

    if (alreadyReviewed) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'You\'ve already reviewed this stay',
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Show review deadline
    final completedAt = booking.completedAt ?? booking.effectiveCheckOut;
    final reviewDeadline = completedAt.add(BookingRules.reviewWindowDuration);
    final now = DateTime.now();

    // The 14-day review window has closed — reviews are no longer accepted.
    if (now.isAfter(reviewDeadline)) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_clock_rounded,
                color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'The 14-day review window for this stay has closed',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    final daysLeft = reviewDeadline.difference(now).inDays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (daysLeft <= 7) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: daysLeft <= 2
                  ? Colors.red.withValues(alpha: 0.1)
                  : Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.timer_rounded,
                  size: 18,
                  color: daysLeft <= 2 ? Colors.red : Colors.amber.shade700,
                ),
                const SizedBox(width: 8),
                Text(
                  daysLeft <= 0
                      ? 'Last day to review!'
                      : '$daysLeft day${daysLeft == 1 ? '' : 's'} left to review',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: daysLeft <= 2 ? Colors.red : Colors.amber.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(context);
            _navigateToReview(context);
          },
          icon: const Icon(Icons.rate_review_rounded),
          label: const Text('Leave a Review'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
        ),
      ],
    );
  }

  void _navigateToReview(BuildContext context) {
    final user = authState.currentUser;
    if (user == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GuestReviewScreen(
          booking: booking,
          onSubmit: (GuestReviewRatings ratings, String comment) async {
            final hostId =
                await repository.fetchHostIdForListing(booking.listingId);
            if (!context.mounted) return false;
            if (hostId == null || hostId.isEmpty) {
              ModernBanner.showError(
                context,
                'Could not submit review. Please try again later.',
              );
              return false;
            }

            final review = Review.guestReview(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              bookingId: booking.id,
              listingId: booking.listingId,
              reviewerId: user.id,
              reviewerName: user.name,
              reviewerAvatarUrl: user.avatarUrl,
              hostId: hostId,
              ratings: ratings,
              comment: comment,
            );

            final saved = await repository.saveReview(review);
            if (!context.mounted) return saved;
            if (!saved) {
              ModernBanner.showError(
                context,
                'Could not submit review. Please check your connection and try again.',
              );
              return false;
            }

            Navigator.pop(context);
            ModernBanner.showSuccess(
              context,
              'Thank you for your review!',
            );
            return true;
          },
        ),
      ),
    );
  }

  void _showCancelDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: const Text(
          'Are you sure you want to cancel this booking? The host will be notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep Booking'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _performCancel(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
  }

  /// Cancel via the coordinator so the host gets the cancellation message in
  /// the conversation; falls back to a plain status update when absent.
  /// Runs while the sheet is still mounted so the result banner can show,
  /// then closes the sheet.
  Future<void> _performCancel(BuildContext context) async {
    final coordinator = bookingMessagingCoordinator;
    final userId = authState.currentUser?.id;

    if (coordinator != null && userId != null) {
      try {
        final listing = repository.getListingById(booking.listingId);
        await coordinator.cancelBookingWithNotification(
          bookingId: booking.id,
          cancelledBy: userId,
          isHost: false,
          hostId: listing?.hostId ?? '',
        );
        if (!context.mounted) return;
        ModernBanner.showSuccess(context, 'Booking cancelled');
        Navigator.pop(context);
      } on InvalidBookingStateException catch (e) {
        if (context.mounted) ModernBanner.showError(context, e.message);
      } catch (_) {
        if (context.mounted) {
          ModernBanner.showError(
              context, 'Could not cancel. Please try again.');
        }
      }
      return;
    }

    final updated = booking.copyWith(
      status: BookingStatus.cancelled,
      cancelledAt: DateTime.now(),
      cancelledBy: userId,
    );
    repository.updateBooking(updated);
    if (!context.mounted) return;
    ModernBanner.showSuccess(context, 'Booking cancelled');
    Navigator.pop(context);
  }

  String _formatFullDate(DateTime date) {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  /// Date + time, e.g. "Jun 28, 3:30 PM" — used for check-in/out and lifecycle
  /// timestamps so the guest can see the actual time, not just the day.
  String _formatDateTime(DateTime date) {
    // Milestone timestamps are stored/parsed as UTC — show them in local time.
    date = date.toLocal();
    const months = [
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
    final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour < 12 ? 'AM' : 'PM';
    return '${months[date.month - 1]} ${date.day}, $hour12:$minute $period';
  }
}

/// Card surfacing the host's welcome message on the booking detail. Decoupled
/// from chat so the guest sees it regardless of messaging state.
class _HostMessageCard extends StatelessWidget {
  const _HostMessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.format_quote_rounded,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'Message from your host',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _DetailsBanner extends StatelessWidget {
  const _DetailsBanner({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final IconData icon;
  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: valueStyle ??
              theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

// =============================================================================
// SEGMENTED CONTROL WITH BADGES
// =============================================================================

class _SegmentedControlWithBadges extends StatelessWidget {
  const _SegmentedControlWithBadges({
    required this.selectedIndex,
    required this.tabs,
    required this.onChanged,
  });

  final int selectedIndex;
  final List<_TabData> tabs;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = (constraints.maxWidth - 8) / tabs.length;

          return Stack(
            children: [
              // Sliding indicator
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                left: 4 + (selectedIndex * segmentWidth),
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.shadow.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              // Labels with badges
              Row(
                children: tabs.asMap().entries.map((entry) {
                  final index = entry.key;
                  final tab = entry.value;
                  final isSelected = index == selectedIndex;

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onChanged(index),
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: theme.textTheme.titleSmall!.copyWith(
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isSelected
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              child: Text(tab.label),
                            ),
                            if (tab.count > 0) ...[
                              const SizedBox(width: 6),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : theme
                                          .colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${tab.count}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? theme.colorScheme.onPrimary
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}
