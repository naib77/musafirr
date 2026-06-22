import 'package:flutter/material.dart';

import '../../models/booking.dart';
import '../../models/booking_categorizer.dart';
import '../../models/booking_status.dart';
import '../../models/guest_review_ratings.dart';
import '../../models/review.dart';
import '../../repositories/musafir_repository.dart';
import '../../services/booking/booking_rules.dart';
import '../../state/auth_state.dart';
import '../../state/messaging_state.dart';
import '../../state/notification_state.dart';
import '../../widgets/modern_banner.dart';
import '../../widgets/notification_bell.dart';
import '../messaging/chat_screen.dart';
import '../review/guest_review_screen.dart';

class TripsScreen extends StatefulWidget {
  const TripsScreen({
    super.key,
    required this.repository,
    required this.authState,
    this.messagingState,
    this.notificationState,
    this.onOpenInbox,
    this.onOpenNotifications,
    this.onNavigateToExplore,
    this.onTabTapped,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final MessagingStateNotifier? messagingState;
  final NotificationStateNotifier? notificationState;
  final VoidCallback? onOpenInbox;
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

  // Scroll controllers for each tab (for pagination)
  late final ScrollController _upcomingScrollController;
  late final ScrollController _currentScrollController;
  late final ScrollController _pastScrollController;

  // Refresh state
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _upcomingScrollController = ScrollController()..addListener(_onUpcomingScroll);
    _currentScrollController = ScrollController()..addListener(_onCurrentScroll);
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
    if (controller.position.pixels >= controller.position.maxScrollExtent * 0.8) {
      _loadMore();
    }
  }

  void _loadMore() {
    final user = widget.authState.currentUser;
    if (user == null) return;

    if (!widget.repository.isLoadingBookings && widget.repository.hasMoreBookings) {
      widget.repository.fetchNextBookingsPage(user.id);
    }
  }

  Future<void> _onRefresh() async {
    final user = widget.authState.currentUser;
    if (user == null) return;

    setState(() => _isRefreshing = true);
    // Refresh both counts and bookings
    await Future.wait([
      widget.repository.getBookingCounts(user.id),
      widget.repository.resetBookingsPagination(user.id),
    ]);
    setState(() => _isRefreshing = false);
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
    final unreadMessageCount = widget.messagingState?.totalUnreadCount ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Trips'),
        centerTitle: false,
        actions: [
          if (widget.messagingState != null && widget.onOpenInbox != null)
            IconButton(
              icon: Badge(
                isLabelVisible: unreadMessageCount > 0,
                label: Text(
                  unreadMessageCount > 99 ? '99+' : '$unreadMessageCount',
                ),
                child: const Icon(Icons.chat_bubble_outline),
              ),
              onPressed: widget.onOpenInbox,
              tooltip: 'Messages',
            ),
          if (widget.notificationState != null &&
              widget.onOpenNotifications != null)
            AnimatedNotificationBell(
              notificationState: widget.notificationState!,
              onTap: widget.onOpenNotifications!,
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.repository, widget.authState]),
        builder: (context, _) {
          final user = widget.authState.currentUser;
          if (user == null) {
            return _buildLoginPrompt(context, theme);
          }

          final allBookings = widget.repository.getBookingsForUser(user.id);
          final categorizer = BookingCategorizer(allBookings);

          // Use cached total counts for badges (not loaded count)
          final counts = widget.repository.cachedBookingCounts;
          final tabs = [
            _TabData('Upcoming', counts?['upcoming'] ?? categorizer.upcoming.length),
            _TabData('Current', counts?['current'] ?? categorizer.current.length),
            _TabData('Past', counts?['past'] ?? categorizer.past.length),
          ];

          return Column(
            children: [
              // Modern 3-tab segmented control with badges
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _SegmentedControlWithBadges(
                  selectedIndex: _selectedIndex,
                  tabs: tabs,
                  onChanged: (index) => setState(() => _selectedIndex = index),
                ),
              ),
              // Content
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _buildTabContent(
                    context,
                    theme,
                    categorizer,
                    user.id,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabContent(
    BuildContext context,
    ThemeData theme,
    BookingCategorizer categorizer,
    String userId,
  ) {
    switch (_selectedIndex) {
      case 0:
        return _buildBookingsList(
          context,
          theme,
          categorizer.upcoming,
          tabType: _TabType.upcoming,
          userId: userId,
          key: const ValueKey('upcoming'),
        );
      case 1:
        return _buildBookingsList(
          context,
          theme,
          categorizer.current,
          tabType: _TabType.current,
          userId: userId,
          key: const ValueKey('current'),
        );
      case 2:
        return _buildBookingsList(
          context,
          theme,
          categorizer.past,
          tabType: _TabType.past,
          userId: userId,
          key: const ValueKey('past'),
        );
      default:
        return const SizedBox.shrink();
    }
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
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
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
              child: _buildEmptyState(context, theme, tabType: tabType, key: key),
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
                r.reviewerId == userId && r.reviewType == ReviewType.guestToHost,
          );
          if (!hasReviewed) {
            needsReviewBookings.add(booking);
          }
        }
      }
    }

    final hasReviewBanner = tabType == _TabType.past && needsReviewBookings.isNotEmpty;
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
                  // Show message button for confirmed/active bookings
                  final showMessageButton = widget.messagingState != null &&
                      (booking.status == BookingStatus.confirmed ||
                          booking.status == BookingStatus.active);

                  return Padding(
                    padding: EdgeInsets.only(top: index > 0 ? 16 : 0),
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
    // Show message button for confirmed/active bookings
    final showMessageButton = widget.messagingState != null &&
        (booking.status == BookingStatus.confirmed ||
            booking.status == BookingStatus.active);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EnhancedBookingDetailsSheet(
        booking: booking,
        repository: widget.repository,
        authState: widget.authState,
        bookingRules: _bookingRules,
        onNavigateToExplore: widget.onNavigateToExplore,
        onMessageHost: showMessageButton
            ? () => _openChatForBooking(booking)
            : null,
      ),
    );
  }

  Future<void> _openChatForBooking(Booking booking) async {
    if (widget.messagingState == null) return;

    final user = widget.authState.currentUser;
    if (user == null) return;

    // Find the conversation for this booking
    final conversations = widget.messagingState!.conversations;
    var conversation = conversations.where((c) => c.bookingId == booking.id).firstOrNull;

    // If no conversation exists, create one
    if (conversation == null) {
      // Get the host ID from the listing
      final listing = widget.repository.listings
          .where((l) => l.id == booking.listingId)
          .firstOrNull;

      final hostId = listing?.hostId;
      if (hostId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot message: host information not available'),
            ),
          );
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to start conversation. Please try again.'),
            ),
          );
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
}

enum _TabType { upcoming, current, past }

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
  });

  final Booking booking;
  final VoidCallback onTap;
  final _TabType tabType;
  final BookingRules bookingRules;
  final bool showReviewBadge;
  final List<Booking> needsReviewBookings;
  final VoidCallback? onMessageHost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.2),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with status overlay
            _buildImageSection(theme),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Contextual state banner - THE KEY UX IMPROVEMENT
                  _buildContextualBanner(context, theme),
                  const SizedBox(height: 12),
                  // Title
                  Text(
                    booking.listingTitle ?? 'Booking',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Location
                  if (booking.listingCity != null)
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            booking.listingCity!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  // Dates and duration
                  _buildDatesRow(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection(ThemeData theme) {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 2.2,
          child: booking.listingImageUrl != null
              ? Image.network(
                  booking.listingImageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildPlaceholder(theme),
                )
              : _buildPlaceholder(theme),
        ),
        // Status badge overlay
        Positioned(
          top: 12,
          left: 12,
          child: _StatusBadge(status: booking.status),
        ),
        // Review badge if needed
        if (showReviewBadge)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.amber.shade600, Colors.orange.shade600],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Review',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// THE DEEP MODULE: Contextual banner based on booking state
  /// This surfaces the right information at the right time
  Widget _buildContextualBanner(BuildContext context, ThemeData theme) {
    final now = DateTime.now();

    // PENDING: Show expiration countdown
    if (booking.status == BookingStatus.pending) {
      return _PendingExpirationBanner(
        booking: booking,
        bookingRules: bookingRules,
      );
    }

    // CONFIRMED: Show check-in readiness + Message Host button
    if (booking.status == BookingStatus.confirmed) {
      final canCheckIn = bookingRules.canCheckIn(booking, now: now);
      final daysUntilCheckIn =
          booking.effectiveCheckIn.difference(now).inDays;

      Widget infoBanner;
      if (canCheckIn) {
        infoBanner = _InfoBanner(
          icon: Icons.login_rounded,
          text: 'Ready to check in today!',
          color: Colors.green,
        );
      } else if (daysUntilCheckIn <= 3) {
        infoBanner = _InfoBanner(
          icon: Icons.event_available_rounded,
          text: 'Check-in in $daysUntilCheckIn day${daysUntilCheckIn == 1 ? '' : 's'}',
          color: Colors.blue,
        );
      } else {
        infoBanner = _InfoBanner(
          icon: Icons.check_circle_outline_rounded,
          text: 'Confirmed - ${_formatDate(booking.effectiveCheckIn)}',
          color: Colors.green,
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          infoBanner,
          if (onMessageHost != null) ...[
            const SizedBox(height: 8),
            _MessageHostButton(onTap: onMessageHost!),
          ],
        ],
      );
    }

    // ACTIVE: Show stay progress + Message Host button
    if (booking.status == BookingStatus.active) {
      final totalDays = booking.numberOfNights;
      final daysStayed = now.difference(booking.effectiveCheckIn).inDays + 1;
      final daysLeft = booking.effectiveCheckOut.difference(now).inDays;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoBanner(
            icon: Icons.hotel_rounded,
            text: 'Day $daysStayed of $totalDays • ${daysLeft > 0 ? '$daysLeft days left' : 'Checkout today'}',
            color: Colors.teal,
            showProgress: true,
            progress: daysStayed / totalDays,
          ),
          if (onMessageHost != null) ...[
            const SizedBox(height: 8),
            _MessageHostButton(onTap: onMessageHost!),
          ],
        ],
      );
    }

    // COMPLETED: Show review deadline
    if (booking.status == BookingStatus.completed && showReviewBadge) {
      final completedAt = booking.completedAt ?? booking.effectiveCheckOut;
      final reviewDeadline =
          completedAt.add(BookingRules.reviewWindowDuration);
      final daysLeft = reviewDeadline.difference(now).inDays;

      if (daysLeft > 0) {
        return _InfoBanner(
          icon: Icons.rate_review_rounded,
          text: '$daysLeft days left to leave a review',
          color: Colors.amber.shade700,
        );
      } else {
        return _InfoBanner(
          icon: Icons.warning_amber_rounded,
          text: 'Last day to leave a review!',
          color: Colors.red,
        );
      }
    }

    // REJECTED: Show rebooking prompt
    if (booking.status == BookingStatus.rejected) {
      return _InfoBanner(
        icon: Icons.search_rounded,
        text: 'Declined - Tap to find similar stays',
        color: Colors.red.shade700,
      );
    }

    // CANCELLED
    if (booking.status == BookingStatus.cancelled) {
      final cancelledByGuest = booking.cancelledBy == booking.userId;
      return _InfoBanner(
        icon: Icons.cancel_outlined,
        text: cancelledByGuest ? 'You cancelled this booking' : 'Cancelled by host',
        color: Colors.grey,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildDatesRow(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CHECK-IN',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(booking.effectiveCheckIn),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${booking.numberOfNights} night${booking.numberOfNights == 1 ? '' : 's'}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'CHECK-OUT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(booking.effectiveCheckOut),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.home_outlined,
          size: 48,
          color: theme.colorScheme.onSurfaceVariant,
        ),
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

// =============================================================================
// STATUS BADGE - Modern status indicator
// =============================================================================

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      BookingStatus.pending => (Colors.orange, Icons.schedule_rounded),
      BookingStatus.confirmed => (Colors.green, Icons.check_circle_rounded),
      BookingStatus.rejected => (Colors.red.shade700, Icons.cancel_rounded),
      BookingStatus.active => (Colors.teal, Icons.hotel_rounded),
      BookingStatus.completed => (Colors.blue, Icons.task_alt_rounded),
      BookingStatus.cancelled => (Colors.red, Icons.cancel_outlined),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            status.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// CONTEXTUAL BANNERS
// =============================================================================

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.text,
    required this.color,
    this.showProgress = false,
    this.progress = 0.0,
  });

  final IconData icon;
  final String text;
  final Color color;
  final bool showProgress;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (showProgress) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: color.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 6,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageHostButton extends StatelessWidget {
  const _MessageHostButton({required this.onTap});

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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Message Host',
                style: TextStyle(
                  fontSize: 13,
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

class _PendingExpirationBanner extends StatelessWidget {
  const _PendingExpirationBanner({
    required this.booking,
    required this.bookingRules,
  });

  final Booking booking;
  final BookingRules bookingRules;

  @override
  Widget build(BuildContext context) {
    final createdAt = booking.createdAt;
    if (createdAt == null) {
      return _InfoBanner(
        icon: Icons.schedule_rounded,
        text: 'Awaiting host response',
        color: Colors.orange,
      );
    }

    final expiresAt = createdAt.add(BookingRules.expirationDuration);
    final now = DateTime.now();
    final remaining = expiresAt.difference(now);

    String timeText;
    if (remaining.isNegative) {
      timeText = 'Expired';
    } else if (remaining.inHours >= 1) {
      timeText = '${remaining.inHours}h ${remaining.inMinutes % 60}m left';
    } else if (remaining.inMinutes >= 1) {
      timeText = '${remaining.inMinutes}m left';
    } else {
      timeText = 'Less than a minute';
    }

    final progress = 1.0 - (remaining.inMinutes / (24 * 60));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hourglass_top_rounded,
                  size: 18, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Awaiting host response',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: remaining.inHours < 6
                      ? Colors.red.withValues(alpha: 0.2)
                      : Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  timeText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: remaining.inHours < 6
                        ? Colors.red.shade700
                        : Colors.orange.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: Colors.orange.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(
                remaining.inHours < 6 ? Colors.red : Colors.orange,
              ),
              minHeight: 6,
            ),
          ),
        ],
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

class _EnhancedBookingDetailsSheet extends StatelessWidget {
  const _EnhancedBookingDetailsSheet({
    required this.booking,
    required this.repository,
    required this.authState,
    required this.bookingRules,
    this.onNavigateToExplore,
    this.onMessageHost,
  });

  final Booking booking;
  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final BookingRules bookingRules;
  final VoidCallback? onNavigateToExplore;
  final VoidCallback? onMessageHost;

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
        subtitle: booking.rejectionReason ?? 'The host couldn\'t accommodate your request',
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
            icon: Icons.calendar_today_rounded,
            label: 'Check-in',
            value: _formatFullDate(booking.effectiveCheckIn),
          ),
          const SizedBox(height: 16),
          _DetailRow(
            icon: Icons.calendar_today_rounded,
            label: 'Check-out',
            value: _formatFullDate(booking.effectiveCheckOut),
          ),
          const SizedBox(height: 16),
          _DetailRow(
            icon: Icons.nights_stay_rounded,
            label: 'Duration',
            value:
                '${booking.numberOfNights} night${booking.numberOfNights > 1 ? 's' : ''}',
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
          onSubmit: (GuestReviewRatings ratings, String comment) {
            final listing = repository.listings.firstWhere(
              (l) => l.id == booking.listingId,
              orElse: () => repository.listings.first,
            );

            final review = Review.guestReview(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              bookingId: booking.id,
              listingId: booking.listingId,
              reviewerId: user.id,
              reviewerName: user.name ?? 'Guest',
              reviewerAvatarUrl: user.avatarUrl,
              hostId: listing.hostId ?? '',
              ratings: ratings,
              comment: comment,
            );

            repository.saveReview(review);

            Navigator.pop(context);
            ModernBanner.showSuccess(
              context,
              'Thank you for your review!',
            );
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
              final updated = booking.copyWith(
                status: BookingStatus.cancelled,
                cancelledAt: DateTime.now(),
                cancelledBy: authState.currentUser?.id,
              );
              repository.updateBooking(updated);
              Navigator.pop(dialogContext);
              Navigator.pop(context);
              ModernBanner.showSuccess(context, 'Booking cancelled');
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

  String _formatFullDate(DateTime date) {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
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
                                      : theme.colorScheme.surfaceContainerHighest,
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
